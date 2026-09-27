import Combine
import FirebaseCore
import FirebaseFirestore
import Foundation

/// The single in-app read source for registered places.
/// Firestore's persistent local cache is checked first; the bundled seed remains
/// immediately available while a server refresh runs or when that refresh fails.
@MainActor
final class PlacesRepository: ObservableObject {
    enum State: Equatable {
        case initialLoading
        case cached
        case loaded
        case refreshing
        case fallbackSeed
        case failed(message: String)
    }

    @Published private(set) var places: [PhotoSpot]
    @Published private(set) var state: State

    private let firestore: Firestore?
    private let fallbackSeedPlaces: [PhotoSpot]
    private var refreshTask: Task<Void, Never>?
    private var didStartInitialLoad = false
    private var hasFirestorePlaces = false
    private var lastRefreshAttemptAt: Date?

    init(
        firestore: Firestore? = nil,
        seedService: LocalSeedDataService = LocalSeedDataService()
    ) {
        self.firestore = firestore ?? (FirebaseApp.app() == nil ? nil : Firestore.firestore())
        fallbackSeedPlaces = seedService.allPhotoSpots()
        places = []
        state = .initialLoading
    }

    func place(id: String) -> PhotoSpot? {
        places.first { $0.id == id }
    }

    /// Creates a user-owned Firestore Place. A server snapshot checks identity
    /// duplicates, then a transaction makes the stable document ID create-only
    /// and closes the common concurrent-submit race.
    func createUserPlace(_ candidate: PhotoSpot, createdBy uid: String) async throws -> PhotoSpot {
        guard !uid.isEmpty else { throw PlacesRepositoryError.notAuthenticated }
        guard let firestore else { throw PlacesRepositoryError.notConfigured }
        guard !candidate.id.isEmpty, !candidate.id.contains("/") else {
            throw PlacesRepositoryError.invalidID
        }
        await loadIfNeeded()

        let remoteSnapshot = try await fetchPlaces(from: firestore, source: .server)
        let remotePlaces = decodePlaces(from: remoteSnapshot)
        if let duplicate = remotePlaces.first(where: {
            PlaceIdentityMatcher.matches(PlaceIdentity(spot: candidate), PlaceIdentity(spot: $0))
        }) {
            if duplicate.id == candidate.id, duplicate.isOwned(by: uid) {
                // Idempotent retry after a client-side connection loss: the
                // deterministic document already belongs to this submitter.
                return duplicate
            }
            throw PlacesRepositoryError.duplicate
        }

        let reference = firestore.collection("places").document(candidate.id)
        let now = Date()
        let newSpot = candidate.replacingPlaceLifecycle(
            source: "user-submitted",
            createdBy: uid,
            createdAt: now,
            updatedAt: now,
            status: "active",
            removeImages: true
        )
        let payload = createPayload(for: newSpot, ownerID: uid)
        let transactionResult = try await firestore.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(reference)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            if snapshot.exists {
                let fields = snapshot.data() ?? [:]
                guard fields["source"] as? String == "user-submitted",
                      fields["createdBy"] as? String == uid,
                      fields["status"] as? String != "deleted" else {
                    errorPointer?.pointee = PlacesRepositoryError.duplicate as NSError
                    return nil
                }
                return ["alreadyOwned": true, "fields": fields] as [String: Any]
            }

            transaction.setData(payload, forDocument: reference)
            return ["alreadyOwned": false] as [String: Any]
        }

        if let result = transactionResult as? [String: Any],
           result["alreadyOwned"] as? Bool == true,
           let fields = result["fields"] as? [String: Any],
           let existing = FirestorePlaceRecord(documentID: candidate.id, fields: fields)?.photoSpot {
            upsert(existing)
            return existing
        }

        hasFirestorePlaces = true
        didStartInitialLoad = true
        upsert(newSpot)
        state = .loaded
        return newSpot
    }

    /// Updates only editable fields on a place owned by the current user.
    /// Identity, provider, creator, and creation time are validated again in
    /// the transaction and are never included in the update payload.
    func updateUserPlace(_ candidate: PhotoSpot, updatedBy uid: String) async throws -> PhotoSpot {
        guard !uid.isEmpty else { throw PlacesRepositoryError.notAuthenticated }
        guard let firestore else { throw PlacesRepositoryError.notConfigured }
        guard candidate.isOwned(by: uid) else { throw PlacesRepositoryError.notOwner }

        let reference = firestore.collection("places").document(candidate.id)
        var originalFields: [String: Any]?
        var updatedFields = editablePayload(for: candidate)
        updatedFields["updatedAt"] = FieldValue.serverTimestamp()
        updatedFields["status"] = "active"

        _ = try await firestore.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(reference)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard let fields = snapshot.data(),
                  fields["source"] as? String == "user-submitted",
                  fields["createdBy"] as? String == uid,
                  fields["status"] as? String != "deleted" else {
                errorPointer?.pointee = PlacesRepositoryError.notOwner as NSError
                return nil
            }
            originalFields = fields
            transaction.updateData(updatedFields, forDocument: reference)
            return true
        }

        guard let originalFields,
              let original = FirestorePlaceRecord(documentID: candidate.id, fields: originalFields)?.photoSpot else {
            throw PlacesRepositoryError.invalidDocument
        }

        let updated = candidate.replacingPlaceLifecycle(
            source: original.source,
            createdBy: original.createdBy,
            createdAt: original.createdAt,
            updatedAt: Date(),
            status: "active",
            deletedAt: nil,
            deletedBy: nil
        )
        upsert(updated)
        state = .loaded
        return updated
    }

    /// Soft-deletes an owned user place. Public reads remain compatible with
    /// the collection-wide listing query; deleted records are excluded while
    /// decoding this repository's normal Home/Map/Search source.
    func softDeleteUserPlace(id: String, deletedBy uid: String) async throws {
        guard !uid.isEmpty else { throw PlacesRepositoryError.notAuthenticated }
        guard let firestore else { throw PlacesRepositoryError.notConfigured }

        let reference = firestore.collection("places").document(id)
        _ = try await firestore.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(reference)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard let fields = snapshot.data(),
                  fields["source"] as? String == "user-submitted",
                  fields["createdBy"] as? String == uid,
                  fields["status"] as? String != "deleted" else {
                errorPointer?.pointee = PlacesRepositoryError.notOwner as NSError
                return nil
            }

            transaction.updateData([
                "status": "deleted",
                "deletedAt": FieldValue.serverTimestamp(),
                "deletedBy": uid,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: reference)
            return true
        }

        places.removeAll { $0.id == id }
        state = .loaded
    }

    private func createPayload(for spot: PhotoSpot, ownerID: String) -> [String: Any] {
        var data: [String: Any] = [
            "name": spot.name,
            "address": spot.region,
            "summary": spot.summary,
            "tags": normalizedTags(spot.hashtags),
            "latitude": spot.latitude,
            "longitude": spot.longitude,
            "primaryTheme": spot.theme.rawValue,
            "source": "user-submitted",
            "schemaVersion": 1,
            "createdBy": ownerID,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "status": "active",
            "isHiddenSpot": spot.isHiddenSpot,
        ]

        let optionalText: [(String, String)] = [
            ("category", spot.category),
            ("reason", spot.eventPeriod),
            ("bestTime", spot.bestTime),
            ("openingHours", spot.openingHours),
            ("feeInfo", spot.feeInfo),
            ("parkingInfo", spot.parkingInfo),
            ("nearbyParkingInfo", spot.nearbyParkingInfo),
            ("crowdLevelCode", spot.crowdLevelCode),
            ("provider", spot.provider ?? ""),
            ("providerPlaceID", spot.providerPlaceID ?? ""),
        ]
        for (key, value) in optionalText where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data[key] = value
        }
        if !spot.season.isEmpty { data["season"] = spot.season }
        if !spot.weather.isEmpty { data["weather"] = spot.weather }
        if !spot.mood.isEmpty { data["mood"] = spot.mood }
        return data
    }

    private func editablePayload(for spot: PhotoSpot) -> [String: Any] {
        [
            "summary": spot.summary,
            "tags": normalizedTags(spot.hashtags),
            "primaryTheme": spot.theme.rawValue,
            "reason": spot.eventPeriod,
            "bestTime": spot.bestTime,
            "openingHours": spot.openingHours,
            "feeInfo": spot.feeInfo,
            "parkingInfo": spot.parkingInfo,
            "nearbyParkingInfo": spot.nearbyParkingInfo,
            "season": spot.season,
            "weather": spot.weather,
            "mood": spot.mood,
            "crowdLevelCode": spot.crowdLevelCode,
            "isHiddenSpot": spot.isHiddenSpot,
        ]
    }

    private func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { rawValue in
            let value = rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard !value.isEmpty, value.count <= 50,
                  seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }
    }

    private func upsert(_ spot: PhotoSpot) {
        places.removeAll { $0.id == spot.id }
        places.append(spot)
        places.sort { $0.id < $1.id }
    }

    /// Starts one shared initial load. Concurrent callers await the same task.
    func loadIfNeeded() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        guard !didStartInitialLoad else { return }
        didStartInitialLoad = true
        await startRefresh(now: Date())
    }

    /// Refreshes on foreground return at most once per interval.
    func refreshIfStale(
        now: Date = Date(),
        minimumInterval: TimeInterval = 5 * 60
    ) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        if let lastRefreshAttemptAt,
           now.timeIntervalSince(lastRefreshAttemptAt) < minimumInterval {
            return
        }
        didStartInitialLoad = true
        await startRefresh(now: now)
    }

    private func startRefresh(now: Date) async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        lastRefreshAttemptAt = now
        state = places.isEmpty ? .initialLoading : .refreshing
        let task = Task { [weak self] in
            guard let self else { return }
            await self.refreshFromFirestore()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func refreshFromFirestore() async {
        guard let firestore else {
            finishWithFallbackOrFailure("Firebase가 준비되지 않았어요.")
            return
        }

        do {
            let cachedSnapshot = try await fetchPlaces(from: firestore, source: .cache)
            let cachedPlaces = decodePlaces(from: cachedSnapshot)
            if !cachedPlaces.isEmpty {
                places = cachedPlaces
                hasFirestorePlaces = true
                state = .cached
            }
#if DEBUG
            AppLog.network.debug(
                "[Places] source=firestoreCache count=\(cachedPlaces.count, privacy: .public)"
            )
#endif
        } catch {
            // A cache miss is expected on first launch; seed fallback waits for server failure.
            AppLog.network.debug(
                "Firestore places cache unavailable: \(error.localizedDescription, privacy: .public)"
            )
        }

        if !places.isEmpty {
            state = .refreshing
        }

        do {
            let serverSnapshot = try await fetchPlaces(from: firestore, source: .server)
            let serverPlaces = decodePlaces(from: serverSnapshot)
            if !serverSnapshot.documents.isEmpty && serverPlaces.isEmpty {
                throw PlacesRepositoryError.noValidDocuments
            }

            places = serverPlaces
            hasFirestorePlaces = true
            state = .loaded
#if DEBUG
            AppLog.network.info(
                "[Places] source=firestore count=\(serverSnapshot.documents.count, privacy: .public) decoded=\(serverPlaces.count, privacy: .public)"
            )
#endif
            AppLog.network.info(
                "Loaded \(serverPlaces.count, privacy: .public) places from Firestore"
            )
        } catch {
            AppLog.network.error(
                "Firestore places refresh failed: \(error.localizedDescription, privacy: .public)"
            )
            finishWithFallbackOrFailure("출사지를 불러오지 못했어요.", reason: error.localizedDescription)
        }
    }

    private func finishWithFallbackOrFailure(_ message: String, reason: String? = nil) {
        if hasFirestorePlaces {
            state = .cached
#if DEBUG
            AppLog.network.debug(
                "[Places] source=firestoreCache count=\(self.places.count, privacy: .public) reason=\((reason ?? message), privacy: .public)"
            )
#endif
        } else if !fallbackSeedPlaces.isEmpty {
            places = fallbackSeedPlaces
            state = .fallbackSeed
#if DEBUG
            AppLog.network.debug(
                "[Places] source=localSeed count=\(self.places.count, privacy: .public) reason=\((reason ?? message), privacy: .public)"
            )
#endif
        } else {
            state = .failed(message: message)
#if DEBUG
            AppLog.network.debug(
                "[Places] source=none count=0 reason=\((reason ?? message), privacy: .public)"
            )
#endif
        }
    }

    private func fetchPlaces(
        from firestore: Firestore,
        source: FirestoreSource
    ) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            firestore.collection("places").getDocuments(source: source) { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: PlacesRepositoryError.emptyResponse)
                }
            }
        }
    }

    private func decodePlaces(from snapshot: QuerySnapshot) -> [PhotoSpot] {
        var decoded: [PhotoSpot] = []
        var invalidCount = 0

        for document in snapshot.documents {
            guard let record = FirestorePlaceRecord(
                documentID: document.documentID,
                fields: document.data()
            ) else {
                invalidCount += 1
                AppLog.network.error(
                    "Skipping malformed Firestore place document: \(document.documentID, privacy: .public)"
                )
                continue
            }
            guard record.status != "deleted" else { continue }
            decoded.append(record.photoSpot)
        }

        if invalidCount > 0 {
            AppLog.network.error(
                "Skipped \(invalidCount, privacy: .public) malformed Firestore places"
            )
        }

        return decoded.sorted { $0.id < $1.id }
    }
}

enum PlacesRepositoryError: LocalizedError {
    case emptyResponse
    case noValidDocuments
    case notAuthenticated
    case notConfigured
    case invalidID
    case duplicate
    case notOwner
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "출사지 저장 서버에서 응답을 받지 못했어요."
        case .noValidDocuments:
            return "출사지 정보를 읽을 수 없어요."
        case .notAuthenticated:
            return "로그인한 사용자만 장소를 추가할 수 있어요."
        case .notConfigured:
            return "장소 저장 기능을 사용할 수 없어요."
        case .invalidID:
            return "장소 식별 정보가 올바르지 않아요."
        case .duplicate:
            return "이미 등록된 장소예요. 기존 장소를 확인해주세요."
        case .notOwner:
            return "이 장소를 수정하거나 삭제할 권한이 없어요."
        case .invalidDocument:
            return "장소 정보를 확인할 수 없어요. 다시 불러온 뒤 시도해주세요."
        }
    }
}

/// Decodes only the migrated public `places` schema. Optional fields are read
/// independently so a missing optional value never invalidates the document.
private struct FirestorePlaceRecord {
    let id: String
    let name: String
    let address: String
    let summary: String
    let tags: [String]
    let latitude: Double
    let longitude: Double
    let theme: SpotTheme
    let source: String
    let region: String?
    let regions: [String]
    let bestTime: String?
    let reason: String?
    let category: String?
    let season: [String]
    let weather: [String]
    let mood: [String]
    let crowdLevelCode: String?
    let isHiddenSpot: Bool?
    let imageURL: URL?
    let imageName: String?
    let imageCredit: String?
    let imageLicense: String?
    let imageSourceURL: URL?
    let openingHours: String?
    let feeInfo: String?
    let parkingInfo: String?
    let nearbyParkingInfo: String?
    let provider: String?
    let providerPlaceID: String?
    let createdBy: String?
    let createdAt: Date?
    let updatedAt: Date?
    let status: String
    let deletedAt: Date?
    let deletedBy: String?

    init?(documentID: String, fields: [String: Any]) {
        guard let name = Self.text(fields["name"]),
              let address = Self.text(fields["address"]),
              let latitude = Self.number(fields["latitude"]),
              (-90...90).contains(latitude),
              let longitude = Self.number(fields["longitude"]),
              (-180...180).contains(longitude) else {
            return nil
        }

        let summary = Self.text(fields["summary"]) ?? Self.text(fields["description"]) ?? ""
        let tags = Self.textList(fields["tags"])
        let category = Self.text(fields["category"])
        let themeValue = Self.text(fields["primaryTheme"]) ?? Self.text(fields["theme"])
        let theme = themeValue.flatMap(SpotTheme.init(rawValue:))
            ?? SpotTheme.resolve(legacyValue: themeValue, name: name, description: summary, tags: tags, category: category)

        id = documentID
        self.name = name
        self.address = address
        self.summary = summary
        self.tags = tags
        self.latitude = latitude
        self.longitude = longitude
        self.theme = theme
        source = Self.text(fields["source"]) ?? "local"
        region = Self.text(fields["region"])
        regions = Self.textList(fields["regions"])
        bestTime = Self.text(fields["bestTime"])
        reason = Self.text(fields["reason"])
        self.category = category
        season = Self.textList(fields["season"])
        weather = Self.textList(fields["weather"])
        mood = Self.textList(fields["mood"])
        crowdLevelCode = Self.text(fields["crowdLevelCode"])
        isHiddenSpot = fields["isHiddenSpot"] as? Bool
        imageURL = Self.webURL(fields["imageURL"])
        imageName = Self.text(fields["imageName"])
        imageCredit = Self.text(fields["imageCredit"])
        imageLicense = Self.text(fields["imageLicense"])
        imageSourceURL = Self.webURL(fields["imageSourceURL"])
        openingHours = Self.text(fields["openingHours"])
        feeInfo = Self.text(fields["feeInfo"])
        parkingInfo = Self.text(fields["parkingInfo"])
        nearbyParkingInfo = Self.text(fields["nearbyParkingInfo"])
        provider = Self.text(fields["provider"])
        providerPlaceID = Self.text(fields["providerPlaceID"])
        createdBy = Self.text(fields["createdBy"])
        createdAt = Self.date(fields["createdAt"])
        updatedAt = Self.date(fields["updatedAt"])
        status = Self.text(fields["status"]) ?? "active"
        deletedAt = Self.date(fields["deletedAt"])
        deletedBy = Self.text(fields["deletedBy"])
    }

    var photoSpot: PhotoSpot {
        let isUserSubmitted = source == "user-submitted"
        let displayTags = tags
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .filter { !$0.isEmpty }
        // Preserve every valid stored tag in the shared model so a later edit
        // cannot silently drop tags that are not currently shown in compact UI.
        let hashtags = Array((displayTags.isEmpty ? ["출사지"] : displayTags).prefix(12))
        let resolvedCategory = category ?? inferredCategory
        let displayImageName = Self.nonEmpty(imageName)
        let galleryPhotos: [PlacePhoto] = imageURL != nil || displayImageName != nil
            ? [PlacePhoto(
                id: "firestore-\(id)-cover",
                placeID: id,
                imageURL: imageURL,
                imageName: displayImageName,
                source: isUserSubmitted ? .placeSubmission : .seed
            )]
            : []

        return PhotoSpot(
            id: id,
            name: name,
            region: address,
            summary: summary.isEmpty && isUserSubmitted ? "사용자가 추가한 출사지예요." : summary,
            hashtags: hashtags,
            eventTitle: isUserSubmitted ? "사용자 추가 장소" : "추천 이유",
            eventPeriod: reason ?? (isUserSubmitted ? "상시" : "촬영 시간 확인 추천"),
            feeInfo: Self.nonEmpty(feeInfo) ?? (isUserSubmitted ? "확인 필요" : "방문 전 공식 정보 확인 필요"),
            openingHours: Self.nonEmpty(openingHours) ?? (isUserSubmitted ? "운영 정보 확인 필요" : "이용 가능시간 확인 필요"),
            bestTime: Self.nonEmpty(bestTime) ?? (isUserSubmitted ? "현장 상황에 따라 확인" : "시간대별 빛을 확인해보세요"),
            crowdLevel: isUserSubmitted ? "현장 정보 확인 필요" : "주말 오후와 해질녘은 혼잡할 수 있어요",
            lensSuggestion: Self.lensSuggestion(for: theme),
            weatherFit: Self.weatherFit(for: theme),
            parkingInfo: Self.nonEmpty(parkingInfo) ?? "주차 정보 확인 필요",
            nearbyParkingInfo: Self.nonEmpty(nearbyParkingInfo) ?? "네이버 지도 또는 카카오맵에서 주변 주차장 확인",
            communityTitle: isUserSubmitted ? "사용자 추가 장소" : "\(name) 실시간",
            communitySubtitle: isUserSubmitted ? summary : "날씨, 혼잡도, 촬영 포인트 공유 예정",
            mapQuery: "\(name) \(address)",
            latitude: latitude,
            longitude: longitude,
            theme: theme,
            imageURL: imageURL,
            category: resolvedCategory,
            season: season,
            weather: weather,
            mood: mood,
            crowdLevelCode: Self.nonEmpty(crowdLevelCode) ?? "normal",
            imageName: displayImageName,
            imageCredit: imageCredit,
            imageLicense: imageLicense,
            imageSourceURL: imageSourceURL,
            recommendationRegions: recommendationRegions,
            isHiddenSpot: isHiddenSpot ?? inferredHiddenSpot,
            provider: provider,
            providerPlaceID: providerPlaceID,
            galleryPhotos: galleryPhotos,
            source: source,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status,
            deletedAt: deletedAt,
            deletedBy: deletedBy
        )
    }

    private var inferredCategory: String {
        if tags.contains(where: { $0.contains("공원") || $0.contains("숲") }) { return "park" }
        if tags.contains(where: { $0.contains("산책") || $0.contains("길") }) { return "walk" }
        return theme == .cafeIndoor ? "indoor" : "spot"
    }

    private var recommendationRegions: [String] {
        let regionHint = Self.knownRegionHints.first { address.contains($0) || name.contains($0) }
        let regionTags = tags.filter { Self.regionTags.contains($0) }
        return Self.uniqueText(([region, regionHint].compactMap { $0 }) + regions + regionTags)
    }

    private var inferredHiddenSpot: Bool {
        crowdLevelCode == "low"
            || ([summary, reason ?? ""] + tags + mood).joined(separator: " ").contains("숨은")
            || ([summary, reason ?? ""] + tags + mood).joined(separator: " ").contains("한적")
    }

    private static let knownRegionHints = [
        "문래", "성수", "을지로", "연남", "익선동", "서촌", "해방촌", "한강", "서울숲", "선유도",
        "북촌", "망원", "보라매", "경의선숲길", "항동", "안양천", "서래섬", "반포", "이촌", "뚝섬",
        "양화", "잠원", "도농", "삼패", "하늘공원", "백빈", "압구정", "영천"
    ]

    private static let regionTags = [
        "문래", "성수", "을지로", "연남", "익선동", "서촌", "해방촌", "한강", "서울숲", "선유도",
        "북촌", "망원", "잠실", "대학로", "보라매", "경의선숲길", "항동", "안양천", "서래섬", "반포",
        "이촌", "뚝섬", "양화", "잠원", "도농", "삼패", "하늘공원", "백빈", "압구정", "영천"
    ]

    private static func uniqueText(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func textList(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { text($0) }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }

    private static func webURL(_ value: Any?) -> URL? {
        guard let rawValue = text(value),
              let url = URL(string: rawValue),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    private static func lensSuggestion(for theme: SpotTheme) -> String {
        switch theme {
        case .cityArchitecture, .retroAlley, .historyTradition, .viewpoint:
            return "24-70mm 줌, 야경은 밝은 단렌즈"
        case .landscape:
            return "50mm 단렌즈 또는 접사 가능한 표준 줌"
        case .cafeIndoor:
            return "35mm 밝은 단렌즈"
        }
    }

    private static func weatherFit(for theme: SpotTheme) -> String {
        switch theme {
        case .retroAlley:
            return "맑은 밤과 비 온 뒤 반사 컷에 좋아요"
        case .historyTradition:
            return "맑은 날 건축 디테일과 차분한 색감이 좋아요"
        case .landscape:
            return "맑거나 얇게 흐린 날 색감이 부드러워요"
        case .cafeIndoor:
            return "비 오는 날에도 촬영하기 좋아요"
        case .viewpoint:
            return "바람 적은 날 반영이 깔끔해요"
        case .cityArchitecture:
            return "맑은 날 선명하고 흐린 날은 차분한 색감이 좋아요"
        }
    }
}

import Combine
import CoreLocation
import Foundation

struct PlaceVerificationService {
    private struct RequestBody: Encodable {
        struct UserLocationPayload: Encodable {
            let latitude: Double
            let longitude: Double
        }

        let region: String
        let userLocation: UserLocationPayload?
        let recommendations: [PhotoSpotRecommendation]
    }

    private struct ResponseBody: Decodable {
        let spots: [VerifiedPhotoSpot]
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    func verify(
        recommendations: [PhotoSpotRecommendation],
        region: String,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> [VerifiedPhotoSpot] {
        guard let endpointURL else {
            throw PhotoSpotSearchError.notConfigured
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let allowedRecommendations = recommendations.filter {
            SearchRegionPolicy.allowsRecommendationCandidate($0, query: region)
                && !CafeRecommendationPolicy.isBlacklistedRecommendation($0)
                && !RecommendationBlacklist.isBlacklistedRecommendation($0)
        }

        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                region: region,
                userLocation: userLocation.map {
                    RequestBody.UserLocationPayload(latitude: $0.latitude, longitude: $0.longitude)
                },
                recommendations: allowedRecommendations
            )
        )

        let (data, response) = try await BackendClient.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoSpotSearchError.malformedResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw Self.serverError(from: data, statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.spots.filter {
            SearchRegionPolicy.matches($0, query: region)
                && !RecommendationBlacklist.isBlacklistedRecommendation($0)
        }
    }

    private var endpointURL: URL? {
        AppBackendConfiguration.current.endpoint(named: "verify-spots")
    }

    /// 서버 실패를 진단 정보와 함께 감싸고 로그를 남깁니다.
    ///
    /// 전에는 이 함수가 사용자에게 보여줄 문장을 만들었습니다.
    /// 그 과정에서 서버 응답의 error 필드를 그대로 반환하는 경로가 있어서,
    /// 서버가 보낸
    ///   KAKAO_REST_API_KEY or NAVER_CLIENT_ID/NAVER_CLIENT_SECRET is required
    /// 같은 영문 환경변수 이름이 사용자 화면에 닿을 수 있었습니다.
    /// 키를 확인하라는 말을 들어야 하는 사람은 사용자가 아니라 저희입니다.
    ///
    /// 지금은 사용자 문구를 만들지 않습니다. 원인은 로그로 보내고,
    /// 화면 문구는 PhotoSpotSearchError 가 혼자 정합니다.
    static func serverError(from data: Data, statusCode: Int) -> PhotoSpotSearchError {
        let diagnostic = (try? JSONDecoder().decode(ErrorBody.self, from: data).error)
            ?? String(data: data.prefix(200), encoding: .utf8)
            ?? "no body"
        let error = PhotoSpotSearchError.server(statusCode: statusCode, diagnostic: diagnostic)
        AppLog.network.error("Place backend failed: \(error.diagnosticDescription, privacy: .public)")
        return error
    }
}

struct PlaceSearchService {
    private struct RequestBody: Encodable {
        struct UserLocationPayload: Encodable {
            let latitude: Double
            let longitude: Double
        }

        let query: String
        let userLocation: UserLocationPayload?
    }

    private struct ResponseBody: Decodable {
        let spots: [VerifiedPhotoSpot]
    }

    private struct ErrorBody: Decodable {
        let error: String
        let code: String?
    }

    func search(
        query: String,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> [VerifiedPhotoSpot] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        return try await searchServer(
            query: trimmedQuery,
            userLocation: userLocation
        )
    }

    private func searchServer(
        query: String,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> [VerifiedPhotoSpot] {
        guard let endpointURL else {
            throw PhotoSpotSearchError.notConfigured
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                query: query,
                userLocation: userLocation.map {
                    RequestBody.UserLocationPayload(latitude: $0.latitude, longitude: $0.longitude)
                }
            )
        )

        let (data, response) = try await BackendClient.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoSpotSearchError.malformedResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data)

            // 서버가 네이버 키 없이 떠 있는 상태입니다. 다시 시도해도 같습니다.
            // 사용자에게는 "지금은 쓸 수 없다" 로 전달되어야 하고,
            // 키가 없다는 사실은 로그로 갑니다.
            if errorBody?.code == "naver_place_search_unconfigured" {
                AppLog.network.error("Place search backend is missing Naver credentials")
                throw PhotoSpotSearchError.notConfigured
            }

            throw PlaceVerificationService.serverError(from: data, statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data).spots
    }

    private var endpointURL: URL? {
        AppBackendConfiguration.current.endpoint(named: "search-places")
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - 공용 장소 검색기
//
//  [문제였던 상황]
//  검색 진입점이 세 곳인데 서로 다른 것을 찾고 있었습니다.
//
//    제보 화면  PlaceSearchService(네이버 실제 장소검색) + 로컬 시드
//               -> 앱에 없는 장소도 찾습니다.
//    지도 검색  앱이 아는 장소만 필터
//               -> "강릉 경포대" 를 찾을 수 없습니다.
//    홈 검색    앱이 아는 장소 + AI 추천
//
//  같은 앱에서 같은 말을 입력했는데 화면마다 다른 결과가 나왔습니다.
//  사용자에게는 "이 앱은 어디까지 아는가" 가 예측 불가능해집니다.
//
//  [이 타입의 역할]
//  세 화면이 같은 방식으로 장소를 찾게 합니다.
//
//    1) 로컬을 먼저, 즉시.
//       LocalSeedDataService 는 static 캐시라 키 입력마다 호출해도
//       131곳 필터링뿐입니다. 네트워크를 기다리는 동안 화면이
//       비어 있지 않게 합니다.
//    2) 원격은 입력이 멈춘 뒤 한 번만.
//       키 입력마다 서버를 때리지 않기 위해 디바운스합니다.
//    3) 로컬을 원격보다 앞에 둡니다.
//       우리가 큐레이션한 장소가 먼저 와야 합니다.
//
//  원격 검색이 실패해도 로컬 결과가 있으면 오류를 알리지 않습니다.
//  사용자는 이미 고를 수 있는 목록을 보고 있고, 그 상황에서
//  오류 문구는 소음입니다.
// ═══════════════════════════════════════════════════════════════════

struct PlaceSearchResult: Identifiable, Equatable {
    let spot: PhotoSpot
    /// 네이버 지역 검색의 장소 분류. 로컬 결과는 앱 태그를 보조로 표시합니다.
    let category: String
    let address: String
    /// 검색 결과가 새 제보로 이어질 수 있는지 나타냅니다.
    let availability: PlaceSubmissionAvailability

    var id: String { spot.id }
    var name: String { spot.name }
    var isKnown: Bool { availability == .registered }
}

@MainActor
final class PlaceFinder: ObservableObject {
    private struct RemoteSearchCacheEntry {
        let spots: [VerifiedPhotoSpot]
        let storedAt: Date
    }

    private static let remoteSearchCacheTTL: TimeInterval = 2 * 60
    private static let remoteSearchCacheLimit = 20
    private static var remoteSearchCache: [String: RemoteSearchCacheEntry] = [:]

    @Published private(set) var results: [PlaceSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasNoResults = false
    @Published private(set) var message: String?

    /// 한 번에 보여줄 결과 개수.
    /// 지도는 패널이 스크롤되므로 넉넉하게, 제보 폼은 인라인 목록이라
    /// 길어지면 아래 섹션이 화면 밖으로 밀려나므로 적게 씁니다.
    let resultLimit: Int
    /// 한 글자로는 결과가 너무 많아 의미가 없습니다.
    var minimumQueryLength = 2
    /// 입력이 멈춘 것으로 볼 시간.
    var debounceNanoseconds: UInt64 = 350_000_000

    private let placeSearchService = PlaceSearchService()
    private let localSeed = LocalSeedDataService()
    private var task: Task<Void, Never>?

    init(resultLimit: Int = 8) {
        self.resultLimit = resultLimit
    }

    deinit {
        task?.cancel()
    }

    func clear() {
        task?.cancel()
        results = []
        hasNoResults = false
        message = nil
        isSearching = false
    }

    /// - Parameters:
    ///   - knownSpots: 앱이 이미 아는 장소. 시드 외에 AI 추천·저장분까지
    ///     넘기면 그쪽이 먼저 노출됩니다.
    func search(
        _ rawQuery: String,
        near userLocation: CLLocationCoordinate2D?,
        knownSpots: [PhotoSpot]
    ) {
        task?.cancel()

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard query.count >= minimumQueryLength else {
            results = []
            hasNoResults = false
            message = nil
            isSearching = false
            return
        }

        let localResults = localMatches(
            for: query,
            in: knownSpots
        )
        results = Array(localResults.prefix(resultLimit))
        hasNoResults = false
        message = nil
        isSearching = true

        let requestKey = Self.requestKey(query: query, userLocation: userLocation)
        if let cachedRemoteSpots = Self.cachedRemoteSpots(for: requestKey) {
            let remoteResults = Self.placeSearchResults(
                from: cachedRemoteSpots,
                knownSpots: knownSpots
            )
            let merged = Self.deduplicated(localResults + remoteResults)
            results = Array(merged.prefix(resultLimit))
            hasNoResults = merged.isEmpty
            isSearching = false
            return
        }

        task = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            guard !Task.isCancelled else { return }

            do {
                let remote = try await self.placeSearchService.search(
                    query: query,
                    userLocation: userLocation
                )
                guard !Task.isCancelled else { return }

                Self.storeRemoteSpots(remote, for: requestKey)
                let remoteResults = Self.placeSearchResults(
                    from: remote,
                    knownSpots: knownSpots
                )

                let merged = Self.deduplicated(localResults + remoteResults)

                self.results = Array(merged.prefix(self.resultLimit))
                self.hasNoResults = merged.isEmpty
                self.message = nil
                self.isSearching = false
            } catch {
                guard !Task.isCancelled else { return }

                // 로컬 결과가 있으면 원격 실패를 알리지 않습니다.
                self.hasNoResults = false
                self.message = localResults.isEmpty ? Self.failureMessage(for: error) : nil
                self.isSearching = false
            }
        }
    }

    // MARK: 로컬

    private func localMatches(
        for query: String,
        in knownSpots: [PhotoSpot]
    ) -> [PlaceSearchResult] {
        let fromKnown = knownSpots
            .filter { spot in
                let fields = [spot.name, spot.region, spot.mapQuery] + spot.recommendationRegions
                return fields.contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .map {
                PlaceSearchResult(
                    spot: $0,
                    category: Self.localCategory(for: $0),
                    address: $0.region,
                    availability: .registered
                )
            }

        // 시드 조회도 함께 씁니다. verifiedSpots 는 위 필터가 보지 않는
        // 필드(설명·태그)까지 훑기 때문에 놓치는 장소가 줄어듭니다.
        //
        // 단, 블랙리스트를 다시 적용합니다.
        // 호출부가 넘기는 knownSpots(selectableSpots)는 이미 블랙리스트를
        // 걸러낸 목록인데, 시드를 직접 조회하면 그 필터를 우회해서
        // 제외했던 장소가 검색 결과로 되살아납니다.
        let fromSeed = localSeed
            .verifiedSpots(matching: query, limit: resultLimit)
            .map(\.photoSpot)
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
            .map {
                PlaceSearchResult(
                    spot: $0,
                    category: Self.localCategory(for: $0),
                    address: $0.region,
                    availability: .registered
                )
            }

        return Self.deduplicated(fromKnown + fromSeed)
    }

    // MARK: 중복 제거

    private static func placeSearchResults(
        from remoteSpots: [VerifiedPhotoSpot],
        knownSpots: [PhotoSpot]
    ) -> [PlaceSearchResult] {
        remoteSpots.map {
            let remoteSpot = $0.photoSpot
            let availability = availability(for: remoteSpot, knownSpots: knownSpots)
            let displaySpot = availability == .registered
                ? registeredSpot(matching: remoteSpot, in: knownSpots) ?? remoteSpot
                : remoteSpot

            return PlaceSearchResult(
                spot: displaySpot,
                category: $0.displayCategory,
                address: $0.address,
                availability: availability
            )
        }
    }

    private static func requestKey(
        query: String,
        userLocation: CLLocationCoordinate2D?
    ) -> String {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let userLocation else { return "\(normalizedQuery)|none" }

        // 약 1km 단위로 묶어 같은 검색 세션의 미세한 GPS 흔들림이
        // 동일 요청을 다시 만들지 않게 합니다.
        let latitude = Int((userLocation.latitude * 100).rounded())
        let longitude = Int((userLocation.longitude * 100).rounded())
        return "\(normalizedQuery)|\(latitude)|\(longitude)"
    }

    private static func cachedRemoteSpots(for key: String) -> [VerifiedPhotoSpot]? {
        guard let entry = remoteSearchCache[key] else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) <= remoteSearchCacheTTL else {
            remoteSearchCache[key] = nil
            return nil
        }
        return entry.spots
    }

    private static func storeRemoteSpots(_ spots: [VerifiedPhotoSpot], for key: String) {
        remoteSearchCache[key] = RemoteSearchCacheEntry(spots: spots, storedAt: Date())

        if remoteSearchCache.count > remoteSearchCacheLimit,
           let oldestKey = remoteSearchCache.min(by: {
               $0.value.storedAt < $1.value.storedAt
           })?.key {
            remoteSearchCache[oldestKey] = nil
        }
    }

    /// 같은 장소가 로컬과 원격에서 각각 올라오므로 공통 장소 식별자로 접습니다.
    /// 등록된 장소 결과가 새 장소 결과보다 우선합니다.
    private static func deduplicated(_ values: [PlaceSearchResult]) -> [PlaceSearchResult] {
        values.reduce(into: [PlaceSearchResult]()) { merged, result in
            guard let existingIndex = merged.firstIndex(where: {
                PlaceIdentityMatcher.matches(
                    PlaceIdentity(spot: $0.spot),
                    PlaceIdentity(spot: result.spot)
                )
            }) else {
                merged.append(result)
                return
            }

            if priority(result.availability) > priority(merged[existingIndex].availability) {
                merged[existingIndex] = result
            }
        }
    }

    private static func availability(
        for spot: PhotoSpot,
        knownSpots: [PhotoSpot]
    ) -> PlaceSubmissionAvailability {
        if knownSpots.contains(where: {
            PlaceIdentityMatcher.matches(
                PlaceIdentity(spot: spot),
                PlaceIdentity(spot: $0)
            )
        }) {
            return .registered
        }

        return .new
    }

    private static func registeredSpot(matching candidate: PhotoSpot, in knownSpots: [PhotoSpot]) -> PhotoSpot? {
        knownSpots.first {
            PlaceIdentityMatcher.matches(
                PlaceIdentity(spot: candidate),
                PlaceIdentity(spot: $0)
            )
        }
    }

    private static func priority(_ availability: PlaceSubmissionAvailability) -> Int {
        switch availability {
        case .new:
            return 0
        case .registered:
            return 1
        }
    }

    private static func localCategory(for spot: PhotoSpot) -> String {
        let tags = spot.hashtags
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let label = tags.prefix(2).joined(separator: " · ")
        return label.isEmpty ? "등록된 출사지" : label
    }

    /// 원격 검색이 실패했을 때 사용자에게 할 말.
    ///
    /// "문제가 생겼어요, 잠시 후 다시 시도해주세요" 라고 쓰고 있었는데
    /// 두 가지가 잘못됐습니다.
    ///  1. 앱이 고장난 것처럼 읽힙니다. 실제로는 등록된 출사지 검색이
    ///     정상 동작했고, 실제 장소 검색만 닿지 않은 것입니다.
    ///  2. "잠시 후 다시 시도" 가 거짓일 수 있습니다. 서버 주소가
    ///     설정되지 않았거나 서버가 꺼져 있으면 다시 시도해도 같습니다.
    ///
    /// 무엇을 찾았는지를 먼저 말하고, 닿지 않은 범위를 설명합니다.
    ///
    /// 서버가 준 문자열은 여기서 쓰지 않습니다.
    /// 전에는 .server(let message) 에서 그 message 를 그대로 돌려줬고,
    /// 그 값이 서버 응답의 error 필드였습니다. 그래서
    ///   KAKAO_REST_API_KEY or NAVER_CLIENT_ID/... is required
    /// 같은 영문 환경변수 이름이 사용자에게 표시될 수 있었습니다.
    /// 지금은 PhotoSpotSearchError 가 문자열을 들고 있지 않으므로
    /// 그런 실수를 하려고 해도 할 수 없습니다.
    private static func failureMessage(for error: Error) -> String {
        if let searchError = error as? PhotoSpotSearchError {
            switch searchError {
            case .notConfigured:
                // 다시 시도를 권하지 않습니다. 주소가 없는 상태는
                // 몇 번을 해도 같습니다.
                return "등록된 출사지에서만 찾았어요. 장소 검색은 아직 준비 중이에요."
            case .server, .malformedResponse:
                return "등록된 출사지에서만 찾았어요. 잠시 후 다시 시도해주세요."
            case .empty:
                return "장소 이름에 지역을 함께 넣어보세요."
            }
        }

        // URLError. 서버가 꺼져 있거나 같은 네트워크에 없을 때입니다.
        if error is URLError {
            return "등록된 출사지에서만 찾았어요. 장소 검색에 연결할 수 없어요."
        }

        return "장소 이름에 지역을 함께 넣어보세요."
    }
}

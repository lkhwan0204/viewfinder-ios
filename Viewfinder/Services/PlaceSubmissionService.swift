import Combine
import Foundation

enum PlaceSubmissionError: LocalizedError, Equatable {
    case duplicate

    var errorDescription: String? {
        "이미 등록된 장소예요. 장소 상세에서 확인해주세요."
    }
}

struct PlaceSubmissionReceipt: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let submittedAt: String
    let alreadyApproved: Bool
    /// 이전 UserDefaults receipt와의 호환을 위한 중복 검사 보조 정보입니다.
    var region: String? = nil
    var mapQuery: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var provider: String? = nil
    var providerPlaceID: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id, name, submittedAt, alreadyApproved
        case region, mapQuery, latitude, longitude, provider, providerPlaceID
    }

    var confirmationMessage: String {
        if alreadyApproved {
            return "이미 공개된 장소예요. 홈, 지도, 검색에서 바로 확인할 수 있어요."
        }

        return "장소가 바로 공개됐어요. 홈, 지도, 검색에서 확인할 수 있어요."
    }

    init(
        id: String,
        name: String,
        submittedAt: String,
        alreadyApproved: Bool,
        region: String? = nil,
        mapQuery: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        provider: String? = nil,
        providerPlaceID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.submittedAt = submittedAt
        self.alreadyApproved = alreadyApproved
        self.region = region
        self.mapQuery = mapQuery
        self.latitude = latitude
        self.longitude = longitude
        self.provider = provider
        self.providerPlaceID = providerPlaceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt) ?? ""
        alreadyApproved = try container.decodeIfPresent(Bool.self, forKey: .alreadyApproved) ?? false
        region = try container.decodeIfPresent(String.self, forKey: .region)
        mapQuery = try container.decodeIfPresent(String.self, forKey: .mapQuery)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerPlaceID = try container.decodeIfPresent(String.self, forKey: .providerPlaceID)
        // 과거 receipt의 status 키는 의도적으로 읽지 않습니다.
        // 현재부터 장소 제보는 모두 공개 상태이며, 기존 receipt도 공개된
        // 장소로 표시해 이전 상태 안내가 다시 나타나지 않게 합니다.
    }
}

struct PlaceSubmissionResult {
    let receipt: PlaceSubmissionReceipt
    let publishedSpot: PhotoSpot
}

@MainActor
final class PlaceSubmissionStore: ObservableObject {
    @Published private(set) var receipts: [PlaceSubmissionReceipt]

    private let defaults: UserDefaults
    private let storageKey = "viewfinder.placeSubmissionReceipts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let receipts = try? JSONDecoder().decode([PlaceSubmissionReceipt].self, from: data) {
            self.receipts = receipts
            // 예전 status 필드를 제외한 현재 receipt 형식으로 즉시 저장해
            // 다음 실행에도 이전 공개 상태 값이 남지 않게 합니다.
            if let normalizedData = try? JSONEncoder().encode(receipts) {
                defaults.set(normalizedData, forKey: storageKey)
            }
        } else {
            self.receipts = []
        }
    }

    func record(_ receipt: PlaceSubmissionReceipt) {
        receipts.removeAll { $0.id == receipt.id }
        receipts.insert(receipt, at: 0)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct PlaceSubmissionService {
    /// 장소 제보는 대표 사진을 최대 5장까지 받습니다.
    /// Community 게시글의 기존 8장 제한과는 별개의 장소 제보 제한입니다.
    static let maxPhotoCount = 5

    private struct KnownPlace: Encodable {
        let id: String
        let name: String
        let region: String
        let mapQuery: String
        let latitude: Double
        let longitude: Double
        let provider: String?
        let providerPlaceID: String?
    }

    private struct RequestBody: Encodable {
        let id: String
        let name: String
        let region: String
        let summary: String
        let tags: [String]
        let mapQuery: String
        let latitude: Double
        let longitude: Double
        let category: String
        let imageURL: String?
        let photoDataBase64: String?
        let photoDataBase64s: [String]?
        let submittedByID: String
        let submittedByName: String
        let submittedAt: String
        let provider: String?
        let providerPlaceID: String?
        let knownPlaces: [KnownPlace]
    }

    private struct SubmittedSpotsResponse: Decodable {
        let spots: [SubmittedSpot]
    }

    private struct SubmissionResponse: Decodable {
        let spot: SubmittedSpot
        let alreadyApproved: Bool?
    }

    private struct SubmittedSpot: Decodable {
        let id: String
        let name: String
        let region: String
        let summary: String
        let tags: [String]
        let mapQuery: String
        let latitude: Double
        let longitude: Double
        let category: String
        let imageURL: String?
        let photoURLs: [String]?
        let submittedAt: String?
        let provider: String?
        let providerPlaceID: String?

        var photoSpot: PhotoSpot {
            let normalizedTags = tags.reduce(into: [String]()) { result, tag in
                let normalized = Self.normalizedTag(tag)
                guard !normalized.isEmpty,
                      !result.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else {
                    return
                }
                result.append(normalized)
            }

            // 다중 사진 응답의 첫 URL을 대표 사진으로도 사용해
            // `/photo`와 `/photo/0`가 같은 이미지를 두 번 세지 않게 합니다.
            let resolvedImageURL = photoURLs?.compactMap(URL.init(string:)).first
                ?? imageURL.flatMap(URL.init(string:))
            let galleryPhotos = (photoURLs ?? [imageURL].compactMap { $0 })
                .compactMap(URL.init(string:))
                .enumerated()
                .map { index, url in
                    PlacePhoto(
                        id: "submission-\(id)-\(index)",
                        placeID: id,
                        imageURL: url,
                        uploaderID: nil,
                        uploaderName: nil,
                        createdAt: submittedAt.flatMap(Self.date(from:)),
                        source: .placeSubmission
                    )
                }

            return PhotoSpot(
                id: id,
                name: name,
                region: region,
                summary: summary.isEmpty ? "사용자가 추가한 출사지예요." : summary,
                hashtags: normalizedTags,
                eventTitle: "사용자 추가 장소",
                eventPeriod: "상시",
                feeInfo: "확인 필요",
                openingHours: "운영 정보 확인 필요",
                bestTime: "현장 상황에 따라 확인",
                crowdLevel: "현장 정보 확인 필요",
                lensSuggestion: "표준 줌 또는 선호 화각",
                weatherFit: "날씨에 맞춰 확인",
                parkingInfo: "주차 정보 확인 필요",
                nearbyParkingInfo: "근처 주차장 확인 필요",
                communityTitle: "사용자 추가 장소",
                communitySubtitle: summary,
                mapQuery: mapQuery,
                latitude: latitude,
                longitude: longitude,
                theme: SpotTheme.resolve(
                    legacyValue: category,
                    name: name,
                    description: summary,
                    tags: normalizedTags,
                    category: category
                ),
                imageURL: resolvedImageURL,
                category: category,
                mood: normalizedTags,
                imageName: nil,
                imageCredit: resolvedImageURL == nil ? nil : "Viewfinder 사용자 제보",
                imageLicense: resolvedImageURL == nil ? nil : "업로더 제공",
                imageSourceURL: nil,
                provider: provider,
                providerPlaceID: providerPlaceID,
                galleryPhotos: galleryPhotos
            )
        }

        private static func date(from value: String) -> Date? {
            return ISO8601DateFormatter().date(from: value)
        }

        private static func normalizedTag(_ value: String) -> String {
            var tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            while tag.hasPrefix("#") {
                tag.removeFirst()
            }
            return tag
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
        }
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    func submit(
        spot: PhotoSpot,
        tags: [String],
        photoData: Data?,
        submitter: AuthUser,
        registeredSpots: [PhotoSpot] = [],
        photoDatas: [Data] = []
    ) async throws -> PlaceSubmissionResult {
        guard let endpointURL else {
            throw PhotoSpotSearchError.notConfigured
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let photos = photoDatas.isEmpty
            ? photoData.map { [$0] } ?? []
            : photoDatas
        let encodedPhotos = Array(
            photos
                .prefix(Self.maxPhotoCount)
                .map { $0.base64EncodedString() }
        )
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                id: spot.id,
                name: spot.name,
                region: spot.region,
                summary: spot.summary,
                tags: tags.isEmpty ? spot.hashtags : tags,
                mapQuery: spot.mapQuery,
                latitude: spot.latitude,
                longitude: spot.longitude,
                category: spot.category,
                imageURL: spot.imageURL?.absoluteString,
                photoDataBase64: encodedPhotos.first,
                photoDataBase64s: encodedPhotos.isEmpty ? nil : encodedPhotos,
                submittedByID: submitter.id,
                submittedByName: submitter.displayName,
                submittedAt: ISO8601DateFormatter().string(from: Date()),
                provider: spot.provider,
                providerPlaceID: spot.providerPlaceID,
                knownPlaces: registeredSpots.map {
                    KnownPlace(
                        id: $0.id,
                        name: $0.name,
                        region: $0.region,
                        mapQuery: $0.mapQuery,
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        provider: $0.provider,
                        providerPlaceID: $0.providerPlaceID
                    )
                }
            )
        )

        let (data, response) = try await BackendClient.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoSpotSearchError.malformedResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 409 {
                throw PlaceSubmissionError.duplicate
            }
            throw PlaceVerificationService.serverError(from: data, statusCode: httpResponse.statusCode)
        }

        let submission = try JSONDecoder().decode(SubmissionResponse.self, from: data)

        let receipt = PlaceSubmissionReceipt(
            id: submission.spot.id,
            name: submission.spot.name,
            submittedAt: submission.spot.submittedAt ?? ISO8601DateFormatter().string(from: Date()),
            alreadyApproved: submission.alreadyApproved ?? false,
            region: submission.spot.region,
            mapQuery: submission.spot.mapQuery,
            latitude: submission.spot.latitude,
            longitude: submission.spot.longitude,
            provider: submission.spot.provider,
            providerPlaceID: submission.spot.providerPlaceID
        )

        return PlaceSubmissionResult(
            receipt: receipt,
            publishedSpot: submission.spot.photoSpot
        )
    }

    func fetchSubmittedSpots() async throws -> [PhotoSpot] {
        guard let endpointURL else {
            throw PhotoSpotSearchError.notConfigured
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 4

        let (data, response) = try await BackendClient.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoSpotSearchError.malformedResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw PlaceVerificationService.serverError(from: data, statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder()
            .decode(SubmittedSpotsResponse.self, from: data)
            .spots
            .map(\.photoSpot)
    }

    private var endpointURL: URL? {
        AppBackendConfiguration.current.endpoint(named: "submitted-spots")
    }
}

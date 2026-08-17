import Combine
import Foundation

enum PlaceSubmissionStatus: String, Codable, Equatable {
    case pendingReview = "pending_review"
    case approved
    case rejected

    var title: String {
        switch self {
        case .pendingReview:
            return "검토 중"
        case .approved:
            return "공개됨"
        case .rejected:
            return "보완 필요"
        }
    }

    var detail: String {
        switch self {
        case .pendingReview:
            return "검토가 끝나면 홈, 지도, 검색에 공개돼요"
        case .approved:
            return "홈, 지도, 검색에 공개됐어요"
        case .rejected:
            return "등록 정보를 확인한 뒤 다시 제보할 수 있어요"
        }
    }
}

struct PlaceSubmissionReceipt: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var status: PlaceSubmissionStatus
    let submittedAt: String
    let alreadyApproved: Bool

    var confirmationMessage: String {
        alreadyApproved
            ? "이미 공개된 장소예요. 홈, 지도, 검색에서 바로 확인할 수 있어요."
            : "사진 권리와 장소 정보를 확인한 뒤 홈, 지도, 검색에 공개됩니다."
    }
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
        } else {
            self.receipts = []
        }
    }

    func record(_ receipt: PlaceSubmissionReceipt) {
        receipts.removeAll { $0.id == receipt.id }
        receipts.insert(receipt, at: 0)
        persist()
    }

    func markApproved(spotIDs: Set<String>) {
        var didChange = false

        for index in receipts.indices where spotIDs.contains(receipts[index].id) {
            guard receipts[index].status != .approved else { continue }
            receipts[index].status = .approved
            didChange = true
        }

        if didChange {
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct PlaceSubmissionService {
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
        let submittedByID: String
        let submittedByName: String
        let submittedAt: String
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
        let status: String?
        let submittedAt: String?

        var photoSpot: PhotoSpot {
            let normalizedTags = tags.reduce(into: [String]()) { result, tag in
                let normalized = Self.normalizedTag(tag)
                guard !normalized.isEmpty,
                      !result.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else {
                    return
                }
                result.append(normalized)
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
                theme: SpotTheme(rawValue: category) ?? .city,
                imageURL: imageURL.flatMap(URL.init(string:)),
                category: category,
                mood: normalizedTags,
                imageName: nil,
                imageCredit: imageURL == nil ? nil : "Viewfinder 사용자 제보",
                imageLicense: imageURL == nil ? nil : "업로더 제공",
                imageSourceURL: nil
            )
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
        submitter: AuthUser
    ) async throws -> PlaceSubmissionReceipt {
        guard let endpointURL else {
            throw PhotoSpotSearchError.notConfigured
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                photoDataBase64: photoData?.base64EncodedString(),
                submittedByID: submitter.id,
                submittedByName: submitter.displayName,
                submittedAt: ISO8601DateFormatter().string(from: Date())
            )
        )

        let (data, response) = try await BackendClient.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoSpotSearchError.malformedResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw PlaceVerificationService.serverError(from: data, statusCode: httpResponse.statusCode)
        }

        let submission = try JSONDecoder().decode(SubmissionResponse.self, from: data)
        let status = PlaceSubmissionStatus(rawValue: submission.spot.status ?? "pending_review")
            ?? .pendingReview

        return PlaceSubmissionReceipt(
            id: submission.spot.id,
            name: submission.spot.name,
            status: status,
            submittedAt: submission.spot.submittedAt ?? ISO8601DateFormatter().string(from: Date()),
            alreadyApproved: submission.alreadyApproved ?? false
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

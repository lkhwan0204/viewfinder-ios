import Combine
import Foundation

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

    func remove(id: String) {
        receipts.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

enum PlaceSubmissionService {
    /// 장소 제보 사진의 선택 UI 제한입니다. Storage 업로드는 별도 작업입니다.
    static let maxPhotoCount = 5
}

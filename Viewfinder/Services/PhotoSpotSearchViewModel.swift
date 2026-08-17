import CoreLocation
import Foundation

// ═══════════════════════════════════════════════════════════════════
//  홈 검색 결과 화면의 상태.
//
//  [정리 전 상태]
//  이 뷰모델은 AI 검색을 하는 척하고 있었습니다.
//   - geminiService 와 verificationService 를 생성해서 들고 있었지만
//     어떤 메서드에서도 호출하지 않았습니다.
//   - requestAIRecommendations(userLocation:) 의 본문은
//     canRequestAI = false 한 줄이었습니다.
//   - recommendations 는 항상 빈 배열이었습니다.
//   - state 에 loadingAI 가 있었지만 아무도 그 값을 넣지 않았습니다.
//     그래서 isAIRequestRunning 은 항상 false 였습니다.
//
//  그런데 검색 결과가 없을 때 나오는 화면에는 "AI로 추천 받기" 버튼이
//  있었고, 그 버튼이 위의 빈 함수를 불렀습니다. 사용자가 누르면 아무
//  일도 일어나지 않습니다. 이것이 가장 나쁜 종류의 죽은 코드입니다.
//  코드가 안 쓰이는 것에서 끝나지 않고 사용자에게 거짓 약속을 합니다.
//
//  [정리 후]
//  이 뷰모델이 하는 일은 하나입니다.
//  앱에 등록된 출사지에서 검색어와 맞는 것을 찾습니다.
//
//  실제 장소(네이버 지도 데이터) 검색은 PlaceFinder 가 따로 합니다.
//  홈·지도·커뮤니티 세 곳이 같은 PlaceFinder 를 씁니다.
// ═══════════════════════════════════════════════════════════════════

@MainActor
final class PhotoSpotSearchViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published var searchText = ""
    @Published private(set) var verifiedSpots: [VerifiedPhotoSpot] = []
    @Published private(set) var state: State = .idle

    private let localSeedDataService: LocalSeedDataService
    private let cacheService: PhotoSpotCacheService

    init(
        localSeedDataService: LocalSeedDataService = LocalSeedDataService(),
        cacheService: PhotoSpotCacheService = PhotoSpotCacheService()
    ) {
        self.localSeedDataService = localSeedDataService
        self.cacheService = cacheService
    }

    var isLoading: Bool {
        state == .loading
    }

    /// 검색 결과 아래에 나오는 한 줄.
    ///
    /// 문구에서 내부 사정을 뺐습니다.
    /// 전에는 "앱 안의 기본 출사지 데이터에서 찾는 중이에요" 와
    /// "AI 후보를 만들고 장소검색 API로 검증 중이에요" 였습니다.
    /// 사용자는 데이터가 앱 안에 있는지 서버에 있는지, 어떤 API 를
    /// 쓰는지 알 필요가 없습니다. 찾고 있다는 것만 알면 됩니다.
    var message: String? {
        switch state {
        case .idle, .loaded:
            return nil
        case .loading:
            return "출사지를 찾고 있어요"
        case .empty:
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty
                ? "찾는 출사지를 입력해보세요"
                : "'\(query)' 와 맞는 출사지가 아직 없어요"
        case .failed(let message):
            return message
        }
    }

    func search(userLocation: CLLocationCoordinate2D?) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            state = .idle
            verifiedSpots = []
            return
        }

        state = .loading

        let localSpots = localSeedDataService.verifiedSpots(matching: query)
        verifiedSpots = mergedSpots(localSpots)
        state = verifiedSpots.isEmpty ? .empty : .loaded
    }

    func clear() {
        searchText = ""
        verifiedSpots = []
        state = .idle
    }

    private func mergedSpots(_ spots: [VerifiedPhotoSpot]) -> [VerifiedPhotoSpot] {
        spots.reduce(into: [VerifiedPhotoSpot]()) { result, spot in
            let normalizedKey = "\(spot.name)-\(spot.address)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !result.contains(where: {
                $0.id == spot.id || "\($0.name)-\($0.address)".lowercased() == normalizedKey
            }) else { return }

            result.append(spot)
        }
    }
}

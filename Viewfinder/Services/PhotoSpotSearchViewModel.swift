import CoreLocation
import Foundation

@MainActor
final class PhotoSpotSearchViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loadingAI
        case loaded
        case empty
        case failed(String)
    }

    @Published var searchText = ""
    @Published private(set) var recommendations: [PhotoSpotRecommendation] = []
    @Published private(set) var verifiedSpots: [VerifiedPhotoSpot] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var canRequestAI = false

    private let localSeedDataService: LocalSeedDataService
    private let cacheService: PhotoSpotCacheService
    private let geminiService: GeminiRecommendationService
    private let verificationService: PlaceVerificationService

    init(
        localSeedDataService: LocalSeedDataService = LocalSeedDataService(),
        cacheService: PhotoSpotCacheService = PhotoSpotCacheService(),
        geminiService: GeminiRecommendationService = GeminiRecommendationService(),
        verificationService: PlaceVerificationService = PlaceVerificationService()
    ) {
        self.localSeedDataService = localSeedDataService
        self.cacheService = cacheService
        self.geminiService = geminiService
        self.verificationService = verificationService
    }

    var isLoading: Bool {
        state == .loading || state == .loadingAI
    }

    var isAIRequestRunning: Bool {
        state == .loadingAI
    }

    var message: String? {
        switch state {
        case .idle:
            return nil
        case .loading:
            return "앱 안의 기본 출사지 데이터에서 찾는 중이에요"
        case .loadingAI:
            return "AI 후보를 만들고 장소검색 API로 검증 중이에요"
        case .loaded:
            return nil
        case .empty:
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty ? "출사지 데이터가 아직 부족해요." : "\(query) 출사지 데이터가 아직 부족해요."
        case .failed(let message):
            return message
        }
    }

    func search(userLocation: CLLocationCoordinate2D?) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            state = .idle
            recommendations = []
            verifiedSpots = []
            canRequestAI = false
            return
        }

        state = .loading
        recommendations = []
        canRequestAI = false

        let localSpots = localSeedDataService.verifiedSpots(matching: query)
        verifiedSpots = mergedSpots(localSpots)
        state = verifiedSpots.isEmpty ? .empty : .loaded
    }

    func requestAIRecommendations(userLocation: CLLocationCoordinate2D?) async {
        canRequestAI = false
    }

    func clear() {
        searchText = ""
        recommendations = []
        verifiedSpots = []
        state = .idle
        canRequestAI = false
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

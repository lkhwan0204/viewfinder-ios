import CoreLocation
import Foundation

@MainActor
final class HomeRecommendationsViewModel: ObservableObject {
    @Published private(set) var todayRecommendations: [GPTRecommendedSpot] = []
    @Published private(set) var sectionRecommendations: [HomeRecommendationKind: [GPTRecommendedSpot]] = [:]
    @Published private(set) var expandedSectionRecommendations: [HomeRecommendationKind: [GPTRecommendedSpot]] = [:]
    @Published private(set) var refreshState: AsyncLoadState = .idle

    private let service: HomeRecommendationService
    private var communityPosts: [CommunityPost] = []
    private var userLocation: CLLocationCoordinate2D?
    private var weatherContext: RecommendationWeatherContext?
    private var lastGeneratedLocation: CLLocationCoordinate2D?
    private let locationRefreshThresholdMeters: CLLocationDistance = 1_500
    private var hasGeneratedInitialSnapshot = false
    private var recommendationVariation = 0
    private var requestedGeneration = 0
    private var appliedGeneration = 0
    private var generationTask: Task<Void, Never>?
    private var generationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(service: HomeRecommendationService = HomeRecommendationService()) {
        self.service = service
    }

    func prepareIfNeeded() {
        guard !hasGeneratedInitialSnapshot else { return }
        hasGeneratedInitialSnapshot = true
        requestGeneration()
    }

    var visibleSpots: [PhotoSpot] {
        let sectionSpots = sectionRecommendations.values.flatMap { $0.map(\.spot) }
        return (todayRecommendations.map(\.spot) + sectionSpots).reduce(into: [PhotoSpot]()) { result, spot in
            guard !result.contains(where: { $0.id == spot.id }) else { return }
            result.append(spot)
        }
    }

    func updateCommunityContext(posts: [CommunityPost]) {
        guard communityPosts != posts else { return }
        communityPosts = posts
        requestGeneration()
    }

    func updateLocationContext(userLocation: CLLocationCoordinate2D?) {
        guard shouldRefreshRecommendations(for: userLocation) else {
            return
        }

        self.userLocation = userLocation
        requestGeneration()
    }

    func updateWeatherContext(_ context: RecommendationWeatherContext?) {
        guard weatherContext != context else { return }
        weatherContext = context
        requestGeneration()
    }

    @MainActor
    func refresh() async {
        guard !refreshState.isLoading else { return }
        refreshState = .loading
        recommendationVariation &+= 1
        let generation = requestGeneration()
        await waitUntilApplied(generation)
        refreshState = .loaded
    }

    @discardableResult
    private func requestGeneration() -> Int {
        requestedGeneration &+= 1
        startGenerationIfNeeded()
        return requestedGeneration
    }

    private func startGenerationIfNeeded() {
        guard generationTask == nil else { return }

        let generation = requestedGeneration
        let service = service
        let communityPosts = communityPosts
        let userLocation = userLocation
        let weatherContext = weatherContext
        let variationSeed = recommendationVariation

        generationTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                service.makeSnapshot(
                    communityPosts: communityPosts,
                    userLocation: userLocation,
                    weatherContext: weatherContext,
                    referenceDate: Date(),
                    variationSeed: variationSeed
                )
            }.value

            guard let self else { return }
            generationTask = nil

            if generation == requestedGeneration {
                apply(snapshot, generation: generation)
            } else {
                startGenerationIfNeeded()
            }
        }
    }

    private func apply(_ snapshot: HomeRecommendationSnapshot, generation: Int) {
        lastGeneratedLocation = userLocation
        todayRecommendations = snapshot.todayRecommendations
        sectionRecommendations = snapshot.sections
        expandedSectionRecommendations = snapshot.expandedSections
        appliedGeneration = generation
        resumeWaiters(upTo: generation)
    }

    private func waitUntilApplied(_ generation: Int) async {
        guard appliedGeneration < generation else { return }

        await withCheckedContinuation { continuation in
            generationWaiters[generation, default: []].append(continuation)
        }
    }

    private func resumeWaiters(upTo generation: Int) {
        let completedGenerations = generationWaiters.keys.filter { $0 <= generation }
        for completedGeneration in completedGenerations {
            generationWaiters.removeValue(forKey: completedGeneration)?.forEach {
                $0.resume()
            }
        }
    }

    private func shouldRefreshRecommendations(for newLocation: CLLocationCoordinate2D?) -> Bool {
        guard let newLocation else {
            return userLocation != nil
        }

        guard let lastGeneratedLocation else {
            return true
        }

        let old = CLLocation(latitude: lastGeneratedLocation.latitude, longitude: lastGeneratedLocation.longitude)
        let new = CLLocation(latitude: newLocation.latitude, longitude: newLocation.longitude)
        return new.distance(from: old) >= locationRefreshThresholdMeters
    }
}

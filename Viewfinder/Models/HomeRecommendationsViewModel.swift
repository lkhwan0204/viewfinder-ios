import CoreLocation
import Combine
import Foundation

enum HomeRecommendationState: Equatable {
    case initialLoading
    case loaded
    case refreshing
    case empty
    case locationUnavailable
    case failed(message: String)

    var isLoading: Bool {
        self == .initialLoading
    }

    var errorMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}

/// Home-only city-scale context. Map must keep its global catalog.
struct HomeGeographicContext: Equatable, Sendable {
    static let candidateRadiusMeters: CLLocationDistance = 50_000
    static let retentionRadiusMeters: CLLocationDistance = 30_000
    let latitudeBucket: Int
    let longitudeBucket: Int

    init(coordinate: CLLocationCoordinate2D) {
        latitudeBucket = Int((coordinate.latitude * 4).rounded())
        longitudeBucket = Int((coordinate.longitude * 4).rounded())
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(latitudeBucket) / 4, longitude: Double(longitudeBucket) / 4)
    }

    var key: String { "home-v2-50km-\(latitudeBucket)-\(longitudeBucket)" }

    func retains(_ location: CLLocationCoordinate2D) -> Bool {
        distance(to: location) <= Self.retentionRadiusMeters
    }

    func contains(_ spot: PhotoSpot) -> Bool {
        distance(to: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)) <= Self.candidateRadiusMeters
    }

    private func distance(to location: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: location.latitude, longitude: location.longitude))
    }
}

/// 홈 추천은 장소 ID와 추천 문구만 저장합니다.
/// 장소의 실제 데이터는 앱에 이미 있는 LocalSeedDataService에서 다시 풀기 때문에
/// 캐시가 오래되어도 장소 모델 전체를 복제하거나 영구적인 오래된 데이터를 만들지 않습니다.
private struct HomeRecommendationCache {
    var overrideFileURL: URL? = nil
    private struct CachedRecommendation: Codable {
        let spotID: String
        let reason: String
    }

    private struct CachedSection: Codable {
        let kind: String
        let recommendations: [CachedRecommendation]
    }

    private struct Payload: Codable {
        let contextKey: String
        let cachedAt: Date
        let todayRecommendations: [CachedRecommendation]
        let sections: [CachedSection]
        let expandedSections: [CachedSection]
    }

    /// 추천 규칙이나 장소 데이터가 바뀌었을 때도 오래된 홈이 계속 남지 않도록
    /// 캐시는 짧은 기간만 stale 상태로 허용합니다.
    private let maxAge: TimeInterval = 24 * 60 * 60

    private var fileURL: URL? {
        if let overrideFileURL { return overrideFileURL }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Viewfinder", isDirectory: true)
            .appendingPathComponent("home-recommendations.json")
    }

    func load(availableSpots: [PhotoSpot], contextKey: String, now: Date = Date()) -> HomeRecommendationSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let payload = decode(data),
              payload.contextKey == contextKey,
              now.timeIntervalSince(payload.cachedAt) >= 0,
              now.timeIntervalSince(payload.cachedAt) <= maxAge else {
            return nil
        }

        let spotsByID = Dictionary(availableSpots.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

        func resolve(_ cached: [CachedRecommendation]) -> [RecommendedSpot] {
            cached.compactMap { item in
                guard let spot = spotsByID[item.spotID] else { return nil }
                return RecommendedSpot(spot: spot, reason: item.reason)
            }
        }

        let sections = payload.sections.reduce(
            into: [HomeRecommendationKind: [RecommendedSpot]]()
        ) { result, section in
            guard let kind = HomeRecommendationKind(rawValue: section.kind) else { return }
            result[kind] = resolve(section.recommendations)
        }

        let expandedSections = payload.expandedSections.reduce(
            into: [HomeRecommendationKind: [RecommendedSpot]]()
        ) { result, section in
            guard let kind = HomeRecommendationKind(rawValue: section.kind) else { return }
            result[kind] = resolve(section.recommendations)
        }

        let snapshot = HomeRecommendationSnapshot(
            todayRecommendations: resolve(payload.todayRecommendations),
            sections: sections,
            expandedSections: expandedSections
        )

        return snapshot.hasContent ? snapshot : nil
    }

    func save(_ snapshot: HomeRecommendationSnapshot, contextKey: String, at date: Date = Date()) {
        guard let fileURL else {
            return
        }
        let directory = fileURL.deletingLastPathComponent()

        let payload = Payload(
            contextKey: contextKey,
            cachedAt: date,
            todayRecommendations: snapshot.todayRecommendations.map {
                CachedRecommendation(spotID: $0.spot.id, reason: $0.reason)
            },
            sections: snapshot.sections.map { kind, recommendations in
                CachedSection(
                    kind: kind.rawValue,
                    recommendations: recommendations.map {
                        CachedRecommendation(spotID: $0.spot.id, reason: $0.reason)
                    }
                )
            },
            expandedSections: snapshot.expandedSections.map { kind, recommendations in
                CachedSection(
                    kind: kind.rawValue,
                    recommendations: recommendations.map {
                        CachedRecommendation(spotID: $0.spot.id, reason: $0.reason)
                    }
                )
            }
        )

        guard let data = encode(payload) else { return }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLog.persistence.debug(
                "Home recommendation cache write skipped: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func encode(_ payload: Payload) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(payload)
    }

    private func decode(_ data: Data) -> Payload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Payload.self, from: data)
    }
}

private extension HomeRecommendationSnapshot {
    var hasContent: Bool {
        !todayRecommendations.isEmpty
            || sections.values.contains { !$0.isEmpty }
    }
}

@MainActor
final class HomeRecommendationsViewModel: ObservableObject {
    private struct Presentation {
        var snapshot = HomeRecommendationSnapshot(todayRecommendations: [], sections: [:], expandedSections: [:])
        var candidates: [PhotoSpot] = []
        var state: HomeRecommendationState = .initialLoading
    }
    @Published private var presentation = Presentation()
    var todayRecommendations: [RecommendedSpot] { presentation.snapshot.todayRecommendations }
    var sectionRecommendations: [HomeRecommendationKind: [RecommendedSpot]] { presentation.snapshot.sections }
    var expandedSectionRecommendations: [HomeRecommendationKind: [RecommendedSpot]] { presentation.snapshot.expandedSections }
    var geographicCandidateSpots: [PhotoSpot] { presentation.candidates }
    var recommendationState: HomeRecommendationState { presentation.state }
    @Published private(set) var refreshState: AsyncLoadState = .idle

    private let service: HomeRecommendationService
    private let cache: HomeRecommendationCache
    private var availableSpots: [PhotoSpot]
    private var geographicContext: HomeGeographicContext?
    private var hasResolvedLocation = false
    private var communityPosts: [CommunityPost] = []
    private var userLocation: CLLocationCoordinate2D?
    private var weatherContext: RecommendationWeatherContext?
    private var hasGeneratedInitialSnapshot = false
    private var recommendationVariation = 0
    private var requestedGeneration = 0
    private var appliedGeneration = 0
    private var lastGenerationHour: Int?
    private var generationTask: Task<Void, Never>?
    private var generationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(
        service: HomeRecommendationService = HomeRecommendationService(),
        seedService: LocalSeedDataService = LocalSeedDataService(),
        cacheFileURL: URL? = nil
    ) {
        self.service = service
        self.cache = HomeRecommendationCache(overrideFileURL: cacheFileURL)
        self.availableSpots = seedService.allPhotoSpots()
    }

    func prepareIfNeeded() {
        guard !hasGeneratedInitialSnapshot else { return }
        hasGeneratedInitialSnapshot = true
        if requestedGeneration == 0 { requestGeneration() }
    }

    var visibleSpots: [PhotoSpot] {
        let sectionSpots = sectionRecommendations.values.flatMap { $0.map(\.spot) }
        var seenIDs = Set<String>()

        return (todayRecommendations.map(\.spot) + sectionSpots).filter { spot in
            seenIDs.insert(spot.id).inserted
        }
    }

    func updateCommunityContext(posts: [CommunityPost]) {
        guard communityPosts != posts else { return }
        communityPosts = posts
        requestGeneration()
    }

    func updateLocationContext(userLocation: CLLocationCoordinate2D?) {
        let wasResolved = hasResolvedLocation
        hasResolvedLocation = true
        let nextContext: HomeGeographicContext?
        if let userLocation, CLLocationCoordinate2DIsValid(userLocation) {
            nextContext = geographicContext.flatMap { $0.retains(userLocation) ? $0 : nil }
                ?? HomeGeographicContext(coordinate: userLocation)
        } else {
            nextContext = nil
        }
        guard !wasResolved || nextContext != geographicContext else {
            refreshTimeContextIfNeeded()
            return
        }
        geographicContext = nextContext
        self.userLocation = nextContext?.coordinate
        weatherContext = nil
        if let nextContext, !hasUsableContent {
            let candidates = availableSpots.filter { nextContext.contains($0) }
            if let cached = cache.load(availableSpots: candidates, contextKey: nextContext.key) {
                presentation = Presentation(snapshot: cached, candidates: candidates, state: .loaded)
            }
        }
        requestGeneration()
    }

    func updateAvailableSpots(_ spots: [PhotoSpot]) {
        let unique = Dictionary(spots.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            .values.sorted { $0.id < $1.id }
        guard availableSpots != unique else { return }
        let oldCandidates = geographicContext.map { context in availableSpots.filter { context.contains($0) } } ?? []
        availableSpots = unique
        let newCandidates = geographicContext.map { context in availableSpots.filter { context.contains($0) } } ?? []
        if oldCandidates != newCandidates { requestGeneration() }
    }

    func updateWeatherContext(_ context: RecommendationWeatherContext?) {
        guard weatherContext != context else { return }
        weatherContext = context
        requestGeneration()
    }

    func refreshTimeContextIfNeeded(referenceDate: Date = Date()) {
        guard geographicContext != nil,
              lastGenerationHour != Int(referenceDate.timeIntervalSince1970 / 3600) else { return }
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
        guard hasResolvedLocation else { return requestedGeneration }
        if hasUsableContent {
            presentation.state = .refreshing
        }
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
        let context = geographicContext
        let referenceDate = Date()
        lastGenerationHour = Int(referenceDate.timeIntervalSince1970 / 3600)
        let candidates = context.map { context in availableSpots.filter {
            context.contains($0)
                && !CafeRecommendationPolicy.isBlacklistedCafe($0)
                && !RecommendationBlacklist.isBlacklistedRecommendation($0)
        } } ?? []

        generationTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                service.makeSnapshot(
                    communityPosts: communityPosts,
                    availableSpots: candidates,
                    userLocation: userLocation,
                    weatherContext: weatherContext,
                    timeZone: weatherContext.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current,
                    referenceDate: referenceDate,
                    variationSeed: variationSeed
                )
            }.value

            guard let self else { return }
            generationTask = nil

            if generation == requestedGeneration {
                apply(snapshot, candidates: candidates, context: context, generation: generation)
            } else {
                startGenerationIfNeeded()
            }
        }
    }

    private func apply(_ snapshot: HomeRecommendationSnapshot, candidates: [PhotoSpot], context: HomeGeographicContext?, generation: Int) {
        presentation = Presentation(
            snapshot: snapshot,
            candidates: candidates,
            state: context == nil ? .locationUnavailable : (candidates.isEmpty ? .empty : .loaded)
        )
        if let context { cache.save(snapshot, contextKey: context.key) }

        appliedGeneration = generation
        resumeWaiters(upTo: generation)
    }

    private var hasUsableContent: Bool {
        !todayRecommendations.isEmpty
            || sectionRecommendations.values.contains { !$0.isEmpty }
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

}

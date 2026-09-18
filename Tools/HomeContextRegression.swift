// Standalone regression harness. Compile with the actual HomeRecommendationsViewModel.swift.
// Fixtures replace external catalog/scoring dependencies, not the production context/cache/state code.
import Foundation
import CoreLocation
import OSLog

struct PhotoSpot: Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
}
struct RecommendedSpot: Sendable {
    let spot: PhotoSpot
    let reason: String
}
struct CommunityPost: Equatable, Sendable {}
enum HomeRecommendationKind: String, Sendable { case walk }
struct HomeRecommendationSnapshot: Sendable {
    let todayRecommendations: [RecommendedSpot]
    let sections: [HomeRecommendationKind: [RecommendedSpot]]
    let expandedSections: [HomeRecommendationKind: [RecommendedSpot]]
}
struct RecommendationWeatherContext: Equatable, Sendable {
    var timeZoneIdentifier = "Asia/Tokyo"
}
struct LocalSeedDataService {
    var spots: [PhotoSpot] = []
    func allPhotoSpots() -> [PhotoSpot] { spots }
}
enum AsyncLoadState: Equatable {
    case idle, loading, loaded
    case failed(message: String)
    var isLoading: Bool { self == .loading }
}
enum CafeRecommendationPolicy {
    static func isBlacklistedCafe(_ spot: PhotoSpot) -> Bool { false }
}
enum RecommendationBlacklist {
    static func isBlacklistedRecommendation(_ spot: PhotoSpot) -> Bool { false }
}
enum AppLog {
    static let persistence = Logger(subsystem: "Viewfinder.Regression", category: "cache")
    static let location = Logger(subsystem: "Viewfinder.Regression", category: "location")
}
final class GenerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
}
struct HomeRecommendationService: Sendable {
    let counter: GenerationCounter
    init(counter: GenerationCounter = GenerationCounter()) { self.counter = counter }
    func makeSnapshot(
        communityPosts: [CommunityPost], availableSpots: [PhotoSpot]?,
        userLocation: CLLocationCoordinate2D?, weatherContext: RecommendationWeatherContext?,
        timeZone: TimeZone, referenceDate: Date, variationSeed: Int
    ) -> HomeRecommendationSnapshot {
        counter.increment()
        Thread.sleep(forTimeInterval: 0.01)
        let entries = (availableSpots ?? []).prefix(5).map { RecommendedSpot(spot: $0, reason: "fixture") }
        return HomeRecommendationSnapshot(todayRecommendations: entries, sections: [.walk: entries], expandedSections: [.walk: entries])
    }
}

@main struct HomeContextRegression {
    struct Failure: Error { let message: String }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
        print("PASS: \(message)")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("viewfinder-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("home.json")
        let now = Date()
        func location(age: TimeInterval, accuracy: CLLocationAccuracy = 100) -> CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.56, longitude: 126.97), altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
        }
        try check(RecommendationLocationReader.isUsable(location(age: 30), now: now, maxAge: 3600), "fresh last-known location accepted")
        try check(!RecommendationLocationReader.isUsable(location(age: 86400), now: now, maxAge: 3600), "F day-old Korean location rejected")
        try check(!RecommendationLocationReader.isUsable(location(age: -60), now: now, maxAge: 3600), "future location timestamps rejected")
        try check(!RecommendationLocationReader.isUsable(location(age: 30, accuracy: 50_000), now: now, maxAge: 3600), "coarse location cannot select the wrong city")
        let instant = ISO8601DateFormatter().date(from: "2026-09-11T00:00:00Z")!
        try check(RecommendationTimeContext(referenceDate: instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!).phase == .morning, "Tokyo time context uses local morning")
        try check(RecommendationTimeContext(referenceDate: instant, timeZone: TimeZone(identifier: "Europe/London")!).phase == .night, "non-UTC+9 timezone uses local night with DST")
        let seoul = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let busan = CLLocationCoordinate2D(latitude: 35.1796, longitude: 129.0756)
        let koreanSpot = PhotoSpot(id: "seoul", latitude: seoul.latitude, longitude: seoul.longitude)
        let tokyoSpot = PhotoSpot(id: "tokyo", latitude: tokyo.latitude, longitude: tokyo.longitude)
        let tokyoNearby = PhotoSpot(id: "tokyo-20km", latitude: 35.82, longitude: 139.70)
        let far = PhotoSpot(id: "osaka", latitude: 34.69, longitude: 135.50)
        let counter = GenerationCounter()
        let model = HomeRecommendationsViewModel(service: HomeRecommendationService(counter: counter), seedService: LocalSeedDataService(spots: [koreanSpot, tokyoSpot, tokyoNearby, far]), cacheFileURL: cache)
        model.prepareIfNeeded()
        try check(model.recommendationState == .initialLoading && counter.value == 0, "wait for initial location before generating")
        model.updateLocationContext(userLocation: seoul)
        await model.refresh()
        try check(model.geographicCandidateSpots.map(\.id) == ["seoul"], "A Seoul excludes Japan")
        let beforeMove = counter.value
        model.updateLocationContext(userLocation: CLLocationCoordinate2D(latitude: 37.57, longitude: 126.98))
        try await Task.sleep(for: .milliseconds(60))
        try check(counter.value == beforeMove, "H/G small move or same-region foreground does not regenerate")
        model.refreshTimeContextIfNeeded(referenceDate: Date().addingTimeInterval(7200))
        try await Task.sleep(for: .milliseconds(100))
        try check(counter.value == beforeMove + 1, "same-region foreground refreshes after time advances")
        model.updateLocationContext(userLocation: tokyo)
        await model.refresh()
        try check(Set(model.geographicCandidateSpots.map(\.id)) == ["tokyo", "tokyo-20km"], "B Tokyo selects city-scale Japanese candidates only")
        try check(!model.todayRecommendations.contains { $0.spot.id == "seoul" }, "B old Korean recommendations replaced")
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as! [String: Any]
        try check(payload["contextKey"] as? String == HomeGeographicContext(coordinate: tokyo).key, "cache key includes current geographic context")
        let matchingCache = directory.appendingPathComponent("matching.json")
        try JSONSerialization.data(withJSONObject: payload).write(to: matchingCache)
        let matchingModel = HomeRecommendationsViewModel(seedService: LocalSeedDataService(spots: [tokyoSpot, tokyoNearby]), cacheFileURL: matchingCache)
        matchingModel.updateLocationContext(userLocation: tokyo)
        try check(!matchingModel.todayRecommendations.isEmpty, "fresh matching-context cache restores synchronously")
        try check(matchingModel.recommendationState == .refreshing, "cached content stays visible during background refresh")
        await matchingModel.refresh()
        let olderCache = directory.appendingPathComponent("older-usable.json")
        var olderPayload = payload
        olderPayload["cachedAt"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200))
        try JSONSerialization.data(withJSONObject: olderPayload).write(to: olderCache)
        let olderModel = HomeRecommendationsViewModel(seedService: LocalSeedDataService(spots: [tokyoSpot]), cacheFileURL: olderCache)
        olderModel.updateLocationContext(userLocation: tokyo)
        try check(!olderModel.todayRecommendations.isEmpty && olderModel.recommendationState == .refreshing, "two-hour regional cache displays before revalidation")
        await olderModel.refresh()
        try check(olderModel.recommendationState == .loaded, "background refresh settles to loaded")
        let staleCache = directory.appendingPathComponent("stale.json")
        var stalePayload = payload
        stalePayload["cachedAt"] = "2020-01-01T00:00:00Z"
        try JSONSerialization.data(withJSONObject: stalePayload).write(to: staleCache)
        let staleModel = HomeRecommendationsViewModel(seedService: LocalSeedDataService(spots: [tokyoSpot]), cacheFileURL: staleCache)
        staleModel.updateLocationContext(userLocation: tokyo)
        try check(staleModel.todayRecommendations.isEmpty, "expired matching-region cache is rejected")
        await staleModel.refresh()
        let mismatchCache = directory.appendingPathComponent("mismatch.json")
        try JSONSerialization.data(withJSONObject: payload).write(to: mismatchCache)
        let mismatchModel = HomeRecommendationsViewModel(seedService: LocalSeedDataService(spots: [koreanSpot, tokyoSpot]), cacheFileURL: mismatchCache)
        mismatchModel.updateLocationContext(userLocation: seoul)
        try check(mismatchModel.todayRecommendations.isEmpty, "fresh other-region cache is rejected")
        await mismatchModel.refresh()
        model.updateAvailableSpots([koreanSpot, far])
        await model.refresh()
        try check(model.recommendationState == .empty && model.visibleSpots.isEmpty, "C empty Tokyo clears prior content without Korea fallback")
        model.updateAvailableSpots([koreanSpot, far, tokyoSpot])
        await model.refresh()
        try check(model.todayRecommendations.map { $0.spot.id } == ["tokyo"], "I new regional place appears without cache expiry")
        model.updateLocationContext(userLocation: nil)
        await model.refresh()
        try check(model.recommendationState == .locationUnavailable && model.geographicCandidateSpots.isEmpty, "E/F unavailable location is neutral, not regional empty")
        model.updateLocationContext(userLocation: seoul)
        model.updateLocationContext(userLocation: tokyo)
        await model.refresh()
        try check(model.todayRecommendations.map { $0.spot.id } == ["tokyo"], "obsolete generation cannot restore Seoul after Tokyo update")
        try check(!HomeGeographicContext(coordinate: seoul).retains(busan), "Seoul to Busan changes context")
        let legacy = "{\"cachedAt\":\"2026-09-11T00:00:00Z\",\"todayRecommendations\":[],\"sections\":[],\"expandedSections\":[]}"
        try Data(legacy.utf8).write(to: cache)
        let legacyModel = HomeRecommendationsViewModel(seedService: LocalSeedDataService(spots: [koreanSpot]), cacheFileURL: cache)
        legacyModel.updateLocationContext(userLocation: tokyo)
        try check(legacyModel.todayRecommendations.isEmpty, "legacy cache without context is never restored")
        await legacyModel.refresh()
        try check(legacyModel.recommendationState == .empty, "legacy Korea cache cannot fill empty Tokyo")
        print("All Home context/cache/state regression checks passed. Scoring/network/Map UI are separate integration checks.")
    }
}

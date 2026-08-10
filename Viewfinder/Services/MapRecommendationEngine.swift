import CoreLocation
import Foundation

struct MapRecommendationResult {
    let spots: [PhotoSpot]
    let radius: CLLocationDistance?
    let candidateCount: Int
    let fallbackUsed: Bool
}

struct MapRecommendationEngine {
    private let localSeedDataService: LocalSeedDataService

    init(localSeedDataService: LocalSeedDataService = LocalSeedDataService()) {
        self.localSeedDataService = localSeedDataService
    }

    func recommendations(
        near coordinate: CLLocationCoordinate2D?,
        from recommendedSpots: [PhotoSpot],
        categoryFilter: MapCategoryFilter
    ) -> MapRecommendationResult {
        guard let coordinate else {
            let fallbackSpots = filtered(recommendedSpots, categoryFilter: categoryFilter)
            return MapRecommendationResult(
                spots: fallbackSpots,
                radius: nil,
                candidateCount: fallbackSpots.count,
                fallbackUsed: true
            )
        }

        for radius in [10_000.0, 20_000.0, 30_000.0] {
            let nearbyLocalSpots = localSeedDataService.photoSpots(
                near: coordinate,
                within: radius,
                limit: 36
            )
            let nearbyGeneratedSpots = recommendedSpots.filter {
                distance(from: coordinate, to: $0) <= radius
            }
            let candidates = filtered(
                unique(nearbyLocalSpots + nearbyGeneratedSpots),
                categoryFilter: categoryFilter
            )

            if !candidates.isEmpty {
                return MapRecommendationResult(
                    spots: Array(candidates.prefix(6)),
                    radius: radius,
                    candidateCount: candidates.count,
                    fallbackUsed: false
                )
            }
        }

        return MapRecommendationResult(
            spots: [],
            radius: 30_000,
            candidateCount: 0,
            fallbackUsed: false
        )
    }

    private func filtered(
        _ spots: [PhotoSpot],
        categoryFilter: MapCategoryFilter
    ) -> [PhotoSpot] {
        spots.filter {
            categoryFilter.matches($0)
                && !RecommendationBlacklist.isBlacklistedRecommendation($0)
        }
    }

    private func distance(
        from coordinate: CLLocationCoordinate2D,
        to spot: PhotoSpot
    ) -> CLLocationDistance {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let destination = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        return destination.distance(from: origin)
    }

    private func unique(_ spots: [PhotoSpot]) -> [PhotoSpot] {
        spots.reduce(into: [PhotoSpot]()) { result, spot in
            guard !result.contains(where: { $0.id == spot.id || $0.mapQuery == spot.mapQuery }) else {
                return
            }
            result.append(spot)
        }
    }
}

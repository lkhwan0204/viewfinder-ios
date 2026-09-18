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
    /// 위치 권한을 아직 받지 못했을 때의 탐색 시작점입니다.
    /// 전국 추천을 한 화면에 모두 맞추면 핀이 지나치게 멀어져 발견할 수 없으므로,
    /// 앱의 기본 탐색 도시인 서울 중심에서 시작합니다.
    private let fallbackCoordinate = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)

    init(localSeedDataService: LocalSeedDataService = LocalSeedDataService()) {
        self.localSeedDataService = localSeedDataService
    }

    func recommendations(
        near coordinate: CLLocationCoordinate2D?,
        from recommendedSpots: [PhotoSpot],
        categoryFilter: MapCategoryFilter
    ) -> MapRecommendationResult {
        let searchCoordinate = coordinate ?? fallbackCoordinate
        let usesFallbackLocation = coordinate == nil

        for radius in [10_000.0, 20_000.0, 30_000.0] {
            let nearbyLocalSpots = localSeedDataService.photoSpots(
                near: searchCoordinate,
                within: radius,
                limit: 36
            )
            let nearbyGeneratedSpots = recommendedSpots.filter {
                distance(from: searchCoordinate, to: $0) <= radius
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
                    fallbackUsed: usesFallbackLocation
                )
            }
        }

        return MapRecommendationResult(
            spots: [],
            radius: 30_000,
            candidateCount: 0,
            fallbackUsed: usesFallbackLocation
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

import CoreLocation
import Foundation

struct AIPhotoSpotResolver {
    func resolvedRecommendations(
        from discoveries: [GPTDiscoveredSpot],
        near coordinate: CLLocationCoordinate2D?
    ) async -> [GPTRecommendedSpot] {
        []
    }
}

@MainActor
final class RecommendationLocationReader: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func coordinateForRecommendation() async -> CLLocationCoordinate2D? {
        if let coordinate {
            return coordinate
        }

        requestLocation()
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        return coordinate
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            coordinate = locations.last?.coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

import CoreLocation
import Foundation
import OSLog

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
    @Published private(set) var state: AsyncLoadState = .idle

    private let manager = CLLocationManager()
    private var pendingContinuations: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .loading
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            state = .loading
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: nil, state: .failed(message: "위치 권한이 필요해요"))
        @unknown default:
            finish(with: nil, state: .failed(message: "위치 상태를 확인하지 못했어요"))
        }
    }

    func coordinateForRecommendation() async -> CLLocationCoordinate2D? {
        if let coordinate {
            return coordinate
        }

        return await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
            requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                state = .loading
                manager.requestLocation()
            case .denied, .restricted:
                finish(with: nil, state: .failed(message: "위치 권한이 필요해요"))
            case .notDetermined:
                break
            @unknown default:
                finish(with: nil, state: .failed(message: "위치 상태를 확인하지 못했어요"))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let newCoordinate = locations.last?.coordinate else {
                finish(with: nil, state: .failed(message: "현재 위치를 찾지 못했어요"))
                return
            }
            coordinate = newCoordinate
            finish(with: newCoordinate, state: .loaded)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            AppLog.location.error(
                "Location request failed: \(error.localizedDescription, privacy: .public)"
            )
            finish(with: nil, state: .failed(message: "현재 위치를 불러오지 못했어요"))
        }
    }

    private func finish(with result: CLLocationCoordinate2D?, state newState: AsyncLoadState) {
        state = newState
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        continuations.forEach { $0.resume(returning: result) }
    }
}

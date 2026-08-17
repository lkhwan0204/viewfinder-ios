import CoreLocation
import Foundation
import OSLog

// ═══════════════════════════════════════════════════════════════════
//  현재 위치를 읽는 객체. ContentView 가 @StateObject 로 들고 씁니다.
//  홈 추천의 거리 표시와 지도 "내 위치" 가 이 값을 씁니다.
//
//  [이 파일이 따로 생긴 이유]
//  이 클래스는 AIPhotoSpotResolver.swift 안에 있었습니다.
//  AI 코드를 정리하면서 그 파일을 이름만 보고 지웠고, 그 안에 살아
//  있던 이 클래스가 함께 사라졌습니다. ContentView 가 쓰고 있으므로
//  빌드가 깨졌습니다.
//
//  파일 이름이 그 안에 든 것을 전부 설명하지 않는다는 것을 놓쳤습니다.
//  같은 실수를 막기 위해 파일 이름을 타입 이름과 맞췄습니다.
//
//  함께 있던 AIPhotoSpotResolver 는 본문이 [] 를 돌려주는 빈 구조체였고
//  참조도 없어서 되살리지 않았습니다.
// ═══════════════════════════════════════════════════════════════════

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

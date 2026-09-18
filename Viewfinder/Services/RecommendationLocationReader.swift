import CoreLocation
import Combine
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
    nonisolated static func isUsable(_ location: CLLocation, now: Date, maxAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 5_000
            && age >= 0 && age <= maxAge
    }
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var locationTimestamp: Date?
    @Published private(set) var state: AsyncLoadState = .idle

    private let manager = CLLocationManager()
    private var pendingContinuations: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    private var requestTimeoutTask: Task<Void, Never>?
    private var isRequestInFlight = false
    private let maximumCachedLocationAge: TimeInterval = 60 * 60
    private let maximumLiveLocationAge: TimeInterval = 2 * 60
    private let defaultRequestTimeout: Duration = .seconds(4)

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Foreground callers use this to revalidate the current position. Existing recent
    /// content remains available while Core Location obtains a new fix.
    func recentCoordinateForRecommendation() -> CLLocationCoordinate2D? {
        expirePublishedLocationIfNeeded()
        return usableCachedLocation()?.coordinate
    }

    func requestLocation(forceRefresh: Bool = true) {
        expirePublishedLocationIfNeeded()
        guard !isRequestInFlight else { return }

        beginLocationRequest(forceRefresh: forceRefresh, timeout: defaultRequestTimeout)
    }

    func coordinateForRecommendation(
        forceRefresh: Bool = false,
        timeout: Duration = .seconds(4)
    ) async -> CLLocationCoordinate2D? {
        expirePublishedLocationIfNeeded()

        if !forceRefresh, let location = usableCachedLocation() {
            publish(location)
            return location.coordinate
        }

        return await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)

            if !isRequestInFlight {
                beginLocationRequest(forceRefresh: forceRefresh, timeout: timeout)
            }
        }
    }

    private func beginLocationRequest(forceRefresh: Bool, timeout: Duration) {
        isRequestInFlight = true
        state = .loading
        scheduleTimeout(after: timeout)

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if !forceRefresh, let location = usableCachedLocation() {
                finish(with: location, state: .loaded)
            } else {
                manager.requestLocation()
            }
        case .denied, .restricted:
            finishWithFallbackOrFailure(message: "위치 권한이 필요해요")
        @unknown default:
            finishWithFallbackOrFailure(message: "위치 상태를 확인하지 못했어요")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if isRequestInFlight {
                    manager.requestLocation()
                } else {
                    requestLocation()
                }
            case .denied, .restricted:
                expirePublishedLocationIfNeeded()
                finishWithFallbackOrFailure(message: "위치 권한이 필요해요")
            case .notDetermined:
                break
            @unknown default:
                if isRequestInFlight {
                    finishWithFallbackOrFailure(message: "위치 상태를 확인하지 못했어요")
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let now = Date()
            guard let location = locations
                .filter({ Self.isUsable($0, now: now, maxAge: maximumLiveLocationAge) })
                .max(by: { $0.timestamp < $1.timestamp }),
                  now.timeIntervalSince(location.timestamp) >= 0,
                  now.timeIntervalSince(location.timestamp) <= maximumLiveLocationAge else {
                finishWithFallbackOrFailure(message: "현재 위치를 찾지 못했어요")
                return
            }

            finish(with: location, state: .loaded)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            AppLog.location.error(
                "Location request failed: \(error.localizedDescription, privacy: .public)"
            )
            finishWithFallbackOrFailure(message: "현재 위치를 불러오지 못했어요")
        }
    }

    private func scheduleTimeout(after timeout: Duration) {
        requestTimeoutTask?.cancel()
        requestTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.isRequestInFlight else { return }

            AppLog.location.debug("Location request timed out")
            self.finishWithFallbackOrFailure(message: "현재 위치를 불러오지 못했어요")
        }
    }

    private func finishWithFallbackOrFailure(message: String) {
        if let location = usableCachedLocation() {
            finish(with: location, state: .loaded)
        } else {
            finish(with: nil, state: .failed(message: message))
        }
    }

    private func finish(with result: CLLocation?, state newState: AsyncLoadState) {
        requestTimeoutTask?.cancel()
        requestTimeoutTask = nil
        isRequestInFlight = false

        if let result {
            publish(result)
        } else {
            coordinate = nil
            locationTimestamp = nil
        }

        state = newState
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        continuations.forEach { $0.resume(returning: result?.coordinate) }
    }

    private func publish(_ location: CLLocation) {
        coordinate = location.coordinate
        locationTimestamp = location.timestamp
    }

    private func usableCachedLocation(now: Date = Date()) -> CLLocation? {
        let candidates = [
            manager.location,
            coordinate.flatMap { coordinate in
                guard let locationTimestamp else { return nil }
                return CLLocation(
                    coordinate: coordinate,
                    altitude: 0,
                    horizontalAccuracy: manager.location?.horizontalAccuracy ?? kCLLocationAccuracyHundredMeters,
                    verticalAccuracy: -1,
                    timestamp: locationTimestamp
                )
            }
        ]
        .compactMap { $0 }
        .filter { location in
            Self.isUsable(location, now: now, maxAge: maximumCachedLocationAge)
        }

        return candidates.max(by: { $0.timestamp < $1.timestamp })
    }

    private func expirePublishedLocationIfNeeded(now: Date = Date()) {
        guard let locationTimestamp else { return }
        let age = now.timeIntervalSince(locationTimestamp)
        guard age < 0 || age > maximumCachedLocationAge else {
            return
        }

        coordinate = nil
        self.locationTimestamp = nil
    }
}

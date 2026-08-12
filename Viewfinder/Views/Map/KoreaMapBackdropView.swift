import CoreLocation
import NMapsMap
import SwiftUI
import UIKit

struct KoreaMapBackdropView: View {
    let spots: [PhotoSpot]
    let selectedSpot: PhotoSpot
    let selectedSpotRevision: Int
    let focusUserLocationRevision: Int
    let userCoordinate: CLLocationCoordinate2D?
    let savedSpotIDs: Set<String>
    let onSelectSpot: (PhotoSpot) -> Void
    let onShowDetail: (PhotoSpot) -> Void

    @StateObject private var locationPermission = LocationPermissionRequester()

    var body: some View {
        ZStack {
            NaverMapRepresentable(
                spots: spots,
                selectedSpot: selectedSpot,
                selectedSpotRevision: selectedSpotRevision,
                focusUserLocationRevision: focusUserLocationRevision,
                userCoordinate: userCoordinate,
                savedSpotIDs: savedSpotIDs,
                onSelectSpot: { spot in
                    onSelectSpot(spot)
                    onShowDetail(spot)
                },
                onFocusSpot: { spot in
                    onSelectSpot(spot)
                }
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    LocateMeButton {
                        locationPermission.requestWhenInUse()
                        locationPermission.focusRevision += 1
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 104)
                }
            }
        }
        .onAppear {
            locationPermission.requestWhenInUse()
        }
    }
}

private struct NaverMapRepresentable: UIViewRepresentable {
    let spots: [PhotoSpot]
    let selectedSpot: PhotoSpot
    let selectedSpotRevision: Int
    let focusUserLocationRevision: Int
    let userCoordinate: CLLocationCoordinate2D?
    let savedSpotIDs: Set<String>
    let onSelectSpot: (PhotoSpot) -> Void
    let onFocusSpot: (PhotoSpot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectSpot: onSelectSpot, onFocusSpot: onFocusSpot)
    }

    func makeUIView(context: Context) -> NMFNaverMapView {
        let naverMapView = NMFNaverMapView(frame: .zero)
        naverMapView.showLocationButton = false
        naverMapView.showZoomControls = false
        naverMapView.showCompass = false
        // 축척 바("1km")는 출사지를 찾는 데 쓰이지 않는데
        // 우하단에서 내 위치 버튼, 네이버 로고와 겹쳐 보였습니다.
        naverMapView.showScaleBar = false
        naverMapView.mapView.logoAlign = .rightBottom
        naverMapView.mapView.logoMargin = UIEdgeInsets(top: 0, left: 0, bottom: 6, right: 14)
        context.coordinator.configure(naverMapView)
        context.coordinator.syncMarkers(spots: spots, savedSpotIDs: savedSpotIDs, on: naverMapView.mapView)
        if let userCoordinate {
            context.coordinator.focusOnUserLocation(userCoordinate, mapView: naverMapView.mapView, animated: false)
        } else if selectedSpotRevision > 0 {
            context.coordinator.focus(on: selectedSpot, mapView: naverMapView.mapView, animated: false)
        }
        return naverMapView
    }

    func updateUIView(_ naverMapView: NMFNaverMapView, context: Context) {
        context.coordinator.syncMarkers(spots: spots, savedSpotIDs: savedSpotIDs, on: naverMapView.mapView)

        if selectedSpotRevision > 0,
           context.coordinator.selectedSpotRevision != selectedSpotRevision
            || context.coordinator.selectedSpotID != selectedSpot.id {
            context.coordinator.selectedSpotRevision = selectedSpotRevision
            context.coordinator.selectedSpotID = selectedSpot.id
            context.coordinator.focus(on: selectedSpot, mapView: naverMapView.mapView, animated: true)
        }

        if context.coordinator.focusUserLocationRevision != focusUserLocationRevision
            || context.coordinator.localFocusRevision != LocationPermissionRequester.sharedFocusRevision {
            context.coordinator.focusUserLocationRevision = focusUserLocationRevision
            context.coordinator.localFocusRevision = LocationPermissionRequester.sharedFocusRevision
            naverMapView.mapView.positionMode = .direction
            if let userCoordinate {
                context.coordinator.focusOnUserLocation(userCoordinate, mapView: naverMapView.mapView, animated: true)
            }
        } else if selectedSpotRevision == 0,
                  let userCoordinate,
                  context.coordinator.userCoordinateKey != Self.coordinateKey(for: userCoordinate) {
            context.coordinator.focusOnUserLocation(userCoordinate, mapView: naverMapView.mapView, animated: true)
        }
    }

    private static func coordinateKey(for coordinate: CLLocationCoordinate2D) -> String {
        "\(Int((coordinate.latitude * 10_000).rounded()))-\(Int((coordinate.longitude * 10_000).rounded()))"
    }

    final class Coordinator {
        var selectedSpotRevision = 0
        var focusUserLocationRevision = 0
        var localFocusRevision = 0
        var selectedSpotID: String?
        var userCoordinateKey: String?

        private let onSelectSpot: (PhotoSpot) -> Void
        private let onFocusSpot: (PhotoSpot) -> Void
        private var markers: [String: NMFMarker] = [:]

        init(onSelectSpot: @escaping (PhotoSpot) -> Void, onFocusSpot: @escaping (PhotoSpot) -> Void) {
            self.onSelectSpot = onSelectSpot
            self.onFocusSpot = onFocusSpot
        }

        func configure(_ naverMapView: NMFNaverMapView) {
            // 상단: 카테고리 칩 한 줄 + 상태 pill.  하단: 탭바 + 내 위치 버튼.
            // (이전 bottom 220 은 항상 떠 있던 큰 프리뷰 카드를 위한 값이었습니다.
            //  카드가 선택 시에만 나타나도록 바뀌어 그만큼 필요하지 않습니다.
            //  이 값이 네이버 로고를 화면 중앙까지 밀어 올리고 있었습니다.)
            naverMapView.mapView.contentInset = UIEdgeInsets(top: 92, left: 0, bottom: 100, right: 0)
        }

        func syncMarkers(spots: [PhotoSpot], savedSpotIDs: Set<String>, on mapView: NMFMapView) {
            let incomingIDs = Set(spots.map(\.id))

            for (id, marker) in markers where !incomingIDs.contains(id) {
                marker.mapView = nil
                markers[id] = nil
            }

            for spot in spots {
                if let marker = markers[spot.id] {
                    marker.position = NMGLatLng(lat: spot.latitude, lng: spot.longitude)
                    configure(marker: marker, spot: spot, isSaved: savedSpotIDs.contains(spot.id))
                    continue
                }

                let marker = NMFMarker(position: NMGLatLng(lat: spot.latitude, lng: spot.longitude))
                configure(marker: marker, spot: spot, isSaved: savedSpotIDs.contains(spot.id))
                marker.userInfo = ["spotID": spot.id, "title": spot.name]
                marker.touchHandler = { [weak self] overlay in
                    guard let self else { return true }
                    self.selectedSpotID = spot.id
                    self.onSelectSpot(spot)
                    self.focus(on: spot, mapView: mapView, animated: true)
                    return true
                }
                marker.mapView = mapView
                markers[spot.id] = marker
            }
        }

        private func configure(marker: NMFMarker, spot: PhotoSpot, isSaved: Bool) {
            marker.captionText = spot.name
            marker.captionTextSize = 12
            marker.captionRequestedWidth = 84
            marker.captionColor = AppColors.uiPrimary
            marker.captionHaloColor = AppColors.uiCardBackground.withAlphaComponent(0.96)
            marker.captionAligns = [NMFAlignType.bottom]
            marker.captionOffset = 4
            marker.iconTintColor = .clear
            // 꼬리가 없어졌으므로 좌표에 정사각형의 "중심"을 맞춥니다.
            // (꼬리가 있을 때는 아래 끝이 좌표를 가리켰으므로 y: 1.0 이었습니다.)
            marker.anchor = CGPoint(x: 0.5, y: 0.5)
            marker.isHideCollidedSymbols = false
            marker.isHideCollidedMarkers = false
            marker.isHideCollidedCaptions = false
            marker.isForceShowIcon = true
            marker.isForceShowCaption = true

            // 핀은 항상 사진 정사각형입니다.
            //
            // 이전에는 사진을 못 구하면 검은 물방울 핀으로 폴백했는데,
            // 한 화면에 물방울과 사진 사각형이 섞여 나와 핀이 두 종류로 보였습니다.
            // 지금은 사진이 없거나 아직 로딩 중이면 같은 크기·같은 모양의
            // 회색 자리표시 사각형을 쓰고, 사진이 도착하면 그 자리에서 교체합니다.
            if let photoOverlay = MapPinPhotoStore.shared.cachedOverlay(for: spot, isSaved: isSaved) {
                apply(photoOverlay: photoOverlay, to: marker)
            } else {
                apply(photoOverlay: MapPinPhotoStore.shared.placeholderOverlay(isSaved: isSaved), to: marker)

                MapPinPhotoStore.shared.loadOverlay(for: spot, isSaved: isSaved) { [weak self] overlay in
                    guard let self, let target = self.markers[spot.id] else { return }
                    self.apply(photoOverlay: overlay, to: target)
                }
            }
        }

        private func apply(photoOverlay: NMFOverlayImage, to marker: NMFMarker) {
            marker.iconImage = photoOverlay
            marker.width = ViewfinderMapPhotoPin.size.width
            marker.height = ViewfinderMapPhotoPin.size.height
        }

        func focus(on spot: PhotoSpot, mapView: NMFMapView, animated: Bool) {
            let update = NMFCameraUpdate(scrollTo: NMGLatLng(lat: spot.latitude, lng: spot.longitude), zoomTo: 14.5)
            update.pivot = CGPoint(x: 0.5, y: 0.38)

            if animated {
                update.animation = .easeIn
                update.animationDuration = 0.35
            }

            mapView.moveCamera(update)
            onFocusSpot(spot)
        }

        func focusOnUserLocation(_ coordinate: CLLocationCoordinate2D, mapView: NMFMapView, animated: Bool) {
            userCoordinateKey = NaverMapRepresentable.coordinateKey(for: coordinate)
            let update = NMFCameraUpdate(scrollTo: NMGLatLng(lat: coordinate.latitude, lng: coordinate.longitude), zoomTo: 12.2)
            update.pivot = CGPoint(x: 0.5, y: 0.48)

            if animated {
                update.animation = .easeIn
                update.animationDuration = 0.32
            }

            mapView.moveCamera(update)
        }

    }
}

struct NaverSpotPreviewMap: UIViewRepresentable {
    let spot: PhotoSpot
    /// 확대/축소를 허용할지. 상세 화면의 "위치 미리보기" 에서 true 로 씁니다.
    var allowsZoom: Bool = false

    func makeUIView(context: Context) -> NMFNaverMapView {
        let naverMapView = NMFNaverMapView(frame: .zero)
        naverMapView.showCompass = false
        naverMapView.showScaleBar = false
        naverMapView.showZoomControls = allowsZoom
        naverMapView.showLocationButton = false

        // 핀치/더블탭 확대는 허용하되, 패닝·회전·기울기는 막습니다.
        // 세로 스크롤 화면 안에 있는 지도라 패닝을 허용하면 스크롤이 막힙니다.
        naverMapView.mapView.isZoomGestureEnabled = allowsZoom
        naverMapView.mapView.isScrollGestureEnabled = false
        naverMapView.mapView.isRotateGestureEnabled = false
        naverMapView.mapView.isTiltGestureEnabled = false
        naverMapView.mapView.logoAlign = .rightBottom
        naverMapView.mapView.logoMargin = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 10)
        context.coordinator.render(spot: spot, on: naverMapView.mapView, animated: false)
        return naverMapView
    }

    func updateUIView(_ naverMapView: NMFNaverMapView, context: Context) {
        context.coordinator.render(spot: spot, on: naverMapView.mapView, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private let marker = NMFMarker()
        private var renderedSpotID: String?

        func render(spot: PhotoSpot, on mapView: NMFMapView, animated: Bool) {
            marker.position = NMGLatLng(lat: spot.latitude, lng: spot.longitude)
            marker.captionText = spot.name
            marker.captionTextSize = 12
            marker.captionRequestedWidth = 84
            marker.captionColor = AppColors.uiPrimary
            marker.captionHaloColor = AppColors.uiCardBackground.withAlphaComponent(0.96)
            marker.captionAligns = [NMFAlignType.bottom]
            marker.captionOffset = 5
            marker.iconImage = ViewfinderMapMarkerIcon.preview
            marker.iconTintColor = .clear
            marker.width = 42
            marker.height = 54
            marker.anchor = CGPoint(x: 0.5, y: 1.0)
            marker.isHideCollidedCaptions = false
            marker.isForceShowCaption = true
            marker.mapView = mapView

            guard renderedSpotID != spot.id else { return }
            renderedSpotID = spot.id

            let update = NMFCameraUpdate(scrollTo: NMGLatLng(lat: spot.latitude, lng: spot.longitude), zoomTo: 15.4)
            if animated {
                update.animation = .easeIn
                update.animationDuration = 0.25
            }
            mapView.moveCamera(update)
        }
    }
}

private struct LocateMeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // 저장 버튼과 같은 표면·같은 크기를 씁니다.
            // 지도 위 컨트롤이 서로 다른 재료로 보이지 않게 하기 위한 것입니다.
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: MapChrome.circleSize, height: MapChrome.circleSize)
                .mapChromeSurface(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("내 위치로 이동")
    }
}

private final class LocationPermissionRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
    static var sharedFocusRevision = 0

    @Published var focusRevision = 0 {
        didSet {
            Self.sharedFocusRevision = focusRevision
        }
    }

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUse() {
        if manager.delegate == nil {
            manager.delegate = self
        }

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

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

private enum ViewfinderMapMarkerIcon {
    private enum CenterStyle {
        case dot
        case bookmark
    }

    private static let markerFillColor = UIColor(white: 0.08, alpha: 1)
    private static let markerStrokeColor = UIColor.white
    private static let markerCenterColor = UIColor.white

    // 지도 탭의 핀은 전부 사진 사각형(ViewfinderMapPhotoPin)입니다.
    // 물방울 핀은 상세 화면의 위치 미리보기 지도에만 남깁니다.
    // 그 지도는 장소가 하나뿐이고 위에 이미 대표 사진이 있으므로,
    // 사진을 한 번 더 반복하는 것보다 좌표를 가리키는 편이 맞습니다.
    static let preview: NMFOverlayImage = makeOverlayImage(
        size: CGSize(width: 42, height: 54),
        fillColor: markerFillColor,
        strokeColor: markerStrokeColor,
        centerColor: markerCenterColor,
        reuseIdentifier: "viewfinder-marker-preview-fixed-v1"
    )

    private static func makeOverlayImage(
        size: CGSize,
        fillColor: UIColor,
        strokeColor: UIColor,
        centerColor: UIColor,
        reuseIdentifier: String,
        centerStyle: CenterStyle = .dot
    ) -> NMFOverlayImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            let radius = (size.width - 8) / 2
            let center = CGPoint(x: size.width / 2, y: radius + 4)
            let tailTip = CGPoint(x: size.width / 2, y: size.height - 4)
            let leftShoulder = CGPoint(x: center.x - radius, y: center.y + 1)

            let markerPath = UIBezierPath()
            markerPath.move(to: tailTip)
            markerPath.addCurve(
                to: leftShoulder,
                controlPoint1: CGPoint(x: center.x - 8, y: size.height - 11),
                controlPoint2: CGPoint(x: center.x - radius, y: center.y + radius * 0.78)
            )
            markerPath.addArc(
                withCenter: center,
                radius: radius,
                startAngle: CGFloat.pi * 0.95,
                endAngle: CGFloat.pi * 0.05,
                clockwise: true
            )
            markerPath.addCurve(
                to: tailTip,
                controlPoint1: CGPoint(x: center.x + radius, y: center.y + radius * 0.78),
                controlPoint2: CGPoint(x: center.x + 8, y: size.height - 11)
            )
            markerPath.close()

            cgContext.saveGState()
            cgContext.setShadow(
                offset: CGSize(width: 0, height: 3),
                blur: 7,
                color: UIColor.black.withAlphaComponent(0.18).cgColor
            )
            fillColor.setFill()
            markerPath.fill()
            cgContext.restoreGState()

            strokeColor.setStroke()
            markerPath.lineWidth = 2.5
            markerPath.stroke()

            switch centerStyle {
            case .dot:
                let dotDiameter = radius * 0.48
                let dotRect = CGRect(
                    x: center.x - dotDiameter / 2,
                    y: center.y - dotDiameter / 2,
                    width: dotDiameter,
                    height: dotDiameter
                )
                centerColor.setFill()
                UIBezierPath(ovalIn: dotRect).fill()
            case .bookmark:
                let bookmarkWidth = radius * 0.64
                let bookmarkHeight = radius * 0.86
                let bookmarkRect = CGRect(
                    x: center.x - bookmarkWidth / 2,
                    y: center.y - bookmarkHeight / 2,
                    width: bookmarkWidth,
                    height: bookmarkHeight
                )
                let bookmarkPath = UIBezierPath()
                bookmarkPath.move(to: CGPoint(x: bookmarkRect.minX, y: bookmarkRect.minY))
                bookmarkPath.addLine(to: CGPoint(x: bookmarkRect.maxX, y: bookmarkRect.minY))
                bookmarkPath.addLine(to: CGPoint(x: bookmarkRect.maxX, y: bookmarkRect.maxY))
                bookmarkPath.addLine(to: CGPoint(x: bookmarkRect.midX, y: bookmarkRect.maxY - bookmarkHeight * 0.26))
                bookmarkPath.addLine(to: CGPoint(x: bookmarkRect.minX, y: bookmarkRect.maxY))
                bookmarkPath.close()
                centerColor.setStroke()
                bookmarkPath.lineWidth = 2.2
                bookmarkPath.lineJoinStyle = .round
                bookmarkPath.stroke()
            }
        }

        return NMFOverlayImage(image: image, reuseIdentifier: reuseIdentifier)
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - 지도 스타일
//
//  Phase 4A 에서 지도를 앱의 다크 캔버스에 맞추려고
//  ViewfinderMapStyle.applyDark(lightness / symbolScale / setLayerGroup)
//  를 넣었지만 실기에서 효과가 나타나지 않았고,
//  사용자 판단으로 지도는 네이버 기본 외관을 그대로 쓰기로 했습니다.
//
//  검증되지 않은 SDK 프로퍼티 3개를 코드에 남겨둘 이유가 없어 제거했습니다.
//  지도 위 컨트롤의 대비는 지도를 어둡게 만드는 방식이 아니라,
//  컨트롤 자체를 불투명 검정으로 만드는 방식으로 확보합니다.
//  (MapCategoryFilter.swift 의 MapChrome 참고)
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
// MARK: - 사진 핀
//
//  [문제였던 상황]
//  사진 출사지 앱인데 지도에 사진이 한 장도 없었습니다.
//  검정 물방울 핀만 떠 있어서, 지도만 보면 무슨 앱인지 알 수 없었습니다.
//  게다가 네이버 기본 POI("스타필드", "이케아")가 우리 핀보다 시각적으로
//  강해서, 우리 콘텐츠가 배경으로 밀려 있었습니다.
//
//  [변경]
//  핀 안에 그 장소의 사진을 넣습니다.
//  "문래창작촌" 이라는 텍스트보다 그 골목 사진 한 장이
//  "여기 갈까?" 판단에 압도적으로 유용합니다.
//  기능적으로도 우월하고, 사진 앱이라는 정체성을 지도에서도 유지합니다.
//
//  사진이 없거나 아직 로딩 중인 장소는 기존 물방울 핀으로 폴백합니다.
// ═══════════════════════════════════════════════════════════════════

final class MapPinPhotoStore {
    static let shared = MapPinPhotoStore()

    private var overlays: [String: NMFOverlayImage] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    private func cacheKey(spotID: String, isSaved: Bool) -> String {
        "vf-photo-pin-\(spotID)-\(isSaved ? "saved" : "normal")"
    }

    /// 이미 만들어둔 핀이 있으면 즉시 반환합니다. (메인 스레드에서만 호출)
    func cachedOverlay(for spot: PhotoSpot, isSaved: Bool) -> NMFOverlayImage? {
        overlays[cacheKey(spotID: spot.id, isSaved: isSaved)]
    }

    /// 사진이 없거나 로딩 중일 때 쓰는 자리표시 핀.
    /// 사진 핀과 같은 크기·같은 모양이라 지도에 핀이 두 종류로 보이지 않습니다.
    func placeholderOverlay(isSaved: Bool) -> NMFOverlayImage {
        let key = "vf-photo-pin-placeholder-\(isSaved ? "saved" : "normal")"

        if let existing = overlays[key] {
            return existing
        }

        let overlay = NMFOverlayImage(
            image: ViewfinderMapPhotoPin.placeholderImage(isSaved: isSaved),
            reuseIdentifier: key
        )
        overlays[key] = overlay
        return overlay
    }

    /// 사진 핀을 준비합니다. 완료 콜백은 메인 스레드에서 호출됩니다.
    /// 사진을 구할 수 없으면 콜백이 호출되지 않고, 호출부는 자리표시 핀을 유지합니다.
    func loadOverlay(
        for spot: PhotoSpot,
        isSaved: Bool,
        completion: @escaping (NMFOverlayImage) -> Void
    ) {
        let key = cacheKey(spotID: spot.id, isSaved: isSaved)

        if let existing = overlays[key] {
            completion(existing)
            return
        }

        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)

        // 1) 번들 애셋이 있으면 네트워크를 타지 않습니다.
        if let imageName = spot.imageName, let asset = UIImage(named: imageName) {
            render(key: key, source: asset, isSaved: isSaved, completion: completion)
            return
        }

        // 2) 원격 이미지. 핀은 48pt 짜리라 아주 작게 받습니다.
        guard let imageURL = spot.imageURL else {
            inFlight.remove(key)
            return
        }

        let requestURL = imageURL.wikimediaPreviewURL(width: 240) ?? imageURL

        URLSession.shared.dataTask(with: requestURL) { [weak self] data, _, _ in
            guard let self else { return }

            guard let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { self.inFlight.remove(key) }
                return
            }

            self.render(key: key, source: image, isSaved: isSaved, completion: completion)
        }
        .resume()
    }

    private func render(
        key: String,
        source: UIImage,
        isSaved: Bool,
        completion: @escaping (NMFOverlayImage) -> Void
    ) {
        // 그리기는 백그라운드에서 해도 안전하지만,
        // NMFOverlayImage 생성과 캐시 갱신은 메인에서 합니다.
        let rendered = ViewfinderMapPhotoPin.image(from: source, isSaved: isSaved)

        DispatchQueue.main.async {
            let overlay = NMFOverlayImage(image: rendered, reuseIdentifier: key)
            self.overlays[key] = overlay
            self.inFlight.remove(key)
            completion(overlay)
        }
    }
}

enum ViewfinderMapPhotoPin {
    /// 핀 전체 크기. 사진 48 + 그림자 여백.
    ///
    /// 꼬리(아래로 뾰족한 삼각형)를 없앴습니다.
    /// 꼬리가 있으면 좌표를 정확히 가리키는 장점이 있지만,
    /// 이 지도에서는 핀이 "사진"이고 사진이 주인공입니다.
    /// 꼬리는 사진 아래에 흰 삼각형을 덧붙여 사각형의 형태를 흐리고,
    /// 핀이 여러 개 모이면 삼각형들이 서로 겹쳐 지저분해집니다.
    static let size = CGSize(width: 54, height: 54)

    private static let photoInset: CGFloat = 3
    private static let photoSide: CGFloat = 48
    private static let cornerRadius: CGFloat = 12

    static func image(from source: UIImage, isSaved: Bool) -> UIImage {
        render(isSaved: isSaved) { innerRect in
            draw(source, filling: innerRect)
        }
    }

    /// 사진이 없거나 아직 로딩 중인 장소용.
    /// 물방울 핀으로 폴백하지 않고, 같은 사각형 안에 조리개 기호만 놓습니다.
    static func placeholderImage(isSaved: Bool) -> UIImage {
        render(isSaved: isSaved) { innerRect in
            UIColor(white: 0.16, alpha: 1).setFill()
            UIBezierPath(rect: innerRect).fill()

            let glyphSide = innerRect.width * 0.46
            let config = UIImage.SymbolConfiguration(
                pointSize: glyphSide,
                weight: .regular
            )

            guard let glyph = UIImage(systemName: "camera.aperture", withConfiguration: config)?
                .withTintColor(UIColor(white: 1, alpha: 0.42), renderingMode: .alwaysOriginal)
            else { return }

            glyph.draw(
                in: CGRect(
                    x: innerRect.midX - glyph.size.width / 2,
                    y: innerRect.midY - glyph.size.height / 2,
                    width: glyph.size.width,
                    height: glyph.size.height
                )
            )
        }
    }

    private static func render(
        isSaved: Bool,
        fillingInner: (CGRect) -> Void
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cgContext = context.cgContext

            let photoRect = CGRect(
                x: photoInset,
                y: photoInset,
                width: photoSide,
                height: photoSide
            )

            let ringColor: UIColor = isSaved ? AppColors.uiAccent : .white
            let ringWidth: CGFloat = isSaved ? 2.6 : 2.0

            // 링. 아래에 그림자를 둬서 어떤 지도 색에서도 떠 보이게 합니다.
            cgContext.saveGState()
            cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 6,
                color: UIColor.black.withAlphaComponent(0.35).cgColor
            )
            ringColor.setFill()
            UIBezierPath(roundedRect: photoRect, cornerRadius: cornerRadius).fill()
            cgContext.restoreGState()

            // 내용을 링 안쪽에 클리핑해서 그립니다.
            let innerRect = photoRect.insetBy(dx: ringWidth, dy: ringWidth)
            let clipPath = UIBezierPath(
                roundedRect: innerRect,
                cornerRadius: cornerRadius - ringWidth
            )

            cgContext.saveGState()
            clipPath.addClip()
            fillingInner(innerRect)
            cgContext.restoreGState()
        }
    }

    /// aspect fill: 잘리더라도 빈 공간이 생기지 않게 채웁니다.
    private static func draw(_ image: UIImage, filling rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let scaledSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let origin = CGPoint(
            x: rect.midX - scaledSize.width / 2,
            y: rect.midY - scaledSize.height / 2
        )

        image.draw(in: CGRect(origin: origin, size: scaledSize))
    }
}

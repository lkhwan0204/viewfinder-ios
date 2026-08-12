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
    /// 사용자가 지금 고른 핀. 이 핀만 커지고 이름표가 붙습니다.
    let selectedPinID: String?
    let onSelectSpot: (PhotoSpot) -> Void
    let onDeselect: () -> Void

    @StateObject private var locationPermission = LocationPermissionRequester()

    var body: some View {
        ZStack {
            NaverMapRepresentable(
                spots: spots,
                selectedSpot: selectedSpot,
                selectedSpotRevision: selectedSpotRevision,
                focusUserLocationRevision: focusUserLocationRevision,
                userCoordinate: userCoordinate,
                selectedPinID: selectedPinID,
                // 핀 탭은 상세를 열지 않습니다.
                //
                // [문제였던 상황]
                // 핀을 누르면 곧바로 화면 72% 를 덮는 상세 시트가 떴습니다.
                // 핀 6개를 둘러보려면 모달을 6번 열고 닫아야 했습니다.
                // 지도는 "둘러보는" 화면인데 한 곳을 볼 때마다 지도가 사라졌습니다.
                //
                // 이제 핀 탭 -> 하단 카드, 카드 탭 -> 상세 두 단계입니다.
                onSelectSpot: onSelectSpot,
                // onFocusSpot 은 updateUIView 안에서 호출됩니다.
                // 거기서 SwiftUI 상태를 바로 고치면
                // "Modifying state during view update" 경고가 납니다.
                onFocusSpot: { spot in
                    DispatchQueue.main.async { onSelectSpot(spot) }
                },
                onDeselect: onDeselect
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
    let selectedPinID: String?
    let onSelectSpot: (PhotoSpot) -> Void
    let onFocusSpot: (PhotoSpot) -> Void
    let onDeselect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectSpot: onSelectSpot, onFocusSpot: onFocusSpot, onDeselect: onDeselect)
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
        context.coordinator.syncMarkers(spots: spots, selectedPinID: selectedPinID, on: naverMapView.mapView)
        if let userCoordinate {
            context.coordinator.focusOnUserLocation(userCoordinate, mapView: naverMapView.mapView, animated: false)
        } else if selectedSpotRevision > 0 {
            context.coordinator.focus(on: selectedSpot, mapView: naverMapView.mapView, animated: false)
        }
        return naverMapView
    }

    func updateUIView(_ naverMapView: NMFNaverMapView, context: Context) {
        context.coordinator.syncMarkers(spots: spots, selectedPinID: selectedPinID, on: naverMapView.mapView)

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
        private let onDeselect: () -> Void
        private var markers: [String: NMFMarker] = [:]

        init(
            onSelectSpot: @escaping (PhotoSpot) -> Void,
            onFocusSpot: @escaping (PhotoSpot) -> Void,
            onDeselect: @escaping () -> Void
        ) {
            self.onSelectSpot = onSelectSpot
            self.onFocusSpot = onFocusSpot
            self.onDeselect = onDeselect
        }

        /// 줌은 그대로 두고 좌표만 화면 중앙 위쪽으로 옮깁니다.
        /// pivot y 0.36 은 선택된 핀이 하단 카드에 가리지 않게 하는 값입니다.
        func center(on spot: PhotoSpot, mapView: NMFMapView) {
            let update = NMFCameraUpdate(
                scrollTo: NMGLatLng(lat: spot.latitude, lng: spot.longitude)
            )
            update.pivot = CGPoint(x: 0.5, y: 0.36)
            update.animation = .easeIn
            update.animationDuration = 0.28
            mapView.moveCamera(update)
            // onFocusSpot 을 부르지 않습니다.
            // 이 메서드는 touchHandler 에서만 호출되고,
            // 그 자리에서 이미 onSelectSpot 으로 선택을 알렸습니다.
        }

        func configure(_ naverMapView: NMFNaverMapView) {
            // 상단: 카테고리 칩 한 줄 + 상태 pill.  하단: 탭바 + 내 위치 버튼.
            // (이전 bottom 220 은 항상 떠 있던 큰 프리뷰 카드를 위한 값이었습니다.
            //  카드가 선택 시에만 나타나도록 바뀌어 그만큼 필요하지 않습니다.
            //  이 값이 네이버 로고를 화면 중앙까지 밀어 올리고 있었습니다.)
            naverMapView.mapView.contentInset = UIEdgeInsets(top: 92, left: 0, bottom: 100, right: 0)
        }

        func syncMarkers(spots: [PhotoSpot], selectedPinID: String?, on mapView: NMFMapView) {
            let incomingIDs = Set(spots.map(\.id))

            for (id, marker) in markers where !incomingIDs.contains(id) {
                marker.mapView = nil
                markers[id] = nil
            }

            for spot in spots {
                let isSelected = spot.id == selectedPinID

                if let marker = markers[spot.id] {
                    marker.position = NMGLatLng(lat: spot.latitude, lng: spot.longitude)
                    configure(marker: marker, spot: spot, isSelected: isSelected)
                    continue
                }

                let marker = NMFMarker(position: NMGLatLng(lat: spot.latitude, lng: spot.longitude))
                configure(marker: marker, spot: spot, isSelected: isSelected)
                marker.userInfo = ["spotID": spot.id, "title": spot.name]
                marker.touchHandler = { [weak self] overlay in
                    guard let self else { return true }

                    // 같은 핀을 다시 누르면 선택을 해제합니다.
                    // (지도 빈 곳 탭으로 해제하려면 터치 델리게이트가 필요한데,
                    //  검증할 수 없는 SDK API 라서 재탭 토글로 대신합니다.)
                    if self.selectedSpotID == spot.id {
                        self.selectedSpotID = nil
                        self.onDeselect()
                        return true
                    }

                    self.selectedSpotID = spot.id
                    self.onSelectSpot(spot)
                    // 확대는 하지 않습니다. 핀을 하나씩 눌러보는 중인데
                    // 매번 줌이 14.5 로 튀면 둘러보던 맥락이 사라집니다.
                    self.center(on: spot, mapView: mapView)
                    return true
                }
                marker.mapView = mapView
                markers[spot.id] = marker
            }
        }

        private func configure(marker: NMFMarker, spot: PhotoSpot, isSelected: Bool) {
            // ═══════════════════════════════════════════════════════
            //  이름표는 선택된 핀에만 붙입니다.
            //
            //  [문제였던 상황]
            //  모든 핀에 이름을 강제로 표시(isForceShowCaption = true)했더니
            //  우리 캡션("보래매공원", "푸른수목원")이 네이버 자체 라벨
            //  ("국회의사당", "여의도한강공원")과 뒤섞여서
            //  어느 것이 우리 콘텐츠인지 구분되지 않았습니다.
            //
            //  사진이 이미 "여기 뭔가 있다"를 말하고 있습니다.
            //  이름은 사용자가 그 핀을 골랐을 때 필요한 정보입니다.
            // ═══════════════════════════════════════════════════════
            if isSelected {
                marker.captionText = spot.name
                marker.captionTextSize = 13
                marker.captionRequestedWidth = 108
                marker.captionColor = AppColors.uiPrimary
                marker.captionHaloColor = AppColors.uiCardBackground.withAlphaComponent(0.96)
                marker.captionAligns = [NMFAlignType.bottom]
                marker.captionOffset = 4
            } else {
                marker.captionText = ""
            }

            marker.iconTintColor = .clear
            // 꼬리가 없어졌으므로 좌표에 정사각형의 "중심"을 맞춥니다.
            // (꼬리가 있을 때는 아래 끝이 좌표를 가리켰으므로 y: 1.0 이었습니다.)
            marker.anchor = CGPoint(x: 0.5, y: 0.5)
            marker.isHideCollidedSymbols = false
            marker.isHideCollidedMarkers = false
            marker.isHideCollidedCaptions = false
            marker.isForceShowIcon = true
            marker.isForceShowCaption = isSelected
            // 선택된 핀이 이웃 핀에 가리지 않게 위로 올립니다.
            marker.zIndex = isSelected ? 100 : 0

            // 핀은 항상 사진 정사각형입니다.
            //
            // 이전에는 사진을 못 구하면 검은 물방울 핀으로 폴백했는데,
            // 한 화면에 물방울과 사진 사각형이 섞여 나와 핀이 두 종류로 보였습니다.
            // 지금은 사진이 없거나 아직 로딩 중이면 같은 크기·같은 모양의
            // 회색 자리표시 사각형을 쓰고, 사진이 도착하면 그 자리에서 교체합니다.
            if let photoOverlay = MapPinPhotoStore.shared.cachedOverlay(for: spot, isSelected: isSelected) {
                apply(photoOverlay: photoOverlay, isSelected: isSelected, to: marker)
            } else {
                apply(
                    photoOverlay: MapPinPhotoStore.shared.placeholderOverlay(isSelected: isSelected),
                    isSelected: isSelected,
                    to: marker
                )

                MapPinPhotoStore.shared.loadOverlay(for: spot, isSelected: isSelected) { [weak self] overlay in
                    guard let self, let target = self.markers[spot.id] else { return }
                    self.apply(photoOverlay: overlay, isSelected: isSelected, to: target)
                }
            }
        }

        private func apply(photoOverlay: NMFOverlayImage, isSelected: Bool, to marker: NMFMarker) {
            let size = ViewfinderMapPhotoPin.size(isSelected: isSelected)
            marker.iconImage = photoOverlay
            marker.width = size.width
            marker.height = size.height
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
    /// 원본 사진. 선택 상태가 바뀔 때 핀을 다시 그려야 하는데,
    /// 원본이 없으면 매번 네트워크를 다시 타게 됩니다.
    private var sources: [String: UIImage] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    private func cacheKey(spotID: String, isSelected: Bool) -> String {
        "vf-photo-pin-\(spotID)-\(isSelected ? "selected" : "idle")"
    }

    /// 즉시 쓸 수 있는 핀을 반환합니다. (메인 스레드에서만 호출)
    ///
    /// 완성된 핀이 없더라도 원본 사진이 캐시에 있으면 그 자리에서 그려서 줍니다.
    /// 핀을 선택/해제할 때 사진을 다시 받지 않게 하려는 것입니다.
    func cachedOverlay(for spot: PhotoSpot, isSelected: Bool) -> NMFOverlayImage? {
        let key = cacheKey(spotID: spot.id, isSelected: isSelected)

        if let existing = overlays[key] {
            return existing
        }

        guard let source = sources[spot.id] else { return nil }

        let overlay = NMFOverlayImage(
            image: ViewfinderMapPhotoPin.image(from: source, isSelected: isSelected),
            reuseIdentifier: key
        )
        overlays[key] = overlay
        return overlay
    }

    /// 사진이 없거나 로딩 중일 때 쓰는 자리표시 핀.
    /// 사진 핀과 같은 크기·같은 모양이라 지도에 핀이 두 종류로 보이지 않습니다.
    func placeholderOverlay(isSelected: Bool) -> NMFOverlayImage {
        let key = "vf-photo-pin-placeholder-\(isSelected ? "selected" : "idle")"

        if let existing = overlays[key] {
            return existing
        }

        let overlay = NMFOverlayImage(
            image: ViewfinderMapPhotoPin.placeholderImage(isSelected: isSelected),
            reuseIdentifier: key
        )
        overlays[key] = overlay
        return overlay
    }

    /// 사진 핀을 준비합니다. 완료 콜백은 메인 스레드에서 호출됩니다.
    /// 사진을 구할 수 없으면 콜백이 호출되지 않고, 호출부는 자리표시 핀을 유지합니다.
    func loadOverlay(
        for spot: PhotoSpot,
        isSelected: Bool,
        completion: @escaping (NMFOverlayImage) -> Void
    ) {
        if let ready = cachedOverlay(for: spot, isSelected: isSelected) {
            completion(ready)
            return
        }

        let fetchKey = "fetch-\(spot.id)"
        guard !inFlight.contains(fetchKey) else { return }
        inFlight.insert(fetchKey)

        // 1) 번들 애셋이 있으면 네트워크를 타지 않습니다.
        if let imageName = spot.imageName, let asset = UIImage(named: imageName) {
            finish(spotID: spot.id, fetchKey: fetchKey, source: asset, isSelected: isSelected, completion: completion)
            return
        }

        // 2) 원격 이미지. 핀은 48pt 짜리라 아주 작게 받습니다.
        guard let imageURL = spot.imageURL else {
            inFlight.remove(fetchKey)
            return
        }

        let requestURL = imageURL.wikimediaPreviewURL(width: 240) ?? imageURL

        URLSession.shared.dataTask(with: requestURL) { [weak self] data, _, _ in
            guard let self else { return }

            guard let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { self.inFlight.remove(fetchKey) }
                return
            }

            self.finish(
                spotID: spot.id,
                fetchKey: fetchKey,
                source: image,
                isSelected: isSelected,
                completion: completion
            )
        }
        .resume()
    }

    private func finish(
        spotID: String,
        fetchKey: String,
        source: UIImage,
        isSelected: Bool,
        completion: @escaping (NMFOverlayImage) -> Void
    ) {
        // 그리기는 백그라운드에서 해도 안전하지만,
        // NMFOverlayImage 생성과 캐시 갱신은 메인에서 합니다.
        let rendered = ViewfinderMapPhotoPin.image(from: source, isSelected: isSelected)
        let key = cacheKey(spotID: spotID, isSelected: isSelected)

        DispatchQueue.main.async {
            self.sources[spotID] = source
            let overlay = NMFOverlayImage(image: rendered, reuseIdentifier: key)
            self.overlays[key] = overlay
            self.inFlight.remove(fetchKey)
            completion(overlay)
        }
    }
}

enum ViewfinderMapPhotoPin {
    /// 기본 핀 크기. 사진 48 + 그림자 여백.
    ///
    /// 꼬리(아래로 뾰족한 삼각형)는 없습니다.
    /// 이 지도에서 핀은 "사진"이고 사진이 주인공입니다.
    /// 꼬리는 사각형의 형태를 흐리고, 핀이 모이면 삼각형끼리 겹칩니다.
    static let size = CGSize(width: 54, height: 54)

    /// 선택된 핀. 카드에 뜬 장소가 지도의 어느 핀인지 눈으로 찾을 수 있어야 합니다.
    static let selectedSize = CGSize(width: 68, height: 68)

    static func size(isSelected: Bool) -> CGSize {
        isSelected ? selectedSize : size
    }

    static func image(from source: UIImage, isSelected: Bool) -> UIImage {
        render(isSelected: isSelected) { innerRect in
            draw(source, filling: innerRect)
        }
    }

    /// 사진이 없거나 아직 로딩 중인 장소용.
    /// 물방울 핀으로 폴백하지 않고, 같은 사각형 안에 조리개 기호만 놓습니다.
    static func placeholderImage(isSelected: Bool) -> UIImage {
        render(isSelected: isSelected) { innerRect in
            UIColor(white: 0.16, alpha: 1).setFill()
            UIBezierPath(rect: innerRect).fill()

            let config = UIImage.SymbolConfiguration(
                pointSize: innerRect.width * 0.46,
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

    // ═══════════════════════════════════════════════════════════════
    //  링 색에서 isSaved 를 뺐습니다.
    //
    //  전에는 저장한 장소의 링을 앰버로 칠했습니다. 그런데
    //   1. 선택된 핀도 앰버로 칠해야 하므로 두 상태가 같은 색이 됩니다.
    //   2. 저장 모드에서는 화면의 모든 핀이 저장된 것이라 전부 앰버가 되어
    //      구분 정보가 0이 되고 화면만 시끄러워집니다.
    //
    //  앰버는 "지금 선택된 것" 하나에만 씁니다.
    //  (VFDesign 의 규칙: 앰버는 한 화면에 2곳 이하, 의미는 하나)
    //  저장 여부는 하단 카드의 북마크 아이콘이 말해줍니다.
    // ═══════════════════════════════════════════════════════════════
    private static func render(
        isSelected: Bool,
        fillingInner: (CGRect) -> Void
    ) -> UIImage {
        let canvas = size(isSelected: isSelected)
        let inset: CGFloat = isSelected ? 4 : 3
        let cornerRadius: CGFloat = isSelected ? 16 : 12
        let ringWidth: CGFloat = isSelected ? 3 : 2
        let ringColor: UIColor = isSelected ? AppColors.uiAccent : .white

        let renderer = UIGraphicsImageRenderer(size: canvas)

        return renderer.image { context in
            let cgContext = context.cgContext

            let photoRect = CGRect(
                x: inset,
                y: inset,
                width: canvas.width - inset * 2,
                height: canvas.height - inset * 2
            )

            // 링. 아래에 그림자를 둬서 어떤 지도 색에서도 떠 보이게 합니다.
            cgContext.saveGState()
            cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: isSelected ? 8 : 6,
                color: UIColor.black.withAlphaComponent(isSelected ? 0.45 : 0.35).cgColor
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

    /// 원본을 대상 영역에 aspect fill 로 그립니다.
    private static func draw(_ image: UIImage, filling rect: CGRect) {
        let imageSize = image.size

        guard imageSize.width > 0, imageSize.height > 0 else {
            UIColor(white: 0.16, alpha: 1).setFill()
            UIBezierPath(rect: rect).fill()
            return
        }

        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        image.draw(
            in: CGRect(
                x: rect.midX - drawSize.width / 2,
                y: rect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
        )
    }
}

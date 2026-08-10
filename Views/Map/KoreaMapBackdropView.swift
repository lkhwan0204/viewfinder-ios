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
        naverMapView.mapView.logoAlign = .rightBottom
        naverMapView.mapView.logoMargin = UIEdgeInsets(top: 0, left: 0, bottom: 92, right: 14)
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
            naverMapView.mapView.contentInset = UIEdgeInsets(top: 86, left: 0, bottom: 220, right: 0)
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
            marker.captionOffset = 5
            marker.iconImage = isSaved ? ViewfinderMapMarkerIcon.saved : ViewfinderMapMarkerIcon.normal
            marker.iconTintColor = .clear
            marker.width = 38
            marker.height = 50
            marker.anchor = CGPoint(x: 0.5, y: 1.0)
            marker.isHideCollidedSymbols = false
            marker.isHideCollidedMarkers = false
            marker.isHideCollidedCaptions = false
            marker.isForceShowIcon = true
            marker.isForceShowCaption = true
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

    func makeUIView(context: Context) -> NMFNaverMapView {
        let naverMapView = NMFNaverMapView(frame: .zero)
        naverMapView.showCompass = false
        naverMapView.showScaleBar = false
        naverMapView.showZoomControls = false
        naverMapView.showLocationButton = false
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
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 46, height: 46)
                .background(AppColors.cardBackground, in: Circle())
                .overlay(
                    Circle()
                        .stroke(AppColors.divider, lineWidth: 1)
                )
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

    static let normal: NMFOverlayImage = makeOverlayImage(
        size: CGSize(width: 38, height: 50),
        fillColor: markerFillColor,
        strokeColor: markerStrokeColor,
        centerColor: markerCenterColor,
        reuseIdentifier: "viewfinder-marker-normal-fixed-v1"
    )

    static let preview: NMFOverlayImage = makeOverlayImage(
        size: CGSize(width: 42, height: 54),
        fillColor: markerFillColor,
        strokeColor: markerStrokeColor,
        centerColor: markerCenterColor,
        reuseIdentifier: "viewfinder-marker-preview-fixed-v1"
    )

    static let saved: NMFOverlayImage = makeOverlayImage(
        size: CGSize(width: 38, height: 50),
        fillColor: markerFillColor,
        strokeColor: markerStrokeColor,
        centerColor: markerCenterColor,
        reuseIdentifier: "viewfinder-marker-saved-fixed-v1",
        centerStyle: .bookmark
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

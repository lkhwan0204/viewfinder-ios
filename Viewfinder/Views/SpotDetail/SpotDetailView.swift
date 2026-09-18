import CoreLocation
import Foundation
import SwiftUI
import UIKit

enum SpotDetailSource {
    case home
    case search
    case map
    case community
    case saved

    var detents: Set<PresentationDetent> {
        switch self {
        case .map:
            return [.fraction(0.72), .large]
        case .home, .search, .community, .saved:
            return [.large]
        }
    }

    var isMapContext: Bool {
        self == .map
    }

    var isCompact: Bool {
        self == .map
    }
}

struct SpotDetailPresentation: Identifiable {
    let id = UUID()
    let spot: PhotoSpot
    let source: SpotDetailSource
}

struct SpotDetailView: View {
    @ObservedObject var authViewModel: AuthViewModel
    let spot: PhotoSpot
    let source: SpotDetailSource
    let isSaved: Bool
    let communityPosts: [CommunityPost]
    let placePhotos: [PlacePhoto]
    let placePhotoGalleryStore: PlacePhotoGalleryStore
    let crowdReports: [CrowdReport]
    @ObservedObject var crowdReportStore: CrowdReportStore
    let currentUserID: String
    let spots: [PhotoSpot]
    /// 거리 표시용. 없으면 거리 지표가 "위치 확인 필요" 로 표시됩니다.
    var userLocation: CLLocationCoordinate2D? = nil
    let onToggleSave: () -> Void
    let onOpenMap: () -> Void
    let onReportPhoto: () -> Void
    let onSubmitCrowdReport: (CommunityPost.Crowd) -> Void
    let onSubmitCommunity: (CommunityPostDraft) -> Void
    let onUpdateCommunity: (CommunityPost, CommunityPostDraft) -> Void
    let onDeleteCommunity: (CommunityPost) -> Void
    @ObservedObject var communityViewModel: CommunityViewModel
    let onToggleCommunityLike: (CommunityPost) -> Void
    let onToggleCommunityFollow: (CommunityPost) -> Void
    let onAddCommunityComment: (String, CommunityPost) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDirectionsDialogPresented = false
    @State private var isCommunityComposerPresented = false
    @State private var editingCommunityPost: CommunityPost?
    @State private var authenticationDestination: AuthenticationDestination?
    @State private var pendingAuthenticatedAction: (() -> Void)?
    @State private var isVisitInformationExpanded = false
    @State private var sessionGalleryPhotos: [PlacePhoto]
    @State private var selectedGalleryIndex = 0

    init(
        authViewModel: AuthViewModel,
        spot: PhotoSpot,
        source: SpotDetailSource,
        isSaved: Bool,
        communityPosts: [CommunityPost],
        placePhotos: [PlacePhoto] = [],
        placePhotoGalleryStore: PlacePhotoGalleryStore? = nil,
        crowdReports: [CrowdReport] = [],
        crowdReportStore: CrowdReportStore? = nil,
        currentUserID: String,
        spots: [PhotoSpot],
        userLocation: CLLocationCoordinate2D? = nil,
        onToggleSave: @escaping () -> Void,
        onOpenMap: @escaping () -> Void,
        onReportPhoto: @escaping () -> Void,
        onSubmitCrowdReport: @escaping (CommunityPost.Crowd) -> Void = { _ in },
        onSubmitCommunity: @escaping (CommunityPostDraft) -> Void,
        onUpdateCommunity: @escaping (CommunityPost, CommunityPostDraft) -> Void,
        onDeleteCommunity: @escaping (CommunityPost) -> Void,
        communityViewModel: CommunityViewModel? = nil,
        onToggleCommunityLike: @escaping (CommunityPost) -> Void = { _ in },
        onToggleCommunityFollow: @escaping (CommunityPost) -> Void = { _ in },
        onAddCommunityComment: @escaping (String, CommunityPost) -> Bool = { _, _ in false }
    ) {
        self.authViewModel = authViewModel
        self.spot = spot
        self.source = source
        self.isSaved = isSaved
        self.communityPosts = communityPosts
        self.placePhotos = placePhotos
        self.placePhotoGalleryStore = placePhotoGalleryStore ?? .shared
        self.crowdReports = crowdReports
        self._crowdReportStore = ObservedObject(wrappedValue: crowdReportStore ?? .shared)
        self.currentUserID = currentUserID
        self.spots = spots
        self.userLocation = userLocation
        self.onToggleSave = onToggleSave
        self.onOpenMap = onOpenMap
        self.onReportPhoto = onReportPhoto
        self.onSubmitCrowdReport = onSubmitCrowdReport
        self.onSubmitCommunity = onSubmitCommunity
        self.onUpdateCommunity = onUpdateCommunity
        self.onDeleteCommunity = onDeleteCommunity
        self._communityViewModel = ObservedObject(wrappedValue: communityViewModel ?? CommunityViewModel())
        self.onToggleCommunityLike = onToggleCommunityLike
        self.onToggleCommunityFollow = onToggleCommunityFollow
        self.onAddCommunityComment = onAddCommunityComment
        _sessionGalleryPhotos = State(
            initialValue: PlacePhotoPool.select(
                from: placePhotos.isEmpty ? PlacePhotoPool.candidates(for: spot) : placePhotos
            )
        )
    }

    private var isDetailOverlayPresented: Bool {
        isDirectionsDialogPresented
            || isCommunityComposerPresented
            || authenticationDestination != nil
    }

    private var isCrowdReportSubmitting: Bool {
        guard !currentUserID.isEmpty else { return false }
        return crowdReportStore.isSubmitting(
            placeID: spot.id,
            authorID: currentUserID
        )
    }

    private var isCrowdReportLoading: Bool {
        crowdReportStore.isLoading(placeID: spot.id)
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding = detailHorizontalPadding
            let contentWidth = max(0, proxy.size.width - horizontalPadding * 2)

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: source.isCompact ? 14 : 20) {
                        SpotDetailPhotoGallery(
                            spot: spot,
                            photos: sessionGalleryPhotos,
                            selectedIndex: $selectedGalleryIndex,
                            height: heroHeight(in: proxy.size),
                            cornerRadius: source.isMapContext ? AppLayout.cardCornerRadius : 0,
                            showsBorder: source.isMapContext,
                            onReportPhoto: {
                                requireAuthentication(action: onReportPhoto)
                            }
                        )
                            // 사진 진입(전체 화면)에서는 화면 폭을 꽉 채웁니다.
                            // 음수 패딩으로 부모의 좌우 마진을 상쇄합니다.
                            .frame(width: source.isMapContext ? contentWidth : proxy.size.width)

                            .padding(
                                .horizontal,
                                source.isMapContext ? 0 : -horizontalPadding
                            )

                        header
                        shootingConditions
                        visitInformation

                        if !source.isMapContext {
                            mapPreview
                        }

                        SpotDetailCommunitySection(
                            spot: spot,
                            posts: communityPosts,
                            crowdReports: crowdReports,
                            currentUserID: currentUserID,
                            spots: spots,
                            isCrowdReportSubmitting: isCrowdReportSubmitting,
                            isCrowdReportLoading: isCrowdReportLoading,
                            onReportCrowd: { crowd in
                                requireAuthentication {
                                    onSubmitCrowdReport(crowd)
                                }
                            },
                            onEdit: { post in
                                requireAuthentication {
                                    editingCommunityPost = post
                                    isCommunityComposerPresented = true
                                }
                            },
                            onDelete: { post in
                                requireAuthentication {
                                    onDeleteCommunity(post)
                                }
                            },
                            communityViewModel: communityViewModel,
                            onToggleLike: { post in
                                requireAuthentication {
                                    onToggleCommunityLike(post)
                                }
                            },
                            onToggleFollow: { post in
                                requireAuthentication {
                                    onToggleCommunityFollow(post)
                                }
                            },
                            onAddComment: { message, post in
                                onAddCommunityComment(message, post)
                            }
                        )
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    // full-bleed 사진이 화면 최상단에 붙어야 하므로
                    // 전체 화면일 때는 상단 여백을 두지 않습니다.
                    .padding(.top, source.isMapContext ? 12 : 0)
                    .padding(.bottom, actionBarOverlayReserve)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: proxy.size.width)

                actionBar
                    .frame(width: proxy.size.width)
                    .padding(.bottom, actionBarBottomPadding)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .accessibilityHidden(isDetailOverlayPresented)
        .background(AppColors.background.ignoresSafeArea())
        .confirmationDialog("길찾기 앱 선택", isPresented: $isDirectionsDialogPresented, titleVisibility: .visible) {
            ForEach(MapProvider.allCases) { provider in
                Button(provider.title) {
                    openDirections(with: provider)
                }
            }

            Button("취소", role: .cancel) {}
        }
        .sheet(isPresented: $isCommunityComposerPresented) {
            CommunityComposerView(
                spots: spots,
                selectedSpot: spot,
                locksSelectedSpot: true,
                editingPost: editingCommunityPost,
                onSubmit: { draft in
                    if let editingCommunityPost {
                        onUpdateCommunity(editingCommunityPost, draft)
                    } else {
                        onSubmitCommunity(draft)
                    }
                    self.editingCommunityPost = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(
            item: $authenticationDestination,
            onDismiss: resumePendingAuthenticatedActionIfPossible
        ) { _ in
            LoginView(authViewModel: authViewModel)
        }
        .task(id: spot.id) {
            let loadedPhotos = await placePhotoGalleryStore.load(for: spot)
            sessionGalleryPhotos = PlacePhotoPool.select(
                from: loadedPhotos.isEmpty ? PlacePhotoPool.candidates(for: spot) : loadedPhotos
            )
            selectedGalleryIndex = min(selectedGalleryIndex, max(sessionGalleryPhotos.count - 1, 0))
            await crowdReportStore.load(for: spot)
        }
    }

    private func requireAuthentication(action: @escaping () -> Void) {
        guard !authViewModel.isAuthenticated else {
            action()
            return
        }

        pendingAuthenticatedAction = action
        authViewModel.prepareForSignInPresentation()
        authenticationDestination = .signIn
    }

    private func resumePendingAuthenticatedActionIfPossible() {
        guard authViewModel.isAuthenticated else {
            pendingAuthenticatedAction = nil
            return
        }

        let action = pendingAuthenticatedAction
        pendingAuthenticatedAction = nil
        DispatchQueue.main.async {
            guard authViewModel.isAuthenticated else { return }
            action?()
        }
    }

    /// 대표 사진 높이.
    ///
    /// 전체 화면에서는 화면 높이의 44% 를 씁니다. 홈 Hero(72%)보다는 작지만
    /// 사진이 먼저 눈에 들어오고, 아래 정보도 함께 보이는 균형점입니다.
    private func heroHeight(in size: CGSize) -> CGFloat {
        if source.isCompact {
            return 172
        }
        return max(300, size.height * 0.44)
    }

    private var detailHorizontalPadding: CGFloat {
        source.isCompact ? 14 : AppLayout.pageHorizontalPadding
    }

    private var actionBarOverlayReserve: CGFloat {
        actionButtonHeight + actionBarBottomPadding + (source.isCompact ? 16 : 18)
    }

    private var actionBarBottomPadding: CGFloat {
        source.isCompact ? 15 : 17
    }

    @ViewBuilder
    private var actionBar: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                actionButtons
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
            .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: actionBarCornerRadius, style: .continuous)
                    )
            }
            .padding(.horizontal, source.isCompact ? 14 : 18)
        } else {
            actionButtons
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: actionBarCornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: actionBarCornerRadius, style: .continuous)
                        .stroke(AppColors.divider.opacity(0.82), lineWidth: 1)
                )
                .padding(.horizontal, source.isCompact ? 14 : 18)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            if !source.isMapContext {
                Button {
                    dismiss()
                    onOpenMap()
                } label: {
                    DetailActionButton(title: "지도에서 보기", symbolName: "map.fill", isPrimary: false, height: actionButtonHeight)
                }
                .buttonStyle(.plain)
            }

            if !source.isMapContext {
                NativeActionDivider()
            }

            Button {
                isDirectionsDialogPresented = true
            } label: {
                DetailActionButton(title: "길찾기", symbolName: "location.fill", isPrimary: true, height: actionButtonHeight)
            }
            .buttonStyle(.plain)

        }
    }

    private var actionButtonHeight: CGFloat {
        AppLayout.touchTarget
    }

    private var actionBarCornerRadius: CGFloat {
        source.isCompact ? 22 : 24
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: source.isCompact ? 8 : 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(source.isCompact ? AppTypography.sectionTitle : AppTypography.prominentCardTitle)
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(HomeSpotDisplayFormatter.region(for: spot))
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // 저장은 하단 액션 바에서 여기로 옮겼습니다.
                // 액션 바의 "지도에서 보기 / 길찾기" 는 장소로 이동하는 동작이고,
                // 저장은 장소 자체에 대한 상태 토글이라 성격이 다릅니다.
                // 제목 반대편에 두면 "이 장소를 저장한다" 는 관계가 분명해집니다.
                VFSaveButton(
                    isSaved: isSaved,
                    action: onToggleSave,
                    diameter: 30,
                    style: .plain
                )
                .offset(y: -4)
            }

            Text(spot.summary)
                .font(source.isCompact ? AppTypography.metadata : AppTypography.body)
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(source.isCompact ? 2 : 2)
                .lineSpacing(1)

            VFMetaLine(items: decisionSummaryItems)

            HStack(spacing: 6) {
                ForEach(spot.hashtags.prefix(2), id: \.self) { tag in
                    Text("#\(tag.replacingOccurrences(of: "#", with: ""))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
    }

    private func openDirections(with provider: MapProvider) {
        let appURL = spot.directionsURL(for: provider)
        if UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
        } else {
            openURL(spot.fallbackDirectionsURL(for: provider))
        }
    }

    private var shootingConditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "촬영 가이드",
                subtitle: "현장에서 바로 판단할 수 있는 정보예요"
            )

            LazyVGrid(
                columns: shootingConditionColumns,
                spacing: 10
            ) {
                SpotShootingMetric(
                    symbolName: "clock.fill",
                    title: "추천 시간",
                    value: HomeSpotDisplayFormatter.bestTime(spot.bestTime)
                )
                SpotShootingMetric(
                    symbolName: "clock.badge.checkmark.fill",
                    title: "이용 시간",
                    value: openingHoursMetricValue
                )
            }
            SpotShootingMetric(
                symbolName: "cloud.sun.fill",
                title: "날씨 궁합",
                value: spot.weatherFit
            )
        }
    }

    private var decisionSummaryItems: [String] {
        [
            VFSpotDistance.text(from: userLocation, to: spot)
                ?? HomeSpotDisplayFormatter.region(for: spot),
            HomeSpotDisplayFormatter.bestTime(spot.bestTime)
        ]
    }

    private var shootingConditionColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    /// 지금 들어갈 수 있는지. 사진가가 출발 전 가장 먼저 확인하는 정보입니다.
    ///
    /// 기존에는 "방문 전 확인" 접힌 영역 안에만 있어서 잘 보이지 않았습니다.
    /// 촬영 가이드로 끌어올리고 접힌 영역에서는 제거했습니다.
    private var openingHoursMetricValue: String {
        let hours = spot.openingHours.trimmingCharacters(in: .whitespacesAndNewlines)
        return hours.isEmpty ? "정보 없음" : hours
    }

    private var visitInformation: some View {
        DisclosureGroup(isExpanded: $isVisitInformationExpanded) {
            VStack(spacing: 14) {
                // "추천 이유"(eventTitle) 행을 제거했습니다.
                // 이 섹션은 운영시간/비용/주차를 확인하는 곳이라
                // 추천 이유가 들어갈 자리가 아니었습니다.
                DetailInfoRow(symbolName: "ticket.fill", title: "입장/비용", value: spot.feeInfo, tint: AppColors.secondaryText)
                DetailInfoRow(
                    symbolName: "parkingsign.circle.fill",
                    title: "주차",
                    value: "\(spot.parkingInfo) · \(spot.nearbyParkingInfo)",
                    tint: AppColors.secondaryText
                )
            }
            .padding(.top, 14)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text("방문 전 확인")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.primary)
                    Text("비용과 주차 정보를 확인하세요")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .tint(AppColors.accent)
        .padding(16)
        .appCardSurface()
    }

    private var mapPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "위치 미리보기",
                subtitle: HomeSpotDisplayFormatter.region(for: spot)
            )

            SpotHeroMap(spot: spot)
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.mediaCornerRadius, style: .continuous))
        }
    }
}

struct SpotDetailHeroImage: View {
    let spot: PhotoSpot
    let height: CGFloat
    /// full-bleed 로 쓸 때는 0. 지도 시트에서는 카드처럼 둥글게.
    var cornerRadius: CGFloat = AppLayout.cardCornerRadius
    /// full-bleed 에서는 테두리를 그리지 않습니다.
    var showsBorder: Bool = true
    let onReportPhoto: () -> Void

    var body: some View {
        Group {
            if spot.hasReliableDisplayImage {
                ZStack(alignment: .bottomTrailing) {
                    // 상세 화면 대표 사진은 화면 폭을 채우므로 hero 해상도로 받습니다.
                    PhotoSpotImageView(
                        spot: spot,
                        symbolSize: 34,
                        targetPixelWidth: VFPhotoDetail.hero.pixelWidth
                    )

                    if let attributionText {
                        Text(attributionText)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(.black.opacity(0.42), in: Capsule())
                            .padding(8)
                    }
                }
            } else {
                Button(action: onReportPhoto) {
                    ZStack(alignment: .bottom) {
                        MissingSpotPhotoPrompt(layout: .hero)

                        Text("대표 사진 제보")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 15)
                            .frame(height: 34)
                            .background(AppColors.cardBackground, in: Capsule())
                            .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                            .padding(.bottom, 15)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.divider.opacity(0.65), lineWidth: 1)
            }
        }
    }

    private var attributionText: String? {
        guard let credit = spot.imageCredit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !credit.isEmpty else {
            return nil
        }

        if let license = spot.imageLicense?.trimmingCharacters(in: .whitespacesAndNewlines),
           !license.isEmpty {
            return "\(credit) · \(license)"
        }

        return credit
    }
}

struct SpotDetailPhotoGallery: View {
    let spot: PhotoSpot
    let photos: [PlacePhoto]
    @Binding var selectedIndex: Int
    let height: CGFloat
    var cornerRadius: CGFloat = AppLayout.cardCornerRadius
    var showsBorder: Bool = true
    let onReportPhoto: () -> Void

    var body: some View {
        Group {
            if photos.isEmpty {
                Button(action: onReportPhoto) {
                    ZStack(alignment: .bottom) {
                        MissingSpotPhotoPrompt(layout: .hero)

                        Text("대표 사진 제보")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 15)
                            .frame(height: 34)
                            .background(AppColors.cardBackground, in: Capsule())
                            .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                            .padding(.bottom, 15)
                    }
                }
                .buttonStyle(.plain)
            } else {
                ZStack(alignment: .bottomTrailing) {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            SpotDetailGalleryImage(photo: photo)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    VStack {
                        HStack {
                            Spacer(minLength: 0)

                            Button(action: onReportPhoto) {
                                Label("사진 추가", systemImage: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(.black.opacity(0.46), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("이 장소에 사진 추가")
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(10)

                    HStack(spacing: 8) {
                        if let attributionText {
                            Text(attributionText)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .frame(height: 22)
                                .background(.black.opacity(0.42), in: Capsule())
                        }

                        if photos.count > 1 {
                            Text("\(min(selectedIndex + 1, photos.count)) / \(photos.count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(.black.opacity(0.48), in: Capsule())
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.divider.opacity(0.65), lineWidth: 1)
            }
        }
    }

    private var attributionText: String? {
        guard let credit = spot.imageCredit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !credit.isEmpty else {
            return nil
        }

        if let license = spot.imageLicense?.trimmingCharacters(in: .whitespacesAndNewlines),
           !license.isEmpty {
            return "\(credit) · \(license)"
        }

        return credit
    }
}

private struct SpotDetailGalleryImage: View {
    let photo: PlacePhoto
    @State private var revealedRemoteImageKey: String?

    var body: some View {
        Group {
            if let imageData = photo.imageData,
               let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let imageName = photo.imageName,
                      let image = UIImage(named: imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let imageURL = photo.imageURL {
                AsyncImage(
                    url: imageURL,
                    transaction: Transaction(animation: .easeOut(duration: 0.18))
                ) { phase in
                    ZStack {
                        placeholderSurface

                        switch phase {
                        case .empty:
                            EmptyView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .opacity(revealedRemoteImageKey == imageURL.absoluteString ? 1 : 0)
                                .onAppear {
                                    guard revealedRemoteImageKey != imageURL.absoluteString else { return }
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        revealedRemoteImageKey = imageURL.absoluteString
                                    }
                                }
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                }
                .onChange(of: imageURL) { _, newURL in
                    guard revealedRemoteImageKey != newURL.absoluteString else { return }
                    revealedRemoteImageKey = nil
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        placeholderSurface
            .overlay {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText.opacity(0.58))
            }
    }

    private var placeholderSurface: some View {
        AppColors.mutedSurface
            .overlay {
                Rectangle()
                    .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
            }
    }
}

struct SpotHeroMap: View {
    let spot: PhotoSpot

    var body: some View {
        // 기존에는 allowsHitTesting(false) 로 지도가 완전히 상호작용 불가였습니다.
        // 위치만 확인할 수 있었고 확대/축소가 아예 되지 않았습니다.
        //
        // 핀치 확대/축소와 확대 버튼은 켜고, 지도 패닝(드래그)은 끕니다.
        // 상세 화면이 세로 스크롤 시트라서 지도 패닝을 허용하면
        // 지도 위에서 손가락을 움직일 때 화면 스크롤이 막힙니다.
        // 위치를 옮겨서 둘러보는 것은 "지도에서 보기" 전체 지도에서 하도록 유도합니다.
        NaverSpotPreviewMap(spot: spot, allowsZoom: true)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous))
    }
}

func communityRelativeTimeText(for date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 {
        return "방금 전"
    }

    let minutes = Int(interval / 60)
    if minutes < 60 {
        return "\(minutes)분 전"
    }

    let hours = Int(interval / (60 * 60))
    if hours < 24 {
        return "\(hours)시간 전"
    }

    if Calendar.current.isDateInYesterday(date) {
        return "어제"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "M월 d일"
    return formatter.string(from: date)
}

func communityAbsoluteTimeText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy.MM.dd a h:mm"
    return formatter.string(from: date)
}

func communityWrittenTimeText(for date: Date) -> String {
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "ko_KR")
    timeFormatter.dateFormat = "a h:mm"
    let timeText = timeFormatter.string(from: date)

    if Calendar.current.isDateInToday(date) {
        return "오늘 \(timeText) 작성"
    }

    if Calendar.current.isDateInYesterday(date) {
        return "어제 \(timeText) 작성"
    }

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ko_KR")
    dateFormatter.dateFormat = "M월 d일"
    return "\(dateFormatter.string(from: date)) \(timeText) 작성"
}

struct SpotDetailCommunitySection: View {
    let spot: PhotoSpot
    let posts: [CommunityPost]
    let crowdReports: [CrowdReport]
    let currentUserID: String
    let spots: [PhotoSpot]
    let isCrowdReportSubmitting: Bool
    let isCrowdReportLoading: Bool
    let onReportCrowd: (CommunityPost.Crowd) -> Void
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) -> Void
    @ObservedObject var communityViewModel: CommunityViewModel
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool

    @State private var isCommunityPostsPresented = false

    private var relatedCommunityPosts: [CommunityPost] {
        var seenIDs = Set<String>()

        return posts
            .filter { $0.relatedSpotID == spot.id }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seenIDs.insert($0.id).inserted }
    }

    private var selectedCrowd: CommunityPost.Crowd? {
        guard !currentUserID.isEmpty else { return nil }

        let cutoff = Date().addingTimeInterval(-CrowdReportStore.freshnessWindow)
        if let report = crowdReports
            .filter({
                $0.placeID == spot.id
                    && $0.authorID == currentUserID
                    && $0.updatedAt >= cutoff
            })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            return report.crowd
        }

        // 구버전 Community 글은 아직 crowdReports 문서가 없을 수 있어
        // 같은 유효 시간창 안에서만 UI 선택 상태를 복원합니다.
        return posts
            .filter({
                $0.spotID == spot.id
                    && $0.authorID == currentUserID
                    && $0.hasStatusInfo
                    && ($0.updatedAt ?? $0.createdAt) >= cutoff
            })
            .max(by: { ($0.updatedAt ?? $0.createdAt) < ($1.updatedAt ?? $1.createdAt) })?
            .crowd
    }

    private var recentCrowdSummary: CrowdReportSummary? {
        VFLiveCrowd.summary(
            spot: spot,
            reports: crowdReports,
            legacyPosts: posts
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("실시간 현장 정보")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.primary)

            VStack(alignment: .leading, spacing: 14) {
                // 현재 상태를 먼저 보여주고, 바로 아래에서 사용자가
                // 자신의 현장 상태를 선택하도록 한 덩어리로 묶습니다.
                CommunityCrowdSummaryCard(summary: recentCrowdSummary)

                SpotDetailCrowdReportControl(
                    selection: selectedCrowd,
                    isSubmitting: isCrowdReportSubmitting || isCrowdReportLoading,
                    onSelect: onReportCrowd
                )
            }
            .padding(12)
            .appCardSurface()

            if !relatedCommunityPosts.isEmpty {
                Button {
                    isCommunityPostsPresented = true
                } label: {
                    SpotDetailCommunityEntryCard(postCount: relatedCommunityPosts.count)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isCommunityPostsPresented) {
                    SpotCommunityPostsSheet(
                        spot: spot,
                        posts: relatedCommunityPosts,
                        spots: spots,
                        currentUserID: currentUserID,
                        communityViewModel: communityViewModel,
                        onEdit: onEdit,
                        onDelete: onDelete,
                        onToggleLike: onToggleLike,
                        onToggleFollow: onToggleFollow,
                        onAddComment: onAddComment
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

}

private struct SpotDetailCommunityEntryCard: View {
    let postCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text("커뮤니티에서 이 장소")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.primary)

                Text("최근 언급 \(postCount)개를 확인해보세요")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("커뮤니티에서 이 장소, 최근 언급 \(postCount)개 보기")
    }
}

private struct SpotCommunityPostsSheet: View {
    private static let initialLimit = 5
    private static let maximumLimit = 10

    let spot: PhotoSpot
    let posts: [CommunityPost]
    let spots: [PhotoSpot]
    let currentUserID: String
    @ObservedObject var communityViewModel: CommunityViewModel
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var visiblePostCount = SpotCommunityPostsSheet.initialLimit

    private var orderedPosts: [CommunityPost] {
        var seenIDs = Set<String>()

        return posts
            .filter { $0.relatedSpotID == spot.id }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seenIDs.insert($0.id).inserted }
            .prefix(Self.maximumLimit)
            .map { $0 }
    }

    private var visiblePosts: [CommunityPost] {
        Array(orderedPosts.prefix(min(visiblePostCount, Self.maximumLimit)))
    }

    private var canShowMore: Bool {
        visiblePosts.count < orderedPosts.count
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: VFSpace.md) {
                    ForEach(visiblePosts) { post in
                        NavigationLink(value: post.id) {
                            SpotCommunityPostRow(post: post, spot: spot)
                        }
                        .buttonStyle(.plain)
                    }

                    if canShowMore {
                        Button {
                            visiblePostCount = min(visiblePostCount + Self.initialLimit, Self.maximumLimit)
                        } label: {
                            Text("더 보기")
                                .vfText(.callout.weight(.semibold))
                                .foregroundStyle(AppColors.accent)
                                .frame(maxWidth: .infinity, minHeight: AppLayout.touchTarget)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .vfScreenMargin()
                .padding(.top, VFSpace.md)
                .vfScrollBottomInset()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("커뮤니티에서 이 장소")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: String.self) { postID in
                if let post = orderedPosts.first(where: { $0.id == postID }) {
                    CommunityPostDetailView(
                        post: post,
                        spot: spot,
                        captureLocationSpot: captureLocationSpot(for: post),
                        currentUserID: currentUserID,
                        isLiked: communityViewModel.isLiked(post),
                        likeCount: post.likeCount + (communityViewModel.isLiked(post) ? 1 : 0),
                        isFollowing: communityViewModel.isFollowing(post),
                        comments: communityViewModel.comments(for: post),
                        focusCommentComposerOnAppear: false,
                        onToggleLike: onToggleLike,
                        onToggleFollow: onToggleFollow,
                        onAddComment: onAddComment,
                        onSelectSpot: { _ in
                            dismiss()
                        },
                        onEdit: onEdit,
                        onDelete: onDelete,
                        communityViewModel: communityViewModel
                    )
                } else {
                    EmptyView()
                }
            }
        }
    }

    private func captureLocationSpot(for post: CommunityPost) -> PhotoSpot? {
        guard let placeID = post.captureLocation?.placeID else { return nil }
        return spots.first { $0.id == placeID }
    }
}

private struct SpotCommunityPostRow: View {
    let post: CommunityPost
    let spot: PhotoSpot

    private var displayTags: [String] {
        communityDisplayTags(post.tags, excluding: spot, crowd: post.crowd, limit: 2)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .vfText(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text("·")
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)

                    Text(communityRelativeTimeText(for: post.createdAt))
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }

                if let title = post.title {
                    Text(title)
                        .vfText(.subhead.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)
                }

                if !post.message.isEmpty {
                    Text(post.message)
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.primary.opacity(0.82))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if post.hasStatusInfo || !displayTags.isEmpty {
                    HStack(spacing: 6) {
                        if post.hasStatusInfo {
                            CommunityCrowdBadge(crowd: post.crowd)
                        }

                        ForEach(displayTags, id: \.self) { tag in
                            Text(tag)
                                .vfText(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let attachment = post.publicPhotoAttachments.first {
                SpotCommunityPostThumbnail(attachment: attachment)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText.opacity(0.8))
                .padding(.top, 26)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface(cornerRadius: VFRadius.inner)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(post.authorName), \(communityRelativeTimeText(for: post.createdAt)), 게시글 보기")
    }
}

private struct SpotCommunityPostThumbnail: View {
    let attachment: CommunityPhotoAttachment

    var body: some View {
        ZStack {
            AppColors.mutedSurface

            if let imageData = attachment.imageData,
               let image = CommunityPhotoDecoder.image(from: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL = attachment.remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if case .failure = phase {
                        Image(systemName: "photo")
                            .foregroundStyle(AppColors.secondaryText)
                    } else {
                        ProgressView()
                            .tint(AppColors.secondaryText)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .frame(width: 76, height: 64)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct SpotDetailCrowdReportControl: View {
    let selection: CommunityPost.Crowd?
    let isSubmitting: Bool
    let onSelect: (CommunityPost.Crowd) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("지금 얼마나 붐비나요?")
                .font(AppTypography.metadata.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)

            HStack(spacing: 8) {
                ForEach(CommunityPost.Crowd.allCases) { crowd in
                    VFCrowdLevelButton(
                        crowd: crowd,
                        isSelected: selection == crowd,
                        isDisabled: isSubmitting
                    ) {
                        onSelect(crowd)
                    }
                }
            }
        }
    }
}

private struct CommunityCrowdSummaryCard: View {
    let summary: CrowdReportSummary?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: summary == nil ? "person.2.slash" : "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("현재 혼잡도")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppColors.primary)

                    if let summary {
                        Text(summary.crowd.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(summary.crowd.tint)
                            .padding(.horizontal, 7)
                            .frame(height: 21)
                            .background(summary.crowd.fill, in: Capsule())
                    }
                }

                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var tint: Color {
        summary?.crowd.tint ?? AppColors.secondaryText
    }

    private var subtitle: String {
        guard let summary else {
            return "최근 유효한 제보 없음"
        }

        return "최근 제보 \(summary.reportCount)개 기준 · \(communityRelativeTimeText(for: summary.latestDate)) 갱신"
    }
}

struct DetailInfoRow: View {
    let symbolName: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.metadata.weight(.bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(value)
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SpotShootingMetric: View {
    let symbolName: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 32, height: 32)
                .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)

            Text(value)
                .font(AppTypography.bodyStrong)
                .foregroundStyle(AppColors.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .appCardSurface()
        .accessibilityElement(children: .combine)
    }
}

struct DetailActionButton: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool
    let height: CGFloat
    var tint: Color? = nil

    private var foregroundColor: Color {
        // "지도에서 보기" 와 "길찾기" 는 같은 유리 바 안의 같은 계층이므로
        // 글자색을 동일하게 둡니다.
        //
        // 한동안 길찾기만 앰버로 강조했는데, 두 버튼이 나란히 있는 상태에서
        // 한쪽만 색이 다르면 위계보다 불일치로 읽혔습니다.
        // 주 동작 강조가 필요해지면 배경이나 크기로 구분하는 편이 낫습니다.
        tint ?? AppColors.primary.opacity(0.94)
    }

    var body: some View {
        content
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(height, AppLayout.touchTarget))
            // 액션 바 전체에 이미 Liquid Glass 가 적용되어 있습니다.
            // 여기서 흰 캡슐을 덮으면 유리 위에 불투명 블록이 얹혀
            // "지도에서 보기" 와 재료가 달라 보입니다. (유리 위 유리/불투명 금지)
            // 주 동작 구분은 배경이 아니라 글자 색(앰버)으로 표현합니다.
            .contentShape(Rectangle())
    }

    private var content: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: isPrimary ? .bold : .semibold))
                .symbolRenderingMode(.monochrome)

            Text(title)
                .font(.system(size: 13, weight: isPrimary ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

struct NativeActionDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(AppColors.divider.opacity(colorScheme == .dark ? 0.42 : 0.64))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

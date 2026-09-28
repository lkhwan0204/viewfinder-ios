import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════
//  마이 탭 — 3차 개편: 홈과 같은 언어로
//
//  [2차가 앱과 어긋났던 이유]
//  앱 어디에도 없는 모양을 새로 만들었습니다.
//   - 모서리 괄호 장식, 주황 빛이 번지는 배경
//     (VFPalette 규칙: 주황은 큰 면적 배경에 쓰지 않는다)
//   - 40pt 숫자 타일, 타일 속 워터마크 아이콘, 누르면 작아지는 버튼
//   - 큰 내비게이션 제목, 주황 캡슐 버튼
//  홈 · 커뮤니티 · 상세는 "사진이 주인공, 검정 캔버스, 사진 위 흰 글자,
//  작은 계기판 글씨" 로 말합니다. 마이만 다른 앱처럼 보였습니다.
//
//  [지금] 새 모양을 만들지 않고, 앱에 이미 있는 부품과 규칙만 씁니다.
//    커버        홈 Hero 와 같은 전면 사진. 사진 위에 이름(display) + 계기판 한 줄.
//                왼쪽 위 유리 pill · 오른쪽 위 유리 원 버튼도 홈과 같은 자리 · 크기입니다.
//    저장한 장소  홈 레일과 같은 카드(HomePhotoCard 4:5) · 같은 폭(42%).
//    내 활동      추가한 장소 · 내 글. 누르면 각각 전용 화면이 열립니다.
//    전용 화면    저장한 장소 = 홈 2열 그리드 + 홈 테마 칩
//                추가한 장소 = 홈 카테고리 목록과 같은 행
//                내 글       = 커뮤니티 피드 카드(CommunityPostCard) 그대로
//                설정        = 커버 오른쪽 위 톱니바퀴
//                제목은 앱의 다른 화면처럼 작은(inline) 제목입니다.
//    빈 상태      앱 공용 AppStatePanel.
//
//  주황은 게스트의 "로그인" 버튼과 빈 상태의 첫 행동에만 씁니다.
// ═══════════════════════════════════════════════════════════════════

struct MyTabView: View {
    let user: AuthUser?
    let savedSpots: [PhotoSpot]
    let submissionReceipts: [PlaceSubmissionReceipt]
    let posts: [CommunityPost]
    let spots: [PhotoSpot]
    let likedPostIDs: Set<String>
    let followedAuthorIDs: Set<String>
    let commentsByPostID: [String: [CommunityComment]]
    let communityViewModel: CommunityViewModel
    let onTabBarVisibilityChange: (Bool) -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    /// 저장한 장소 카드를 길게 눌러 저장을 해제합니다.
    let onToggleSave: (PhotoSpot) -> Void
    let onEditPost: (CommunityPost) -> Void
    let onDeletePost: (CommunityPost) async throws -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool
    let onRequestSignIn: () -> Void
    let onExploreSpots: () -> Void
    /// 빈 "추가한 장소" 화면에서 바로 장소 추가로 갑니다.
    let onAddPlace: () -> Void
    /// 빈 "내 글" 화면에서 바로 글쓰기로 갑니다.
    let onCompose: () -> Void
    let onResetTaste: () -> Void
    let onSignOut: () -> Void

    /// 온보딩에서 고른 사진 취향. 커버로 쓸 저장 사진이 없을 때 1순위 사진이 커버가 됩니다.
    /// 취향을 다시 고르면 저장 값이 바뀌고, 커버도 바로 따라 바뀝니다.
    @AppStorage(TastePreferenceStore.preferenceKey) private var tastePreferenceData: Data?

    /// 커버가 차지할 화면 높이 비율.
    ///
    /// 홈 Hero(0.64)보다 낮춥니다. 첫 화면에서 저장한 장소 카드가 끝까지 보이고
    /// 그 아래 "내 활동" 제목이 걸쳐 보여야 아래에 더 있다는 게 드러납니다.
    /// (iPhone 16 Pro 기준: 커버 약 411pt, 카드 끝 약 710pt, "내 활동" 제목 약 742pt, 탭바 위쪽 끝 약 791pt)
    private static let coverHeightRatio: CGFloat = 0.52
    /// 첫 화면 레일에 올리는 카드 수. 나머지는 "더보기" 의 격자에서 봅니다.
    private static let railLimit = 10

    // MARK: - 데이터

    private var myPosts: [CommunityPost] {
        guard let user else { return [] }
        return posts
            .filter { $0.authorID == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 사진이 있는 저장 장소.
    private var savedPhotoSpots: [PhotoSpot] {
        savedSpots.filter(\.hasReliableDisplayImage)
    }

    /// 커버 사진. 저장 사진 → 사진 취향 1순위 → 기본 사진 순서로 고릅니다.
    ///
    /// 저장 사진은 2장 이상일 때만 첫 장을 씁니다. 1장뿐이면 레일에만 둬서
    /// 같은 사진이 커버와 바로 아래 카드에 두 번 나오지 않게 합니다.
    /// 취향 · 기본 사진은 번들 사진이라 네트워크 없이도 늘 보입니다.
    private var cover: MyCover {
        if savedPhotoSpots.count >= 2, let first = savedPhotoSpots.first {
            return .saved(first)
        }
        if let assetName = tasteCoverAssetName {
            return .taste(assetName: assetName)
        }
        if let assetName = TasteOnboardingCatalog.photos.first?.assetName {
            return .suggestion(assetName: assetName)
        }
        return .blank
    }

    private var tasteCoverAssetName: String? {
        guard let tastePreferenceData,
              let preference = try? JSONDecoder().decode(TastePreference.self, from: tastePreferenceData),
              let firstID = preference.selectedPhotoIDs.first else {
            return nil
        }
        return TasteOnboardingCatalog.photos.first { $0.id == firstID }?.assetName
    }

    /// 첫 화면 레일. 홈 레일처럼 사진 있는 곳을 먼저 두고, 커버에 쓴 장소는 뺍니다.
    private func railSpots(excluding coverSpotID: String?) -> [PhotoSpot] {
        let withPhoto = savedPhotoSpots.filter { $0.id != coverSpotID }
        let withoutPhoto = savedSpots.filter { !$0.hasReliableDisplayImage }
        return Array((withPhoto + withoutPhoto).prefix(Self.railLimit))
    }

    /// 지금 불러온 장소 목록에서 찾은 "내가 추가한 장소". receipt 는 최신순입니다.
    private var myPlaceSpots: [PhotoSpot] {
        submissionReceipts.compactMap { receipt in
            spots.first { $0.id == receipt.id }
        }
    }

    /// "추가한 장소" 행 왼쪽 사진. 가장 최근에 추가한 곳 중 사진이 있는 곳입니다.
    private var placeThumbnailSpot: PhotoSpot? {
        myPlaceSpots.first(where: \.hasReliableDisplayImage)
    }

    /// "내 글" 행 왼쪽 사진. 가장 최근 글 중 사진이 있는 글의 첫 사진입니다.
    /// 사진 없는 글에 장소 대표 사진을 대신 쓰지 않습니다. 내가 찍은 사진처럼 보이기 때문입니다.
    private var postThumbnailAttachment: CommunityPhotoAttachment? {
        myPosts
            .first { !$0.publicPhotoAttachments.isEmpty }?
            .publicPhotoAttachments
            .first
    }

    // MARK: - 화면

    var body: some View {
        let cover = self.cover

        NavigationStack {
            GeometryReader { proxy in
                let topInset = proxy.safeAreaInsets.top
                let coverSize = CGSize(
                    width: proxy.size.width,
                    height: (proxy.size.height + topInset) * Self.coverHeightRatio
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        coverView(cover, size: coverSize, topInset: topInset)

                        if user == nil {
                            guestSignIn
                                .padding(.top, VFSpace.lg)
                        }

                        savedSection(excludingCoverSpotID: cover.savedSpot?.id)
                            .padding(.top, VFSpace.xl)

                        if user != nil {
                            activitySection
                                .padding(.top, VFSpace.xl)
                        }
                    }
                    .padding(.bottom, VFSpace.xl)
                }
                // iOS 26: 위로 조금만 올려도 줄어든 탭바가 다시 펼쳐지게 합니다.
                .vfReportsTabBarScroll()
                // 커버 사진이 상태바까지 올라갑니다. 홈 Hero 와 같은 방식입니다.
                .ignoresSafeArea(edges: .top)
                // 스크롤한 본문이 상태바와 겹쳐 읽히지 않게 시스템 재료로 경계를 만듭니다.
                .modifier(VFTopScrollEdgeEffect())
            }
            .background(AppColors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                onTabBarVisibilityChange(false)
            }
        }
    }

    // MARK: - 커버

    /// 홈 Hero 와 같은 구조입니다. (HomeHeroCard · HomeHeroSection)
    ///   전면 사진 → 캔버스로 이어지는 아래쪽 전환 → 왼쪽 아래 이름과 계기판 한 줄 → 위쪽 유리 컨트롤
    /// 커버 자체는 누르는 곳이 아닙니다. 누를 수 있는 것은 위쪽 pill 과 톱니바퀴뿐입니다.
    private func coverView(_ cover: MyCover, size: CGSize, topInset: CGFloat) -> some View {
        MyCoverPhoto(cover: cover, size: size)
            .accessibilityHidden(true)
            .overlay(alignment: .bottom) {
                MyCoverCanvasTransition()
            }
            .overlay(alignment: .bottomLeading) {
                coverText(width: size.width)
            }
            .overlay(alignment: .top) {
                coverControls(cover, topInset: topInset)
            }
    }

    private func coverText(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            Text(coverTitle)
                .vfText(.display)
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .fixedSize(horizontal: false, vertical: true)

            VFMetaLineOnPhoto(items: coverMetaItems)
        }
        .padding(.horizontal, VFSpace.lg)
        // 아래쪽 캔버스 전환(라이트 32pt)보다 위에 글자가 오게 합니다.
        .padding(.bottom, VFSpace.xl + VFSpace.sm)
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// 로그인했으면 이름, 아니면 "게스트".
    private var coverTitle: String {
        guard let user else { return "게스트" }
        let trimmed = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "뷰파인더 사용자" : trimmed
    }

    /// 계기판 한 줄. 개수는 여기에만 둡니다. 아래 행들은 개수 대신 "최근" 을 말합니다.
    private var coverMetaItems: [String] {
        guard user != nil else {
            return ["저장 \(savedSpots.count)"]
        }
        return [
            "저장 \(savedSpots.count)",
            "추가한 장소 \(submissionReceipts.count)",
            "글 \(myPosts.count)"
        ]
    }

    /// 왼쪽 위 pill(커버 사진이 무엇인지) · 오른쪽 위 톱니바퀴.
    /// 홈 Hero 의 날씨 pill · 검색 버튼과 같은 자리 · 크기 · 여백입니다.
    private func coverControls(_ cover: MyCover, topInset: CGFloat) -> some View {
        HStack(alignment: .top, spacing: VFSpace.sm) {
            coverPill(cover)

            Spacer(minLength: VFSpace.sm)

            NavigationLink {
                MySettingsView(
                    user: user,
                    onResetTaste: onResetTaste,
                    onSignOut: onSignOut,
                    onRequestSignIn: onRequestSignIn
                )
            } label: {
                MyCoverCircleLabel(symbolName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정")
        }
        .padding(.leading, VFSpace.lg - VFSpace.xs)
        .padding(.trailing, VFSpace.lg - VFSpace.xs - MyCoverControl.hitInset)
        .padding(.top, topInset + VFSpace.sm - MyCoverControl.hitInset)
    }

    /// 모르는 사진이 내 이름 뒤에 걸려 있으면 어색합니다. 어디서 온 사진인지 적고,
    /// 누르면 그 출처로 갑니다. (저장한 장소 → 장소 상세, 사진 취향 → 취향 다시 고르기)
    @ViewBuilder
    private func coverPill(_ cover: MyCover) -> some View {
        switch cover {
        case .saved(let spot):
            Button {
                onSelectSpot(spot)
            } label: {
                MyCoverPill(symbolName: "bookmark.fill", title: spot.name)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("커버 사진, 저장한 장소 \(spot.name)")
            .accessibilityHint("장소 상세를 엽니다")
        case .taste:
            Button(action: onResetTaste) {
                MyCoverPill(symbolName: "photo.on.rectangle.angled", title: "내 사진 취향")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("커버 사진, 내 사진 취향 1순위")
            .accessibilityHint("사진 취향을 다시 고릅니다")
        case .suggestion:
            Button(action: onResetTaste) {
                MyCoverPill(symbolName: "photo.on.rectangle.angled", title: "사진 취향 고르기")
            }
            .buttonStyle(.plain)
            .accessibilityHint("고른 사진이 커버와 홈 추천의 출발점이 돼요")
        case .blank:
            EmptyView()
        }
    }

    // MARK: - 게스트

    /// 게스트에게 이 화면의 주 동작은 로그인 하나입니다.
    /// 사진 위에는 주황을 올리지 않으므로 커버 아래 캔버스에 둡니다.
    private var guestSignIn: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            Text("로그인하면 장소를 추가하고 현장 글을 남길 수 있어요.")
                .vfText(.subhead)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            MyPrimaryButton(title: "로그인", action: onRequestSignIn)
        }
        .vfScreenMargin()
    }

    // MARK: - 저장한 장소

    private func savedSection(excludingCoverSpotID coverSpotID: String?) -> some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            // 제목 줄 전체가 전용 화면으로 가는 링크입니다.
            // 비어 있을 때도 링크를 남겨둡니다. 링크가 화면에서 사라지면
            // 그 링크로 연 화면(마지막 장소를 방금 해제한 저장 화면)이 같이 닫힙니다.
            NavigationLink {
                MySavedSpotsView(
                    spots: savedSpots,
                    onSelect: onSelectSpot,
                    onUnsave: unsave,
                    onExplore: onExploreSpots
                )
            } label: {
                MySectionHeader(title: "저장한 장소", showsMore: !savedSpots.isEmpty)
            }
            .buttonStyle(.plain)
            .vfScreenMargin()

            if savedSpots.isEmpty {
                MySavedEmptyPanel(onExplore: onExploreSpots)
                    .vfScreenMargin()
            } else {
                savedRail(railSpots(excluding: coverSpotID))
            }
        }
    }

    /// 홈 레일(HomeSpotRailSection)과 같은 카드 · 폭 · 간격 · 스냅입니다.
    private func savedRail(_ items: [PhotoSpot]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: VFSpace.md) {
                ForEach(items) { spot in
                    MySavedSpotCard(
                        spot: spot,
                        onSelect: { onSelectSpot(spot) },
                        onUnsave: { unsave(spot) }
                    )
                    .containerRelativeFrame(.horizontal) { length, _ in
                        length * VFPhoto.railWidthRatio
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, VFSpace.lg)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    /// 길게 눌러 저장 해제. 저장 버튼(VFSaveButton)과 같은 촉감이고,
    /// 빠진 자리를 나머지 카드가 채우는 움직임이 보이게 합니다.
    private func unsave(_ spot: PhotoSpot) {
        VFHaptics.save()
        withAnimation(VFMotion.standard) {
            onToggleSave(spot)
        }
    }

    // MARK: - 내 활동

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            Text("내 활동")
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                NavigationLink {
                    MyPlacesView(
                        receipts: submissionReceipts,
                        spots: spots,
                        onSelectSpot: onSelectSpot,
                        onAddPlace: onAddPlace
                    )
                } label: {
                    MyEntryRow(title: "추가한 장소", detailItems: placesDetailItems) {
                        if let spot = placeThumbnailSpot {
                            PhotoSpotImageView(
                                spot: spot,
                                symbolSize: 18,
                                targetPixelWidth: VFPhotoDetail.thumbnail.pixelWidth
                            )
                        } else {
                            MyIconTile(symbolName: "mappin.and.ellipse")
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("추가한 장소 목록을 엽니다")

                MyRowDivider(leadingInset: MyEntryMetrics.dividerInset)

                NavigationLink {
                    MyPostsView(posts: myPosts, makeCard: postCard, onCompose: onCompose)
                } label: {
                    MyEntryRow(title: "내 글", detailItems: postsDetailItems) {
                        if let attachment = postThumbnailAttachment {
                            MyAttachmentImage(attachment: attachment, detail: .thumbnail)
                        } else {
                            MyIconTile(symbolName: "text.bubble")
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("내 글 목록을 엽니다")
            }
        }
        .vfScreenMargin()
    }

    private var placesDetailItems: [String] {
        guard let latest = submissionReceipts.first else { return ["아직 없어요"] }
        let photolessCount = myPlaceSpots.filter { !$0.hasReliableDisplayImage }.count
        if photolessCount > 0 {
            return ["사진 없는 곳 \(photolessCount)곳"]
        }
        return ["최근", latest.name]
    }

    private var postsDetailItems: [String] {
        guard let latest = myPosts.first else { return ["아직 없어요"] }
        return ["마지막 글", communityRelativeTimeText(for: latest.createdAt)]
    }

    // MARK: - 내 글 카드

    /// 커뮤니티 피드와 같은 카드입니다. 내 글도 다른 사람에게 보이는 모양 그대로 봅니다.
    /// (개편 전 마이 탭도 같은 카드를 썼습니다)
    private func postCard(_ post: CommunityPost) -> some View {
        CommunityPostCard(
            post: post,
            spot: spot(for: post),
            captureLocationSpot: captureLocationSpot(for: post),
            currentUserID: user?.id ?? "",
            isLiked: likedPostIDs.contains(post.id),
            likeCount: displayedLikeCount(for: post),
            isFollowing: followedAuthorIDs.contains(post.authorID),
            comments: commentsByPostID[post.id] ?? [],
            onEdit: onEditPost,
            onDelete: onDeletePost,
            onToggleLike: onToggleLike,
            onToggleFollow: onToggleFollow,
            onAddComment: onAddComment,
            onSelectSpot: onSelectSpot,
            communityViewModel: communityViewModel
        )
    }

    private func displayedLikeCount(for post: CommunityPost) -> Int {
        post.likeCount + (likedPostIDs.contains(post.id) ? 1 : 0)
    }

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        spots.first(where: { $0.id == post.spotID })
    }

    private func captureLocationSpot(for post: CommunityPost) -> PhotoSpot? {
        guard let placeID = post.captureLocation?.placeID else { return nil }
        return spots.first(where: { $0.id == placeID })
    }
}

// MARK: - 커버

/// 커버 사진이 어디서 왔는지. 왼쪽 위 pill 이 이걸 알려주고, 누르면 그 출처로 갑니다.
private enum MyCover {
    /// 저장한 장소의 사진. pill 을 누르면 장소 상세.
    case saved(PhotoSpot)
    /// 온보딩에서 고른 사진 취향 1순위. pill 을 누르면 취향 다시 고르기.
    case taste(assetName: String)
    /// 취향을 건너뛴 사용자의 기본 사진(취향 목록의 첫 장). pill 을 누르면 취향 고르기.
    case suggestion(assetName: String)
    /// 번들 사진도 없을 때. 실제로는 오지 않는 경우입니다.
    case blank

    var savedSpot: PhotoSpot? {
        if case .saved(let spot) = self {
            return spot
        }
        return nil
    }
}

/// 커버 사진 한 장. scrim 값은 홈 Hero 카드(HomeHeroCard)와 같습니다.
private struct MyCoverPhoto: View {
    let cover: MyCover
    let size: CGSize

    private static let bottomScrimHeightRatio: CGFloat = 0.44
    private static let bottomScrimStrength: Double = 1.05
    /// 상태바(흰 시계 · 배터리)까지 받쳐야 해서 홈 Hero 처럼 진하게 둡니다.
    private static let topScrimStrength: Double = 0.62
    private static let topScrimHeight: CGFloat = 130

    var body: some View {
        switch cover {
        case .saved(let spot):
            VFPhotoTile(
                spot: spot,
                aspectRatio: nil,
                height: size.height,
                cornerRadius: 0,
                showsScrim: true,
                scrimHeightRatio: Self.bottomScrimHeightRatio,
                scrimStrength: Self.bottomScrimStrength,
                showsTopControlScrim: true,
                topScrimStrength: Self.topScrimStrength,
                topScrimHeight: Self.topScrimHeight,
                imageDetail: .hero
            )
            .frame(width: size.width, height: size.height)
            .clipped()
        case .taste(let assetName), .suggestion(let assetName):
            assetPhoto(named: assetName)
        case .blank:
            AppColors.mutedSurface
                .frame(width: size.width, height: size.height)
        }
    }

    /// 번들 사진을 바로 그립니다. 원격 주소가 없는 시드 사진이라,
    /// 장소 목록을 아직 못 불러왔어도 커버가 비지 않습니다.
    private func assetPhoto(named name: String) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                Image(name)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .vfPhotoScrim(heightRatio: Self.bottomScrimHeightRatio, strength: Self.bottomScrimStrength)
            .overlay(alignment: .top) {
                VFScrim(edge: .top, strength: Self.topScrimStrength)
                    .frame(height: Self.topScrimHeight)
            }
    }
}

/// 커버 아래쪽을 캔버스로 잇습니다.
///
/// 홈의 HeroFeedBackgroundTransition 과 같은 높이 · 단계이고, 색만 이 화면의
/// 배경(canvas)에 맞춥니다. 홈 피드는 라이트에서 살짝 따뜻한 흰색이라 색이 다릅니다.
/// 마지막 픽셀까지 불투명하게 만들어 커버와 아래 섹션 사이의 직선 이음새를 숨깁니다.
private struct MyCoverCanvasTransition: View {
    @Environment(\.colorScheme) private var colorScheme

    private var canvas: Color {
        AppColors.background
    }

    private var height: CGFloat {
        colorScheme == .dark ? 96 : 32
    }

    private var stops: [Gradient.Stop] {
        if colorScheme == .dark {
            return [
                .init(color: canvas.opacity(0), location: 0),
                .init(color: canvas.opacity(0.06), location: 0.26),
                .init(color: canvas.opacity(0.20), location: 0.52),
                .init(color: canvas.opacity(0.46), location: 0.74),
                .init(color: canvas.opacity(0.78), location: 0.91),
                .init(color: canvas, location: 1)
            ]
        }

        return [
            .init(color: canvas.opacity(0), location: 0),
            .init(color: canvas.opacity(0), location: 0.50),
            .init(color: canvas.opacity(0.12), location: 0.72),
            .init(color: canvas.opacity(0.50), location: 0.92),
            .init(color: canvas, location: 1)
        ]
    }

    var body: some View {
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 커버 위 컨트롤 치수. 홈 Hero 의 컨트롤과 같습니다.
private enum MyCoverControl {
    /// 보이는 크기.
    static let visibleSize: CGFloat = 38
    /// 누를 수 있는 크기. (개선안 41)
    static let hitSize: CGFloat = AppLayout.touchTarget
    /// 보이는 컨트롤 바깥으로 넓힌 여백. (44 - 38) / 2 = 3pt
    static let hitInset: CGFloat = (AppLayout.touchTarget - visibleSize) / 2
}

/// 커버 왼쪽 위 유리 pill. 홈 Hero 의 날씨 pill 과 같은 모양입니다.
private struct MyCoverPill: View {
    let symbolName: String
    let title: String

    var body: some View {
        HStack(spacing: VFSpace.xs + 2) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .vfText(.mono)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, VFSpace.md)
        .frame(height: MyCoverControl.visibleSize)
        .contentShape(Capsule())
        .vfGlass(interactive: true)
        // 보이는 pill 은 38pt, 누를 수 있는 영역은 위아래 3pt 씩 넓힌 44pt 입니다.
        .padding(.vertical, MyCoverControl.hitInset)
        .contentShape(Rectangle())
    }
}

/// 커버 오른쪽 위 유리 원 버튼. 홈 Hero 의 검색 버튼과 같은 모양입니다.
private struct MyCoverCircleLabel: View {
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            // Dynamic Type 제외: 고정 38pt 원 안의 기호.
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: MyCoverControl.visibleSize, height: MyCoverControl.visibleSize)
            .contentShape(Circle())
            .vfGlass(in: Circle(), interactive: true)
            .clipShape(Circle())
            // 보이는 원은 38pt, 누를 수 있는 영역은 44pt 입니다.
            .frame(width: MyCoverControl.hitSize, height: MyCoverControl.hitSize)
            .contentShape(Rectangle())
    }
}

// MARK: - 섹션

/// 섹션 제목. 홈 섹션 제목(title2)과 같은 크기이고,
/// 오른쪽 "더보기" 는 VFSectionTitle 의 것과 같은 모양입니다.
private struct MySectionHeader: View {
    let title: String
    var showsMore: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.sm) {
            Text(title)
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)

            Spacer(minLength: VFSpace.sm)

            if showsMore {
                HStack(spacing: 2) {
                    Text("더보기")
                        .vfText(.callout)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppColors.secondaryText)
            }
        }
        .frame(minHeight: AppLayout.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsMore ? "\(title), 전체 보기" : title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 저장한 장소가 없을 때. 개편 전 마이 탭과 같은 문구 · 같은 공용 패널입니다.
private struct MySavedEmptyPanel: View {
    let onExplore: () -> Void

    var body: some View {
        AppStatePanel(
            symbolName: "bookmark",
            title: "저장한 출사지가 아직 없어요",
            message: "마음에 드는 장소를 저장하면 이곳에서 빠르게 다시 찾을 수 있어요.",
            actionTitle: "출사지 둘러보기",
            action: onExplore
        )
    }
}

// MARK: - 저장한 장소 카드

/// 저장한 장소 카드. 사진이 있으면 홈 카드(HomePhotoCard) 그대로입니다.
///
/// 사진이 없는 장소는 홈에는 나오지 않지만 저장 목록에는 남아 있어야 합니다.
/// 같은 크기의 빈 사진 자리에 이름을 본문 색으로 씁니다.
/// (사진 위 흰 글자를 빈 자리에 그대로 쓰면 라이트 모드에서 읽히지 않습니다)
private struct MySavedSpotCard: View {
    let spot: PhotoSpot
    let onSelect: () -> Void
    let onUnsave: () -> Void

    private static let aspectRatio: CGFloat = 4.0 / 5.0

    var body: some View {
        card
            // 길게 눌렀을 때 떠오르는 미리보기도 카드 모서리를 따릅니다.
            .contentShape(
                .contextMenuPreview,
                RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
            )
            .contextMenu {
                Button(role: .destructive, action: onUnsave) {
                    Label("저장 해제", systemImage: "bookmark.slash")
                }
            }
            .accessibilityAction(named: "저장 해제", onUnsave)
    }

    @ViewBuilder
    private var card: some View {
        if spot.hasReliableDisplayImage {
            HomePhotoCard(
                recommendation: RecommendedSpot(spot: spot, reason: ""),
                aspectRatio: Self.aspectRatio,
                onSelect: onSelect
            )
        } else {
            VFPhotoTile(spot: spot, aspectRatio: Self.aspectRatio)
                .overlay(alignment: .bottomLeading) {
                    // HomePhotoCard 캡션과 같은 자리 · 크기입니다. 색만 본문 색입니다.
                    VStack(alignment: .leading, spacing: VFSpace.xs) {
                        Text(spot.name)
                            .vfText(.headline)
                            .foregroundStyle(AppColors.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        VFMetaLine(items: [HomeSpotDisplayFormatter.region(for: spot)])
                    }
                    .padding(.horizontal, VFSpace.md + 2)
                    .padding(.bottom, VFSpace.md)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(spot.name), \(HomeSpotDisplayFormatter.region(for: spot)), 사진 없음")
        }
    }
}

// MARK: - 내 활동 행

private enum MyEntryMetrics {
    static let leadingSize: CGFloat = 56
    /// 구분선은 글자가 시작하는 곳부터 그립니다.
    static let dividerInset: CGFloat = leadingSize + VFSpace.md
}

/// 첫 화면의 "추가한 장소" · "내 글" 한 줄. 누르면 전용 화면이 열립니다.
/// 카드 표면 없이 캔버스 위에 두고, 행 사이는 얇은 선 하나로 나눕니다. (홈 목록 행과 같은 방식)
private struct MyEntryRow<Leading: View>: View {
    let title: String
    let detailItems: [String]
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: VFSpace.md) {
            leading()
                .frame(width: MyEntryMetrics.leadingSize, height: MyEntryMetrics.leadingSize)
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                VFMetaLine(items: detailItems)
            }

            Spacer(minLength: VFSpace.xs)

            MyRowChevron()
        }
        .padding(.vertical, VFSpace.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 사진이 없을 때의 행 왼쪽 칸. 사진 자리 표면(surface2) 위 기호 하나.
private struct MyIconTile: View {
    let symbolName: String

    var body: some View {
        ZStack {
            AppColors.mutedSurface

            Image(systemName: symbolName)
                // Dynamic Type 제외: 고정 56pt 칸 안의 기호.
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
        }
    }
}

/// 커뮤니티 글에 붙은 사진 한 장. (기기에 있는 데이터 또는 서버 주소)
private struct MyAttachmentImage: View {
    let attachment: CommunityPhotoAttachment
    var detail: VFPhotoDetail = .thumbnail

    var body: some View {
        if let data = attachment.imageData,
           let image = CommunityPhotoDecoder.image(
            from: data,
            cacheKey: attachment.id,
            detail: detail
           ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let remoteURL = attachment.remoteURL {
            AsyncImage(url: remoteURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    AppColors.mutedSurface
                }
            }
        } else {
            AppColors.mutedSurface
        }
    }
}

// MARK: - 버튼 · 칩

/// 화면의 주 동작 버튼. 사진 취향 온보딩의 "탐색 시작" 과 같은 모양입니다.
/// (주황 채움 · 모서리 12 · 높이 54)
private struct MyPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .vfText(.headline)
                .foregroundStyle(AppColors.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    AppColors.accent,
                    in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 필터 칩. 홈 테마 필터(HomeThemeFilterSection)의 칩과 같은 모양입니다.
/// (유리 · 선택은 주황 tint · 보이는 높이 34pt · 터치 44pt)
private struct MyThemeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            VFHaptics.selection()
            action()
        } label: {
            Text(title)
                .vfText(.subhead.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.primary)
                .padding(.horizontal, VFSpace.sm + 2)
                .frame(minHeight: 34)
                .contentShape(Capsule())
                .vfGlass(
                    tint: isSelected ? AppColors.accent : nil,
                    interactive: true
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppLayout.touchTarget)
        .accessibilityValue(isSelected ? "선택됨" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(VFMotion.quick, value: isSelected)
    }
}

// MARK: - 목록 공용

private enum MyListRowMetrics {
    static let horizontalPadding: CGFloat = 14
}

private struct MyRowDivider: View {
    let leadingInset: CGFloat

    var body: some View {
        Rectangle()
            .fill(AppColors.divider)
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
    }
}

private struct MyRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.secondaryText)
            .accessibilityHidden(true)
    }
}

private enum MyDateText {
    private static let isoFormatter = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()

    static func day(fromISO8601 raw: String) -> String? {
        guard let date = isoFormatter.date(from: raw) else { return nil }
        return dayFormatter.string(from: date)
    }
}

// MARK: - 추가한 장소 행

/// 내가 추가한 장소 한 줄. 홈 카테고리 목록 행(HomeCategoryListRow)과 같은 모양입니다.
/// (112pt 사진 · 이름 · 계기판 한 줄 · 설명 · 아래 얇은 선, 카드 표면 없음)
private struct MyPlaceRow: View {
    let receipt: PlaceSubmissionReceipt
    /// 지금 불러온 장소 목록에서 찾은 장소입니다. 아직 못 불러왔으면 nil 이고,
    /// 그때는 누를 수 없는 행으로 둡니다.
    let spot: PhotoSpot?
    let onSelectSpot: (PhotoSpot) -> Void

    private static let photoSize: CGFloat = 112

    var body: some View {
        if let spot {
            Button {
                onSelectSpot(spot)
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityHint("장소 상세를 엽니다")
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            photo
                .frame(width: Self.photoSize, height: Self.photoSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(receipt.name)
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(2)

                VFMetaLine(items: [regionText, submittedDayText].compactMap { $0 })

                if let statusText {
                    Text(statusText)
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var photo: some View {
        let shape = RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)

        if let spot, spot.hasReliableDisplayImage {
            VFPhotoTile(
                spot: spot,
                aspectRatio: 1,
                cornerRadius: VFRadius.inner,
                imageDetail: .thumbnail
            )
        } else if spot != nil {
            // 홈 목록과 같은 "첫 사진을 남겨주세요" 칸입니다.
            // 행을 누르면 장소 상세가 열리고, 거기서 사진을 추가할 수 있습니다.
            MissingSpotPhotoPrompt(layout: .compact)
                .clipShape(shape)
                .overlay {
                    shape.stroke(AppColors.divider, lineWidth: 1)
                }
        } else {
            AppColors.mutedSurface
                .clipShape(shape)
        }
    }

    private var regionText: String? {
        if let spot {
            return HomeSpotDisplayFormatter.region(for: spot)
        }
        guard let region = receipt.region?.trimmingCharacters(in: .whitespacesAndNewlines),
              !region.isEmpty else {
            return nil
        }
        return region
    }

    private var submittedDayText: String? {
        MyDateText.day(fromISO8601: receipt.submittedAt)
    }

    /// 실제로 어디에 보이는지를 말합니다.
    ///
    /// 홈과 지도는 사진이 있는 장소만 보여주므로, 사진이 없는 장소는 검색에서만 찾을 수 있습니다.
    private var statusText: String? {
        guard let spot else { return nil }
        return spot.hasReliableDisplayImage
            ? "홈 · 지도 · 검색에 보여요"
            : "사진이 없어 아직 검색에만 보여요"
    }
}

// MARK: - 설정 행

private struct MySettingsRow: View {
    enum Trailing {
        case chevron
        case value(String)
        case hidden
    }

    static let iconSize: CGFloat = 32
    static let dividerInset: CGFloat = MyListRowMetrics.horizontalPadding + iconSize + VFSpace.md

    let symbolName: String
    let title: String
    var trailing: Trailing = .chevron

    var body: some View {
        HStack(spacing: VFSpace.md) {
            Image(systemName: symbolName)
                // Dynamic Type 제외: 고정 32pt 아이콘 상자 안의 기호.
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background(
                    AppColors.mutedSurface,
                    in: RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(title)
                .vfText(.callout.weight(.semibold))
                .foregroundStyle(AppColors.primary)

            Spacer(minLength: VFSpace.sm)

            switch trailing {
            case .chevron:
                MyRowChevron()
            case .value(let value):
                HStack(spacing: 4) {
                    Text(value)
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.secondaryText)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .accessibilityHidden(true)
                }
            case .hidden:
                EmptyView()
            }
        }
        .padding(.horizontal, MyListRowMetrics.horizontalPadding)
        .padding(.vertical, VFSpace.sm + 2)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct MyAppearanceModeRow: View {
    let appearance: AppAppearance
    @Binding var selection: String

    var body: some View {
        Menu {
            // Picker 를 쓰면 지금 고른 모드에 시스템 체크 표시가 붙습니다.
            Picker("화면 모드", selection: $selection) {
                ForEach(AppAppearance.allCases) { option in
                    Label(option.title, systemImage: option.symbolName)
                        .tag(option.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            MySettingsRow(
                symbolName: appearance.symbolName,
                title: "화면 모드",
                trailing: .value(appearance.title)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("화면 모드")
        .accessibilityValue(appearance.title)
        .accessibilityHint("시스템 설정, 라이트, 다크 중에서 선택")
    }
}

/// 설정 화면의 묶음. 작은 제목 + 표면 하나에 모은 행.
private struct MySettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            Text(title)
                .vfText(.subhead.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.horizontal, VFSpace.xs)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                content()
            }
            .appCardSurface()
        }
    }
}

/// 설정 맨 위의 내 계정 한 줄. 커버에서 뺀 이메일은 여기서 봅니다.
private struct MyAccountRow: View {
    let user: AuthUser

    var body: some View {
        HStack(spacing: VFSpace.md) {
            MyAvatar(name: user.displayName, size: MySettingsRow.iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .vfText(.callout.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                if let email = user.email, !email.isEmpty {
                    Text(email)
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: VFSpace.sm)
        }
        .padding(.horizontal, MyListRowMetrics.horizontalPadding)
        .padding(.vertical, VFSpace.sm + 2)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 커뮤니티 아바타(CommunityAuthorAvatar)와 같은 규칙입니다.
/// 이름 첫 글자 + 이름으로 고른 무채색 톤이라, 내 글에 붙는 아바타와 똑같이 보입니다.
private struct MyAvatar: View {
    let name: String
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(initial)
            // Dynamic Type 제외: 원 지름에 비례하는 크기다. 원이 안 커지므로 글자도 안 커진다.
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.72))
            .frame(width: size, height: size)
            .background(tone, in: Circle())
            .overlay {
                Circle()
                    .stroke(AppColors.divider, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var tone: Color {
        let tones = VFPalette.avatarTones
        let seed = name.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return Color(uiColor: tones[seed % tones.count])
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 전용 화면
//
//  첫 화면에서 누르면 열립니다. 첫 화면은 입구이고, 목록은 여기서 봅니다.
//  제목은 앱의 다른 화면(커뮤니티 · 게시글 · 목록)처럼 작은(inline) 제목입니다.
// ═══════════════════════════════════════════════════════════════════

private struct MySavedSpotsView: View {
    let spots: [PhotoSpot]
    let onSelect: (PhotoSpot) -> Void
    let onUnsave: (PhotoSpot) -> Void
    let onExplore: () -> Void

    @State private var selectedTheme: SpotTheme?

    /// 저장한 장소에 실제로 있는 테마만, SpotTheme 순서대로.
    private var themes: [SpotTheme] {
        SpotTheme.allCases.filter { theme in
            spots.contains { $0.theme == theme }
        }
    }

    /// 고른 테마의 장소를 모두 저장 해제하면 "전체" 로 돌아갑니다.
    private var activeTheme: SpotTheme? {
        guard let selectedTheme, themes.contains(selectedTheme) else { return nil }
        return selectedTheme
    }

    private var visibleSpots: [PhotoSpot] {
        guard let activeTheme else { return spots }
        return spots.filter { $0.theme == activeTheme }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if spots.isEmpty {
                MySavedEmptyPanel(onExplore: onExplore)
                    .vfScreenMargin()
                    .padding(.top, VFSpace.lg)
            } else {
                VStack(alignment: .leading, spacing: VFSpace.md) {
                    // 테마가 하나뿐이면 거를 게 없으므로 칩을 두지 않습니다.
                    if themes.count >= 2 {
                        themeChips
                    }

                    // 홈 2열 그리드(HomeCompactRecommendationGrid)와 같은 카드 · 간격입니다.
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: VFSpace.md),
                            GridItem(.flexible(), spacing: VFSpace.md)
                        ],
                        spacing: VFSpace.md
                    ) {
                        ForEach(visibleSpots) { spot in
                            MySavedSpotCard(
                                spot: spot,
                                onSelect: { onSelect(spot) },
                                onUnsave: { onUnsave(spot) }
                            )
                        }
                    }
                    .vfScreenMargin()
                }
                .padding(.top, VFSpace.sm)
                .vfScrollBottomInset()
            }
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("저장한 장소")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// 홈 테마 필터(HomeThemeFilterSection)와 같은 줄 · 간격입니다.
    private var themeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: VFSpace.sm) {
                MyThemeChip(title: "전체", isSelected: activeTheme == nil) {
                    select(nil)
                }
                .accessibilityLabel("전체 테마")

                ForEach(themes) { theme in
                    MyThemeChip(title: theme.title, isSelected: activeTheme == theme) {
                        select(theme)
                    }
                    .accessibilityLabel("\(theme.title) 테마")
                }
            }
            .padding(.horizontal, VFSpace.lg)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
    }

    private func select(_ theme: SpotTheme?) {
        withAnimation(VFMotion.quick) {
            selectedTheme = theme
        }
    }
}

private struct MyPlacesView: View {
    let receipts: [PlaceSubmissionReceipt]
    let spots: [PhotoSpot]
    let onSelectSpot: (PhotoSpot) -> Void
    let onAddPlace: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            if receipts.isEmpty {
                AppStatePanel(
                    symbolName: "mappin.and.ellipse",
                    title: "직접 추가한 장소가 아직 없어요",
                    message: "나만 아는 출사지를 알려주세요. 다른 사진가의 다음 출사지가 돼요.",
                    actionTitle: "장소 추가",
                    action: onAddPlace
                )
                .vfScreenMargin()
                .padding(.top, VFSpace.lg)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(receipts) { receipt in
                        MyPlaceRow(
                            receipt: receipt,
                            spot: spots.first(where: { $0.id == receipt.id }),
                            onSelectSpot: onSelectSpot
                        )
                    }
                }
                .vfScreenMargin()
                .vfScrollBottomInset()
            }
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("추가한 장소")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            // 비어 있을 때는 가운데 "장소 추가" 버튼이 같은 일을 하므로 숨깁니다.
            if !receipts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAddPlace) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("장소 추가")
                }
            }
        }
    }
}

/// 카드 생성을 클로저로 받습니다.
///
/// 커뮤니티 카드에 필요한 인자가 많습니다. 이 화면이 그것들을 다시
/// 프로퍼티로 받으면 MyTabView 의 인자 목록을 그대로 복사해야 하고,
/// 하나라도 어긋나면 다르게 동작합니다. MyTabView.postCard 를 그대로 받습니다.
private struct MyPostsView<Card: View>: View {
    let posts: [CommunityPost]
    let makeCard: (CommunityPost) -> Card
    let onCompose: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            if posts.isEmpty {
                AppStatePanel(
                    symbolName: "square.and.pencil",
                    title: "남긴 글이 아직 없어요",
                    message: "지금 현장의 혼잡도와 분위기를 남겨보세요. 다음 사람의 출사가 쉬워져요.",
                    actionTitle: "글쓰기",
                    action: onCompose
                )
                .vfScreenMargin()
                .padding(.top, VFSpace.lg)
            } else {
                // 커뮤니티 피드와 같은 간격입니다. 카드 표면이 없어서 글과 글을 나누는 것은 여백입니다.
                LazyVStack(alignment: .leading, spacing: VFSpace.xl) {
                    ForEach(posts) { post in
                        makeCard(post)
                    }
                }
                .vfScreenMargin()
                .padding(.top, VFSpace.md)
                .vfScrollBottomInset()
            }
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("내 글")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !posts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onCompose) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("글쓰기")
                }
            }
        }
    }
}

private struct MySettingsView: View {
    let user: AuthUser?
    let onResetTaste: () -> Void
    let onSignOut: () -> Void
    let onRequestSignIn: () -> Void

    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.defaultValue.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .defaultValue
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "뷰파인더 \(version) (\(build))"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: VFSpace.xl) {
                MySettingsGroup(title: "계정") {
                    if let user {
                        MyAccountRow(user: user)

                        MyRowDivider(leadingInset: MySettingsRow.dividerInset)

                        // 로그아웃은 다시 로그인하면 되돌릴 수 있어서 확인 창을 띄우지 않습니다.
                        Button(action: onSignOut) {
                            MySettingsRow(
                                symbolName: "rectangle.portrait.and.arrow.right",
                                title: "로그아웃",
                                trailing: .hidden
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onRequestSignIn) {
                            MySettingsRow(
                                symbolName: "person.crop.circle",
                                title: "로그인",
                                trailing: .chevron
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                MySettingsGroup(title: "화면") {
                    MyAppearanceModeRow(
                        appearance: appearance,
                        selection: $appearanceRawValue
                    )

                    MyRowDivider(leadingInset: MySettingsRow.dividerInset)

                    Button(action: onResetTaste) {
                        MySettingsRow(
                            symbolName: "photo.on.rectangle.angled",
                            title: "사진 취향 다시 설정",
                            trailing: .chevron
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("커버와 홈 추천의 출발점이 되는 사진 3장을 다시 고릅니다")
                }

                // 누를 게 없는 정보는 행이 아니라 안내 글로 둡니다.
                VStack(alignment: .leading, spacing: VFSpace.xs) {
                    Text("저장한 장소는 이 기기에 저장돼요. 로그인하지 않아도 그대로 남아요.")
                    Text(versionText)
                }
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, VFSpace.xs)
            }
            .vfScreenMargin()
            .padding(.top, VFSpace.sm)
            .vfScrollBottomInset()
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

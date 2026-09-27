import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════
//  마이 탭 — 2차 개편
//
//  [1차 개편 뒤 실기기에서 보인 문제]
//  - 프로필의 개수 3칸(저장 · 추가한 장소 · 글)을 누르면 같은 화면 아래
//    섹션으로 스크롤됐습니다. 개수와 섹션이 같은 내용을 두 번 보여줬습니다.
//  - 사진이 없는 사용자는 회색 상자만 다섯 개 쌓인 화면이었습니다.
//  - 스크롤하면 "마이" 제목이 상태바 시계와 겹쳐 보였습니다.
//
//  [지금]
//    커버      뷰파인더 프레임 + 골든아워 빛. 저장한 사진이 있으면 그 사진.
//              디자인 시스템 이름 "Frame & Light" 를 그대로 화면으로 옮겼습니다.
//    타일 3개  저장한 장소 · 추가한 장소 · 내 글. 누르면 각각 전용 화면이 열립니다.
//              개수가 곧 입구라서 같은 내용을 두 번 보여주지 않습니다.
//              사진이 있으면 사진이 배경, 없으면 큰 숫자가 주인공입니다.
//    톱니바퀴  화면 모드 · 사진 취향 · 로그인/로그아웃은 설정 화면으로.
//
//  주황은 게스트의 "로그인" 버튼과 빈 화면의 첫 행동 버튼에만 씁니다.
//  커버의 주황 빛은 채움이 아니라 22% 에서 0 으로 사라지는 빛입니다.
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
    /// 저장한 장소 화면에서 길게 눌러 저장을 해제합니다.
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let coverTopBarHeight: CGFloat = 44
    private static let frameInset: CGFloat = AppLayout.pageHorizontalPadding
    private static let frameCornerLength: CGFloat = 22
    /// 프레임 안에서 글자가 시작하는 곳. 프레임 여백 + 16pt.
    private static let frameContentInset: CGFloat = frameInset + VFSpace.md + VFSpace.xs

    // MARK: - 데이터

    private var myPosts: [CommunityPost] {
        guard let user else { return [] }
        return posts
            .filter { $0.authorID == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 사진이 있는 저장 장소. 커버와 저장 타일에 씁니다.
    private var savedPhotoSpots: [PhotoSpot] {
        savedSpots.filter(\.hasReliableDisplayImage)
    }

    /// 사진이 2장 이상일 때만 첫 장을 커버로 씁니다.
    /// 1장뿐이면 타일에만 두어, 같은 사진이 커버와 타일에 두 번 나오지 않게 합니다.
    private var coverSpot: PhotoSpot? {
        savedPhotoSpots.count >= 2 ? savedPhotoSpots.first : nil
    }

    /// 저장 타일 모자이크. 커버에 쓴 사진은 빼고 최대 3장입니다.
    private var mosaicSpots: [PhotoSpot] {
        let source = coverSpot == nil ? savedPhotoSpots : Array(savedPhotoSpots.dropFirst())
        return Array(source.prefix(3))
    }

    /// 지금 불러온 장소 목록에서 찾은 "내가 추가한 장소". receipt 는 최신순입니다.
    private var myPlaceSpots: [PhotoSpot] {
        submissionReceipts.compactMap { receipt in
            spots.first { $0.id == receipt.id }
        }
    }

    private var photolessPlaceCount: Int {
        myPlaceSpots.filter { !$0.hasReliableDisplayImage }.count
    }

    /// 가장 최근에 추가한 장소 중 사진이 있는 곳.
    private var placeCoverSpot: PhotoSpot? {
        myPlaceSpots.first(where: \.hasReliableDisplayImage)
    }

    /// 가장 최근 글 중 사진이 있는 글의 첫 사진.
    private var postCoverAttachment: CommunityPhotoAttachment? {
        myPosts
            .first { !$0.publicPhotoAttachments.isEmpty }?
            .publicPhotoAttachments
            .first
    }

    // MARK: - 화면

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let topInset = proxy.safeAreaInsets.top

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        cover(topInset: topInset)

                        VStack(alignment: .leading, spacing: VFSpace.md) {
                            savedTile
                            activityTiles
                        }
                        .padding(.horizontal, AppLayout.pageHorizontalPadding)
                        .padding(.top, VFSpace.lg)
                        .padding(.bottom, VFSpace.xl)
                    }
                }
                // iOS 26: 위로 조금만 올려도 줄어든 탭바가 다시 펼쳐지게 합니다.
                .vfReportsTabBarScroll()
                // 커버가 상태바까지 올라갑니다. 홈 Hero 와 같은 방식입니다.
                .ignoresSafeArea(edges: .top)
                // 스크롤한 타일이 상태바와 겹쳐 읽히지 않게 시스템 재료로 경계를 만듭니다.
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

    private func cover(topInset: CGFloat) -> some View {
        let onPhoto = coverSpot != nil

        return VStack(alignment: .leading, spacing: 0) {
            // 상태바 + "마이" · 톱니바퀴 줄
            Color.clear
                .frame(height: topInset + Self.coverTopBarHeight)

            coverIdentity(onPhoto: onPhoto)
                .padding(.horizontal, Self.frameContentInset)
                .padding(.top, VFSpace.xxl)
                .padding(.bottom, VFSpace.xl + VFSpace.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            coverBackground(topInset: topInset)
        }
        .overlay {
            // 뷰파인더 프레임. 이름을 프레임 왼쪽 아래 1/3 지점에 둬서
            // 사진 구도처럼 읽히게 합니다.
            VFViewfinderCorners(cornerLength: Self.frameCornerLength)
                .stroke(
                    onPhoto ? Color.white.opacity(0.55) : AppColors.primary.opacity(0.26),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .padding(.horizontal, Self.frameInset)
                .padding(.top, topInset + Self.coverTopBarHeight + VFSpace.sm)
                .padding(.bottom, VFSpace.md)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            if let coverSpot {
                coverCaption(for: coverSpot)
                    .padding(.leading, Self.frameContentInset)
                    .padding(.top, topInset + Self.coverTopBarHeight + VFSpace.sm + VFSpace.md + VFSpace.xs)
            }
        }
        .overlay(alignment: .top) {
            coverTopBar(onPhoto: onPhoto)
                .padding(.top, topInset)
        }
        .clipped()
    }

    @ViewBuilder
    private func coverBackground(topInset: CGFloat) -> some View {
        if let coverSpot {
            PhotoSpotImageView(
                spot: coverSpot,
                symbolSize: 28,
                targetPixelWidth: VFPhotoDetail.hero.pixelWidth
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // 이름·이메일(흰 글자)을 받치는 아래쪽 어둠.
            .vfPhotoScrim(heightRatio: 0.7, strength: 1.1)
            // 상태바와 톱니바퀴 뒤는 화면 모드의 캔버스 색으로 흐리게 합니다.
            // 다크는 검정, 라이트는 흰색이라 상태바 글자색과 항상 반대가 됩니다.
            .overlay(alignment: .top) {
                MyCanvasFade(height: topInset + Self.coverTopBarHeight + VFSpace.lg)
            }
        } else {
            MyGoldenLightBackground()
        }
    }

    private func coverTopBar(onPhoto: Bool) -> some View {
        HStack(spacing: VFSpace.sm) {
            Text("마이")
                .vfText(.headline)
                .foregroundStyle(AppColors.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: VFSpace.sm)

            NavigationLink {
                MySettingsView(
                    isSignedIn: user != nil,
                    onResetTaste: onResetTaste,
                    onSignOut: onSignOut,
                    onRequestSignIn: onRequestSignIn
                )
            } label: {
                MyCoverIconButtonLabel(symbolName: "gearshape", onPhoto: onPhoto)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정")
        }
        .padding(.leading, AppLayout.pageHorizontalPadding)
        // 터치 영역(44pt)이 보이는 원(38pt)보다 3pt 넓으므로, 원의 오른쪽 끝이
        // 다른 여백과 같은 20pt 에 오게 3pt 를 뺍니다.
        .padding(.trailing, AppLayout.pageHorizontalPadding - (AppLayout.touchTarget - MyCoverIconButtonLabel.visibleSize) / 2)
        .frame(height: Self.coverTopBarHeight)
    }

    @ViewBuilder
    private func coverIdentity(onPhoto: Bool) -> some View {
        let ink: Color = onPhoto ? .white : AppColors.primary
        let subInk: Color = onPhoto ? Color.white.opacity(0.78) : AppColors.secondaryText

        if let user {
            HStack(spacing: VFSpace.md + 2) {
                MyProfileAvatar(name: user.displayName, onPhoto: onPhoto)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(for: user))
                        .vfText(.title1)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let email = user.email, !email.isEmpty {
                        Text(email)
                            .vfText(.subhead)
                            .foregroundStyle(subInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: VFSpace.lg) {
                VStack(alignment: .leading, spacing: VFSpace.sm) {
                    Text("나만의 출사 기록을\n만들어보세요")
                        .vfText(.title1)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("저장은 로그인 없이도 돼요.\n장소 추가와 글쓰기는 로그인이 필요해요.")
                        .vfText(.subhead)
                        .foregroundStyle(subInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                // 게스트에게 이 화면의 주 동작은 로그인 하나입니다.
                MyPrimaryButton(title: "로그인", action: onRequestSignIn)
            }
        }
    }

    /// 커버 사진이 어디서 왔는지 알려줍니다. 모르는 사진이 내 프로필에 걸려 있으면 어색합니다.
    private func coverCaption(for spot: PhotoSpot) -> some View {
        Label {
            Text(spot.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: "bookmark.fill")
        }
        .labelStyle(.titleAndIcon)
        .vfText(.caption.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.8))
        .accessibilityLabel("커버 사진, 저장한 장소 \(spot.name)")
    }

    private func displayName(for user: AuthUser) -> String {
        let trimmed = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "뷰파인더 사용자" : trimmed
    }

    // MARK: - 타일

    private var savedTile: some View {
        NavigationLink {
            MySavedSpotsView(
                spots: savedSpots,
                onSelect: onSelectSpot,
                onExplore: onExploreSpots,
                onToggleSave: onToggleSave
            )
        } label: {
            MyCollectionTile(
                title: "저장한 장소",
                count: savedSpots.count,
                unit: "곳",
                caption: savedCaption,
                symbolName: "bookmark",
                minHeight: 176,
                photo: mosaicSpots.isEmpty ? nil : AnyView(MySavedMosaic(spots: mosaicSpots))
            )
        }
        .buttonStyle(MyPressableButtonStyle())
        .accessibilityLabel("저장한 장소 \(savedSpots.count)곳")
        .accessibilityHint("저장한 장소 목록을 엽니다")
    }

    @ViewBuilder
    private var activityTiles: some View {
        // 큰 글자에서는 두 칸이 좁아지므로 한 줄에 하나씩 둡니다.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: VFSpace.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: VFSpace.md))

        layout {
            placesTile
            postsTile
        }
    }

    @ViewBuilder
    private var placesTile: some View {
        if user == nil {
            Button(action: onRequestSignIn) {
                MyCollectionTile(
                    title: "추가한 장소",
                    count: nil,
                    unit: "곳",
                    caption: "로그인하면 볼 수 있어요",
                    symbolName: "mappin.and.ellipse",
                    minHeight: 148,
                    isLocked: true
                )
            }
            .buttonStyle(MyPressableButtonStyle())
            .accessibilityLabel("추가한 장소, 로그인이 필요해요")
            .accessibilityHint("로그인 화면을 엽니다")
        } else {
            NavigationLink {
                MyPlacesView(
                    receipts: submissionReceipts,
                    spots: spots,
                    onSelectSpot: onSelectSpot,
                    onAddPlace: onAddPlace
                )
            } label: {
                MyCollectionTile(
                    title: "추가한 장소",
                    count: submissionReceipts.count,
                    unit: "곳",
                    caption: placesCaption,
                    symbolName: "mappin.and.ellipse",
                    minHeight: 148,
                    photo: placeCoverSpot.map { spot in
                        AnyView(
                            PhotoSpotImageView(
                                spot: spot,
                                symbolSize: 20,
                                targetPixelWidth: VFPhotoDetail.card.pixelWidth
                            )
                        )
                    }
                )
            }
            .buttonStyle(MyPressableButtonStyle())
            .accessibilityLabel("추가한 장소 \(submissionReceipts.count)곳")
            .accessibilityHint("추가한 장소 목록을 엽니다")
        }
    }

    @ViewBuilder
    private var postsTile: some View {
        if user == nil {
            Button(action: onRequestSignIn) {
                MyCollectionTile(
                    title: "내 글",
                    count: nil,
                    unit: "개",
                    caption: "로그인하면 볼 수 있어요",
                    symbolName: "text.bubble",
                    minHeight: 148,
                    isLocked: true
                )
            }
            .buttonStyle(MyPressableButtonStyle())
            .accessibilityLabel("내 글, 로그인이 필요해요")
            .accessibilityHint("로그인 화면을 엽니다")
        } else {
            NavigationLink {
                MyPostsView(posts: myPosts, makeRow: postRow, onCompose: onCompose)
            } label: {
                MyCollectionTile(
                    title: "내 글",
                    count: myPosts.count,
                    unit: "개",
                    caption: postsCaption,
                    symbolName: "text.bubble",
                    minHeight: 148,
                    photo: postCoverAttachment.map { attachment in
                        AnyView(MyAttachmentImage(attachment: attachment, detail: .card))
                    }
                )
            }
            .buttonStyle(MyPressableButtonStyle())
            .accessibilityLabel("내 글 \(myPosts.count)개")
            .accessibilityHint("내 글 목록을 엽니다")
        }
    }

    private var savedCaption: String {
        guard let first = savedSpots.first else { return "마음에 드는 출사지를 저장해보세요" }
        return savedSpots.count == 1 ? first.name : "\(first.name) 외 \(savedSpots.count - 1)곳"
    }

    private var placesCaption: String {
        guard let latest = submissionReceipts.first else { return "나만 아는 출사지를 알려주세요" }
        if photolessPlaceCount > 0 {
            return "사진 없는 곳 \(photolessPlaceCount)곳"
        }
        return "최근 · \(latest.name)"
    }

    private var postsCaption: String {
        guard let latest = myPosts.first else { return "현장 소식을 남겨보세요" }
        return "마지막 글 · \(communityRelativeTimeText(for: latest.createdAt))"
    }

    // MARK: - 글 행

    /// 목록 행과 글 상세를 한 곳에서 만듭니다.
    /// "내 글" 화면이 이 함수를 그대로 받아 써서 같은 글이 같은 모양으로 보입니다.
    private func postRow(_ post: CommunityPost) -> some View {
        NavigationLink {
            postDetail(post)
        } label: {
            MyPostRow(post: post)
        }
        .buttonStyle(.plain)
    }

    private func postDetail(_ post: CommunityPost) -> some View {
        CommunityPostDetailView(
            post: post,
            spot: spot(for: post),
            captureLocationSpot: captureLocationSpot(for: post),
            currentUserID: user?.id ?? "",
            isLiked: likedPostIDs.contains(post.id),
            likeCount: displayedLikeCount(for: post),
            isFollowing: followedAuthorIDs.contains(post.authorID),
            comments: commentsByPostID[post.id] ?? [],
            focusCommentComposerOnAppear: false,
            onToggleLike: onToggleLike,
            onToggleFollow: onToggleFollow,
            onAddComment: onAddComment,
            onSelectSpot: onSelectSpot,
            onEdit: onEditPost,
            onDelete: onDeletePost,
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

// MARK: - 커버 부품

/// 사진이 없을 때의 커버. "Frame & Light" 의 Light — 프레임 오른쪽에서 번지는 골든아워의 빛.
///
/// 주황을 면으로 칠하지 않습니다. 22% 에서 0 으로 사라지는 빛이라,
/// 캔버스는 여전히 검정(라이트는 흰색)이고 사진이 들어오면 사진에 자리를 내줍니다.
private struct MyGoldenLightBackground: View {
    var body: some View {
        ZStack {
            AppColors.background

            RadialGradient(
                gradient: Gradient(colors: [
                    AppColors.accent.opacity(0.22),
                    AppColors.accent.opacity(0)
                ]),
                center: UnitPoint(x: 0.86, y: 0.62),
                startRadius: 0,
                endRadius: 320
            )
            // 커버 아래 끝에서 빛이 0 이 되게 합니다.
            // 커버 아래(타일 영역)는 빛이 없는 캔버스라, 빛이 켜진 채로 끊기면
            // 커버 밑에 가로 경계선이 생깁니다.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// 사진 커버 위쪽을 캔버스 색으로 흐리게 합니다. 상태바와 톱니바퀴를 받칩니다.
private struct MyCanvasFade: View {
    let height: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: AppColors.background, location: 0),
                .init(color: AppColors.background.opacity(0.75), location: 0.55),
                .init(color: AppColors.background.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 커버 위 원형 아이콘 버튼. 보이는 원 38pt, 터치 44pt.
/// 사진 위에서는 유리, 사진이 없으면 불투명 surface2 입니다.
/// (유리는 사진 위에 뜬 버튼에만 씁니다. 단색 배경 위 유리는 회색 원일 뿐입니다)
private struct MyCoverIconButtonLabel: View {
    static let visibleSize: CGFloat = 38

    let symbolName: String
    let onPhoto: Bool

    var body: some View {
        Group {
            if onPhoto {
                icon
                    .vfGlass(in: Circle(), interactive: true)
            } else {
                icon
                    .background(AppColors.mutedSurface, in: Circle())
            }
        }
        .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
        .contentShape(Rectangle())
    }

    private var icon: some View {
        Image(systemName: symbolName)
            // Dynamic Type 제외: 고정 38pt 원 안의 기호.
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppColors.primary)
            .frame(width: Self.visibleSize, height: Self.visibleSize)
    }
}

/// 커뮤니티 아바타와 같은 규칙(이름 첫 글자)을 씁니다.
/// 두 화면에서 같은 사람이 다르게 보이면 같은 사람인지 알 수 없습니다.
private struct MyProfileAvatar: View {
    let name: String
    var onPhoto: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private let size: CGFloat = 64

    var body: some View {
        Text(initial)
            // Dynamic Type 제외: 원 지름에 비례하는 글자. 원이 안 커지므로 글자도 안 커진다.
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(inkColor)
            .frame(width: size, height: size)
            .background(AppColors.mutedSurface, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(onPhoto ? Color.white.opacity(0.35) : AppColors.divider, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var inkColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : .black.opacity(0.72)
    }
}

// MARK: - 컬렉션 타일

/// 마이 탭의 입구 타일. 누르면 전용 화면이 열립니다.
///
/// 사진이 있으면 사진이 배경이고 흰 글자, 없으면 surface1 위에 큰 숫자가 주인공입니다.
/// 사진이 없는 사용자도 회색 상자가 아니라 계기판처럼 읽히게 합니다.
private struct MyCollectionTile: View {
    let title: String
    /// 잠긴 타일(게스트)은 nil 이고 숫자를 그리지 않습니다.
    let count: Int?
    let unit: String
    let caption: String
    let symbolName: String
    let minHeight: CGFloat
    var photo: AnyView? = nil
    var isLocked: Bool = false

    private var onPhoto: Bool { photo != nil }
    private var ink: Color { onPhoto ? .white : AppColors.primary }
    private var subInk: Color { onPhoto ? Color.white.opacity(0.8) : AppColors.secondaryText }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 제목 줄 높이만큼 비워 둔 자리입니다. 실제 제목은 아래 overlay 가 맨 위에 그립니다.
            //
            // 제목은 맨 위, 숫자는 바닥에 두고 싶은데 ScrollView 안에서는 높이 제안이 없어서
            // Spacer 가 늘어나지 않습니다. 그렇다고 높이를 고정하면 큰 글자에서 숫자가 잘립니다.
            // 그래서 내용은 바닥 정렬로 두고 제목만 위에 겹쳐 그립니다.
            // 글자가 커지면 이 빈 자리도 같이 커지므로 타일이 늘어나고, 제목과 숫자가 겹치지 않습니다.
            titleRow
                .hidden()
                .accessibilityHidden(true)

            Spacer(minLength: VFSpace.lg)

            if let count {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(count)")
                        .vfText(.gauge)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(unit)
                        .vfText(.subhead.weight(.semibold))
                        .foregroundStyle(subInk)
                }
            }

            Text(caption)
                .vfText(.caption)
                .foregroundStyle(subInk)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .padding(Self.contentPadding)
        // 높이는 "최소" 만 정합니다. 큰 글자에서는 타일이 내용만큼 늘어나고 잘리지 않습니다.
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .bottomLeading)
        .overlay(alignment: .topLeading) {
            titleRow
                .padding(Self.contentPadding)
        }
        .background {
            background
        }
        .clipShape(shape)
        .contentShape(shape)
    }

    private static let contentPadding: CGFloat = VFSpace.md + VFSpace.xs

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.sm) {
            Text(title)
                .vfText(.headline)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: VFSpace.xs)

            Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(subInk)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var background: some View {
        if let photo {
            photo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // 위(제목)와 아래(숫자)의 흰 글자를 받치는 어둠. 가운데는 사진이 보이게 옅게 둡니다.
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.50), location: 0),
                            .init(color: .black.opacity(0.12), location: 0.42),
                            .init(color: .black.opacity(0.70), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        } else {
            ZStack(alignment: .bottomTrailing) {
                AppColors.cardBackground

                Image(systemName: symbolName)
                    // 장식용 워터마크. 글자 크기와 무관한 고정 크기입니다.
                    .font(.system(size: 84, weight: .regular))
                    .foregroundStyle(AppColors.primary.opacity(0.06))
                    .offset(x: 14, y: 18)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// 저장 타일의 사진 모자이크. 1장이면 한 장, 2장이면 반반, 3장이면 큰 1 + 작은 2.
private struct MySavedMosaic: View {
    let spots: [PhotoSpot]
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            if spots.count >= 3 {
                HStack(spacing: gap) {
                    photo(spots[0])
                        .frame(width: max(0, (geometry.size.width - gap) * 0.62))

                    VStack(spacing: gap) {
                        photo(spots[1])
                        photo(spots[2])
                    }
                }
            } else if spots.count == 2 {
                HStack(spacing: gap) {
                    photo(spots[0])
                    photo(spots[1])
                }
            } else if let first = spots.first {
                photo(first)
            }
        }
    }

    private func photo(_ spot: PhotoSpot) -> some View {
        PhotoSpotImageView(
            spot: spot,
            symbolSize: 20,
            targetPixelWidth: VFPhotoDetail.card.pixelWidth
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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

// MARK: - 버튼

/// 화면의 주 동작 버튼입니다. 주황 채움 캡슐 52pt.
/// 버튼 공통 컴포넌트(개선안 8)의 "주요 버튼" 규격과 같습니다.
private struct MyPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .vfText(.headline)
                .foregroundStyle(AppColors.onAccent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AppColors.accent, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 누르는 동안 살짝 들어가는 반응. 동작 줄이기 설정이면 크기는 두고 밝기만 바꿉니다.
private struct MyPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(VFMotion.quick, value: configuration.isPressed)
    }
}

/// 필터 칩. 보이는 높이 36pt · 터치 44pt, 선택은 주황 채움.
/// 칩 공통 컴포넌트(개선안 9) 규격과 같습니다.
private struct MyFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private let visibleHeight: CGFloat = 36

    var body: some View {
        Button {
            VFHaptics.selection()
            action()
        } label: {
            Text(title)
                .vfText(.subhead.weight(.semibold))
                .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.primary)
                .lineLimit(1)
                .padding(.horizontal, VFSpace.md + 2)
                .frame(minHeight: visibleHeight)
                .background(isSelected ? AppColors.accent : AppColors.mutedSurface, in: Capsule())
                .padding(.vertical, (AppLayout.touchTarget - visibleHeight) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(VFMotion.quick, value: isSelected)
    }
}

// MARK: - 빈 상태

/// 전용 화면의 빈 상태. 뷰파인더 프레임 안에 기호 하나 + 할 수 있는 일 하나.
private struct MyFramedEmptyState: View {
    let symbolName: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: VFSpace.lg) {
            ZStack {
                VFViewfinderCorners(cornerLength: 18)
                    .stroke(
                        AppColors.secondaryText.opacity(0.6),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                Image(systemName: symbolName)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)

            VStack(spacing: VFSpace.sm) {
                Text(title)
                    .vfText(.title2)
                    .foregroundStyle(AppColors.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .vfText(.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            MyPrimaryButton(title: actionTitle, action: action)
                .frame(maxWidth: 260)
        }
        .padding(.horizontal, VFSpace.xl)
        .padding(.top, VFSpace.xxl + VFSpace.lg)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 목록

private enum MyListRowMetrics {
    static let horizontalPadding: CGFloat = 14
    static let thumbnailSize: CGFloat = 56
    /// 구분선은 썸네일 오른쪽, 글자가 시작하는 곳부터 그립니다.
    static let dividerInset: CGFloat = horizontalPadding + thumbnailSize + VFSpace.md
}

/// 표면 하나에 행을 모으고, 행 사이에만 얇은 구분선을 둡니다.
private struct MyGroupedList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)

                if item.id != items.last?.id {
                    MyRowDivider(leadingInset: MyListRowMetrics.dividerInset)
                }
            }
        }
        .appCardSurface()
    }
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

/// 목록 행 왼쪽의 56pt 칸.
/// isDashed 는 "사진이 들어갈 자리가 비어 있다" 는 뜻의 점선 칸입니다.
private struct MyRowThumbnail<Content: View>: View {
    var isDashed: Bool = false
    @ViewBuilder let content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
    }

    var body: some View {
        ZStack {
            if isDashed {
                Color.clear
            } else {
                AppColors.mutedSurface
            }

            content()
        }
        .frame(width: MyListRowMetrics.thumbnailSize, height: MyListRowMetrics.thumbnailSize)
        .clipShape(shape)
        .overlay {
            if isDashed {
                shape.strokeBorder(
                    AppColors.secondaryText.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private enum MyDateText {
    private static let isoFormatter = ISO8601DateFormatter()

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter
    }

    private static let dayFormatter = formatter("M월 d일")
    private static let dayNumberFormatter = formatter("d")
    private static let monthFormatter = formatter("M월")

    static func day(fromISO8601 raw: String) -> String? {
        guard let date = isoFormatter.date(from: raw) else { return nil }
        return dayFormatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func dayNumber(_ date: Date) -> String {
        dayNumberFormatter.string(from: date)
    }

    static func month(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }
}

/// 사진이 없는 글의 왼쪽 칸. 일기장처럼 날짜를 크게 보여줍니다.
private struct MyDateTile: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(MyDateText.dayNumber(date))
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)
                .monospacedDigit()

            Text(MyDateText.month(date))
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
    }
}

/// 내가 추가한 장소 한 줄. 누르면 장소 상세가 열립니다.
private struct MyPlaceSubmissionRow: View {
    let receipt: PlaceSubmissionReceipt
    /// 지금 불러온 장소 목록에서 찾은 장소입니다. 아직 못 불러왔으면 nil 이고,
    /// 그때는 누를 수 없는 행으로 둡니다.
    let spot: PhotoSpot?
    let onSelectSpot: (PhotoSpot) -> Void

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
        HStack(spacing: VFSpace.md) {
            if let spot, spot.hasReliableDisplayImage {
                MyRowThumbnail {
                    PhotoSpotImageView(
                        spot: spot,
                        symbolSize: 18,
                        targetPixelWidth: VFPhotoDetail.thumbnail.pixelWidth
                    )
                }
            } else {
                // 사진이 비어 있는 자리. 점선 칸으로 "사진이 들어갈 곳" 을 보여줍니다.
                MyRowThumbnail(isDashed: true) {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.name)
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                VFMetaLine(items: [regionText, submittedDayText].compactMap { $0 })

                if let statusText {
                    Text(statusText)
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: VFSpace.xs)

            if spot != nil {
                MyRowChevron()
            }
        }
        .padding(.horizontal, MyListRowMetrics.horizontalPadding)
        .padding(.vertical, VFSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

/// 내 글 한 줄. 누르면 글 상세로 이동합니다.
private struct MyPostRow: View {
    let post: CommunityPost

    private var photo: CommunityPhotoAttachment? {
        post.publicPhotoAttachments.first
    }

    /// 제목이 없으면 본문 첫 줄을 제목처럼 씁니다.
    private var headline: String {
        if let title = post.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        let firstLine = post.message
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        if !firstLine.isEmpty {
            return firstLine
        }

        return post.hasPhotos ? "사진" : "글"
    }

    /// 사진이 없는 글은 왼쪽 날짜 칸이 이미 날짜를 말합니다.
    /// 그래서 하루 안의 글에만 "3시간 전" 을 붙이고, 사진 글에는 항상 붙입니다.
    private var timeText: String {
        let isWithinDay = Date().timeIntervalSince(post.createdAt) < 24 * 60 * 60
        guard photo != nil || isWithinDay else { return "" }
        return communityRelativeTimeText(for: post.createdAt)
    }

    private var accessibilityText: String {
        var parts = [headline]
        if post.hasStatusInfo {
            parts.append("혼잡도 \(post.crowd.displayName)")
        }
        if let spotName = post.relatedSpotName {
            parts.append(spotName)
        }
        parts.append(MyDateText.day(post.createdAt))
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: VFSpace.md) {
            if let photo {
                MyRowThumbnail {
                    MyAttachmentImage(attachment: photo, detail: .thumbnail)
                        .frame(width: MyListRowMetrics.thumbnailSize, height: MyListRowMetrics.thumbnailSize)
                        .clipped()
                }
            } else {
                MyRowThumbnail {
                    MyDateTile(date: post.createdAt)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(2)

                HStack(spacing: VFSpace.sm) {
                    // 현장 정보가 있는 글은 혼잡도를 먼저 보여줍니다. (점 3개 + 글자)
                    if post.hasStatusInfo {
                        VFCrowdBadge(level: VFCrowdLevel.from(post.crowd.displayName))
                    }

                    VFMetaLine(items: [post.relatedSpotName ?? "", timeText])
                }
            }

            Spacer(minLength: VFSpace.xs)

            MyRowChevron()
        }
        .padding(.horizontal, MyListRowMetrics.horizontalPadding)
        .padding(.vertical, VFSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
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

// MARK: - 저장한 장소 카드

/// 저장한 장소 화면의 격자 카드입니다.
///
/// 4:5 사진 + 사진 아래 이름·지역. 홈 레일과 같은 비율이라 홈에서 본 사진을
/// 같은 모양으로 다시 찾습니다. 글자를 사진 아래에 두어 사진을 어둡게 덮지 않습니다.
struct SavedSpotTile: View {
    let spot: PhotoSpot

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            VFPhotoTile(
                spot: spot,
                aspectRatio: 4.0 / 5.0,
                imageDetail: .card
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name)
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(HomeSpotDisplayFormatter.region(for: spot))
                    .vfText(.subhead)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spot.name), \(HomeSpotDisplayFormatter.region(for: spot))")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 전용 화면
//
//  마이 탭 타일을 누르면 열립니다. 마이 탭은 입구이고, 목록은 여기서 봅니다.
//  모두 큰 제목(스크롤하면 작아짐)을 쓰고, 빈 상태는 뷰파인더 프레임 + 첫 행동 하나입니다.
// ═══════════════════════════════════════════════════════════════════

private struct MySavedSpotsView: View {
    let spots: [PhotoSpot]
    let onSelect: (PhotoSpot) -> Void
    let onExplore: () -> Void
    let onToggleSave: (PhotoSpot) -> Void

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
                MyFramedEmptyState(
                    symbolName: "bookmark",
                    title: "저장한 출사지가 아직 없어요",
                    message: "홈이나 지도에서 마음에 드는 곳을 저장하면\n여기에 모여요.",
                    actionTitle: "출사지 둘러보기",
                    action: onExplore
                )
            } else {
                VStack(alignment: .leading, spacing: VFSpace.md) {
                    // 테마가 하나뿐이면 거를 게 없으므로 칩을 두지 않습니다.
                    if themes.count >= 2 {
                        themeChips
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: VFSpace.md),
                            GridItem(.flexible(), spacing: VFSpace.md)
                        ],
                        alignment: .leading,
                        spacing: VFSpace.lg
                    ) {
                        ForEach(visibleSpots) { spot in
                            Button {
                                onSelect(spot)
                            } label: {
                                SavedSpotTile(spot: spot)
                            }
                            .buttonStyle(MyPressableButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    // 다른 화면의 저장 버튼과 같은 촉감입니다.
                                    VFHaptics.save()
                                    // 빠진 칸을 나머지 카드가 채우는 움직임이 보이게 합니다.
                                    withAnimation(VFMotion.standard) {
                                        onToggleSave(spot)
                                    }
                                } label: {
                                    Label("저장 해제", systemImage: "bookmark.slash")
                                }
                            }
                        }
                    }
                    .vfScreenMargin()

                    Text("길게 누르면 저장을 해제할 수 있어요.")
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .vfScreenMargin()
                }
                .padding(.top, VFSpace.sm)
                .vfScrollBottomInset()
            }
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("저장한 장소")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }

    private var themeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VFSpace.sm) {
                MyFilterChip(title: "전체", isSelected: activeTheme == nil) {
                    selectedTheme = nil
                }

                ForEach(themes) { theme in
                    MyFilterChip(title: theme.title, isSelected: activeTheme == theme) {
                        selectedTheme = theme
                    }
                }
            }
            .padding(.horizontal, AppLayout.pageHorizontalPadding)
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
                MyFramedEmptyState(
                    symbolName: "mappin.and.ellipse",
                    title: "직접 추가한 장소가 아직 없어요",
                    message: "나만 아는 출사지를 알려주세요.\n다른 사진가의 다음 출사지가 돼요.",
                    actionTitle: "장소 추가",
                    action: onAddPlace
                )
            } else {
                MyGroupedList(items: receipts) { receipt in
                    MyPlaceSubmissionRow(
                        receipt: receipt,
                        spot: spots.first(where: { $0.id == receipt.id }),
                        onSelectSpot: onSelectSpot
                    )
                }
                .vfScreenMargin()
                .padding(.top, VFSpace.sm)
                .vfScrollBottomInset()
            }
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("추가한 장소")
        .navigationBarTitleDisplayMode(.large)
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

/// 행 생성을 클로저로 받습니다.
///
/// 글 상세로 가는 링크에 필요한 인자가 많습니다. 이 화면이 그것들을 다시
/// 프로퍼티로 받으면 MyTabView 의 인자 목록을 그대로 복사해야 하고,
/// 하나라도 어긋나면 다르게 동작합니다. MyTabView.postRow 를 그대로 받습니다.
private struct MyPostsView<Row: View>: View {
    let posts: [CommunityPost]
    let makeRow: (CommunityPost) -> Row
    let onCompose: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            if posts.isEmpty {
                MyFramedEmptyState(
                    symbolName: "square.and.pencil",
                    title: "남긴 글이 아직 없어요",
                    message: "지금 현장의 혼잡도와 분위기를 남겨보세요.\n다음 사람의 출사가 쉬워져요.",
                    actionTitle: "글쓰기",
                    action: onCompose
                )
            } else {
                MyGroupedList(items: posts) { post in
                    makeRow(post)
                }
                .vfScreenMargin()
                .padding(.top, VFSpace.sm)
                .vfScrollBottomInset()
            }
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("내 글")
        .navigationBarTitleDisplayMode(.large)
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
    let isSignedIn: Bool
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
                    .accessibilityHint("홈 추천의 출발점이 되는 사진 3장을 다시 고릅니다")
                }

                MySettingsGroup(title: "계정") {
                    if isSignedIn {
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
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }
}

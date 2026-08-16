import SwiftUI

private struct MyTabScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum MySectionAnchor: Hashable {
    case saved
    case submissions
    case posts
}

struct MyTabView: View {
    let user: AuthUser?
    let savedSpots: [PhotoSpot]
    let submissionReceipts: [PlaceSubmissionReceipt]
    let posts: [CommunityPost]
    let spots: [PhotoSpot]
    let likedPostIDs: Set<String>
    let followedAuthorIDs: Set<String>
    let commentsByPostID: [String: [CommunityComment]]
    let onTabBarVisibilityChange: (Bool) -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    let onEditPost: (CommunityPost) -> Void
    let onDeletePost: (CommunityPost) -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool
    let onRequestSignIn: () -> Void
    let onExploreSpots: () -> Void
    let onSignOut: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var previousScrollOffset: CGFloat?
    @State private var isTabBarHidden = false
    @State private var isSignInConfirmationPresented = false

    // 미리보기 개수.
    //
    // 저장은 2열 격자이므로 2개 = 정확히 한 줄입니다.
    // 제보는 한 줄짜리 행이라 3개까지 부담이 없습니다.
    // 내 글은 사진 전체 폭 카드라 2개만 해도 화면을 채웁니다.
    private let savedPreviewLimit = 2
    private let submissionPreviewLimit = 3
    private let postPreviewLimit = 2

    private var myPosts: [CommunityPost] {
        guard let user else { return [] }
        return posts.filter { $0.authorID == user.id }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        screenHeader

                        // ═══════════════════════════════════════════
                        //  [버그였던 상황]
                        //  프로필 섹션이 if user != nil 안에 있었습니다.
                        //  그런데 profileSection 자체가 게스트 분기를
                        //  이미 갖고 있습니다(MyProfileCard isGuest: true).
                        //  호출부가 막아서 그 분기에 도달할 수 없었고,
                        //  로그아웃하면 프로필 자리가 그냥 비었습니다.
                        //
                        //  대신 guestSignInSection 이 저장한 장소 아래에
                        //  같은 내용을 다시 그리고 있었습니다.
                        //  로그인 유도가 화면 중간에 묻혀 있었던 것입니다.
                        //
                        //  로그인 여부와 무관하게 프로필 자리는 항상
                        //  최상단에 있어야 합니다. 로그인했으면 내 정보,
                        //  안 했으면 로그인 유도가 같은 자리에 옵니다.
                        // ═══════════════════════════════════════════
                        profileSection

                        if user != nil {
                            activityOverview(using: proxy)
                        }

                        savedSection
                            .id(MySectionAnchor.saved)

                        if user != nil {
                            submissionSection
                                .id(MySectionAnchor.submissions)

                            postSection
                                .id(MySectionAnchor.posts)
                        }

                        usageInfoSection

                        if user != nil {
                            signOutButton
                        }
                    }
                    .padding(.horizontal, AppLayout.pageHorizontalPadding)
                    .padding(.top, AppLayout.pageTopPadding)
                    .padding(.bottom, 34)
                    .background {
                        GeometryReader { geometryProxy in
                            Color.clear
                                .preference(
                                    key: MyTabScrollOffsetPreferenceKey.self,
                                    value: geometryProxy.frame(in: .named("my-tab-scroll")).minY
                                )
                        }
                    }
                }
                .coordinateSpace(name: "my-tab-scroll")
                .onPreferenceChange(MyTabScrollOffsetPreferenceKey.self, perform: updateTabBarVisibility)
                .background(AppColors.background.ignoresSafeArea())
                .onAppear {
                    updateTabBarVisibility(0)
                }
                .confirmationDialog(
                    "로그인하시겠어요?",
                    isPresented: $isSignInConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button("로그인") {
                        onRequestSignIn()
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("로그인하면 프로필과 작성 활동을 계정에 연결할 수 있어요.")
                }
            }
            // Phase 1: 스크롤한 본문이 상태바 시계와 겹쳐 읽히는 문제를 수정합니다.
            .vfTopEdgeFade()
            .navigationBarHidden(true)
        }
    }

    private var screenHeader: some View {
        // Phase 1: 설명 부제를 제거했습니다.
        // "저장한 장소와 나의 활동을 한눈에 확인하세요" 는 화면이 이미 말하고 있는
        // 내용을 반복하는 문장이었습니다. 부제는 정보가 아니라 소음이었습니다.
        Text("마이")
            .vfText(.display)
            .foregroundStyle(AppColors.primary)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var profileSection: some View {
        if let user {
            MyProfileCard(
                title: user.displayName,
                subtitle: user.email ?? "로그인된 프로필",
                isGuest: false
            )
        } else {
            Button {
                requestSignInConfirmation()
            } label: {
                MyProfileCard(
                    title: "게스트로 둘러보는 중",
                    subtitle: "로그인하면 내 글과 제보를 한곳에서 관리할 수 있어요.",
                    isGuest: true
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("게스트 프로필, 로그인")
            .accessibilityHint("로그인 안내를 엽니다")
        }
    }

    private func activityOverview(using proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: AppLayout.contentSpacing) {
            // Phase 1: 설명 부제를 제거했습니다.
            // 아이콘과 숫자가 이미 내용을 전달하고 있어서 설명문이 불필요했습니다.
            Text("나의 활동")
                .vfText(.title1)
                .foregroundStyle(AppColors.primary)
                .accessibilityAddTraits(.isHeader)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        activityCards(using: proxy)
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        activityCards(using: proxy)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activityCards(using proxy: ScrollViewProxy) -> some View {
        MyActivitySummaryCard(
            title: "저장",
            value: "\(savedSpots.count)",
            symbolName: "bookmark.fill",
            isLocked: false,
            action: {
                scroll(to: .saved, using: proxy)
            }
        )

        MyActivitySummaryCard(
            title: "내 글",
            value: user == nil ? "로그인 필요" : "\(myPosts.count)",
            symbolName: "bubble.left.and.bubble.right.fill",
            isLocked: user == nil,
            action: {
                if user == nil {
                    requestSignInConfirmation()
                } else {
                    scroll(to: .posts, using: proxy)
                }
            }
        )

        MyActivitySummaryCard(
            title: "장소 제보",
            value: user == nil ? "로그인 필요" : "\(submissionReceipts.count)",
            symbolName: "mappin.and.ellipse",
            isLocked: user == nil,
            action: {
                if user == nil {
                    requestSignInConfirmation()
                } else {
                    scroll(to: .submissions, using: proxy)
                }
            }
        )
    }

    /// 미리보기와 전체 보기가 같은 카드를 쓰게 합니다.
    /// 두 곳에서 각각 만들면 인자 하나가 어긋나도 알아채기 어렵습니다.
    private func postCard(_ post: CommunityPost) -> some View {
        CommunityPostCard(
            post: post,
            spot: spot(for: post),
            currentUserID: user?.id ?? "",
            isLiked: likedPostIDs.contains(post.id),
            likeCount: post.likeCount + (likedPostIDs.contains(post.id) ? 1 : 0),
            isFollowing: followedAuthorIDs.contains(post.authorID),
            comments: commentsByPostID[post.id] ?? [],
            onEdit: onEditPost,
            onDelete: onDeletePost,
            onToggleLike: onToggleLike,
            onToggleFollow: onToggleFollow,
            onAddComment: onAddComment,
            onSelectSpot: onSelectSpot
        )
    }

    private var usageInfoSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.contentSpacing) {
            Text("이용 안내")
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                MyInformationRow(
                    symbolName: "iphone",
                    title: "기기에 저장",
                    detail: "저장한 장소는 로그인 전후에도 이 기기에서 확인할 수 있어요."
                )

                Divider()
                    .padding(.leading, 52)

                MyInformationRow(
                    symbolName: "person.crop.circle.badge.checkmark",
                    title: "계정 활동",
                    detail: "글, 댓글, 좋아요와 장소 제보가 필요할 때만 로그인하세요."
                )
            }
            .padding(.horizontal, 14)
            .appCardSurface()
        }
    }

    private var signOutButton: some View {
        Button(action: onSignOut) {
            Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                .vfText(.callout)
                .foregroundStyle(AppColors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .overlay(
            Capsule()
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }

    private func requestSignInConfirmation() {
        isSignInConfirmationPresented = true
    }

    private func scroll(to anchor: MySectionAnchor, using proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.24)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if savedSpots.count > savedPreviewLimit {
                MySectionHeader(title: "저장한 장소", count: savedSpots.count) {
                    SavedSpotsGridView(spots: savedSpots, onSelect: onSelectSpot)
                }
            } else {
                MySectionHeader(title: "저장한 장소", count: savedSpots.count)
            }

            if savedSpots.isEmpty {
                AppStatePanel(
                    symbolName: "bookmark",
                    title: "저장한 출사지가 아직 없어요",
                    message: "마음에 드는 장소를 저장하면 이곳에서 빠르게 다시 찾을 수 있어요.",
                    actionTitle: "출사지 둘러보기",
                    action: onExploreSpots
                )
            } else {
                // ═══════════════════════════════════════════════════
                //  목록 -> 2열 사진 격자
                //
                //  [문제였던 상황]
                //  84pt 썸네일 + 이름·지역·시간 3줄짜리 행이었습니다.
                //  저장한 장소는 "여기 가고 싶다" 고 표시해둔 사진입니다.
                //  그런데 사진이 전체 폭의 1/4 을 차지하고 나머지를
                //  글자가 채우고 있었습니다. 연락처 목록과 같은 형태입니다.
                //
                //  사진을 크게 하면 저장 목록이 "가고 싶은 곳 모음" 으로
                //  읽힙니다. 홈에서 사진을 보고 저장한 것이므로
                //  다시 찾을 때도 사진으로 찾습니다.
                //  이름은 사진 아래 한 줄로 충분합니다.
                // ═══════════════════════════════════════════════════
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: VFSpace.sm),
                        GridItem(.flexible(), spacing: VFSpace.sm)
                    ],
                    spacing: VFSpace.md
                ) {
                    ForEach(savedSpots.prefix(savedPreviewLimit)) { spot in
                        Button {
                            onSelectSpot(spot)
                        } label: {
                            SavedSpotTile(spot: spot)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var submissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if submissionReceipts.count > submissionPreviewLimit {
                MySectionHeader(title: "내 장소 제보", count: submissionReceipts.count) {
                    MySubmissionListView(receipts: submissionReceipts)
                }
            } else {
                MySectionHeader(title: "내 장소 제보", count: submissionReceipts.count)
            }

            if submissionReceipts.isEmpty {
                MyEmptyState(
                    symbolName: "checkmark.shield",
                    message: "제보한 장소가 아직 없어요"
                )
            } else {
                LazyVStack(spacing: 0) {
                    let preview = Array(submissionReceipts.prefix(submissionPreviewLimit))

                    ForEach(preview) { receipt in
                        PlaceSubmissionReceiptRow(receipt: receipt)

                        if receipt.id != preview.last?.id {
                            Divider()
                                .overlay(AppColors.divider)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
            }
        }
    }

    private var postSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if myPosts.count > postPreviewLimit {
                MySectionHeader(title: "내 글", count: myPosts.count) {
                    MyPostListView(posts: myPosts, makeCard: postCard)
                }
            } else {
                MySectionHeader(title: "내 글", count: myPosts.count)
            }

            if myPosts.isEmpty {
                MyEmptyState(
                    symbolName: "bubble.left.and.bubble.right",
                    message: "남긴 현장 정보가 아직 없어요"
                )
            } else {
                // CommunityPostCard 가 카드 표면을 버리고 사진 우선으로
                // 바뀌었습니다. 글을 나누는 수단이 여백뿐이므로
                // 커뮤니티 피드와 같은 간격을 씁니다.
                LazyVStack(spacing: VFSpace.xl) {
                    ForEach(myPosts.prefix(postPreviewLimit)) { post in
                        postCard(post)
                    }
                }
            }
        }
    }

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        spots.first { $0.id == post.spotID }
    }

    private func updateTabBarVisibility(_ offset: CGFloat) {
        defer {
            previousScrollOffset = offset
        }

        guard offset < -12 else {
            setTabBarHidden(false)
            return
        }

        guard let previousScrollOffset else { return }
        let delta = offset - previousScrollOffset

        if delta < -4 {
            setTabBarHidden(true)
        } else if delta > 4 {
            setTabBarHidden(false)
        }
    }

    private func setTabBarHidden(_ shouldHide: Bool) {
        guard isTabBarHidden != shouldHide else { return }
        isTabBarHidden = shouldHide
        onTabBarVisibilityChange(shouldHide)
    }
}

// ═══════════════════════════════════════════════════════════════════
//  프로필 카드
//
//  [문제였던 상황]
//  카드 배경이 AppColors.primary 였습니다.
//  다크 모드에서 그 값은 흰색이라, 마이 탭을 열면 화면 최상단에
//  거대한 흰 블록이 있었습니다. 앱에서 가장 밝고 가장 큰 면이
//  프로필 카드였습니다.
//  검정 캔버스 + 사진이 주인공인 앱에서 가장 눈에 띄는 것이
//  내 이메일 주소일 이유가 없습니다.
//
//  같은 실수를 작성 화면(제출 버튼·혼잡도 선택)과 댓글 전송 버튼에서도
//  했습니다. AppColors.primary 는 "글자색" 이고 표면색이 아닙니다.
//
//  [바꾼 것]
//  1. 배경을 surface1(카드 표면)로 내렸습니다.
//  2. 아바타를 커뮤니티와 같은 "이름 첫 글자" 로 통일했습니다.
//     person.crop.circle.fill 아이콘은 모든 사용자가 같아서
//     내 프로필이라는 느낌을 주지 못했습니다.
//  3. "로그인됨" 배지를 없앴습니다. 이름과 이메일이 보이는 것이
//     이미 로그인 상태를 말합니다. 배지는 같은 말을 반복했습니다.
//     게스트일 때만 행동 유도가 필요하므로 그때만 표시합니다.
// ═══════════════════════════════════════════════════════════════════

private struct MyProfileCard: View {
    let title: String
    let subtitle: String
    let isGuest: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: VFSpace.md) {
                    identity
                    if isGuest { signInBadge }
                }
            } else {
                HStack(spacing: VFSpace.md) {
                    identity
                    Spacer(minLength: VFSpace.sm)
                    if isGuest { signInBadge }
                }
            }
        }
        .padding(VFSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface()
    }

    private var identity: some View {
        HStack(spacing: VFSpace.md) {
            MyProfileAvatar(name: title, isGuest: isGuest)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .vfText(.title2)
                    .foregroundStyle(AppColors.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .vfText(.subhead)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 게스트에게만 보이는 로그인 유도.
    /// 주 동작이므로 앰버입니다.
    private var signInBadge: some View {
        HStack(spacing: 5) {
            Text("로그인")
            Image(systemName: "arrow.right")
                .accessibilityHidden(true)
        }
        .vfText(.callout)
        .fontWeight(.semibold)
        .foregroundStyle(AppColors.onAccent)
        .padding(.horizontal, 14)
        .frame(minHeight: AppLayout.touchTarget)
        .background(AppColors.accent, in: Capsule())
    }
}

/// 커뮤니티 아바타와 같은 규칙(이름 첫 글자)을 씁니다.
/// 두 화면에서 같은 사람이 다르게 보이면 같은 사람인지 알 수 없습니다.
private struct MyProfileAvatar: View {
    let name: String
    let isGuest: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let size: CGFloat = 52

    var body: some View {
        Group {
            if isGuest {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
            }
        }
        .foregroundStyle(inkColor)
        .frame(width: size, height: size)
        .background(AppColors.mutedSurface, in: Circle())
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

private struct MyActivitySummaryCard: View {
    let title: String
    let value: String
    let symbolName: String
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbolName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 34, height: 34)
                        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous))
                        .accessibilityHidden(true)

                    Spacer(minLength: 4)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.secondaryText)
                            .accessibilityHidden(true)
                    }
                }

                Text(value)
                    .font(isLocked ? AppTypography.caption : .title2.weight(.bold))
                    .fontWeight(isLocked ? .medium : .bold)
                    .foregroundStyle(isLocked ? AppColors.secondaryText : AppColors.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(title)
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .appCardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isLocked ? "로그인 필요" : "\(value)개")
        .accessibilityHint(isLocked ? "로그인 안내를 엽니다" : "해당 활동 섹션으로 이동합니다")
    }
}

private struct MyInformationRow: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 38, height: 38)
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .vfText(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.primary)

                Text(detail)
                    .vfText(.subhead)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaceSubmissionReceiptRow: View {
    let receipt: PlaceSubmissionReceipt

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 28, height: 28)
                .background(AppColors.mutedSurface, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.name)
                    .vfText(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(receipt.status.detail)
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(receipt.status.title)
                .vfText(.caption)
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(AppColors.mutedSurface, in: Capsule())
        }
        .padding(.vertical, 13)
    }
}

// ═══════════════════════════════════════════════════════════════════
//  섹션 헤더 + 더보기
//
//  [문제였던 상황]
//  마이 탭이 저장·제보·내 글을 전부 나열했습니다.
//  마이 탭은 hub 입니다. 내 활동이 얼마나 있는지 보고, 필요하면
//  그 목록으로 들어가는 화면입니다. 그런데 목록 자체가 되어 있어서
//  저장한 장소가 많으면 이용 안내와 로그아웃까지 한참 스크롤해야
//  했습니다.
//
//  커뮤니티 카드를 사진 전체 폭으로 키운 뒤 "내 글" 이 특히
//  심해졌습니다. 글 5개면 3000pt 가까이 됩니다.
//  제가 커뮤니티를 바꾸면서 만든 문제입니다.
//
//  [지금]
//  각 섹션은 미리보기만 보여주고, 개수가 더 있으면 헤더 오른쪽에
//  "더보기" 가 나타납니다. 전용 화면으로 push 합니다.
// ═══════════════════════════════════════════════════════════════════

private struct MySectionHeader<Destination: View>: View {
    let title: String
    let count: Int
    /// 미리보기보다 항목이 많을 때만 전달합니다.
    ///
    /// var 로 두면 memberwise init 에 nil 기본값이 생겨서
    /// MySectionHeader(title:count:) 호출이 이 init 과 아래 확장 init
    /// 양쪽에 맞아버리고, Destination 을 추론할 수 없게 됩니다.
    /// let 이면 memberwise init 이 이 인자를 반드시 요구하므로
    /// 두 경로가 겹치지 않습니다.
    let destination: (() -> Destination)?

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)

            Text("\(count)")
                .vfText(.mono)
                .foregroundStyle(AppColors.secondaryText)

            Spacer(minLength: VFSpace.sm)

            if let destination {
                NavigationLink {
                    destination()
                } label: {
                    HStack(spacing: 3) {
                        Text("더보기")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(minHeight: AppLayout.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) 전체 보기")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension MySectionHeader where Destination == EmptyView {
    init(title: String, count: Int) {
        self.title = title
        self.count = count
        self.destination = nil
    }
}

private struct MyEmptyState: View {
    let symbolName: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)

            Text(message)
                .vfText(.subhead)
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
    }
}

/// 저장 격자의 한 칸.
///
/// 사진이 주인공이고 이름은 아래 한 줄입니다.
/// 지역과 촬영 시간은 뺐습니다. 격자 칸 폭에 3줄을 넣으면
/// 글자가 잘리거나 사진이 작아집니다. 그 정보는 상세에 있습니다.
struct SavedSpotTile: View {
    let spot: PhotoSpot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VFPhotoTile(
                spot: spot,
                aspectRatio: VFPhoto.squareAspect,
                imageDetail: .thumbnail
            )

            Text(spot.name)
                .vfText(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.primary)
                .lineLimit(1)

            Text(HomeSpotDisplayFormatter.region(for: spot))
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spot.name), \(HomeSpotDisplayFormatter.region(for: spot))")
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - 전체 보기 화면
//
//  마이 탭의 각 섹션에서 "더보기" 로 들어옵니다.
//  마이 탭은 hub 이고 여기가 목록입니다.
//
//  세 화면 모두 미리보기와 같은 컴포넌트를 씁니다.
//  같은 데이터를 두 곳에서 다르게 그리면 같은 것으로 안 읽힙니다.
//  (커뮤니티에서 피드와 상세가 사진 규칙이 달라 버그가 났던 것과
//   같은 이유입니다.)
// ═══════════════════════════════════════════════════════════════════

struct SavedSpotsGridView: View {
    let spots: [PhotoSpot]
    let onSelect: (PhotoSpot) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: VFSpace.sm),
                    GridItem(.flexible(), spacing: VFSpace.sm)
                ],
                spacing: VFSpace.md
            ) {
                ForEach(spots) { spot in
                    Button {
                        onSelect(spot)
                    } label: {
                        SavedSpotTile(spot: spot)
                    }
                    .buttonStyle(.plain)
                }
            }
            .vfScreenMargin()
            .padding(.top, VFSpace.md)
            .vfScrollBottomInset()
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("저장한 장소")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MySubmissionListView: View {
    let receipts: [PlaceSubmissionReceipt]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(receipts) { receipt in
                    PlaceSubmissionReceiptRow(receipt: receipt)

                    if receipt.id != receipts.last?.id {
                        Divider()
                            .overlay(AppColors.divider)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                AppColors.mutedSurface,
                in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
            )
            .vfScreenMargin()
            .padding(.top, VFSpace.md)
            .vfScrollBottomInset()
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("내 장소 제보")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 카드 생성을 클로저로 받습니다.
///
/// CommunityPostCard 는 인자가 13개입니다. 이 화면이 그것들을 다시
/// 프로퍼티로 받으면 MyTabView 의 인자 목록을 그대로 복사해야 하고,
/// 하나라도 어긋나면 미리보기와 전체 보기가 다르게 동작합니다.
/// MyTabView.postCard 를 그대로 넘겨받아 같은 카드임을 보장합니다.
struct MyPostListView<Card: View>: View {
    let posts: [CommunityPost]
    let makeCard: (CommunityPost) -> Card

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: VFSpace.xl) {
                ForEach(posts) { post in
                    makeCard(post)
                }
            }
            .vfScreenMargin()
            .padding(.top, VFSpace.md)
            .vfScrollBottomInset()
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("내 글")
        .navigationBarTitleDisplayMode(.inline)
    }
}

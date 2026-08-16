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

                        if user != nil {
                            profileSection
                            activityOverview(using: proxy)
                        }

                        savedSection
                            .id(MySectionAnchor.saved)

                        if user != nil {
                            submissionSection
                                .id(MySectionAnchor.submissions)

                            postSection
                                .id(MySectionAnchor.posts)
                        } else {
                            guestSignInSection
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

    private var guestBenefitsSection: some View {
        MyGuestBenefitsCard {
            requestSignInConfirmation()
        }
    }

    private var guestSignInSection: some View {
        Button(action: requestSignInConfirmation) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 46, height: 46)
                    .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("게스트로 둘러보는 중")
                        .vfText(.headline)
                        .foregroundStyle(AppColors.primary)

                    Text("글을 쓰거나 장소를 제보할 때 로그인하면 돼요.")
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("게스트로 둘러보는 중, 로그인")
        .accessibilityHint("로그인 안내를 엽니다")
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
            MySectionHeader(title: "저장한 장소", count: savedSpots.count)

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
                    ForEach(savedSpots) { spot in
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
            MySectionHeader(title: "내 장소 제보", count: submissionReceipts.count)

            if submissionReceipts.isEmpty {
                MyEmptyState(
                    symbolName: "checkmark.shield",
                    message: "제보한 장소가 아직 없어요"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(submissionReceipts) { receipt in
                        PlaceSubmissionReceiptRow(receipt: receipt)

                        if receipt.id != submissionReceipts.last?.id {
                            Divider()
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
            MySectionHeader(title: "내 글", count: myPosts.count)

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
                    ForEach(myPosts) { post in
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

private struct MyGuestBenefitsCard: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 40, height: 40)
                    .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("로그인하면 더 편해요")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.primary)

                    Text("둘러보기와 저장은 그대로 이용하면서 계정 활동을 이어갈 수 있어요.")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 12) {
                MyBenefitRow(
                    symbolName: "square.and.pencil",
                    title: "현장 정보 작성",
                    detail: "직접 확인한 촬영 상황을 공유해요."
                )
                MyBenefitRow(
                    symbolName: "mappin.and.ellipse",
                    title: "장소 제보 관리",
                    detail: "제보한 장소의 검토 상태를 확인해요."
                )
                MyBenefitRow(
                    symbolName: "heart",
                    title: "계정이 필요한 활동",
                    detail: "글, 댓글, 좋아요는 로그인 후 이용해요."
                )
            }

            Button(action: onSignIn) {
                // 주 동작이므로 앰버입니다.
                // AppColors.primary 는 다크에서 흰색이라
                // 카드 안에 흰 판이 들어가 있었습니다.
                Text("로그인하고 활동 연결하기")
                    .vfText(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppLayout.touchTarget)
                    .background(AppColors.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("로그인 안내를 엽니다")
        }
        .padding(18)
        .appCardSurface()
    }
}

private struct MyBenefitRow: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 30, height: 30)
                .background(AppColors.mutedSurface, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
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
        .accessibilityElement(children: .combine)
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

private struct MySectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)

            Text("\(count)")
                .vfText(.mono)
                .foregroundStyle(AppColors.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count)개")
        .accessibilityAddTraits(.isHeader)
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

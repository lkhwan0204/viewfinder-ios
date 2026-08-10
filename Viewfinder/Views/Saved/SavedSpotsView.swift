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
            .navigationBarHidden(true)
        }
    }

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("마이")
                .font(AppTypography.screenTitle)
                .foregroundStyle(AppColors.primary)
                .accessibilityAddTraits(.isHeader)

            Text(user == nil ? "저장한 장소를 모아두고, 필요할 때 로그인하세요." : "저장한 장소와 나의 활동을 한눈에 확인하세요.")
                .font(AppTypography.metadata)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            VStack(alignment: .leading, spacing: 3) {
                Text("나의 활동")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(user == nil ? "저장은 바로 확인하고, 계정 활동은 로그인 후 이어갈 수 있어요." : "최근 활동을 항목별로 빠르게 확인하세요.")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                    .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("게스트로 둘러보는 중")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.primary)

                    Text("글을 쓰거나 장소를 제보할 때 로그인하면 돼요.")
                        .font(AppTypography.metadata)
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
                .font(AppTypography.sectionTitle)
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
                .font(AppTypography.bodyStrong)
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
                LazyVStack(spacing: 10) {
                    ForEach(savedSpots) { spot in
                        Button {
                            onSelectSpot(spot)
                        } label: {
                            SavedSpotRow(spot: spot)
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
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                LazyVStack(spacing: 10) {
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

private struct MyProfileCard: View {
    let title: String
    let subtitle: String
    let isGuest: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    identity
                    statusBadge
                }
            } else {
                HStack(spacing: 14) {
                    identity
                    Spacer(minLength: 8)
                    statusBadge
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColors.primary,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var identity: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(AppColors.background)
                .frame(width: 56, height: 56)
                .background(AppColors.background.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.background)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.background.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: isGuest ? "arrow.right" : "checkmark.circle.fill")
                .accessibilityHidden(true)

            Text(isGuest ? "로그인" : "로그인됨")
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(AppColors.primary)
        .padding(.horizontal, 13)
        .frame(minHeight: 44)
        .background(AppColors.background, in: Capsule())
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
                        .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .foregroundStyle(isLocked ? AppColors.secondaryText : AppColors.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(title)
                    .font(AppTypography.metadata)
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
                    .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Text("로그인하고 활동 연결하기")
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.primary)

                Text(detail)
                    .font(AppTypography.metadata)
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
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.primary)

                Text(detail)
                    .font(AppTypography.metadata)
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
                .background(AppColors.background, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(receipt.status.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(receipt.status.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(AppColors.background, in: Capsule())
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
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SavedSpotsView: View {
    let spots: [PhotoSpot]
    let onSelect: (PhotoSpot) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("저장")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppColors.primary)

                    if spots.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(width: 40, height: 40)
                                .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text("아직 저장한 출사지가 없어요")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(spots) { spot in
                                Button {
                                    onSelect(spot)
                                } label: {
                                    SavedSpotRow(spot: spot)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }
}

struct SavedSpotRow: View {
    let spot: PhotoSpot

    var body: some View {
        HStack(spacing: 12) {
            PhotoSpotImageView(spot: spot, symbolSize: 20)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(spot.name)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(HomeSpotDisplayFormatter.region(for: spot))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text(HomeSpotDisplayFormatter.bestTime(spot.bestTime))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(spot.theme.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.secondaryText.opacity(0.65))
        }
        .padding(10)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

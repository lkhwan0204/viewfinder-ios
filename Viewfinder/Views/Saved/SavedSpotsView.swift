import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════
//  마이 탭 — 개편
//
//  [전에 있던 문제]
//  - 제목이 40pt(display) 였습니다. 40pt 는 홈 Hero 장소명 전용 크기라
//    탭마다 첫 화면 제목 크기가 달랐습니다. (커뮤니티 17pt, 마이 40pt)
//  - "나의 활동" 카드 3개(118pt)가 저장·글·제보 개수를 보여주고,
//    바로 아래 섹션 제목이 같은 개수를 또 보여줬습니다.
//  - 저장한 장소는 한 줄(2장)만 보였습니다. 마이 탭에서 가장 자주 다시
//    찾는 것이 저장한 장소인데 가장 작게 보였습니다.
//  - 내 장소 제보 행은 눌러도 아무 일이 없었고, 모든 행이 같은 문구
//    ("홈, 지도, 검색에 공개됐어요" + "공개됨")를 반복했습니다.
//    사진이 없는 장소는 실제로 홈과 지도에 나오지 않는데도 그렇게 적혀 있었습니다.
//  - 내 글은 커뮤니티 피드의 전체 폭 사진 카드를 그대로 써서 2개로 화면을 채웠습니다.
//  - "이용 안내" 의 설명 두 줄이 누를 수 있는 설정 행처럼 생겼습니다.
//
//  [지금]
//    마이               탭 첫 화면 제목 28pt(title1)
//    프로필 카드         이름 · 이메일 · 개수 3칸 (누르면 그 섹션으로)
//    저장한 장소         4:5 사진 레일. 이름은 사진 아래. 홈 레일과 같은 폭
//    내가 추가한 장소    눌러서 상세로 가는 목록. 어디에 보이는지 사실대로
//    내 글              한 줄 목록. 눌러서 글 상세로
//    설정               화면 모드 · 사진 취향 · 로그아웃 + 안내 한 줄
//
//  주황은 게스트의 "로그인" 버튼 한 곳에만 씁니다. 로그인한 사용자에게는
//  이 화면에 주황이 없습니다. 이 화면의 일은 "내 것 다시 찾기" 라서
//  강조할 주 동작이 없습니다.
// ═══════════════════════════════════════════════════════════════════

private enum MySectionAnchor: Hashable {
    case saved
    case places
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
    let communityViewModel: CommunityViewModel
    let onTabBarVisibilityChange: (Bool) -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    let onEditPost: (CommunityPost) -> Void
    let onDeletePost: (CommunityPost) async throws -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool
    let onRequestSignIn: () -> Void
    let onExploreSpots: () -> Void
    /// 빈 "내가 추가한 장소" 에서 바로 장소 추가로 갑니다.
    let onAddPlace: () -> Void
    /// 빈 "내 글" 에서 바로 글쓰기로 갑니다.
    let onCompose: () -> Void
    let onResetTaste: () -> Void
    let onSignOut: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.defaultValue.rawValue

    /// 저장 레일에 올리는 최대 개수. 나머지는 "전체 보기" 격자에서 봅니다.
    private let savedRailLimit = 10
    /// 레일 폭(화면의 42%)에서는 한 화면에 2장 반이 보입니다.
    /// 3장부터는 화면 밖에 장소가 있으므로 "전체 보기" 를 둡니다.
    private let savedSeeAllThreshold = 3
    /// 목록은 한 줄짜리 행이라 3개까지 보여줘도 화면을 채우지 않습니다.
    private let placePreviewLimit = 3
    private let postPreviewLimit = 3

    private var myPosts: [CommunityPost] {
        guard let user else { return [] }
        return posts
            .filter { $0.authorID == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .defaultValue
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VFSpace.xl) {
                        screenHeader

                        // 로그인 여부와 무관하게 프로필 자리는 항상 맨 위입니다.
                        // 로그인했으면 내 정보, 안 했으면 로그인 안내가 같은 자리에 옵니다.
                        profileSection(using: proxy)

                        savedSection
                            .id(MySectionAnchor.saved)

                        if user != nil {
                            placesSection
                                .id(MySectionAnchor.places)

                            postsSection
                                .id(MySectionAnchor.posts)
                        }

                        settingsSection
                    }
                    .padding(.horizontal, AppLayout.pageHorizontalPadding)
                    .padding(.top, AppLayout.pageTopPadding)
                    .padding(.bottom, VFSpace.xl)
                }
                // iOS 26: 위로 조금만 올려도 줄어든 탭바가 다시 펼쳐지게 합니다.
                .vfReportsTabBarScroll()
                .background(AppColors.background.ignoresSafeArea())
            }
            // 스크롤한 본문이 상태바 시계와 겹쳐 읽히지 않게 합니다.
            .vfTopScrollEdge()
            .navigationBarHidden(true)
            .onAppear {
                onTabBarVisibilityChange(false)
            }
        }
    }

    // MARK: - 제목

    private var screenHeader: some View {
        // 탭 첫 화면 제목은 28pt(title1) 로 통일합니다. (개선안 1: 제목 위계)
        // 40pt(display) 는 홈 Hero 장소명과 온보딩 제목에만 씁니다.
        Text("마이")
            .vfText(.title1)
            .foregroundStyle(AppColors.primary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 프로필

    @ViewBuilder
    private func profileSection(using proxy: ScrollViewProxy) -> some View {
        if let user {
            VStack(spacing: 0) {
                HStack(spacing: VFSpace.md) {
                    MyProfileAvatar(name: user.displayName, isGuest: false)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName)
                            .vfText(.title2)
                            .foregroundStyle(AppColors.primary)
                            .lineLimit(2)

                        if let email = user.email, !email.isEmpty {
                            Text(email)
                                .vfText(.subhead)
                                .foregroundStyle(AppColors.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(VFSpace.md + VFSpace.xs)
                .accessibilityElement(children: .combine)

                MyRowDivider(leadingInset: 0)

                // 전에는 "나의 활동" 카드 3개(각 118pt)가 따로 있었습니다.
                // 개수는 프로필에 붙은 한 줄이면 충분하고, 누르면 그 섹션으로 갑니다.
                statsRow(using: proxy)
            }
            .appCardSurface()
        } else {
            VStack(alignment: .leading, spacing: VFSpace.md + VFSpace.xs) {
                HStack(spacing: VFSpace.md) {
                    MyProfileAvatar(name: "", isGuest: true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("로그인하고 기록을 남겨보세요")
                            .vfText(.headline)
                            .foregroundStyle(AppColors.primary)

                        Text("현장 정보, 장소 추가, 글쓰기에 필요해요")
                            .vfText(.subhead)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                // 게스트에게 이 화면의 주 동작은 로그인 하나입니다. 이 화면에서 주황은 여기뿐입니다.
                MyPrimaryButton(title: "로그인", action: onRequestSignIn)
            }
            .padding(VFSpace.md + VFSpace.xs)
            .appCardSurface()
        }
    }

    private struct MyStat: Identifiable {
        let id: MySectionAnchor
        let title: String
        let value: Int
    }

    private var stats: [MyStat] {
        [
            MyStat(id: .saved, title: "저장", value: savedSpots.count),
            MyStat(id: .places, title: "추가한 장소", value: submissionReceipts.count),
            MyStat(id: .posts, title: "글", value: myPosts.count)
        ]
    }

    @ViewBuilder
    private func statsRow(using proxy: ScrollViewProxy) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // 큰 글자에서는 세 칸이 좁아지므로 한 줄에 하나씩 둡니다.
            VStack(spacing: 0) {
                ForEach(stats) { stat in
                    statButton(stat, using: proxy, isColumn: false)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(stats) { stat in
                    statButton(stat, using: proxy, isColumn: true)
                }
            }
        }
    }

    private func statButton(_ stat: MyStat, using proxy: ScrollViewProxy, isColumn: Bool) -> some View {
        Button {
            scroll(to: stat.id, using: proxy)
        } label: {
            Group {
                if isColumn {
                    VStack(spacing: 2) {
                        Text("\(stat.value)")
                            .vfText(.title2)
                            .foregroundStyle(AppColors.primary)
                            .monospacedDigit()

                        Text(stat.title)
                            .vfText(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VFSpace.md)
                } else {
                    HStack(spacing: VFSpace.sm) {
                        Text(stat.title)
                            .vfText(.callout)
                            .foregroundStyle(AppColors.secondaryText)

                        Spacer(minLength: VFSpace.sm)

                        Text("\(stat.value)")
                            .vfText(.title2)
                            .foregroundStyle(AppColors.primary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, VFSpace.md + VFSpace.xs)
                    .padding(.vertical, VFSpace.sm)
                }
            }
            .frame(minHeight: AppLayout.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stat.title) \(stat.value)개")
        .accessibilityHint("해당 섹션으로 이동합니다")
    }

    private func scroll(to anchor: MySectionAnchor, using proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.24)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    // MARK: - 저장한 장소

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            if savedSpots.count >= savedSeeAllThreshold {
                MySectionHeader(title: "저장한 장소", count: savedSpots.count) {
                    SavedSpotsGridView(spots: savedSpots, onSelect: onSelectSpot)
                }
            } else {
                MySectionHeader(title: "저장한 장소", count: savedSpots.count)
            }

            if savedSpots.isEmpty {
                MyInlineEmptyState(
                    symbolName: "bookmark",
                    message: "저장한 출사지가 아직 없어요",
                    actionTitle: "둘러보기",
                    action: onExploreSpots
                )
            } else {
                savedRail
            }
        }
    }

    /// 홈 레일과 같은 카드 폭(VFPhoto.railWidthRatio)과 비율(4:5)을 씁니다.
    /// 이름은 사진 위가 아니라 아래에 둡니다. 글자를 읽히게 하려고 사진을
    /// 어둡게 덮지 않아도 되기 때문입니다.
    private var savedRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: VFSpace.md) {
                ForEach(savedSpots.prefix(savedRailLimit)) { spot in
                    Button {
                        onSelectSpot(spot)
                    } label: {
                        SavedSpotTile(spot: spot)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { length, _ in
                        length * VFPhoto.railWidthRatio
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, AppLayout.pageHorizontalPadding)
        }
        .scrollTargetBehavior(.viewAligned)
        // 페이지 좌우 여백을 넘어 화면 끝까지 넘길 수 있게 합니다.
        // 첫 카드는 다른 섹션과 같은 여백에서 시작합니다.
        .padding(.horizontal, -AppLayout.pageHorizontalPadding)
    }

    // MARK: - 내가 추가한 장소

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            if submissionReceipts.count > placePreviewLimit {
                MySectionHeader(title: "내가 추가한 장소", count: submissionReceipts.count) {
                    MySubmissionListView(
                        receipts: submissionReceipts,
                        spots: spots,
                        onSelectSpot: onSelectSpot
                    )
                }
            } else {
                MySectionHeader(title: "내가 추가한 장소", count: submissionReceipts.count)
            }

            if submissionReceipts.isEmpty {
                MyInlineEmptyState(
                    symbolName: "mappin.and.ellipse",
                    message: "직접 추가한 장소가 아직 없어요",
                    actionTitle: "장소 추가",
                    action: onAddPlace
                )
            } else {
                MyGroupedList(items: Array(submissionReceipts.prefix(placePreviewLimit))) { receipt in
                    MyPlaceSubmissionRow(
                        receipt: receipt,
                        spot: spots.first(where: { $0.id == receipt.id }),
                        onSelectSpot: onSelectSpot
                    )
                }
            }
        }
    }

    // MARK: - 내 글

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            if myPosts.count > postPreviewLimit {
                MySectionHeader(title: "내 글", count: myPosts.count) {
                    MyPostListView(posts: myPosts, makeRow: postRow)
                }
            } else {
                MySectionHeader(title: "내 글", count: myPosts.count)
            }

            if myPosts.isEmpty {
                MyInlineEmptyState(
                    symbolName: "square.and.pencil",
                    message: "남긴 글이 아직 없어요",
                    actionTitle: "글쓰기",
                    action: onCompose
                )
            } else {
                MyGroupedList(items: Array(myPosts.prefix(postPreviewLimit))) { post in
                    postRow(post)
                }
            }
        }
    }

    /// 미리보기와 "전체 보기" 가 같은 행을 쓰게 합니다.
    /// 같은 글을 두 곳에서 다르게 그리면 같은 글로 읽히지 않습니다.
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

    // MARK: - 설정

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            Text("설정")
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
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

                if user != nil {
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
                }
            }
            .appCardSurface()

            // 전에는 이 설명이 누를 수 있는 설정 행처럼 생겼습니다.
            // 누를 게 없는 정보는 목록 아래 안내 한 줄로 둡니다.
            Text("저장한 장소는 이 기기에 저장돼요. 로그인하지 않아도 그대로 남아요.")
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, VFSpace.xs)
        }
    }
}

// MARK: - 프로필 아바타

/// 커뮤니티 아바타와 같은 규칙(이름 첫 글자)을 씁니다.
/// 두 화면에서 같은 사람이 다르게 보이면 같은 사람인지 알 수 없습니다.
private struct MyProfileAvatar: View {
    let name: String
    let isGuest: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let size: CGFloat = 56

    var body: some View {
        Group {
            if isGuest {
                Image(systemName: "person.fill")
                    // Dynamic Type 제외: 고정 56pt 원 안의 기호.
                    .font(.system(size: size * 0.42, weight: .semibold))
            } else {
                Text(initial)
                    // Dynamic Type 제외: 원 지름에 비례하는 글자. 원이 안 커지므로 글자도 안 커진다.
                    .font(.system(size: size * 0.42, weight: .semibold))
            }
        }
        .foregroundStyle(inkColor)
        .frame(width: size, height: size)
        // 카드(surface1) 위에 올라가는 요소이므로 surface2 입니다.
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

// MARK: - 버튼

/// 이 화면의 주 동작 버튼입니다. 주황 채움 캡슐 52pt.
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

/// 빈 상태 안의 보조 버튼입니다. 회색 캡슐, 보이는 높이 36pt · 터치 44pt.
/// 새 사용자는 빈 섹션이 여러 개일 수 있어 주황을 쓰지 않습니다.
private struct MySecondaryButton: View {
    let title: String
    let action: () -> Void

    private let visibleHeight: CGFloat = 36

    var body: some View {
        Button(action: action) {
            Text(title)
                .vfText(.callout.weight(.semibold))
                .foregroundStyle(AppColors.primary)
                .lineLimit(1)
                .padding(.horizontal, VFSpace.md + 2)
                .frame(minHeight: visibleHeight)
                .background(AppColors.mutedSurface, in: Capsule())
                .padding(.vertical, (AppLayout.touchTarget - visibleHeight) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - 빈 상태

/// 섹션 안의 빈 상태 한 줄입니다. 무엇이 없는지 + 바로 할 수 있는 일 하나.
private struct MyInlineEmptyState: View {
    let symbolName: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: VFSpace.md) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(message)
                .vfText(.subhead)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: VFSpace.sm)

            MySecondaryButton(title: actionTitle, action: action)
        }
        .padding(.leading, MyListRowMetrics.horizontalPadding)
        .padding(.trailing, VFSpace.sm + 2)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .appCardSurface()
    }
}

// MARK: - 섹션 제목

/// 22pt 제목 + 개수 + (항목이 더 있을 때만) "전체 보기".
/// 부제는 쓰지 않습니다.
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
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.sm - 1) {
            Text(title)
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)
                .accessibilityAddTraits(.isHeader)

            // 0 은 빈 상태 문구가 이미 말하므로 숫자를 따로 적지 않습니다.
            if count > 0 {
                Text("\(count)")
                    .vfText(.mono)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: VFSpace.sm)

            if let destination {
                NavigationLink {
                    destination()
                } label: {
                    HStack(spacing: 2) {
                        Text("전체 보기")
                            .vfText(.callout)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
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

/// 목록 행 왼쪽의 56pt 사진 자리. 사진이 없으면 같은 크기의 회색 판 위에 기호를 둡니다.
private struct MyRowThumbnail<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            AppColors.mutedSurface
            content()
        }
        .frame(width: MyListRowMetrics.thumbnailSize, height: MyListRowMetrics.thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
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
            MyRowThumbnail {
                if let spot {
                    PhotoSpotImageView(
                        spot: spot,
                        symbolSize: 18,
                        targetPixelWidth: VFPhotoDetail.thumbnail.pixelWidth
                    )
                } else {
                    Image(systemName: "mappin.and.ellipse")
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
    /// 전에는 모든 행이 "홈, 지도, 검색에 공개됐어요" 였습니다. 그런데 홈과 지도는
    /// 사진이 있는 장소만 보여주므로, 사진이 없는 장소는 검색에서만 찾을 수 있습니다.
    private var statusText: String? {
        guard let spot else { return nil }
        return spot.hasReliableDisplayImage
            ? "홈 · 지도 · 검색에 보여요"
            : "사진이 없어 아직 검색에만 보여요"
    }
}

/// 내 글 한 줄. 누르면 글 상세로 이동합니다.
///
/// 전에는 커뮤니티 피드의 전체 폭 사진 카드를 그대로 써서 2개로 화면을 채웠습니다.
/// 마이 탭은 내 글을 "다시 찾는" 곳이라 목록 한 줄이면 충분합니다.
private struct MyPostRow: View {
    let post: CommunityPost

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

    var body: some View {
        HStack(spacing: VFSpace.md) {
            MyRowThumbnail {
                if let attachment = post.publicPhotoAttachments.first {
                    MyPostThumbnailImage(attachment: attachment)
                } else {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
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

                    VFMetaLine(items: [
                        post.relatedSpotName ?? "",
                        communityRelativeTimeText(for: post.createdAt)
                    ])
                }
            }

            Spacer(minLength: VFSpace.xs)

            MyRowChevron()
        }
        .padding(.horizontal, MyListRowMetrics.horizontalPadding)
        .padding(.vertical, VFSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MyPostThumbnailImage: View {
    let attachment: CommunityPhotoAttachment

    var body: some View {
        if let data = attachment.imageData,
           let image = CommunityPhotoDecoder.image(
            from: data,
            cacheKey: attachment.id,
            detail: .thumbnail
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
                    Color.clear
                }
            }
        } else {
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
        }
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

// MARK: - 저장한 장소 카드

/// 저장 레일과 "전체 보기" 격자가 같이 쓰는 카드입니다.
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
// MARK: - 전체 보기 화면
//
//  마이 탭의 각 섹션에서 "전체 보기" 로 들어옵니다. 마이 탭은 hub 이고 여기가 목록입니다.
//  세 화면 모두 미리보기와 같은 카드·행을 씁니다.
// ═══════════════════════════════════════════════════════════════════

struct SavedSpotsGridView: View {
    let spots: [PhotoSpot]
    let onSelect: (PhotoSpot) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: VFSpace.md),
                    GridItem(.flexible(), spacing: VFSpace.md)
                ],
                alignment: .leading,
                spacing: VFSpace.lg
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
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("저장한 장소")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MySubmissionListView: View {
    let receipts: [PlaceSubmissionReceipt]
    let spots: [PhotoSpot]
    let onSelectSpot: (PhotoSpot) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            MyGroupedList(items: receipts) { receipt in
                MyPlaceSubmissionRow(
                    receipt: receipt,
                    spot: spots.first(where: { $0.id == receipt.id }),
                    onSelectSpot: onSelectSpot
                )
            }
            .vfScreenMargin()
            .padding(.top, VFSpace.md)
            .vfScrollBottomInset()
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("내가 추가한 장소")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 행 생성을 클로저로 받습니다.
///
/// 글 상세로 가는 링크에 필요한 인자가 많습니다. 이 화면이 그것들을 다시
/// 프로퍼티로 받으면 MyTabView 의 인자 목록을 그대로 복사해야 하고,
/// 하나라도 어긋나면 미리보기와 전체 보기가 다르게 동작합니다.
/// MyTabView.postRow 를 그대로 넘겨받아 같은 행임을 보장합니다.
struct MyPostListView<Row: View>: View {
    let posts: [CommunityPost]
    let makeRow: (CommunityPost) -> Row

    var body: some View {
        ScrollView(showsIndicators: false) {
            MyGroupedList(items: posts) { post in
                makeRow(post)
            }
            .vfScreenMargin()
            .padding(.top, VFSpace.md)
            .vfScrollBottomInset()
        }
        .vfReportsTabBarScroll()
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("내 글")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════
//  마이 탭 — 프로필 + 탭 3개(저장 · 추가한 장소 · 내 글) + 바로 아래 내용
//
//  [지나온 길]
//   3차  전면 사진 · 사진 위 pill · 사진 줄 · 활동 줄이 한 화면에 → 난잡했습니다.
//   4·5차 설정 앱 같은 목록 → 줄 네 개뿐이라 화면 대부분이 비고, 사진 앱인데 사진이
//        작은 썸네일로만 보여 단조로웠습니다.
//   6차  사진 앱 "앨범" 표지 3개 → 무엇을 보든 한 번 더 들어가야 했고, 대부분 비어 있는
//        추가한 장소 · 내 글이 저장과 같은 크기라 회색 빈 칸 두 개가 보였습니다.
//
//  [지금] 인스타그램 · AllTrails 프로필처럼 열자마자 내 것이 보입니다. iOS 기본 부품만 씁니다.
//    프로필 카드  이름 + 개수 한 줄(저장 · 추가한 장소 · 내 글). 누르면 계정(이메일 · 로그아웃)
//                 게스트는 "로그인" 카드
//    탭 줄        iOS 세그먼트. 내려도 위에 붙어 있습니다. 처음엔 가장 자주 여는 저장.
//                 내린 채로 탭을 바꾸면 새 탭 내용을 처음부터 보여줍니다.
//    저장         사진 앱 "앨범" 과 같은 2열 격자(길게 눌러 저장 해제). 위에 테마 거르기 · "지도에서 보기"
//    추가한 장소  묶음 목록 (사진 · 이름 · 지역과 날짜) → 장소 상세
//                 줄 끝 "…" → 수정 · 삭제
//                 이 계정 것으로 확인되지 않는 장소(Firestore 로 옮기기 전에 추가한 곳 등)는 "목록에서 삭제" 만
//    내 글        메모 앱과 같은 묶음 목록 (제목 · 시간과 장소 · 오른쪽 사진) → 글 상세
//                 줄 끝 "…" → 수정 · 삭제
//                 "…" 은 길게 눌러도 같은 메뉴입니다. 수정 · 삭제는 내가 만든 것에만 보이고,
//                 삭제는 한 번 더 묻습니다. (앱의 다른 삭제와 같은 문구)
//                 추가 · 글쓰기 버튼은 두지 않습니다. 추가는 탭바 가운데 + 에, 글쓰기는 커뮤니티 탭에 있습니다.
//    빈 탭        ContentUnavailableView (iOS 기본 빈 화면) + 첫 행동 버튼 하나
//                 게스트의 추가한 장소 · 내 글 탭은 "로그인이 필요해요" + 로그인
//    오른쪽 위 톱니바퀴 → 설정(화면 모드 · 사진 취향 · 버전)
//
//  [List 대신 묶음 목록을 직접 그리는 이유]
//  프로필 · 탭 줄 · 내용이 스크롤 하나입니다. List 는 따로 스크롤해서 그 안에 넣을 수 없어서,
//  설정 앱 목록과 같은 모양(한 단계 올라온 둥근 표면 · 구분선)을 MyRowGroup 으로 그립니다.
//
//  [설정을 따로 두는 이유]
//  첫 화면에는 "내 것" 만 둡니다. 화면 모드와 사진 취향은 앱 전체에 걸리는 설정입니다.
//  로그인하지 않아도 바꿀 수 있어야 해서 계정 화면 안이 아니라 톱니바퀴로 엽니다.
//
//  글자는 시스템 글자 스타일, 색은 시스템 색(묶음 배경 · 회색 글자)을 그대로 씁니다.
//  주황은 앱의 tint 로, 톱니바퀴 · "지도에서 보기" · 설정 목록 아이콘 · 게스트의 "로그인" 에만 나옵니다.
// ═══════════════════════════════════════════════════════════════════

/// 마이 첫 화면의 탭 셋. 이름은 탭 줄과 프로필 카드의 개수 줄에 같이 씁니다.
private enum MySection: String, CaseIterable, Identifiable {
    case saved
    case places
    case posts

    var id: Self { self }

    var title: String {
        switch self {
        case .saved:
            return "저장"
        case .places:
            return "추가한 장소"
        case .posts:
            return "내 글"
        }
    }
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
    /// 저장 탭에서 길게 눌러 저장을 해제합니다.
    let onToggleSave: (PhotoSpot) -> Void
    let onEditPost: (CommunityPost) -> Void
    let onDeletePost: (CommunityPost) async throws -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool
    let onRequestSignIn: () -> Void
    let onExploreSpots: () -> Void
    /// 저장한 장소를 지도 탭에서 봅니다. (저장 모드 + 저장 목록)
    let onShowSavedOnMap: () -> Void
    /// 추가한 장소 "…" → 수정. 장소 상세를 열고 그 위에 장소 편집기를 올립니다.
    let onEditPlace: (PhotoSpot) -> Void
    /// 추가한 장소 "…" → 삭제. 한 번 더 묻는 것은 목록 화면이 합니다.
    let onDeletePlace: (PhotoSpot) async throws -> Void
    /// 추가한 장소 "…" → 목록에서 삭제. 이 계정 것으로 확인되지 않은 장소를 이 기기의 목록에서만 뺍니다.
    let onRemovePlaceFromList: (String) -> Void
    /// 빈 추가한 장소 탭에서 바로 장소 추가로 갑니다.
    let onAddPlace: () -> Void
    /// 빈 내 글 탭에서 바로 글쓰기로 갑니다.
    let onCompose: () -> Void
    let onResetTaste: () -> Void
    let onSignOut: () -> Void

    @State private var isSettingsPresented = false
    /// 지금 고른 탭. 처음엔 가장 자주 여는 저장입니다.
    @State private var selectedSection: MySection = .saved
    /// 저장 탭의 테마 거르기. 다른 탭에 다녀와도 그대로 둡니다.
    @State private var savedThemeFilter: SpotTheme? = nil
    /// 지금 열린 글 상세.
    @State private var openedPost: MyOpenedPost? = nil
    /// 프로필 카드가 화면에 보이는지. 탭을 바꿀 때 새 내용을 처음부터 보여줄지 정합니다.
    @State private var isProfileCardVisible = true

    private var myPosts: [CommunityPost] {
        guard let user else { return [] }
        return posts
            .filter { $0.authorID == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 프로필 카드 이름 아래 한 줄. "저장 12 · 추가한 장소 3 · 내 글 5"
    private var countSummary: String {
        [
            "\(MySection.saved.title) \(savedSpots.count)",
            "\(MySection.places.title) \(submissionReceipts.count)",
            "\(MySection.posts.title) \(myPosts.count)"
        ]
        .joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // 탭 줄(Section header)이 내려도 위에 붙어 있습니다.
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        profileCard
                            .padding(.horizontal)
                            .padding(.top, VFSpace.sm)
                            .padding(.bottom, VFSpace.md)
                            .onAppear { isProfileCardVisible = true }
                            .onDisappear { isProfileCardVisible = false }

                        // 탭을 바꿀 때 이 자리까지 올려서, 새 내용이 탭 줄 바로 아래부터 보이게 합니다.
                        Color.clear
                            .frame(height: 0)
                            .id(MyScreenMetrics.sectionTopID)

                        Section {
                            sectionContent
                                .padding(.top, VFSpace.sm)
                                .padding(.bottom, VFSpace.xl)
                        } header: {
                            sectionPicker
                        }
                    }
                }
                // 설정 앱과 같은 묶음 배경입니다. 프로필 카드 · 목록이 한 단계 올라온 표면으로 읽힙니다.
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                // iOS 26: 내리면 탭바가 숨고, 위로 조금만 올려도 다시 보입니다.
                .vfReportsTabBarScroll()
                .onChange(of: selectedSection) { _, _ in
                    // 프로필이 보이면 그대로 둡니다. 내려서 탭 줄이 위에 붙어 있을 때만 새 탭을 처음부터
                    // 보여줍니다. 그대로 두면 다른 탭 내용의 중간이나 끝이 보입니다.
                    guard !isProfileCardVisible else { return }
                    proxy.scrollTo(MyScreenMetrics.sectionTopID, anchor: .top)
                }
            }
            .navigationTitle("마이")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("설정")
                }
            }
            // 화면 안쪽(느리게 그리는 LazyVStack)이 아니라 스크롤 화면 바깥에 붙입니다.
            // 안쪽에 두면 동작하지 않을 수 있습니다.
            .navigationDestination(isPresented: $isSettingsPresented) {
                MySettingsView(onResetTaste: onResetTaste)
            }
            .navigationDestination(item: $openedPost) { opened in
                // 목록에 있는 최신 글로 엽니다. 지워져 목록에서 빠지는 중이면 열 때의 글을 씁니다.
                postDetail(myPosts.first(where: { $0.id == opened.id }) ?? opened.post)
            }
            .onAppear {
                onTabBarVisibilityChange(false)
            }
        }
    }

    // MARK: - 프로필

    @ViewBuilder
    private var profileCard: some View {
        if let user {
            NavigationLink {
                MyAccountView(user: user, onSignOut: onSignOut)
            } label: {
                MyProfileCard {
                    MyProfileLabel(user: user, summary: countSummary)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onRequestSignIn) {
                MyProfileCard {
                    MyGuestLabel()
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("로그인 화면을 엽니다")
        }
    }

    // MARK: - 탭

    /// 탭 줄. iOS 기본 세그먼트입니다.
    /// 내려도 위에 붙어 있어서, 붙어 있을 때 아래 내용이 비치지 않게 화면과 같은 배경을 깝니다.
    private var sectionPicker: some View {
        Picker("보기", selection: $selectedSection) {
            ForEach(MySection.allCases) { section in
                Text(section.title)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, VFSpace.sm)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    /// 고른 탭의 내용. 전에 따로 들어가던 세 화면을 이 자리로 옮겼습니다.
    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .saved:
            // 저장은 기기에 남아서 로그인하지 않아도 보입니다.
            MySavedSection(
                spots: savedSpots,
                selectedTheme: $savedThemeFilter,
                onSelect: onSelectSpot,
                onUnsave: unsave,
                onExplore: onExploreSpots,
                onShowOnMap: onShowSavedOnMap
            )
        case .places:
            if let user {
                MyPlacesSection(
                    receipts: submissionReceipts,
                    spots: spots,
                    currentUserID: user.id,
                    onSelectSpot: onSelectSpot,
                    onEdit: onEditPlace,
                    onDelete: onDeletePlace,
                    onRemoveFromList: onRemovePlaceFromList,
                    onAddPlace: onAddPlace
                )
            } else {
                // 게스트에게도 무엇이 있는지 보여주고 로그인으로 보냅니다.
                MySignInPrompt(
                    symbolName: "mappin.and.ellipse",
                    message: "로그인하면 직접 추가한 장소를 여기서 보고 고칠 수 있어요.",
                    onSignIn: onRequestSignIn
                )
            }
        case .posts:
            if user != nil {
                MyPostsSection(
                    posts: myPosts,
                    onOpen: { openedPost = MyOpenedPost(post: $0) },
                    onEdit: onEditPost,
                    onDelete: onDeletePost,
                    onCompose: onCompose
                )
            } else {
                MySignInPrompt(
                    symbolName: "text.bubble",
                    message: "로그인하면 남긴 글을 여기서 모아 보고 고칠 수 있어요.",
                    onSignIn: onRequestSignIn
                )
            }
        }
    }

    // MARK: - 저장 해제

    /// 길게 눌러 저장 해제. 다른 화면의 저장 버튼(VFSaveButton)과 같은 촉감이고,
    /// 빠진 자리를 나머지 사진이 채우는 움직임이 보이게 합니다.
    private func unsave(_ spot: PhotoSpot) {
        VFHaptics.save()
        withAnimation(VFMotion.standard) {
            onToggleSave(spot)
        }
    }

    // MARK: - 내 글

    /// 글 상세. 내 글 탭에서 줄을 누르면 이 화면이 밀려 들어옵니다.
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

// MARK: - 목록 행

private enum MyListMetrics {
    /// 설정 목록 아이콘 칸의 폭. 기호마다 폭이 달라도 제목이 한 줄로 맞게 합니다.
    static let iconWidth: CGFloat = 28
    /// 프로필 행 아바타. 설정 앱 맨 위 계정 행과 비슷한 크기입니다.
    static let profileAvatarSize: CGFloat = 60
    /// 계정 화면 가운데 아바타.
    static let accountAvatarSize: CGFloat = 84
    /// 목록 줄의 작은 사진. (추가한 장소 줄)
    static let thumbnailSize: CGFloat = 56
    /// 줄 끝 "…" 을 줄 오른쪽 여백 쪽으로 당기는 양.
    /// 누르는 칸(44pt)은 그대로 두고, 점 세 개의 오른쪽 끝이 다른 목록의 › 자리에 오게 합니다.
    static let rowMenuTrailingOutset: CGFloat = 14
    /// 지우는 중인 줄의 투명도.
    static let deletingOpacity: Double = 0.4
}

/// 설정 목록 한 줄: 주황 아이콘 + 제목. 메일 · 메모 앱의 폴더 목록과 같은 모양입니다.
private struct MyRowLabel: View {
    let title: String
    let symbolName: String

    var body: some View {
        Label {
            // 버튼 행은 기본으로 글자까지 tint(주황)가 칠해지므로 본문 색을 직접 정합니다.
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(AppColors.accent)
                .frame(width: MyListMetrics.iconWidth)
        }
    }
}

/// 목록 줄 끝의 "…". 커뮤니티 카드의 더보기 버튼과 같은 모양입니다.
/// 같은 항목을 줄의 길게 누르기 메뉴(contextMenu)에도 넣습니다.
private struct MyRowMenu<Items: View>: View {
    let accessibilityLabel: String
    /// 지우는 중에는 "…" 대신 도는 표시를 둡니다.
    var isBusy: Bool = false
    @ViewBuilder let items: () -> Items

    var body: some View {
        Group {
            if isBusy {
                ProgressView()
                    .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                    .accessibilityLabel("삭제하는 중")
            } else {
                Menu {
                    items()
                } label: {
                    Image(systemName: "ellipsis")
                        // Dynamic Type 제외: 고정 44pt 누름 칸 안의 기호. (커뮤니티 카드 "…" 와 같은 크기)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                // 목록 줄 안에서 이 칸만 따로 눌리게 합니다. "…" 을 눌렀을 때 줄(상세 열기)이 같이 눌리지 않습니다.
                .buttonStyle(.borderless)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .padding(.trailing, -MyListMetrics.rowMenuTrailingOutset)
    }
}

// MARK: - 묶음 목록

/// 마이 첫 화면의 간격 · 모양.
private enum MyScreenMetrics {
    /// 프로필 카드 · 묶음 목록의 모서리. 저장 탭 사진 칸과 같습니다.
    static let cornerRadius: CGFloat = VFRadius.inner
    /// 묶음 목록 한 줄의 안쪽 여백.
    static let rowHorizontalPadding: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 10
    /// 구분선이 시작하는 곳(묶음 왼쪽 끝에서). 글자가 시작하는 곳에 맞춥니다.
    /// 추가한 장소: 여백 + 사진 + 사진과 글자 사이(12)
    static let placeSeparatorLeading: CGFloat = rowHorizontalPadding + MyListMetrics.thumbnailSize + 12
    /// 내 글: 글자가 여백 바로 뒤에서 시작합니다.
    static let postSeparatorLeading: CGFloat = rowHorizontalPadding
    /// 저장 탭 2열 격자 간격.
    static let gridColumnSpacing: CGFloat = 16
    static let gridRowSpacing: CGFloat = 20
    /// 탭을 바꿀 때 올려 보내는 자리(탭 줄 바로 위)의 이름.
    static let sectionTopID = "my-section-top"
}

/// 설정 앱 목록과 같은 모양의 묶음: 한 단계 올라온 둥근 표면 + 줄 사이 구분선.
/// 줄의 여백 · 배경은 각 줄이 myGroupedRow() 로 붙입니다. 길게 누를 때 떠오르는 모양을 줄마다 맞추기 위해서입니다.
private struct MyRowGroup<Item: Identifiable, Row: View>: View {
    let items: [Item]
    /// 구분선이 시작하는 곳(묶음 왼쪽 끝에서).
    let separatorLeading: CGFloat
    @ViewBuilder let row: (Item) -> Row

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MyScreenMetrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, separatorLeading)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        .clipShape(shape)
    }
}

private extension View {
    /// 묶음 목록 한 줄: 안쪽 여백 + 줄 배경. 길게 누를 때 떠오르는 모양도 줄 전체(둥근 모서리)로 맞춥니다.
    func myGroupedRow() -> some View {
        padding(.horizontal, MyScreenMetrics.rowHorizontalPadding)
            .padding(.vertical, MyScreenMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .contentShape(
                .contextMenuPreview,
                RoundedRectangle(cornerRadius: MyScreenMetrics.cornerRadius, style: .continuous)
            )
    }
}

/// 게스트가 추가한 장소 · 내 글 탭을 골랐을 때. 무엇이 있는지 보여주고 로그인으로 보냅니다.
private struct MySignInPrompt: View {
    let symbolName: String
    let message: String
    let onSignIn: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("로그인이 필요해요", systemImage: symbolName)
        } description: {
            Text(message)
        } actions: {
            Button("로그인", action: onSignIn)
        }
    }
}

/// "지도에서 보기". 저장 탭 위 도구 줄 오른쪽에 놓입니다.
private struct MyShowOnMapButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("지도에서 보기", systemImage: "map")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.accent)
                .frame(minHeight: AppLayout.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("지도 탭에서 저장한 장소만 모아 봅니다")
    }
}

/// 프로필 카드. 설정 앱 맨 위 계정 칸처럼 한 단계 올라온 표면 위에 둡니다.
private struct MyProfileCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: VFSpace.md) {
            content()

            Spacer(minLength: VFSpace.sm)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: MyScreenMetrics.cornerRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: MyScreenMetrics.cornerRadius, style: .continuous))
    }
}

/// 설정 앱 맨 위 계정 행과 같은 모양입니다. 이름 아래에는 이메일 대신 내 것의 개수를 둡니다.
/// 누르면 계정 화면(이메일 · 로그인 방식 · 로그아웃)이 열립니다.
private struct MyProfileLabel: View {
    let user: AuthUser
    /// "저장 12 · 추가한 장소 3 · 내 글 5"
    let summary: String

    var body: some View {
        HStack(spacing: 14) {
            MyAvatar(name: user.displayName, size: MyListMetrics.profileAvatarSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    // 큰 글자에서는 두 줄까지 내려 씁니다.
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// 설정 앱의 "iPhone에 로그인" 행과 같은 모양입니다.
private struct MyGuestLabel: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .scaledToFit()
                .foregroundStyle(Color(uiColor: .systemGray))
                .frame(width: MyListMetrics.profileAvatarSize, height: MyListMetrics.profileAvatarSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("로그인")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.accent)

                Text("장소를 추가하고 현장 글을 남길 수 있어요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private enum MyAccountText {
    /// "Apple" · "Google". 알 수 없는 로그인 방식이면 nil.
    static func providerTitle(for user: AuthUser) -> String? {
        AuthProviderKind(rawValue: user.provider)?.title
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
            .font(.system(size: size * 0.42, weight: .semibold))
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

/// 목록 행의 작은 사진 칸.
private struct MyRowThumbnail<Content: View>: View {
    var size: CGFloat = MyListMetrics.thumbnailSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 사진이 없을 때의 칸. 시스템 채움 색 위 기호 하나.
private struct MyThumbnailPlaceholder: View {
    let symbolName: String
    var symbolSize: CGFloat = 18

    var body: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)

            Image(systemName: symbolName)
                // Dynamic Type 제외: 고정 크기 칸 안의 기호.
                .font(.system(size: symbolSize, weight: .regular))
                .foregroundStyle(.secondary)
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
                    Color(uiColor: .tertiarySystemFill)
                }
            }
        } else {
            Color(uiColor: .tertiarySystemFill)
        }
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

/// 추가한 장소 한 줄의 "…" 메뉴.
///
/// 수정 · 삭제는 이 계정이 만든 것으로 확인된 장소(PhotoSpot.isOwned)만 됩니다. 서버 규칙도 같습니다.
/// Firestore 로 옮기기 전(defd620)에 추가한 장소는 만든 사람 정보 없이 옮겨져서
/// (scripts/migrate-places-to-firestore.mjs) 누구도 고치거나 지울 수 없습니다.
/// 그런 줄 · 다른 계정으로 추가한 줄 · 장소를 찾을 수 없는 줄에는 "목록에서 삭제" 만 둡니다.
/// 추가한 장소 기록은 이 기기에만 있어서, 목록에서 빼도 공개된 장소는 그대로입니다.
private enum MyPlaceMenuKind: Equatable {
    /// 수정 · 삭제
    case manage
    /// 목록에서 삭제 (이 기기의 기록만 지웁니다)
    case removeFromList
    /// 메뉴 없음. 장소 목록을 아직 불러오는 중이라 어느 쪽인지 모릅니다.
    case hidden

    static func kind(hasSpot: Bool, isOwned: Bool, isPlaceListLoaded: Bool) -> MyPlaceMenuKind {
        if hasSpot {
            return isOwned ? .manage : .removeFromList
        }
        return isPlaceListLoaded ? .removeFromList : .hidden
    }
}

/// 내가 추가한 장소 한 줄. 누르면 장소 상세가 열립니다.
/// 줄 끝 "…" (길게 눌러도 같은 메뉴): 내 장소는 수정 · 삭제, 확인되지 않은 장소는 목록에서 삭제.
private struct MyPlaceRow: View {
    let receipt: PlaceSubmissionReceipt
    /// 지금 불러온 장소 목록에서 찾은 장소. 못 찾았으면 nil 이고, 그때는 누를 수 없는 행으로 둡니다.
    let spot: PhotoSpot?
    /// 이 계정이 만든 장소로 확인됐는지. 수정 · 삭제는 이때만 됩니다.
    let isOwned: Bool
    /// 장소 목록을 불러왔는지. 불러오는 중에 못 찾은 줄에는 "…" 을 두지 않습니다.
    let isPlaceListLoaded: Bool
    let isDeleting: Bool
    let onSelectSpot: (PhotoSpot) -> Void
    let onEdit: (PhotoSpot) -> Void
    /// 바로 지우지 않습니다. 목록 화면이 한 번 더 묻습니다. (목록에서 삭제도 같습니다)
    let onDelete: (PhotoSpot) -> Void
    let onRemoveFromList: () -> Void

    /// 추가한 뒤 이름을 고쳤으면 고친 이름을 보여줍니다. 기록(receipt)에는 추가할 때 이름이 남아 있습니다.
    private var name: String {
        spot?.name ?? receipt.name
    }

    private var menuKind: MyPlaceMenuKind {
        .kind(hasSpot: spot != nil, isOwned: isOwned, isPlaceListLoaded: isPlaceListLoaded)
    }

    var body: some View {
        // 빈 메뉴가 길게 누를 때 떠오르지 않게, 메뉴가 없는 줄에는 길게 누르기 메뉴를 아예 붙이지 않습니다.
        if menuKind == .hidden {
            row
                .myGroupedRow()
        } else {
            row
                .myGroupedRow()
                .contextMenu {
                    menuItems
                }
        }
    }

    private var row: some View {
        HStack(spacing: 0) {
            main
                .opacity(isDeleting ? MyListMetrics.deletingOpacity : 1)

            if menuKind != .hidden {
                MyRowMenu(accessibilityLabel: "장소 메뉴", isBusy: isDeleting) {
                    menuItems
                }
            }
        }
        .disabled(isDeleting)
    }

    /// 줄 본문. 장소를 찾았으면 누르면 상세가 열리는 버튼입니다.
    @ViewBuilder
    private var main: some View {
        if let spot {
            // 줄 본문과 "…" 을 따로 눌리는 버튼으로 둡니다. 한 버튼 안에 넣으면 "…" 을 눌러도 상세가 열립니다.
            // 상세는 밀어 넣는 화면이 아니라 시트라서 오른쪽 화살표(›)를 두지 않습니다.
            Button {
                onSelectSpot(spot)
            } label: {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("장소 상세를 엽니다")
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "…" 과 길게 누르기 메뉴에 같이 들어갑니다.
    /// 지도에서 보기는 넣지 않습니다. 장소 상세 아래 "지도에서 보기" 가 같은 일을 합니다.
    @ViewBuilder
    private var menuItems: some View {
        switch menuKind {
        case .manage:
            if let spot {
                Button {
                    onEdit(spot)
                } label: {
                    Label("수정", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete(spot)
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        case .removeFromList:
            Button(role: .destructive, action: onRemoveFromList) {
                Label("목록에서 삭제", systemImage: "trash")
            }
        case .hidden:
            EmptyView()
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            MyRowThumbnail {
                if let spot, spot.hasReliableDisplayImage {
                    PhotoSpotImageView(
                        spot: spot,
                        symbolSize: 16,
                        targetPixelWidth: VFPhotoDetail.thumbnail.pixelWidth
                    )
                } else {
                    MyThumbnailPlaceholder(symbolName: "photo")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !detailText.isEmpty {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // 홈과 지도는 사진이 있는 장소만 보여줍니다. 사진이 없는 곳만 그 사실을 알립니다.
                if let spot, !spot.hasReliableDisplayImage {
                    Text("사진이 없어 아직 검색에만 보여요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// 지역 · 추가한 날.
    private var detailText: String {
        [regionText, MyDateText.day(fromISO8601: receipt.submittedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
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
}

/// 내 글 한 줄. 메모 앱 목록과 같은 모양입니다. (제목 / 시간 · 장소 / 오른쪽에 첫 사진)
private struct MyPostRow: View {
    let post: CommunityPost

    private var photo: CommunityPhotoAttachment? {
        post.publicPhotoAttachments.first
    }

    private var trimmedTitle: String? {
        guard let title = post.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    /// 본문을 줄 단위로. 빈 줄은 뺍니다.
    private var messageLines: [String] {
        post.message
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 제목이 없으면 본문 첫 줄을 제목처럼 씁니다.
    private var headline: String {
        if let trimmedTitle {
            return trimmedTitle
        }
        if let firstLine = messageLines.first {
            return firstLine
        }
        return post.hasPhotos ? "사진" : "글"
    }

    /// 시간 · 장소. 장소가 없는 글은 장소 대신 본문 미리보기를 붙입니다.
    private var detailText: String {
        var parts = [communityRelativeTimeText(for: post.createdAt)]

        if let spotName = post.relatedSpotName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !spotName.isEmpty {
            parts.append(spotName)
        } else {
            // 제목을 본문 첫 줄에서 가져왔으면 그 다음 줄부터 씁니다.
            let lines = trimmedTitle == nil ? Array(messageLines.dropFirst()) : messageLines
            let preview = lines.joined(separator: " ")
            if !preview.isEmpty {
                parts.append(preview)
            }
        }

        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let photo {
                MyRowThumbnail(size: 52) {
                    MyAttachmentImage(attachment: photo)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 탭 내용
// ═══════════════════════════════════════════════════════════════════

/// 저장 탭. 사진 앱 "앨범" 과 같은 2열 격자이고, 위에 테마 거르기 · "지도에서 보기" 를 둡니다.
private struct MySavedSection: View {
    let spots: [PhotoSpot]
    /// 다른 탭에 다녀와도 그대로 두려고 바깥(MyTabView)에서 받습니다.
    @Binding var selectedTheme: SpotTheme?
    let onSelect: (PhotoSpot) -> Void
    let onUnsave: (PhotoSpot) -> Void
    let onExplore: () -> Void
    /// 지도 탭에서 저장한 장소만 모아 봅니다.
    let onShowOnMap: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: MyScreenMetrics.gridColumnSpacing),
        GridItem(.flexible(), spacing: MyScreenMetrics.gridColumnSpacing)
    ]

    /// 저장한 장소에 실제로 있는 테마만, SpotTheme 순서대로.
    private var themes: [SpotTheme] {
        SpotTheme.allCases.filter { theme in
            spots.contains { $0.theme == theme }
        }
    }

    /// 고른 테마의 장소를 모두 저장 해제하면 "모든 테마" 로 돌아갑니다.
    private var activeTheme: SpotTheme? {
        guard let selectedTheme, themes.contains(selectedTheme) else { return nil }
        return selectedTheme
    }

    private var visibleSpots: [PhotoSpot] {
        guard let activeTheme else { return spots }
        return spots.filter { $0.theme == activeTheme }
    }

    var body: some View {
        Group {
            if spots.isEmpty {
                ContentUnavailableView {
                    Label("저장한 출사지가 아직 없어요", systemImage: "bookmark")
                } description: {
                    Text("홈이나 지도에서 마음에 드는 곳을 저장하면 여기에 모여요.")
                } actions: {
                    Button("출사지 둘러보기", action: onExplore)
                }
            } else {
                VStack(alignment: .leading, spacing: VFSpace.xs) {
                    toolRow

                    LazyVGrid(columns: columns, alignment: .leading, spacing: MyScreenMetrics.gridRowSpacing) {
                        ForEach(visibleSpots) { spot in
                            MySavedSpotTile(
                                spot: spot,
                                onSelect: { onSelect(spot) },
                                onUnsave: { onUnsave(spot) }
                            )
                        }
                    }
                    .animation(VFMotion.quick, value: activeTheme)
                }
                .padding(.horizontal)
            }
        }
        .onChange(of: themes) { _, newThemes in
            if let selectedTheme, !newThemes.contains(selectedTheme) {
                self.selectedTheme = nil
            }
        }
    }

    /// 테마 거르기(왼쪽) · "지도에서 보기"(오른쪽). 큰 글자에서 한 줄에 안 들어가면 두 줄로 둡니다.
    private var toolRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VFSpace.sm) {
                themeMenu
                Spacer(minLength: VFSpace.sm)
                MyShowOnMapButton(action: onShowOnMap)
            }

            VStack(alignment: .leading, spacing: 0) {
                themeMenu
                MyShowOnMapButton(action: onShowOnMap)
            }
        }
    }

    /// 지금 보고 있는 테마를 글자로 보여주는 메뉴입니다. 테마가 하나뿐이면 거를 게 없으므로 두지 않습니다.
    @ViewBuilder
    private var themeMenu: some View {
        if themes.count >= 2 {
            Menu {
                Picker("테마", selection: $selectedTheme) {
                    Text("모든 테마")
                        .tag(SpotTheme?.none)

                    ForEach(themes) { theme in
                        Text(theme.title)
                            .tag(SpotTheme?.some(theme))
                    }
                }
            } label: {
                HStack(spacing: VFSpace.xs) {
                    Text(activeTheme?.title ?? "모든 테마")
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: AppLayout.touchTarget)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("테마로 거르기")
            .accessibilityValue(activeTheme?.title ?? "모든 테마")
        }
    }
}

/// 사진 앱 앨범 칸과 같은 모양: 정사각 사진 + 아래 이름 · 지역.
private struct MySavedSpotTile: View {
    let spot: PhotoSpot
    let onSelect: () -> Void
    let onUnsave: () -> Void

    private var region: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                VFPhotoTile(
                    spot: spot,
                    aspectRatio: 1,
                    cornerRadius: VFRadius.inner,
                    imageDetail: .card
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(spot.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(region)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 길게 눌렀을 때 떠오르는 미리보기의 모서리를 사진과 맞춥니다.
        .contentShape(
            .contextMenuPreview,
            RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
        )
        .contextMenu {
            Button(role: .destructive, action: onUnsave) {
                Label("저장 해제", systemImage: "bookmark.slash")
            }
        }
        .accessibilityLabel("\(spot.name), \(region)")
        .accessibilityAction(named: "저장 해제", onUnsave)
    }
}

/// 추가한 장소 탭. 설정 앱 목록과 같은 묶음 목록입니다.
private struct MyPlacesSection: View {
    let receipts: [PlaceSubmissionReceipt]
    let spots: [PhotoSpot]
    /// 수정 · 삭제를 내가 만든 장소에만 보이려고 받습니다.
    let currentUserID: String
    let onSelectSpot: (PhotoSpot) -> Void
    let onEdit: (PhotoSpot) -> Void
    let onDelete: (PhotoSpot) async throws -> Void
    /// "목록에서 삭제". 이 기기의 추가한 장소 기록만 지웁니다. (receipt id)
    let onRemoveFromList: (String) -> Void
    /// 비어 있을 때 가운데 "장소 추가" 버튼.
    let onAddPlace: () -> Void

    /// "삭제" 를 누른 장소. 한 번 더 물은 뒤 지웁니다.
    @State private var pendingDeleteSpot: PhotoSpot?
    /// "목록에서 삭제" 를 누른 줄. 한 번 더 물은 뒤 뺍니다.
    @State private var pendingListRemoval: PlaceSubmissionReceipt?
    /// 지우는 중인 장소. 그 줄은 흐리게 두고 누를 수 없게 합니다.
    @State private var deletingSpotIDs: Set<String> = []
    @State private var deleteError: String?

    var body: some View {
        Group {
            if receipts.isEmpty {
                // 추가 버튼은 비어 있을 때만 둡니다. 평소에는 탭바 가운데 + 가 같은 장소 추가입니다.
                ContentUnavailableView {
                    Label("직접 추가한 장소가 아직 없어요", systemImage: "mappin.and.ellipse")
                } description: {
                    Text("나만 아는 출사지를 알려주세요. 다른 사진가의 다음 출사지가 돼요.")
                } actions: {
                    Button("장소 추가", action: onAddPlace)
                }
            } else {
                MyRowGroup(items: receipts, separatorLeading: MyScreenMetrics.placeSeparatorLeading) { receipt in
                    let spot = spots.first(where: { $0.id == receipt.id })
                    MyPlaceRow(
                        receipt: receipt,
                        spot: spot,
                        isOwned: spot?.isOwned(by: currentUserID) ?? false,
                        // 장소를 하나도 못 불러왔으면 아직 불러오는 중입니다.
                        isPlaceListLoaded: !spots.isEmpty,
                        isDeleting: deletingSpotIDs.contains(receipt.id),
                        onSelectSpot: onSelectSpot,
                        onEdit: onEdit,
                        onDelete: { pendingDeleteSpot = $0 },
                        onRemoveFromList: { pendingListRemoval = receipt }
                    )
                }
                .padding(.horizontal)
            }
        }
        // 장소 상세의 "장소 삭제" 와 같은 문구 · 같은 모양입니다.
        .confirmationDialog(
            "장소를 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeleteSpot != nil },
                set: { if !$0 { pendingDeleteSpot = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteSpot
        ) { spot in
            Button("장소 삭제", role: .destructive) {
                delete(spot)
            }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("장소를 공개 목록에서 숨깁니다. 게시물과 기존 사진은 삭제되지 않아요.")
        }
        // 공개된 장소는 건드리지 않고 이 기기의 기록만 지웁니다.
        .confirmationDialog(
            "목록에서 삭제할까요?",
            isPresented: Binding(
                get: { pendingListRemoval != nil },
                set: { if !$0 { pendingListRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingListRemoval
        ) { receipt in
            Button("목록에서 삭제", role: .destructive) {
                withAnimation(VFMotion.standard) {
                    onRemoveFromList(receipt.id)
                }
            }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("추가한 장소 목록에서만 빠져요. 이 계정으로 만든 장소로 확인되지 않아서, 공개된 장소는 그대로 둬요.")
        }
        .alert("장소를 삭제하지 못했어요", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("확인", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "다시 시도해 주세요.")
        }
    }

    /// 지워지면 추가한 장소 기록에서도 빠져서 줄이 사라집니다.
    private func delete(_ spot: PhotoSpot) {
        guard !deletingSpotIDs.contains(spot.id) else { return }
        deletingSpotIDs.insert(spot.id)
        Task {
            defer { deletingSpotIDs.remove(spot.id) }
            do {
                try await onDelete(spot)
            } catch {
                // "권한이 없어요" 처럼 이유를 아는 경우는 그 문구를, 아니면 다시 해 보라고 알립니다.
                deleteError = (error as? PlacesRepositoryError)?.errorDescription
                    ?? "삭제하지 못했어요. 다시 시도해 주세요."
            }
        }
    }
}

/// 내 글 탭. 누르면 글 상세, 줄 끝 "…" 이나 길게 누르면 수정 · 삭제입니다.
///
/// 글 상세로 가는 길(navigationDestination)은 MyTabView 가 스크롤 화면 바깥에 붙여 둡니다.
/// 이 탭은 느리게 그리는 LazyVStack 안에 있어서, 여기에 두면 동작하지 않을 수 있습니다.
private struct MyPostsSection: View {
    let posts: [CommunityPost]
    /// 글 상세 열기.
    let onOpen: (CommunityPost) -> Void
    /// 글쓰기 화면을 고치기로 엽니다. 글 상세 오른쪽 위 "…" → 수정 과 같은 길입니다.
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) async throws -> Void
    /// 비어 있을 때 가운데 "글쓰기" 버튼.
    let onCompose: () -> Void

    /// "삭제" 를 누른 글. 한 번 더 물은 뒤 지웁니다.
    @State private var pendingDeletePost: CommunityPost?
    /// 지우는 중인 글. 그 줄은 흐리게 두고 누를 수 없게 합니다.
    @State private var deletingPostIDs: Set<String> = []
    @State private var deleteError: String?

    var body: some View {
        Group {
            if posts.isEmpty {
                // 글쓰기 버튼은 비어 있을 때만 둡니다. 평소에는 커뮤니티 탭 · 장소 상세에서 씁니다.
                ContentUnavailableView {
                    Label("남긴 글이 아직 없어요", systemImage: "text.bubble")
                } description: {
                    Text("지금 현장의 분위기와 혼잡도를 남겨보세요. 다음 사람의 출사가 쉬워져요.")
                } actions: {
                    Button("글쓰기", action: onCompose)
                }
            } else {
                MyRowGroup(items: posts, separatorLeading: MyScreenMetrics.postSeparatorLeading) { post in
                    row(post)
                }
                .padding(.horizontal)
            }
        }
        // 커뮤니티 카드 · 글 상세의 삭제와 같은 문구 · 같은 모양입니다.
        .alert(
            "게시글을 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeletePost != nil },
                set: { if !$0 { pendingDeletePost = nil } }
            ),
            presenting: pendingDeletePost
        ) { post in
            Button("삭제", role: .destructive) {
                delete(post)
            }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("삭제한 게시글은 다시 복구할 수 없습니다.")
        }
        .alert("게시글을 삭제하지 못했어요", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("확인", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "다시 시도해 주세요.")
        }
    }

    /// 줄 본문과 "…" 을 따로 눌리는 버튼으로 둡니다. (MyPlaceRow 와 같은 이유)
    /// 누르면 글 상세가 밀려 들어오지만, 한 줄에 › 와 "…" 을 같이 두면 복잡해서 "…" 만 둡니다.
    private func row(_ post: CommunityPost) -> some View {
        let isDeleting = deletingPostIDs.contains(post.id)

        return HStack(spacing: 0) {
            Button {
                onOpen(post)
            } label: {
                MyPostRow(post: post)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isDeleting ? MyListMetrics.deletingOpacity : 1)
            .accessibilityHint("글 상세를 엽니다")

            MyRowMenu(accessibilityLabel: "게시글 메뉴", isBusy: isDeleting) {
                menuItems(for: post)
            }
        }
        .disabled(isDeleting)
        .myGroupedRow()
        .contextMenu {
            menuItems(for: post)
        }
    }

    /// "…" 과 길게 누르기 메뉴에 같이 들어갑니다. 이 목록에는 내 글만 있어서 늘 수정 · 삭제가 있습니다.
    @ViewBuilder
    private func menuItems(for post: CommunityPost) -> some View {
        Button {
            onEdit(post)
        } label: {
            Label("수정", systemImage: "pencil")
        }

        Button(role: .destructive) {
            pendingDeletePost = post
        } label: {
            Label("삭제", systemImage: "trash")
        }
    }

    /// 지워지면 목록에서 줄이 사라집니다.
    private func delete(_ post: CommunityPost) {
        guard !deletingPostIDs.contains(post.id) else { return }
        deletingPostIDs.insert(post.id)
        Task {
            defer { deletingPostIDs.remove(post.id) }
            do {
                try await onDelete(post)
            } catch {
                deleteError = "삭제하지 못했어요. 다시 시도해 주세요."
            }
        }
    }
}

/// 글 상세로 갈 때 쓰는 값.
/// navigationDestination(item:) 은 Hashable 값이 필요한데 CommunityPost 는 아니어서,
/// 글 id 로만 같은지 보는 작은 상자에 담습니다.
private struct MyOpenedPost: Hashable {
    let post: CommunityPost

    var id: String { post.id }

    static func == (lhs: MyOpenedPost, rhs: MyOpenedPost) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 밀어 넣는 화면 (설정 · 계정)
// ═══════════════════════════════════════════════════════════════════

/// 설정. 첫 화면 오른쪽 위 톱니바퀴로 엽니다.
///
/// 화면 모드 · 사진 취향은 앱 전체에 걸리는 설정이라 로그인과 상관없이 들어올 수 있어야 합니다.
/// 그래서 계정 화면 안이 아니라 따로 둡니다. 로그아웃은 설정 앱처럼 계정 화면에 있습니다.
private struct MySettingsView: View {
    let onResetTaste: () -> Void

    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.defaultValue.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .defaultValue
    }

    /// "1.0 (1)". 설정 앱 "정보" 의 버전 줄과 같은 모양으로 둡니다.
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                // 메뉴 Picker 는 목록에서 "제목 …… 지금 값 ⌃⌄" 한 줄로 그려지고,
                // 고른 값에 시스템 체크 표시가 붙습니다.
                Picker(selection: $appearanceRawValue) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title)
                            .tag(option.rawValue)
                    }
                } label: {
                    MyRowLabel(title: "화면 모드", symbolName: appearance.symbolName)
                }
                .pickerStyle(.menu)

                Button(action: onResetTaste) {
                    MyRowLabel(title: "사진 취향 다시 설정", symbolName: "photo.on.rectangle.angled")
                }
                .accessibilityHint("홈 추천의 출발점이 되는 사진 3장을 다시 고릅니다")
            } footer: {
                Text("고른 사진 3장이 홈 추천의 출발점이 돼요.")
            }

            Section {
                LabeledContent("버전", value: versionText)
            } footer: {
                // 첫 화면에 두던 안내입니다. 첫 화면은 "내 것" 만 두려고 설정으로 옮겼습니다.
                Text("저장한 장소는 이 기기에 저장돼요. 로그인하지 않아도 그대로 남아요.")
            }
        }
        .listStyle(.insetGrouped)
        .vfReportsTabBarScroll()
        .navigationTitle("설정")
    }
}

/// 계정. 설정 앱의 계정 화면처럼 가운데 프로필 + 맨 아래 로그아웃입니다.
private struct MyAccountView: View {
    let user: AuthUser
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    MyAvatar(name: user.displayName, size: MyListMetrics.accountAvatarSize)

                    VStack(spacing: 3) {
                        Text(user.displayName)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)

                        if let email = user.email, !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
            }

            if let providerTitle = MyAccountText.providerTitle(for: user) {
                Section {
                    LabeledContent("로그인 방식", value: providerTitle)
                }
            }

            Section {
                // 다시 로그인하면 되돌릴 수 있어서 확인 창을 띄우지 않습니다.
                Button("로그아웃", role: .destructive) {
                    dismiss()
                    onSignOut()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .vfReportsTabBarScroll()
        .navigationTitle("계정")
        .navigationBarTitleDisplayMode(.inline)
    }
}

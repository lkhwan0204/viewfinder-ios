import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════
//  마이 탭 — iOS 기본 부품 + 사진 앱 "앨범" 표지
//
//  [지나온 길]
//   3차  전면 사진 · 사진 위 pill · 사진 줄 · 활동 줄이 한 화면에 → 난잡했습니다.
//   4·5차 설정 앱 같은 목록 → 줄 네 개뿐이라 화면 대부분이 비고, 사진 앱인데 사진이
//        작은 썸네일로만 보여 단조로웠습니다.
//
//  [지금] 새로 만든 모양 없이 iOS 기본 부품과 사진 앱 "앨범" 의 모양만 씁니다.
//    첫 화면      큰 제목 + 프로필 카드 + 앨범 표지 3개
//                 표지(사진)가 곧 입구이고, 이름 · 개수는 사진 아래에 둡니다. 사진 위에는
//                 글자 · 버튼을 올리지 않습니다.
//                 저장한 장소  넓은 표지(2:1). 사진이 여러 장이면 모자이크(큰 1 + 작은 2)
//                              이름 줄 오른쪽 "지도에서 보기" → 지도 탭 저장 모드
//                 추가한 장소 · 내 글  정사각 표지 두 칸 (큰 글자에서는 한 줄에 하나씩)
//                 게스트는 두 칸이 잠긴 표지로 보이고, 누르면 로그인입니다.
//                 오른쪽 위 톱니바퀴 → 설정(화면 모드 · 사진 취향 · 버전)
//    저장한 장소  사진 앱 "앨범" 과 같은 2열 격자. 오른쪽 위 지도 · 거르기 메뉴.
//    추가한 장소  목록 (사진 · 이름 · 지역과 날짜) → 장소 상세
//                 줄 끝 "…" → 수정 · 삭제
//    내 글        메모 앱과 같은 목록 (제목 · 시간과 장소 · 오른쪽 사진) → 글 상세
//                 줄 끝 "…" → 수정 · 삭제
//                 "…" 은 길게 눌러도 같은 메뉴입니다. 수정 · 삭제는 내가 만든 것에만 보이고,
//                 삭제는 한 번 더 묻습니다. (앱의 다른 삭제와 같은 문구)
//                 두 화면 모두 오른쪽 위 추가 · 글쓰기 버튼은 두지 않습니다. 관리하는 화면이고,
//                 추가는 탭바 가운데 + 에, 글쓰기는 커뮤니티 탭에 이미 있습니다.
//    빈 상태      ContentUnavailableView (iOS 기본 빈 화면) + 첫 행동 버튼 하나
//
//  [사진을 첫 화면 아래에 따로 모아 두지 않는 이유]
//  "저장한 장소" 를 누르면 사진 격자가 나옵니다. 첫 화면에 같은 사진을 또 두면
//  같은 내용을 두 번 보여줍니다. 사진은 입구(앨범 표지)에 넣습니다.
//
//  [설정을 따로 두는 이유]
//  첫 화면에는 "내 것" 만 둡니다. 화면 모드와 사진 취향은 앱 전체에 걸리는 설정입니다.
//  로그인하지 않아도 바꿀 수 있어야 해서 계정 화면 안이 아니라 톱니바퀴로 엽니다.
//
//  글자는 시스템 글자 스타일, 색은 시스템 색(묶음 배경 · 회색 글자)을 그대로 씁니다.
//  주황은 앱의 tint 로, 톱니바퀴 · "지도에서 보기" · 설정 목록 아이콘 · 게스트의 "로그인" 에만 나옵니다.
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
    /// 저장한 장소를 지도 탭에서 봅니다. (저장 모드 + 저장 목록)
    let onShowSavedOnMap: () -> Void
    /// 추가한 장소 "…" → 수정. 장소 상세를 열고 그 위에 장소 편집기를 올립니다.
    let onEditPlace: (PhotoSpot) -> Void
    /// 추가한 장소 "…" → 삭제. 한 번 더 묻는 것은 목록 화면이 합니다.
    let onDeletePlace: (PhotoSpot) async throws -> Void
    /// 빈 "추가한 장소" 화면에서 바로 장소 추가로 갑니다.
    let onAddPlace: () -> Void
    /// 빈 "내 글" 화면에서 바로 글쓰기로 갑니다.
    let onCompose: () -> Void
    let onResetTaste: () -> Void
    let onSignOut: () -> Void

    @State private var isSettingsPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var myPosts: [CommunityPost] {
        guard let user else { return [] }
        return posts
            .filter { $0.authorID == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - 표지 사진

    /// "저장한 장소" 표지. 사진이 있는 곳 중 앞에서 세 곳입니다.
    /// (1장이면 한 장, 2장이면 반반, 3장이면 큰 1 + 작은 2)
    /// 저장 기록에 날짜가 없어서 "최근" 이라고 부르지 않습니다.
    private var savedMosaicSpots: [PhotoSpot] {
        Array(savedSpots.lazy.filter(\.hasReliableDisplayImage).prefix(3))
    }

    /// "추가한 장소" 표지. 가장 최근에 추가한 곳 중 사진이 있는 곳입니다. (receipt 는 최신순)
    private var placeCoverSpot: PhotoSpot? {
        submissionReceipts.lazy
            .compactMap { receipt in spots.first(where: { $0.id == receipt.id }) }
            .first(where: \.hasReliableDisplayImage)
    }

    /// "내 글" 표지. 가장 최근 글 중 사진이 있는 글의 첫 사진입니다.
    /// 사진 없는 글에 장소 대표 사진을 대신 쓰지 않습니다. 남이 찍은 사진이 내 글처럼 보이기 때문입니다.
    private var postCoverAttachment: CommunityPhotoAttachment? {
        myPosts.lazy
            .compactMap { $0.publicPhotoAttachments.first }
            .first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MyAlbumMetrics.sectionSpacing) {
                    profileCard
                    savedAlbum
                    activityAlbums
                }
                .padding(.horizontal)
                .padding(.top, VFSpace.sm)
                .padding(.bottom, VFSpace.xl)
            }
            // 설정 앱과 같은 묶음 배경입니다. 프로필 카드가 한 단계 올라온 표면으로 읽힙니다.
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            // iOS 26: 내리면 탭바가 숨고, 위로 조금만 올려도 다시 보입니다.
            .vfReportsTabBarScroll()
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
            // 화면 안쪽(표지 · 줄)이 아니라 스크롤 화면 자체에 붙입니다. 안쪽에 두면 동작하지 않을 수 있습니다.
            .navigationDestination(isPresented: $isSettingsPresented) {
                MySettingsView(onResetTaste: onResetTaste)
            }
            .onAppear {
                onTabBarVisibilityChange(false)
            }
        }
    }

    /// 개수. 0 이면 숫자 대신 "아직 없어요".
    private func countText(_ count: Int, unit: String) -> String {
        count == 0 ? "아직 없어요" : "\(count)\(unit)"
    }

    // MARK: - 프로필

    @ViewBuilder
    private var profileCard: some View {
        if let user {
            NavigationLink {
                MyAccountView(user: user, onSignOut: onSignOut)
            } label: {
                MyProfileCard {
                    MyProfileLabel(user: user)
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

    // MARK: - 앨범 표지
    //
    //  사진 앱 "앨범" 과 같습니다. 표지(사진)가 곧 입구이고, 이름과 개수는 사진 아래에 둡니다.
    //  사진 위에는 글자 · 버튼을 올리지 않습니다.

    /// 가장 자주 여는 곳이라 넓은 표지(2:1)입니다. 사진이 여러 장이면 모자이크로 보여줍니다.
    private var savedAlbum: some View {
        let showsMapButton = !savedSpots.isEmpty
        // 큰 글자에서는 이름 줄 오른쪽에 둘 자리가 없어서 이름 아래 한 줄로 내립니다.
        let placesMapButtonBelow = dynamicTypeSize.isAccessibilitySize

        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                savedSpotsScreen
            } label: {
                MyAlbum(
                    title: "저장한 장소",
                    detail: countText(savedSpots.count, unit: "곳"),
                    aspectRatio: MyAlbumMetrics.wideAspect
                ) {
                    if savedMosaicSpots.isEmpty {
                        MyThumbnailPlaceholder(
                            symbolName: "bookmark",
                            symbolSize: MyAlbumMetrics.placeholderSymbolSize
                        )
                    } else {
                        MySavedMosaic(spots: savedMosaicSpots)
                    }
                }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomTrailing) {
                // 표지 링크 위에 따로 얹은 버튼입니다. 링크 안에 넣으면 두 동작이 겹칩니다.
                if showsMapButton, !placesMapButtonBelow {
                    MyShowOnMapButton(action: onShowSavedOnMap)
                }
            }

            if showsMapButton, placesMapButtonBelow {
                MyShowOnMapButton(action: onShowSavedOnMap)
            }
        }
    }

    /// 추가한 장소 · 내 글. 두 칸으로 나란히, 큰 글자에서는 한 줄에 하나씩(넓은 표지로) 둡니다.
    @ViewBuilder
    private var activityAlbums: some View {
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: MyAlbumMetrics.sectionSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: MyAlbumMetrics.columnSpacing))
        let aspectRatio = isStacked ? MyAlbumMetrics.wideAspect : 1

        layout {
            placesAlbum(aspectRatio: aspectRatio)
            postsAlbum(aspectRatio: aspectRatio)
        }
    }

    @ViewBuilder
    private func placesAlbum(aspectRatio: CGFloat) -> some View {
        if user == nil {
            // 게스트에게도 무엇이 있는지 보여줍니다. 누르면 로그인입니다.
            lockedAlbum(title: "추가한 장소", symbolName: "mappin.and.ellipse", aspectRatio: aspectRatio)
        } else {
            NavigationLink {
                MyPlacesView(
                    receipts: submissionReceipts,
                    spots: spots,
                    currentUserID: user?.id ?? "",
                    onSelectSpot: onSelectSpot,
                    onEdit: onEditPlace,
                    onDelete: onDeletePlace,
                    onAddPlace: onAddPlace
                )
            } label: {
                MyAlbum(
                    title: "추가한 장소",
                    detail: countText(submissionReceipts.count, unit: "곳"),
                    aspectRatio: aspectRatio
                ) {
                    if let spot = placeCoverSpot {
                        spotCoverPhoto(spot)
                    } else {
                        MyThumbnailPlaceholder(
                            symbolName: "mappin.and.ellipse",
                            symbolSize: MyAlbumMetrics.placeholderSymbolSize
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func postsAlbum(aspectRatio: CGFloat) -> some View {
        if user == nil {
            lockedAlbum(title: "내 글", symbolName: "text.bubble", aspectRatio: aspectRatio)
        } else {
            NavigationLink {
                MyPostsView(
                    posts: myPosts,
                    makeDetail: postDetail,
                    onEdit: onEditPost,
                    onDelete: onDeletePost,
                    onCompose: onCompose
                )
            } label: {
                MyAlbum(
                    title: "내 글",
                    detail: countText(myPosts.count, unit: "개"),
                    aspectRatio: aspectRatio
                ) {
                    if let attachment = postCoverAttachment {
                        MyAttachmentImage(attachment: attachment, detail: .card)
                    } else {
                        MyThumbnailPlaceholder(
                            symbolName: "text.bubble",
                            symbolSize: MyAlbumMetrics.placeholderSymbolSize
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func lockedAlbum(title: String, symbolName: String, aspectRatio: CGFloat) -> some View {
        Button(action: onRequestSignIn) {
            MyAlbum(title: title, detail: "로그인이 필요해요", aspectRatio: aspectRatio) {
                MyThumbnailPlaceholder(symbolName: symbolName, symbolSize: MyAlbumMetrics.placeholderSymbolSize)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("로그인 화면을 엽니다")
    }

    private var savedSpotsScreen: some View {
        MySavedSpotsView(
            spots: savedSpots,
            onSelect: onSelectSpot,
            onUnsave: unsave,
            onExplore: onExploreSpots,
            onShowOnMap: onShowSavedOnMap
        )
    }

    private func spotCoverPhoto(_ spot: PhotoSpot) -> some View {
        PhotoSpotImageView(
            spot: spot,
            symbolSize: 20,
            targetPixelWidth: VFPhotoDetail.card.pixelWidth
        )
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

    /// 글 상세. "내 글" 화면이 이 함수를 그대로 받아 씁니다.
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
    /// 목록 줄의 작은 사진. (첫 화면 모음 줄 · 추가한 장소 줄)
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

// MARK: - 앨범 표지

private enum MyAlbumMetrics {
    /// 첫 화면 묶음 사이 간격.
    static let sectionSpacing: CGFloat = 28
    /// 나란히 놓인 두 표지 사이 간격. 저장한 장소 화면 격자와 같습니다.
    static let columnSpacing: CGFloat = 16
    /// 넓은 표지 비율. (저장한 장소, 큰 글자에서의 모든 표지)
    static let wideAspect: CGFloat = 2
    /// 모자이크 사진 사이 틈.
    static let mosaicGap: CGFloat = 2
    /// 사진이 없을 때 표지 가운데 기호 크기.
    static let placeholderSymbolSize: CGFloat = 28
    /// 표지 모서리. 저장한 장소 화면의 사진 칸과 같습니다.
    static let cornerRadius: CGFloat = VFRadius.inner
}

/// 사진 앱 "앨범" 한 칸: 표지 사진 + 아래에 이름 · 개수.
/// 사진이 없으면 모음의 기호를 회색 칸에 둡니다.
private struct MyAlbum<Cover: View>: View {
    let title: String
    let detail: String
    var aspectRatio: CGFloat = 1
    @ViewBuilder let cover: () -> Cover

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MyAlbumMetrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            // 투명한 상자로 비율을 먼저 정하고, 사진이 그 상자를 채우게 합니다. (VFPhotoTile 과 같은 방식)
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    cover()
                }
                .clipShape(shape)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(detail)")
    }
}

/// 저장한 장소 표지. 1장이면 한 장, 2장이면 반반, 3장이면 큰 1 + 작은 2 입니다.
private struct MySavedMosaic: View {
    let spots: [PhotoSpot]

    private let gap = MyAlbumMetrics.mosaicGap

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

/// "지도에서 보기". 저장한 장소 표지의 이름 줄 오른쪽에 놓입니다.
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
            in: RoundedRectangle(cornerRadius: MyAlbumMetrics.cornerRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: MyAlbumMetrics.cornerRadius, style: .continuous))
    }
}

/// 설정 앱 맨 위 계정 행과 같은 모양입니다. 누르면 계정 화면이 열립니다.
private struct MyProfileLabel: View {
    let user: AuthUser

    var body: some View {
        HStack(spacing: 14) {
            MyAvatar(name: user.displayName, size: MyListMetrics.profileAvatarSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        return MyAccountText.providerTitle(for: user).map { "\($0) 계정" } ?? "내 계정"
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

/// 내가 추가한 장소 한 줄. 누르면 장소 상세가 열리고, 줄 끝 "…" 에 수정 · 삭제가 있습니다.
private struct MyPlaceRow: View {
    let receipt: PlaceSubmissionReceipt
    /// 지금 불러온 장소 목록에서 찾은 장소. 아직 못 불러왔으면 nil 이고,
    /// 그때는 누를 수 없는 행으로 두고 "…" 도 두지 않습니다. (메뉴 항목마다 장소가 필요합니다)
    let spot: PhotoSpot?
    /// 내가 만든 장소일 때만 "…" 과 길게 누르기 메뉴를 둡니다. 메뉴가 수정 · 삭제뿐이라서입니다.
    let isOwned: Bool
    let isDeleting: Bool
    let onSelectSpot: (PhotoSpot) -> Void
    let onEdit: (PhotoSpot) -> Void
    /// 바로 지우지 않습니다. 목록 화면이 한 번 더 묻습니다.
    let onDelete: (PhotoSpot) -> Void

    /// 추가한 뒤 이름을 고쳤으면 고친 이름을 보여줍니다. 기록(receipt)에는 추가할 때 이름이 남아 있습니다.
    private var name: String {
        spot?.name ?? receipt.name
    }

    var body: some View {
        if let spot {
            // 빈 메뉴가 길게 누를 때 떠오르지 않게, 내 장소가 아니면 길게 누르기 메뉴를 아예 붙이지 않습니다.
            if isOwned {
                row(spot)
                    .contextMenu {
                        menuItems(for: spot)
                    }
            } else {
                row(spot)
            }
        } else {
            content
        }
    }

    private func row(_ spot: PhotoSpot) -> some View {
        HStack(spacing: 0) {
            // 줄과 "…" 이 따로 눌리게 둘 다 목록 기본 버튼 모양을 쓰지 않습니다.
            // 기본 모양이면 목록이 줄 전체를 버튼 하나로 만들어서, "…" 을 눌러도 상세가 열릴 수 있습니다.
            // 상세는 밀어 넣는 화면이 아니라 시트라서 오른쪽 화살표(›)를 두지 않습니다.
            Button {
                onSelectSpot(spot)
            } label: {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isDeleting ? MyListMetrics.deletingOpacity : 1)
            .accessibilityHint("장소 상세를 엽니다")

            if isOwned {
                MyRowMenu(accessibilityLabel: "장소 메뉴", isBusy: isDeleting) {
                    menuItems(for: spot)
                }
            }
        }
        .disabled(isDeleting)
    }

    /// "…" 과 길게 누르기 메뉴에 같이 들어갑니다. 내 글 목록과 같은 수정 · 삭제입니다.
    /// 지도에서 보기는 넣지 않습니다. 장소 상세 아래 "지도에서 보기" 가 같은 일을 합니다.
    @ViewBuilder
    private func menuItems(for spot: PhotoSpot) -> some View {
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
            // 구분선을 글자가 시작하는 곳부터 긋습니다. 첫 화면 모음 줄과 같습니다.
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
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
// MARK: - 각 화면
// ═══════════════════════════════════════════════════════════════════

/// 저장한 장소. 사진 앱 "앨범" 과 같은 2열 격자입니다.
private struct MySavedSpotsView: View {
    let spots: [PhotoSpot]
    let onSelect: (PhotoSpot) -> Void
    let onUnsave: (PhotoSpot) -> Void
    let onExplore: () -> Void
    /// 지도 탭에서 저장한 장소만 모아 봅니다.
    let onShowOnMap: () -> Void

    @State private var selectedTheme: SpotTheme?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

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
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(visibleSpots) { spot in
                    MySavedSpotTile(
                        spot: spot,
                        onSelect: { onSelect(spot) },
                        onUnsave: { onUnsave(spot) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(VFMotion.quick, value: activeTheme)
        }
        .vfReportsTabBarScroll()
        .overlay {
            if spots.isEmpty {
                ContentUnavailableView {
                    Label("저장한 출사지가 아직 없어요", systemImage: "bookmark")
                } description: {
                    Text("홈이나 지도에서 마음에 드는 곳을 저장하면 여기에 모여요.")
                } actions: {
                    Button("출사지 둘러보기", action: onExplore)
                }
            }
        }
        .navigationTitle("저장한 장소")
        .toolbar {
            if !spots.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onShowOnMap) {
                        Image(systemName: "map")
                    }
                    .accessibilityLabel("지도에서 보기")
                    .accessibilityHint("지도 탭에서 저장한 장소만 모아 봅니다")
                }
            }

            // 테마가 하나뿐이면 거를 게 없으므로 메뉴를 두지 않습니다.
            if themes.count >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    themeMenu
                }
            }
        }
        .onChange(of: themes) { _, newThemes in
            if let selectedTheme, !newThemes.contains(selectedTheme) {
                self.selectedTheme = nil
            }
        }
    }

    /// 사진 앱 · 메일 앱의 거르기 버튼과 같은 모양입니다. 거르는 중에는 채운 아이콘.
    private var themeMenu: some View {
        Menu {
            Picker("테마", selection: $selectedTheme) {
                Text("전체")
                    .tag(SpotTheme?.none)

                ForEach(themes) { theme in
                    Text(theme.title)
                        .tag(SpotTheme?.some(theme))
                }
            }
        } label: {
            Image(systemName: activeTheme == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("테마로 거르기")
        .accessibilityValue(activeTheme?.title ?? "전체")
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

private struct MyPlacesView: View {
    let receipts: [PlaceSubmissionReceipt]
    let spots: [PhotoSpot]
    /// 수정 · 삭제를 내가 만든 장소에만 보이려고 받습니다.
    let currentUserID: String
    let onSelectSpot: (PhotoSpot) -> Void
    let onEdit: (PhotoSpot) -> Void
    let onDelete: (PhotoSpot) async throws -> Void
    /// 비어 있을 때 가운데 "장소 추가" 버튼.
    let onAddPlace: () -> Void

    /// "삭제" 를 누른 장소. 한 번 더 물은 뒤 지웁니다.
    @State private var pendingDeleteSpot: PhotoSpot?
    /// 지우는 중인 장소. 그 줄은 흐리게 두고 누를 수 없게 합니다.
    @State private var deletingSpotIDs: Set<String> = []
    @State private var deleteError: String?

    var body: some View {
        List {
            if !receipts.isEmpty {
                Section {
                    ForEach(receipts) { receipt in
                        let spot = spots.first(where: { $0.id == receipt.id })
                        MyPlaceRow(
                            receipt: receipt,
                            spot: spot,
                            isOwned: spot?.isOwned(by: currentUserID) ?? false,
                            isDeleting: deletingSpotIDs.contains(receipt.id),
                            onSelectSpot: onSelectSpot,
                            onEdit: onEdit,
                            onDelete: { pendingDeleteSpot = $0 }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .vfReportsTabBarScroll()
        .overlay {
            if receipts.isEmpty {
                ContentUnavailableView {
                    Label("직접 추가한 장소가 아직 없어요", systemImage: "mappin.and.ellipse")
                } description: {
                    Text("나만 아는 출사지를 알려주세요. 다른 사진가의 다음 출사지가 돼요.")
                } actions: {
                    Button("장소 추가", action: onAddPlace)
                }
            }
        }
        // 오른쪽 위 + 는 두지 않습니다. 탭바 가운데 + 가 같은 장소 추가입니다.
        // 비어 있을 때만 가운데 "장소 추가" 버튼을 둡니다.
        .navigationTitle("추가한 장소")
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

/// 내 글. 누르면 글 상세, 줄 끝 "…" 이나 길게 누르면 수정 · 삭제입니다.
///
/// 글 상세를 만드는 함수를 받습니다. 상세에 필요한 인자가 많아서, 이 화면이 그것들을 다시
/// 프로퍼티로 받으면 MyTabView 의 인자 목록을 그대로 복사해야 하고, 하나라도 어긋나면
/// 다르게 동작합니다. MyTabView.postDetail 을 그대로 받습니다.
private struct MyPostsView<Detail: View>: View {
    let posts: [CommunityPost]
    let makeDetail: (CommunityPost) -> Detail
    /// 글쓰기 화면을 고치기로 엽니다. 글 상세 오른쪽 위 "…" → 수정 과 같은 길입니다.
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) async throws -> Void
    /// 비어 있을 때 가운데 "글쓰기" 버튼.
    let onCompose: () -> Void

    /// 지금 열린 글 상세.
    @State private var openedPost: MyOpenedPost?
    /// "삭제" 를 누른 글. 한 번 더 물은 뒤 지웁니다.
    @State private var pendingDeletePost: CommunityPost?
    /// 지우는 중인 글. 그 줄은 흐리게 두고 누를 수 없게 합니다.
    @State private var deletingPostIDs: Set<String> = []
    @State private var deleteError: String?

    var body: some View {
        List {
            if !posts.isEmpty {
                Section {
                    ForEach(posts) { post in
                        row(post)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .vfReportsTabBarScroll()
        .overlay {
            if posts.isEmpty {
                ContentUnavailableView {
                    Label("남긴 글이 아직 없어요", systemImage: "text.bubble")
                } description: {
                    Text("지금 현장의 분위기와 혼잡도를 남겨보세요. 다음 사람의 출사가 쉬워져요.")
                } actions: {
                    Button("글쓰기", action: onCompose)
                }
            }
        }
        // 오른쪽 위 글쓰기 버튼은 두지 않습니다. 글은 커뮤니티 탭 · 장소 상세에서 씁니다.
        // 비어 있을 때만 가운데 "글쓰기" 버튼을 둡니다.
        .navigationTitle("내 글")
        // 줄마다가 아니라 목록 자체에 붙입니다. 목록 줄 안에 두면 동작하지 않을 수 있습니다.
        .navigationDestination(item: $openedPost) { opened in
            // 목록에 있는 최신 글로 엽니다. 지워져 목록에서 빠지는 중이면 열 때의 글을 씁니다.
            makeDetail(posts.first(where: { $0.id == opened.id }) ?? opened.post)
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

    /// 줄과 "…" 이 따로 눌리게 둘 다 목록 기본 버튼 모양을 쓰지 않습니다. (MyPlaceRow 와 같은 이유)
    /// 누르면 글 상세가 밀려 들어오지만, 한 줄에 › 와 "…" 을 같이 두면 복잡해서 "…" 만 둡니다.
    private func row(_ post: CommunityPost) -> some View {
        let isDeleting = deletingPostIDs.contains(post.id)

        return HStack(spacing: 0) {
            Button {
                openedPost = MyOpenedPost(post: post)
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

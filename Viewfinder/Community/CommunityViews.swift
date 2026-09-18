import CoreLocation
import NMapsMap
import PhotosUI
import SwiftUI
import UIKit

// 좋아요는 "내가 반응한 상태" 이므로 저장됨과 같은 계열의 상태 표시입니다.
// 빨강(#FF2E40)은 검정·흰색·오렌지 체계에서 유일하게 튀는 색이었습니다.
private let communityLikeTint = AppColors.accent

struct CommunityTabView: View {
    let posts: [CommunityPost]
    let spots: [PhotoSpot]
    let currentUserID: String
    let likedPostIDs: Set<String>
    let followedAuthorIDs: Set<String>
    let commentsByPostID: [String: [CommunityComment]]
    let onTabBarVisibilityChange: (Bool) -> Void
    let onCompose: () -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    let onEditPost: (CommunityPost) -> Void
    let onDeletePost: (CommunityPost) -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool
    let communityViewModel: CommunityViewModel

    // ═══════════════════════════════════════════════════════════════
    //  "지금 주목받는 현장" 가로 레일을 제거했습니다.
    //
    //  [문제였던 상황]
    //  레일이 반응 순 상위 6개를 가져가고, 아래 "최신 현장 정보" 피드는
    //  그 6개를 제외한 나머지만 보여주고 있었습니다.
    //      feedPosts = posts - popularPosts(6)
    //  제보가 6개 이하인 지금은 피드가 항상 비어서,
    //  화면에 218pt 작은 카드 레일 하나와 "직접 남겨보세요" 패널만
    //  남았습니다. 같은 글이 두 번 보이거나 아래가 텅 비는 구조입니다.
    //
    //  사진 앱의 커뮤니티에서 218pt 카드는 사진을 보여주기에 너무 작습니다.
    //  제보가 쌓이면 사회적 증거로서 의미가 생기지만,
    //  지금 규모에서는 사진을 작게 만들고 피드를 비우는 역효과만 냅니다.
    //
    //  단일 최신순 피드로 바꿉니다. 모든 제보가 전체 폭 3:2 사진을 갖습니다.
    // ═══════════════════════════════════════════════════════════════
    var body: some View {
        let feedPosts = posts.sorted { $0.createdAt > $1.createdAt }
        let spotsByID = Dictionary(
            spots.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        NavigationStack {
            ScrollView(showsIndicators: false) {
                if posts.isEmpty {
                    EmptyCommunityView(onCompose: onCompose)
                        .padding(.top, VFSpace.xl)
                        .vfScreenMargin()
                } else {
                    // 사진 사이 간격을 넓게 둡니다.
                    // 카드 표면이 없어졌으므로 글과 글을 나누는 유일한 수단이
                    // 여백입니다. 12pt 로는 앞 글의 액션 줄과 다음 글의
                    // 작성자 줄이 한 덩어리로 읽힙니다.
                    LazyVStack(alignment: .leading, spacing: VFSpace.xl) {
                        CommunityFeedContextHeader(postCount: feedPosts.count)

                        ForEach(feedPosts) { post in
                            CommunityPostCard(
                                post: post,
                                spot: spotsByID[post.spotID],
                                captureLocationSpot: post.captureLocation?.placeID.flatMap {
                                    spotsByID[$0]
                                },
                                currentUserID: currentUserID,
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
                    }
                    .vfScreenMargin()
                    .padding(.top, VFSpace.md)
                    .vfScrollBottomInset()
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("커뮤니티")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onCompose) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("커뮤니티 글쓰기")
                }
            }
            .onAppear {
                onTabBarVisibilityChange(false)
            }
        }
    }

    private func displayedLikeCount(for post: CommunityPost) -> Int {
        post.likeCount + (likedPostIDs.contains(post.id) ? 1 : 0)
    }

}

// ═══════════════════════════════════════════════════════════════════
//  글의 사진 — 사용자가 올린 사진만
//
//  [전에 있던 문제]
//  제보 사진이 없으면 그 장소의 대표 사진으로 채우고 있었습니다.
//  "서울숲이 좋다" 는 글을 사진 없이 올리면, 피드에는 우리가 가진
//  서울숲 스톡 사진이 떴습니다. 사용자가 찍지 않은 사진이 그 사람의
//  사진처럼 보였습니다. 사진 앱에서 이건 거짓입니다.
//  게다가 그 사진은 "지금" 이 아니라 언제인지도 모르는 사진인데,
//  현장 정보 제보 옆에 붙어 지금처럼 읽혔습니다.
//
//  [지금]
//  post.photoData 가 있을 때만 그립니다. 없으면 사진 영역이 없습니다.
//  장소와의 연결은 사진이 아니라 장소 태그가 담당합니다.
// ═══════════════════════════════════════════════════════════════════

struct CommunityPostPhoto: View {
    let post: CommunityPost
    /// 사진 전체가 NavigationLink 안에 있으면 끕니다. 제스처가 충돌합니다.
    var isTappableForPreview = true

    var body: some View {
        let attachments = post.publicPhotoAttachments
        if attachments.count == 1, let attachment = attachments.first {
            CommunityAttachedPhotoView(
                attachment: attachment,
                isTappableForPreview: isTappableForPreview
            )
        } else if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(attachments) { attachment in
                        CommunityAttachedPhotoView(
                            attachment: attachment,
                            imageDetail: .card,
                            isTappableForPreview: isTappableForPreview
                        )
                        .frame(width: 250, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous))
                    }
                }
            }
        }
    }
}

struct CommunityPostPhotoMetadata: View {
    let post: CommunityPost

    private var firstAttachmentWithMetadata: CommunityPhotoAttachment? {
        post.publicPhotoAttachments.first { $0.metadata?.detailSummary != nil }
    }

    var body: some View {
        if let attachment = firstAttachmentWithMetadata {
            CommunityPhotoMetadataView(attachment: attachment)
        }
    }
}

struct CommunityPhotoMetadataView: View {
    let attachment: CommunityPhotoAttachment

    var body: some View {
        if let summary = attachment.metadata?.detailSummary {
            Text(summary)
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 상세 화면의 사진 영역입니다.
/// 사진을 모두 세로로 쌓지 않고 한 장씩 paging하며, 현재 index만
/// 부모에게 전달해 현재 사진의 EXIF와 연결합니다.
struct CommunityPostPhotoGallery: View {
    let attachments: [CommunityPhotoAttachment]
    @Binding var selectedIndex: Int
    let onTapPhoto: (Int) -> Void

    private var pageHeight: CGFloat {
        min(max((UIScreen.main.bounds.width - 40) * 0.88, 280), 500)
    }

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $selectedIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    CommunityPhotoGalleryPage(attachment: attachment)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTapPhoto(index)
                        }
                        .accessibilityLabel("게시글 사진 \(index + 1) / \(attachments.count)")
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: pageHeight)

            if attachments.count > 1 {
                Text("\(selectedIndex + 1) / \(attachments.count)")
                    .vfText(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityLabel("사진 \(selectedIndex + 1) / \(attachments.count)")
            }
        }
        .onChange(of: attachments.count) { _, count in
            selectedIndex = min(max(selectedIndex, 0), max(count - 1, 0))
        }
    }
}

private struct CommunityPhotoGalleryPage: View {
    let attachment: CommunityPhotoAttachment

    var body: some View {
        ZStack {
            AppColors.mutedSurface

            if let imageData = attachment.imageData,
               let image = CommunityPhotoDecoder.image(
                from: imageData,
                cacheKey: attachment.id,
                detail: .hero
               ) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let remoteURL = attachment.remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        Image(systemName: "photo")
                            .vfIcon(24)
                            .foregroundStyle(AppColors.secondaryText)
                    default:
                        ProgressView()
                            .tint(AppColors.secondaryText)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .vfIcon(24)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous))
        .accessibilityLabel("게시글 사진")
    }
}

// ═══════════════════════════════════════════════════════════════════
//  장소 태그
//
//  글이 어느 출사지에 대한 것인지 알려주고, 누르면 그 장소의 상세로
//  갑니다. 전에는 피드에서 장소 이름이 사진 위에 얹힌 라벨이라
//  누를 수 없었고, 사진이 없는 글은 장소가 어디인지 아예 보이지
//  않았습니다.
//
//  사진 위에서 내려온 이유가 하나 더 있습니다.
//  사진 위에 글자를 얹으면 scrim 으로 사진 아래쪽을 어둡게 해야 합니다.
//  사용자가 올린 사진을 앱이 가리는 셈입니다.
//  이제 사진에는 아무것도 얹지 않습니다.
// ═══════════════════════════════════════════════════════════════════

struct CommunityPlaceTag: View {
    let spotName: String
    let spot: PhotoSpot?
    let onSelect: (PhotoSpot) -> Void
    var isCompact = false

    var body: some View {
        Button {
            guard let spot else { return }
            onSelect(spot)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .vfIcon(isCompact ? 12 : 13)
                    .foregroundStyle(AppColors.secondaryText)

                Text(spotName)
                    .vfText(isCompact ? .caption.weight(.semibold) : .headline)
                    .foregroundStyle(isCompact ? AppColors.secondaryText : AppColors.primary)
                    .lineLimit(1)

                if spot != nil {
                    Image(systemName: "chevron.right")
                        .vfIcon(isCompact ? 10 : 11, weight: .bold)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(spot == nil)
        .accessibilityLabel("\(spotName) 장소 상세 보기")
    }
}

struct CommunityCaptureLocationTag: View {
    let location: CommunityCaptureLocation
    let linkedSpot: PhotoSpot?
    let onSelectSpot: ((PhotoSpot) -> Void)?

    var body: some View {
        if let linkedSpot, let onSelectSpot {
            Button {
                onSelectSpot(linkedSpot)
            } label: {
                labelContent(showChevron: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("촬영 위치 \(location.name), 장소 상세 보기")
        } else {
            labelContent(showChevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("촬영 위치 \(location.name)")
        }
    }

    private func labelContent(showChevron: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "mappin.and.ellipse")
                .vfIcon(13)
                .foregroundStyle(AppColors.secondaryText)

            Text("촬영 위치 · \(location.name)")
                .vfText(.caption.weight(.semibold))
                .foregroundStyle(AppColors.primary)
                .lineLimit(1)

            if showChevron {
                Image(systemName: "chevron.right")
                    .vfIcon(10, weight: .bold)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CommunityPostCard: View {
    let post: CommunityPost
    let spot: PhotoSpot?
    let captureLocationSpot: PhotoSpot?
    let currentUserID: String
    let isLiked: Bool
    let likeCount: Int
    let isFollowing: Bool
    let comments: [CommunityComment]
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool
    let onSelectSpot: (PhotoSpot) -> Void
    let communityViewModel: CommunityViewModel

    // ═══════════════════════════════════════════════════════════════
    //  게시판 행 -> 사진 카드
    //
    //  [문제였던 상황]
    //  순서가 아바타 -> 사진 -> 제목 -> 혼잡도 -> 본문 3줄 -> 해시태그
    //  -> 회색 알약 버튼 2개 였습니다.
    //  38pt 아바타와 이름·시간 두 줄이 먼저 나오고, 사진은 그 아래
    //  214pt 고정 높이 띠로 끼어 있었습니다.
    //  사진 앱의 커뮤니티인데 사진이 네 번째 요소였습니다.
    //  사용자 지적: "커뮤니티도 일반 게시판처럼 보인다"
    //
    //  [바꾼 것]
    //  1. .appCardSurface() 제거.
    //     홈에서 이미 카드 표면을 걷어내고 사진을 검정 캔버스에 직접
    //     올렸습니다. 사진이 3:2 로 커지고 모서리가 둥글면 카드 배경은
    //     아무 정보를 더하지 않고 사진 주위에 회색 테두리만 만듭니다.
    //  2. 사진을 3:2 로 키우고 장소 이름을 사진 위에 올립니다.
    //     214pt 고정 높이는 기기 폭과 무관한 값이라 아이폰마다
    //     비율이 달라졌습니다.
    //  3. 아바타 38 -> 28, 이름·시간을 한 줄로.
    //     작성자는 신뢰 신호이지 콘텐츠가 아닙니다.
    //  4. 회색 알약 버튼 제거. 아이콘 + 숫자만 남깁니다.
    //     알약 두 개가 사진보다 시각적으로 무거웠습니다.
    //  5. 해시태그 줄 제거. 장소 이름과 혼잡도가 이미 맥락을 줍니다.
    // ═══════════════════════════════════════════════════════════════
    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm - 2) {
            authorLine

            if let title = post.title, !title.isEmpty {
                NavigationLink {
                    detailView(focusCommentComposer: false)
                } label: {
                    Text(title)
                        .vfText(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if post.hasPhotos {
                NavigationLink {
                    detailView(focusCommentComposer: false)
                } label: {
                    CommunityPostPhoto(post: post, isTappableForPreview: false)
                }
                .buttonStyle(.plain)
            }

            // 본문도 상세로 가는 링크입니다.
            // 사진이 없는 글은 사진을 누를 수 없으므로, 본문이
            // 상세로 들어가는 유일한 경로가 됩니다.
            if !post.message.isEmpty {
                NavigationLink {
                    detailView(focusCommentComposer: false)
                } label: {
                    Text(post.message)
                        .vfText(.callout)
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let relatedSpotName = post.relatedSpotName {
                CommunityPlaceTag(
                    spotName: relatedSpotName,
                    spot: spot,
                    onSelect: onSelectSpot,
                    isCompact: true
                )
            }

            if let captureLocation = post.captureLocation {
                CommunityCaptureLocationTag(
                    location: captureLocation,
                    linkedSpot: captureLocationSpot,
                    onSelectSpot: onSelectSpot
                )
            }

            if post.hasStatusInfo {
                conditionLine
            }

            listActionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if post.authorID == currentUserID {
                Button {
                    onEdit(post)
                } label: {
                    Label("수정", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete(post)
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  현재 상태 한 줄: 혼잡도 + 상태 태그
    //
    //  [전에 있던 줄의 문제]
    //  해시태그 줄이 두 가지를 섞고 있었습니다.
    //      spot.hashtags.prefix(3)  장소의 고정 속성 (#한강 #노을)
    //      post.tags                지금 현장의 상태 (꽃 만개, 사람 적음)
    //  "그 장소는 항상 그렇다" 와 "지금만 그렇다" 를 #a #b #c 회색 한 줄로
    //  합쳐놔서, 어느 것이 지금 정보인지 알 수 없었습니다.
    //  섞이면 둘 다 의미가 없어집니다.
    //
    //  [지금]
    //  post.tags 만 씁니다. 피드는 "지금" 피드입니다.
    //  # 을 붙이지 않습니다. 해시태그로 보이면 다시 장식이 됩니다.
    //  혼잡도와 한 줄에 두어 "현재 상태" 한 문장으로 읽히게 합니다.
    //      ●●○ 보통 · 꽃 만개 · 사람 적음
    //
    //  상태 태그는 장식이 아니라 제보의 본문입니다.
    //  혼잡도 하나로는 "사람은 보통인데 꽃이 만개했다" 를 전할 수 없고,
    //  작성 화면에서 사용자에게 고르라고 요구하는 값이기도 합니다.
    //  요구해놓고 보여주지 않으면 그 입력은 버려지는 노동입니다.
    // ═══════════════════════════════════════════════════════════════
    @ViewBuilder
    private var conditionLine: some View {
        HStack(spacing: 6) {
            VFCrowdBadge(level: VFCrowdLevel.from(post.crowd.displayName))

            if !statusTagChips.isEmpty {
                Text("·")
                    .vfText(.mono)
                    .foregroundStyle(AppColors.secondaryText)

                VFMetaLine(items: statusTagChips)
            }
        }
    }

    /// 피드 카드는 미리보기이므로 3개까지. 전체는 상세에서 봅니다.
    private var statusTagChips: [String] {
        communityDisplayTags(post.tags, excluding: spot, crowd: post.crowd, limit: 3)
    }

    // ═══════════════════════════════════════════════════════════════
    //  아바타 38 -> 28 로 줄였다가 34 로 되돌립니다.
    //
    //  "작성자는 콘텐츠가 아니라 신뢰 신호" 라는 판단은 맞았지만
    //  너무 줄여서 두 가지가 깨졌습니다.
    //   1. 28pt 아바타와 12pt 이름은 누가 올린 글인지 읽기 어렵습니다.
    //      커뮤니티에서 작성자는 부차적이더라도 식별은 되어야 합니다.
    //   2. 위계가 뒤집혔습니다. 이름은 caption(12pt)인데
    //      VFMetaLine 이 쓰는 mono 는 13pt 라서, 시간 표시가
    //      이름보다 커져 있었습니다.
    //
    //  이름을 callout(15pt) semibold 로 올려 시간(13pt)보다 크게 만듭니다.
    // ═══════════════════════════════════════════════════════════════
    private var authorLine: some View {
        HStack(alignment: .center, spacing: VFSpace.sm) {
            CommunityAuthorAvatar(authorName: post.authorName, size: 34)

            Text(post.authorName)
                .vfText(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.primary)
                .lineLimit(1)

            VFMetaLine(
                items: post.updatedAt == nil
                    ? [communityRelativeTimeText(for: post.createdAt)]
                    : [communityRelativeTimeText(for: post.createdAt), "수정됨"]
            )

            Spacer(minLength: 4)

            if post.authorID != currentUserID {
                Menu {
                    Button {
                        onToggleFollow(post)
                    } label: {
                        Label(isFollowing ? "팔로우 취소" : "팔로우", systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(post.authorName) 게시글 메뉴")
            } else {
                Menu {
                    Button {
                        onEdit(post)
                    } label: {
                        Label("수정", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        onDelete(post)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        // Dynamic Type 제외: 고정 32pt 더보기 버튼.
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var listActionRow: some View {
        HStack(spacing: VFSpace.lg) {
            Button {
                VFHaptics.like()
                onToggleLike(post)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                    Text("\(likeCount)")
                }
                .vfText(.callout)
                .foregroundStyle(isLiked ? communityLikeTint : AppColors.secondaryText)
                .frame(minHeight: AppLayout.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? "좋아요 취소" : "좋아요")

            NavigationLink {
                detailView(focusCommentComposer: true)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                    Text("\(comments.count)")
                }
                .vfText(.callout)
                .foregroundStyle(AppColors.secondaryText)
                .frame(minHeight: AppLayout.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("댓글 \(comments.count)개")

            Spacer(minLength: 0)
        }
    }

    private func detailView(focusCommentComposer: Bool) -> some View {
        CommunityPostDetailView(
            post: post,
            spot: spot,
            captureLocationSpot: captureLocationSpot,
            currentUserID: currentUserID,
            isLiked: isLiked,
            likeCount: likeCount,
            isFollowing: isFollowing,
            comments: comments,
            focusCommentComposerOnAppear: focusCommentComposer,
            onToggleLike: onToggleLike,
            onToggleFollow: onToggleFollow,
            onAddComment: onAddComment,
            onSelectSpot: onSelectSpot,
            onEdit: onEdit,
            onDelete: onDelete,
            communityViewModel: communityViewModel
        )
    }
}

private struct CommunityAuthorAvatar: View {
    let authorName: String
    var size: CGFloat = 42

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // ═══════════════════════════════════════════════════════════
        //  person.fill 아이콘 -> 이름 첫 글자
        //
        //  전에는 모든 사용자가 같은 사람 실루엣이었습니다.
        //  배경만 무채색 6단계로 달랐는데, 무채색끼리는 차이가 작아서
        //  결과적으로 아바타가 사용자를 구분해주지 못했습니다.
        //  아바타의 목적은 장식이 아니라 "누가 올렸는지" 입니다.
        //
        //  첫 글자를 쓰면 6개 톤보다 훨씬 많은 구분이 생깁니다.
        //  프로필 사진 필드가 아직 모델에 없으므로 이것이 최선입니다.
        // ═══════════════════════════════════════════════════════════
        Text(initial)
            // Dynamic Type 제외: 아바타 지름에 비례하는 크기다. 원이 안 커지므로 글자도 안 커진다.
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(inkColor)
            .frame(width: size, height: size)
            .background(avatarColor, in: Circle())
            .overlay {
                Circle()
                    .stroke(AppColors.divider, lineWidth: 0.5)
            }
            .accessibilityLabel("\(authorName) 프로필")
    }

    private var initial: String {
        let trimmed = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// 글자 색을 모드에 따라 정합니다.
    ///
    /// avatarTones 는 다이내믹 컬러입니다.
    /// 다크에서는 어두운 회색(#2A2A2E~#61616A)이라 흰 글자가 맞고,
    /// 라이트에서는 밝은 회색(#E4E4E9~#A8A8B2)이라 어두운 글자가 맞습니다.
    /// 전에는 항상 흰색이라 라이트 모드에서 가장 밝은 톤 위의 글자가
    /// 거의 보이지 않았습니다.
    private var inkColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : .black.opacity(0.72)
    }

    private var avatarColor: Color {
        // 유채색 6개 대신 무채색 밝기 6단계를 씁니다. (VFPalette.avatarTones)
        // 사용자 구분은 유지하면서 팔레트를 검정·흰색·오렌지로 좁힙니다.
        let tones = VFPalette.avatarTones
        let seed = authorName.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return Color(uiColor: tones[seed % tones.count])
    }
}

struct CommunityPostDetailView: View {
    let post: CommunityPost
    let spot: PhotoSpot?
    let captureLocationSpot: PhotoSpot?
    let currentUserID: String
    let isLiked: Bool
    let likeCount: Int
    let isFollowing: Bool
    let comments: [CommunityComment]
    let focusCommentComposerOnAppear: Bool
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Bool
    let onSelectSpot: (PhotoSpot) -> Void
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) -> Void
    @ObservedObject var communityViewModel: CommunityViewModel

    @State private var draft = ""
    @FocusState private var isCommentFieldFocused: Bool
    @State private var selectedPhotoIndex = 0
    @State private var viewerPresentation: CommunityPhotoViewerPresentation?
    @State private var isDeleteConfirmationPresented = false
    @Environment(\.dismiss) private var dismiss
    private let commentComposerAnchorID = "community-comment-composer"

    private var currentPost: CommunityPost {
        communityViewModel.posts.first(where: { $0.id == post.id }) ?? post
    }

    private var currentComments: [CommunityComment] {
        communityViewModel.commentsByPostID[post.id] ?? comments
    }

    private var currentIsLiked: Bool {
        communityViewModel.likedPostIDs.contains(post.id)
    }

    private var currentLikeCount: Int {
        currentPost.likeCount + (currentIsLiked ? 1 : 0)
    }

    private var currentIsFollowing: Bool {
        communityViewModel.followedAuthorIDs.contains(post.authorID)
    }

    private var currentAttachments: [CommunityPhotoAttachment] {
        currentPost.publicPhotoAttachments
    }

    private var currentAttachment: CommunityPhotoAttachment? {
        guard !currentAttachments.isEmpty else { return nil }
        let safeIndex = min(max(selectedPhotoIndex, 0), currentAttachments.count - 1)
        return currentAttachments[safeIndex]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                // 작성자 → 제목 → 사진 → 현재 사진 EXIF → 본문 → 관련 메타데이터 순서로 구성한다.
                VStack(alignment: .leading, spacing: VFSpace.md) {
                    authorHeader

                    if let title = currentPost.title {
                        Text(title)
                            .vfText(.headline.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                    }

                    if !currentAttachments.isEmpty {
                        CommunityPostPhotoGallery(
                            attachments: currentAttachments,
                            selectedIndex: $selectedPhotoIndex,
                            onTapPhoto: { index in
                                viewerPresentation = CommunityPhotoViewerPresentation(
                                    attachments: currentAttachments,
                                    initialIndex: index
                                )
                            }
                        )
                    }

                    if let attachment = currentAttachment,
                       attachment.metadata?.detailSummary != nil {
                        CommunityPhotoMetadataView(attachment: attachment)
                    }

                    if !currentPost.message.isEmpty {
                        Text(currentPost.message)
                            .vfText(.body)
                            .foregroundStyle(AppColors.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    detailMetadataSection

                    detailActionRow(proxy: proxy)
                        .padding(.top, VFSpace.xs)

                    commentSection
                        .padding(.top, VFSpace.lg)

                    Color.clear
                        .frame(height: 1)
                        .id(commentComposerAnchorID)
                }
                .vfScreenMargin()
                .padding(.top, VFSpace.md)
                .padding(.bottom, VFSpace.md)
            }
            .safeAreaInset(edge: .bottom) {
                commentComposer
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("게시글")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if currentPost.authorID == currentUserID {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                onEdit(currentPost)
                            } label: {
                                Label("수정", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                isDeleteConfirmationPresented = true
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("게시글 메뉴")
                    }
                }
            }
            .alert("게시글을 삭제할까요?", isPresented: $isDeleteConfirmationPresented) {
                Button("삭제", role: .destructive) {
                    onDelete(currentPost)
                    dismiss()
                }
                Button("취소", role: .cancel) { }
            } message: {
                Text("삭제한 게시글은 되돌릴 수 없어요.")
            }
            .fullScreenCover(item: $viewerPresentation) { presentation in
                CommunityPhotoViewer(
                    attachments: presentation.attachments,
                    initialIndex: presentation.initialIndex
                )
            }
            .onAppear {
                guard focusCommentComposerOnAppear else { return }
                focusCommentComposer(using: proxy)
            }
        }
    }

    /// 피드 카드와 같은 줄입니다. 혼잡도 + 상태 태그.
    @ViewBuilder
    private var conditionLine: some View {
        HStack(spacing: 6) {
            VFCrowdBadge(level: VFCrowdLevel.from(currentPost.crowd.displayName))

            if !statusTagChips.isEmpty {
                Text("·")
                    .vfText(.mono)
                    .foregroundStyle(AppColors.secondaryText)

                VFMetaLine(items: statusTagChips)
            }
        }
    }

    /// 상세는 전부 보여줍니다. 피드 카드만 3개로 줄입니다.
    private var statusTagChips: [String] {
        communityDisplayTags(currentPost.tags, excluding: spot, crowd: currentPost.crowd, limit: 8)
    }

    private var hasDetailMetadata: Bool {
        currentPost.relatedSpotName != nil
            || currentPost.captureLocation != nil
            || currentPost.hasStatusInfo
    }

    @ViewBuilder
    private var detailMetadataSection: some View {
        if hasDetailMetadata {
            VStack(alignment: .leading, spacing: VFSpace.xs) {
                if let relatedSpotName = currentPost.relatedSpotName {
                    CommunityPlaceTag(
                        spotName: relatedSpotName,
                        spot: spot,
                        onSelect: onSelectSpot,
                        isCompact: true
                    )
                }

                if let captureLocation = currentPost.captureLocation {
                    CommunityCaptureLocationTag(
                        location: captureLocation,
                        linkedSpot: captureLocationSpot,
                        onSelectSpot: onSelectSpot
                    )
                }

                if currentPost.hasStatusInfo {
                    conditionLine
                }
            }
        }
    }

    private var authorHeader: some View {
        HStack(spacing: VFSpace.sm) {
            // 상세 헤더는 콘텐츠보다 앞서지 않도록 피드보다 한 단계 작게 둡니다.
            CommunityAuthorAvatar(authorName: currentPost.authorName, size: 32)

            Text(currentPost.authorName)
                .vfText(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.primary)
                .lineLimit(1)

            VFMetaLine(
                items: currentPost.updatedAt == nil
                    ? [communityRelativeTimeText(for: currentPost.createdAt)]
                    : [communityRelativeTimeText(for: currentPost.createdAt), "수정됨"]
            )

            Spacer(minLength: 4)

            if currentPost.authorID != currentUserID {
                Button {
                    onToggleFollow(currentPost)
                } label: {
                    Text(currentIsFollowing ? "팔로잉" : "팔로우")
                        .vfText(.caption)
                        .foregroundStyle(currentIsFollowing ? AppColors.secondaryText : AppColors.primary)
                        .frame(minWidth: AppLayout.touchTarget, minHeight: AppLayout.touchTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(currentIsFollowing ? "팔로우 취소" : "팔로우")
            }
        }
    }

    /// 피드 카드의 액션 줄과 같은 형태입니다.
    /// 아이콘 + 숫자, 앰버는 좋아요한 하트에만.
    private func detailActionRow(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: VFSpace.lg) {
            Button {
                VFHaptics.like()
                onToggleLike(currentPost)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: currentIsLiked ? "heart.fill" : "heart")
                    Text("\(currentLikeCount)")
                }
                .vfText(.callout)
                .foregroundStyle(currentIsLiked ? communityLikeTint : AppColors.secondaryText)
                .frame(minHeight: AppLayout.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(currentIsLiked ? "좋아요 취소" : "좋아요")

            Button {
                focusCommentComposer(using: proxy)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                    Text("\(currentComments.count)")
                }
                .vfText(.callout)
                .foregroundStyle(AppColors.secondaryText)
                .frame(minHeight: AppLayout.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("댓글 작성")

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .vfText(.callout)
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(minHeight: AppLayout.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("공유")

            Spacer(minLength: 0)
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("댓글 \(currentComments.count)")
                .vfText(.headline)
                .foregroundStyle(AppColors.primary)

            if !currentComments.isEmpty {
                ForEach(currentComments) { comment in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            CommunityAuthorAvatar(authorName: comment.authorName, size: 26)

                            Text(comment.authorName)
                                .vfText(.subhead)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColors.primary)

                            VFMetaLine(items: [communityRelativeTimeText(for: comment.createdAt)])
                        }

                        Text(comment.message)
                            .vfText(.subhead)
                            .foregroundStyle(AppColors.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 32)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var commentComposer: some View {
        HStack(spacing: VFSpace.sm) {
            TextField("댓글 추가…", text: $draft)
                .vfText(.subhead)
                .tint(AppColors.accent)
                .focused($isCommentFieldFocused)
                .submitLabel(.send)
                .onSubmit(submit)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .background(AppColors.mutedSurface, in: Capsule())

            // 전송 버튼이 AppColors.primary 였습니다.
            // 다크에서 그 값은 흰색이라 25pt 흰 원반이 화면에서 가장
            // 밝은 요소가 됐습니다. 주 동작이므로 앰버입니다.
            // 보낼 내용이 없으면 비활성으로 낮춥니다.
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .vfIcon(28, weight: .regular)
                    .foregroundStyle(canSubmitComment ? AppColors.accent : AppColors.secondaryText.opacity(0.45))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitComment)
            .accessibilityLabel("댓글 보내기")
        }
        .padding(.horizontal, VFSpace.md)
        .padding(.vertical, VFSpace.sm)
        .background(AppColors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 0.5)
        }
    }

    private var canSubmitComment: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shareText: String {
        let context = [currentPost.title, currentPost.relatedSpotName, currentPost.captureLocation?.name, currentPost.message]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n")
        return "\(currentPost.authorName)님의 커뮤니티 글\n\(context)"
    }

    private func submit() {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        if onAddComment(trimmedDraft, currentPost) {
            draft = ""
        }
    }

    private func focusCommentComposer(using proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(commentComposerAnchorID, anchor: .bottom)
            }
            isCommentFieldFocused = true
        }
    }
}

struct CommunityPostMetaHeader: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 7) {
                Text(post.authorName)
                    .vfText(.caption.weight(.bold))
                    .foregroundStyle(AppColors.primary.opacity(0.78))
                    .lineLimit(1)

                Text("·")
                    .vfText(.caption.weight(.bold))
                    .foregroundStyle(AppColors.secondaryText.opacity(0.65))

                Text(communityRelativeTimeText(for: post.createdAt))
                    .vfText(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)

                if post.updatedAt != nil {
                    Text("수정됨")
                        .vfText(.caption.weight(.bold))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.65))
                }

                Spacer(minLength: 0)
            }

            Text(communityWrittenTimeText(for: post.createdAt))
                .vfText(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText.opacity(0.86))
        }
        .contextMenu {
            Text(communityAbsoluteTimeText(for: post.createdAt))
        }
    }
}

struct CommunityCrowdBadge: View {
    let crowd: CommunityPost.Crowd

    var body: some View {
        Text(crowd.displayText)
            .vfText(.caption.weight(.bold))
            .foregroundStyle(crowd.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(minHeight: 24)
            .background(crowd.fill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(crowd.tint.opacity(0.16), lineWidth: 1)
            )
    }
}

func communityDisplayTags(
    _ values: [String],
    excluding spot: PhotoSpot?,
    crowd: CommunityPost.Crowd,
    limit: Int
) -> [String] {
    let excluded = communityAddressExclusions(for: spot)

    return values
        .map(communityNormalizedTag)
        .filter { tag in
            !tag.isEmpty
                && tag != crowd.rawValue
                && tag != crowd.displayName
                && !excluded.contains(tag)
                && !communityTagLooksLikeAddress(tag)
        }
        .reduce(into: [String]()) { result, tag in
            guard !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
            result.append(tag)
        }
        .prefix(limit)
        .map { $0 }
}

private func communityAddressExclusions(for spot: PhotoSpot?) -> Set<String> {
    guard let spot else { return [] }

    let values = [
        spot.name,
        spot.region,
        spot.mapQuery,
        HomeSpotDisplayFormatter.region(for: spot)
    ] + spot.recommendationRegions

    return Set(values.map(communityNormalizedTag).filter { !$0.isEmpty })
}

private func communityNormalizedTag(_ value: String) -> String {
    var tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
    while tag.hasPrefix("#") {
        tag.removeFirst()
    }
    return tag.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func communityTagLooksLikeAddress(_ tag: String) -> Bool {
    let compact = tag.replacingOccurrences(of: " ", with: "")
    let addressMarkers = ["특별시", "광역시", "자치도", "시", "군", "구", "읍", "면", "동", "로", "길"]

    if tag.contains(" "),
       addressMarkers.contains(where: { compact.contains($0) }) {
        return true
    }

    if compact.range(of: #"\d+(-\d+)?$"#, options: .regularExpression) != nil,
       addressMarkers.contains(where: { compact.contains($0) }) {
        return true
    }

    return false
}

struct CommunityStatusRow: View {
    let crowd: CommunityPost.Crowd
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                CommunityCrowdBadge(crowd: crowd)

                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .vfText(.caption.weight(.bold))
                        .foregroundStyle(AppColors.primary.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(minHeight: 24)
                        .background(AppColors.mutedSurface, in: Capsule())
                }
            }
            .padding(.vertical, 1)
        }
        .scrollDisabled(tags.count <= 2)
    }
}

struct CommunityPostOwnerActions: View {
    let post: CommunityPost
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onEdit(post)
            } label: {
                Label("수정", systemImage: "pencil")
                    .vfText(.caption.weight(.bold))
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onDelete(post)
            } label: {
                Label("삭제", systemImage: "trash")
                    .vfText(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppColors.secondaryText)
    }
}

// ═══════════════════════════════════════════════════════════════════
//  제보 사진 디코딩 캐시
//
//  CommunityPost.photoData 는 raw Data 입니다.
//  UIImage(data:) 는 호출할 때마다 다시 디코딩하는데,
//  피드가 LazyVStack 이라 스크롤하는 동안 같은 사진을 반복 디코딩합니다.
//  전체 화면 사진(3:2)으로 키우면서 이 비용이 눈에 보이게 되므로 캐시합니다.
// ═══════════════════════════════════════════════════════════════════

enum CommunityPhotoDecoder {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 36
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func image(
        from data: Data,
        cacheKey: String? = nil,
        detail: VFPhotoDetail = .hero
    ) -> UIImage? {
        // 첨부 ID가 있으면 큰 Data 전체를 매 body 계산마다 해시하지 않습니다.
        let sourceKey = cacheKey ?? "\(data.count)-\(data.hashValue)"
        let key = "\(sourceKey)-\(data.count)-\(detail.pixelWidth)" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = VFImageDownsampler.image(
            from: data,
            maxPixelSize: detail.pixelWidth
        ) ?? UIImage(data: data) else {
            return nil
        }

        cache.setObject(
            image,
            forKey: key,
            cost: VFImageDownsampler.memoryCost(of: image)
        )
        return image
    }
}

struct CommunityAttachedPhotoView: View {
    // ═══════════════════════════════════════════════════════════════
    //  사진 비율
    //
    //  [문제였던 상황]
    //  모든 사진을 3:2 상자에 scaledToFill 로 채웠습니다.
    //  세로 사진을 올리면 위아래가 잘려나갔습니다.
    //  사진 앱에서 사진가가 정한 프레이밍을 앱이 잘라내면 안 됩니다.
    //  세로로 찍은 이유가 있어서 세로로 찍은 것입니다.
    //
    //  [지금]
    //  높이도 비율도 지정하지 않으면 사진의 실제 비율을 그대로 씁니다.
    //  다만 범위를 둡니다. 무제한으로 허용하면 9:16 스크린샷 한 장이
    //  화면 두 개 높이를 차지해서 피드를 스크롤할 수 없게 됩니다.
    //
    //    가장 세로  3:4 (0.75)  아이폰 세로 사진이 그대로 들어갑니다.
    //    가장 가로  16:9 (1.78) 파노라마는 이 선에서 잘립니다.
    //
    //  아이폰 기본 카메라가 4:3 이므로, 세로로 찍은 사진은 3:4 입니다.
    //  하한을 4:5(0.8)로 두면 그 흔한 사진이 조금씩 잘리므로 0.75 로
    //  내렸습니다.
    // ═══════════════════════════════════════════════════════════════
    private static let minAspect: CGFloat = 3.0 / 4.0
    private static let maxAspect: CGFloat = 16.0 / 9.0

    let photoData: Data?
    let remoteURL: URL?
    let cacheKey: String?
    /// 고정 높이. 작은 썸네일에만 씁니다.
    var height: CGFloat?
    var maxWidth: CGFloat?
    /// 비율을 강제할 때만 지정합니다. nil 이면 사진의 실제 비율을 씁니다.
    var aspectRatio: CGFloat?
    /// 기존에는 14 로 하드코딩되어 있었습니다.
    /// 같은 카드 안의 장소 사진은 20(VFRadius.photo)이라 두 사진의
    /// 모서리가 서로 달랐습니다. 토큰으로 통일합니다.
    var cornerRadius: CGFloat = VFRadius.photo
    /// 사진 위에 글자를 올릴 때만 켭니다.
    var showsScrim = false
    /// 피드에서는 사진 전체가 상세로 가는 NavigationLink 안에 있습니다.
    /// 그 안에서 또 탭을 받으면 제스처가 충돌하므로 끕니다.
    var isTappableForPreview = true
    var imageDetail: VFPhotoDetail = .hero

    @State private var isPreviewPresented = false

    init(
        photoData: Data,
        cacheKey: String? = nil,
        height: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        aspectRatio: CGFloat? = nil,
        cornerRadius: CGFloat = VFRadius.photo,
        showsScrim: Bool = false,
        imageDetail: VFPhotoDetail = .hero,
        isTappableForPreview: Bool = true
    ) {
        self.photoData = photoData
        self.remoteURL = nil
        self.cacheKey = cacheKey
        self.height = height
        self.maxWidth = maxWidth
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
        self.showsScrim = showsScrim
        self.imageDetail = imageDetail
        self.isTappableForPreview = isTappableForPreview
    }

    init(
        attachment: CommunityPhotoAttachment,
        imageDetail: VFPhotoDetail = .hero,
        isTappableForPreview: Bool = true
    ) {
        self.photoData = attachment.imageData
        self.remoteURL = attachment.remoteURL
        self.cacheKey = attachment.id
        self.height = nil
        self.maxWidth = nil
        self.aspectRatio = nil
        self.cornerRadius = VFRadius.photo
        self.showsScrim = false
        self.imageDetail = imageDetail
        self.isTappableForPreview = isTappableForPreview
    }

    var body: some View {
        if let photoData,
           let image = CommunityPhotoDecoder.image(
            from: photoData,
            cacheKey: cacheKey,
            detail: imageDetail
           ) {
            if isTappableForPreview {
                Button {
                    isPreviewPresented = true
                } label: {
                    photo(image)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(isPreviewPresented)
                .fullScreenCover(isPresented: $isPreviewPresented) {
                    CommunityPhotoViewer(
                        attachments: [
                            CommunityPhotoAttachment(
                                id: "preview-\(photoData.count)",
                                imageData: photoData,
                                remoteURL: nil,
                                metadata: nil,
                                location: nil
                            )
                        ],
                        initialIndex: 0
                    )
                }
            } else {
                photo(image)
            }
        } else if let remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(VFPhoto.carouselAspect, contentMode: .fit)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                default:
                    AppColors.mutedSurface
                        .aspectRatio(VFPhoto.carouselAspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  [버그였던 코드]
    //      Image(uiImage:).resizable().scaledToFill()
    //          .frame(maxWidth: .infinity)
    //          .aspectRatio(3/2, contentMode: .fill)   <- 여기
    //          .clipped()
    //
    //  scaledToFill() 이 이미 aspectRatio(contentMode: .fill) 입니다.
    //  그 위에 또 .fill 비율을 걸면 이미지가 부모 경계를 무시하고
    //  스스로 커집니다. .clipped() 는 이미 커진 프레임을 자르므로
    //  아무 소용이 없었습니다.
    //  결과적으로 사진이 시트 전체 배경으로 퍼졌습니다.
    //
    //  [올바른 패턴 — VFPhotoTile 과 동일]
    //  투명한 상자로 비율을 먼저 확정하고, 사진이 그 상자를 채우게 합니다.
    //  비율을 가진 쪽은 Color.clear 이고 contentMode 는 .fit 입니다.
    // ═══════════════════════════════════════════════════════════════
    private func photo(_ image: UIImage) -> some View {
        sizedBox(for: image)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            // VFScrim 을 직접 overlay 하면 사진 전체에 그라디언트가 깔려
            // 위쪽까지 어두워집니다. 전용 모디파이어는 아래 55% 에만
            // 깔아서 사진을 살립니다. VFPhotoTile 과 같은 값입니다.
            .modifier(CommunityPhotoScrim(isEnabled: showsScrim))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 사진이 채울 자리를 먼저 만듭니다.
    ///
    /// 높이와 비율 중 하나만 씁니다. 둘을 같이 걸면 어느 쪽이 이기는지
    /// 예측할 수 없습니다. maxWidth 는 고정 높이 경로에서만 씁니다.
    /// (유일한 사용처가 상세 화면의 92x178 인라인 카드입니다.)
    @ViewBuilder
    private func sizedBox(for image: UIImage) -> some View {
        if let height {
            Color.clear
                .frame(maxWidth: maxWidth ?? .infinity)
                .frame(height: height)
        } else {
            Color.clear
                .aspectRatio(resolvedAspect(for: image), contentMode: .fit)
        }
    }

    /// 지정된 비율이 없으면 사진의 실제 비율을 범위 안으로 좁혀서 씁니다.
    private func resolvedAspect(for image: UIImage) -> CGFloat {
        if let aspectRatio {
            return aspectRatio
        }

        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return VFPhoto.carouselAspect
        }

        return min(max(size.width / size.height, Self.minAspect), Self.maxAspect)
    }
}

/// showsScrim 이 켜졌을 때만 사진 아래 55% 에 scrim 을 깝니다.
private struct CommunityPhotoScrim: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            // 기본값 0.55 대신 0.40 입니다.
            // 사진 비율을 그대로 쓰게 되면서 세로 사진은 카드가 훨씬
            // 길어집니다. 그 높이의 55% 를 그라디언트로 덮으면 사진
            // 절반이 어두워집니다. 사진 위에 놓이는 것은 장소 이름
            // 한 줄뿐이므로 40% 로 충분합니다.
            content.vfPhotoScrim(heightRatio: 0.40)
        } else {
            content
        }
    }
}

private struct CommunityPhotoViewerPresentation: Identifiable {
    let id = UUID()
    let attachments: [CommunityPhotoAttachment]
    let initialIndex: Int
}

/// 게시글 상세에서 여는 전체화면 사진 감상 화면입니다.
/// 1x에서는 TabView가 좌우 paging을 담당하고, 확대되면 사진 내부의
/// pan gesture가 우선권을 가져가 두 제스처가 서로 넘겨받지 않습니다.
struct CommunityPhotoViewer: View {
    let attachments: [CommunityPhotoAttachment]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int

    init(attachments: [CommunityPhotoAttachment], initialIndex: Int) {
        self.attachments = attachments
        self.initialIndex = initialIndex
        _selectedIndex = State(
            initialValue: min(
                max(initialIndex, 0),
                max(attachments.count - 1, 0)
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    CommunityZoomablePhoto(
                        attachment: attachment,
                        resetKey: selectedIndex
                    )
                    .accessibilityLabel("사진 \(index + 1) / \(attachments.count), 확대 가능")
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 0) {
                HStack {
                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .vfGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("사진 뷰어 닫기")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                if attachments.count > 1 {
                    Text("\(selectedIndex + 1) / \(attachments.count)")
                        .vfText(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.42), in: Capsule())
                        .accessibilityLabel("사진 \(selectedIndex + 1) / \(attachments.count)")
                        .padding(.bottom, 22)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct CommunityZoomablePhoto: View {
    let attachment: CommunityPhotoAttachment
    let resetKey: Int

    @State private var scale: CGFloat = 1
    @State private var scaleAtGestureStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetAtGestureStart: CGSize = .zero

    private let maximumScale: CGFloat = 4.5

    var body: some View {
        GeometryReader { geometry in
            let content = photoContent
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
                .simultaneousGesture(magnificationGesture(in: geometry.size))
                .onTapGesture(count: 2) {
                    toggleZoom()
                }

            if scale > 1.01 {
                content.highPriorityGesture(panGesture(in: geometry.size))
            } else {
                content
            }
        }
        .onChange(of: resetKey) { _, _ in
            resetZoom()
        }
        .accessibilityLabel("확대 가능한 사진")
    }

    @ViewBuilder
    private var photoContent: some View {
        if let imageData = attachment.imageData,
           let image = CommunityPhotoDecoder.image(
            from: imageData,
            cacheKey: attachment.id,
            detail: .fullscreen
           ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let remoteURL = attachment.remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Image(systemName: "photo")
                        .vfIcon(26)
                        .foregroundStyle(.white.opacity(0.7))
                default:
                    ProgressView()
                        .tint(.white)
                }
            }
        } else {
            Image(systemName: "photo")
                .vfIcon(26)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func magnificationGesture(in containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(scaleAtGestureStart * value, 1), maximumScale)
            }
            .onEnded { _ in
                scaleAtGestureStart = scale
                if scale <= 1.01 {
                    resetZoom()
                } else {
                    offset = clampedOffset(offset, in: containerSize)
                    offsetAtGestureStart = offset
                }
            }
    }

    private func panGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                let proposed = CGSize(
                    width: offsetAtGestureStart.width + value.translation.width,
                    height: offsetAtGestureStart.height + value.translation.height
                )
                offset = clampedOffset(proposed, in: containerSize)
            }
            .onEnded { _ in
                offsetAtGestureStart = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if scale > 1.01 {
                resetZoom()
            } else {
                scale = 2.5
                scaleAtGestureStart = 2.5
                offset = .zero
                offsetAtGestureStart = .zero
            }
        }
    }

    private func resetZoom() {
        scale = 1
        scaleAtGestureStart = 1
        offset = .zero
        offsetAtGestureStart = .zero
    }

    private func clampedOffset(_ proposed: CGSize, in containerSize: CGSize) -> CGSize {
        let extraX = max(0, (containerSize.width * scale - containerSize.width) / 2) + 24
        let extraY = max(0, (containerSize.height * scale - containerSize.height) / 2) + 24

        return CGSize(
            width: min(max(proposed.width, -extraX), extraX),
            height: min(max(proposed.height, -extraY), extraY)
        )
    }
}

private struct CommunityFeedContextHeader: View {
    let postCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("사진과 이야기", systemImage: "camera.aperture")
                .vfText(.headline.weight(.bold))
                .foregroundStyle(AppColors.primary)

            Text("최신 글 \(postCount)개 · 최신순")
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyCommunityView: View {
    let onCompose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .vfIcon(24, weight: .regular)
                .foregroundStyle(AppColors.secondaryText)

            Text("아직 올라온 글이 없어요")
                .vfText(.headline.weight(.bold))
                .foregroundStyle(AppColors.primary)

            Text("사진과 이야기를 자유롭게 남겨보세요.")
                .vfText(.subhead)
                .foregroundStyle(AppColors.secondaryText)

            Button(action: onCompose) {
                Label("첫 글 쓰기", systemImage: "square.and.pencil")
                    .vfText(.callout.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(minHeight: AppLayout.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 54)
        .frame(maxWidth: .infinity)
    }
}

enum CommunityComposerPurpose: Equatable {
    case fieldReport
    case addSpot
    case contributePhotos(placeID: String)

    var isPhotoContribution: Bool {
        if case .contributePhotos = self {
            return true
        }
        return false
    }

    var isPlaceSubmissionFlow: Bool {
        switch self {
        case .fieldReport:
            return false
        case .addSpot, .contributePhotos:
            return true
        }
    }

    var photoContributionPlaceID: String? {
        guard case .contributePhotos(let placeID) = self else { return nil }
        return placeID
    }

    var navigationTitle: String {
        switch self {
        case .fieldReport:
            return "글쓰기"
        case .addSpot:
            return "장소 추가"
        case .contributePhotos:
            return "사진 등록"
        }
    }

    var messageSectionTitle: String {
        switch self {
        case .fieldReport:
            return "본문"
        case .addSpot:
            return "추천 이유"
        case .contributePhotos:
            return ""
        }
    }

    var messagePlaceholder: String {
        switch self {
        case .fieldReport:
            return "사진, 카메라, 장비, 촬영 후기를 자유롭게 적어보세요"
        case .addSpot:
            return "예: 저녁빛이 좋은 골목이고 오래된 간판이 많아 필름 사진에 잘 어울려요"
        case .contributePhotos:
            return ""
        }
    }
}

private struct CommunityPlaceSelectionCheck: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppColors.onAccent)
            .frame(width: 26, height: 26)
            .background(AppColors.accent, in: Circle())
            .accessibilityHidden(true)
    }
}

struct CommunityComposerView: View {
    private enum ComposerField: Hashable {
        case title
        case message
        case placeSearch
    }

    /// TextEditor는 내부적으로 UITextView의 lineFragmentPadding과
    /// textContainerInset을 사용합니다. placeholder도 같은 시작점을
    /// 사용하도록 외부 여백과 native content inset을 한 곳에서 관리합니다.
    private enum MessageEditorMetrics {
        static let outerHorizontalPadding: CGFloat = 14
        static let outerVerticalPadding: CGFloat = 13
        static let nativeLeadingInset: CGFloat = 5
        static let nativeTopInset: CGFloat = 8

        static var contentHorizontalPadding: CGFloat {
            outerHorizontalPadding + nativeLeadingInset
        }

        static var contentTopPadding: CGFloat {
            outerVerticalPadding + nativeTopInset
        }
    }

    private struct MetadataEditorTarget: Identifiable {
        let id: String
    }

    let spots: [PhotoSpot]
    let initialSpot: PhotoSpot?
    let locksSelectedSpot: Bool
    let editingPost: CommunityPost?
    let purpose: CommunityComposerPurpose
    let onShowRegisteredSpot: (PhotoSpot) -> Void
    let onSubmit: (CommunityPostDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: ComposerField?
    @State private var selectedSpotID: String
    @State private var selectedSearchedSpot: PhotoSpot?
    @State private var placeSearchText: String
    /// 지도 검색과 같은 검색기입니다.
    /// 전에는 이 화면만 원격 장소검색을 갖고 있었고, 로컬 후보는
    /// 시드 JSON 만 봤습니다. spots(AI 추천·저장분 포함)는 보지 않았습니다.
    @StateObject private var placeFinder = PlaceFinder(resultLimit: 6)
    @State private var title = ""
    @State private var message = ""
    @State private var crowd: CommunityPost.Crowd = .normal
    @State private var selectedCommunityCrowd: CommunityPost.Crowd?
    @State private var selectedTags: Set<String> = []
    @State private var customTags: [String]
    @State private var customTagText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photoDrafts: [CommunityPhotoDraft]
    @State private var retainedRemoteAttachments: [CommunityPhotoAttachment]
    @State private var selectedPhotoData: Data?
    @State private var photoLoadFailed = false
    @State private var hasAcknowledgedSubmissionGuidelines = false
    @State private var isExifPublic = false
    @State private var selectedCaptureLocation: CommunityCaptureLocation?
    @State private var isCaptureLocationPickerPresented = false
    @State private var isMapPlacePickerPresented = false
    @State private var metadataEditorTarget: MetadataEditorTarget?
    @State private var showExifConsent = false
    @State private var promptedExifPhotoIDs: Set<String> = []
    @State private var isPreparingSubmission = false
    @State private var submissionPreparationTask: Task<Void, Never>?
    /// 결과를 골라 검색어를 장소명으로 바꿀 때, 그 변경이 다시 검색을
    /// 일으키지 않게 막습니다.
    @State private var suppressPlaceSearch = false

    private let statusTags = ["노을 좋음", "꽃 만개", "안개 있음", "사람 적음", "야경 좋음", "사진 찍기 좋음", "비 분위기 좋음", "반영 예쁨", "단풍 절정", "조명 좋음"]
    /// Community 글의 기존 사진 첨부 한도는 유지하되, 장소 추가와 같은
    /// 사진 개수·추가 진입점을 사용합니다.
    private static let maxCommunityPhotoCount = 8
    private let placeSearchService = PlaceSearchService()

    init(
        spots: [PhotoSpot],
        selectedSpot: PhotoSpot?,
        locksSelectedSpot: Bool = false,
        editingPost: CommunityPost? = nil,
        purpose: CommunityComposerPurpose = .fieldReport,
        onShowRegisteredSpot: @escaping (PhotoSpot) -> Void = { _ in },
        onSubmit: @escaping (CommunityPostDraft) -> Void
    ) {
        self.spots = spots
        self.initialSpot = selectedSpot
        self.locksSelectedSpot = locksSelectedSpot
        self.editingPost = editingPost
        self.purpose = purpose
        self.onShowRegisteredSpot = onShowRegisteredSpot
        self.onSubmit = onSubmit
        _selectedSpotID = State(initialValue: editingPost?.spotID ?? selectedSpot?.id ?? "")
        _selectedSearchedSpot = State(initialValue: nil)
        _placeSearchText = State(initialValue: editingPost?.spotName ?? selectedSpot?.name ?? "")
        _title = State(initialValue: editingPost?.title ?? "")
        _message = State(initialValue: editingPost?.message ?? "")
        _crowd = State(initialValue: editingPost?.crowd ?? .normal)
        _selectedCommunityCrowd = State(
            initialValue: purpose == .fieldReport && editingPost?.hasStatusInfo == true
                ? editingPost?.crowd
                : nil
        )
        _selectedTags = State(initialValue: Set(editingPost?.tags ?? []))
        _customTags = State(initialValue: purpose == .addSpot ? Self.normalizedTags(editingPost?.tags ?? []) : [])
        _customTagText = State(initialValue: "")
        _photoDrafts = State(
            initialValue: Self.drafts(
                from: editingPost,
                includeExif: purpose == .fieldReport
            )
        )
        _retainedRemoteAttachments = State(
            initialValue: editingPost?.publicPhotoAttachments.filter {
                $0.imageData == nil && $0.remoteURL != nil
            } ?? []
        )
        _selectedPhotoData = State(initialValue: editingPost?.photoData)
        _isExifPublic = State(
            initialValue: purpose == .fieldReport
                && (editingPost?.photoAttachments.contains { $0.metadata != nil } ?? false)
        )
        _selectedCaptureLocation = State(initialValue: editingPost?.captureLocation)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if purpose == .fieldReport {
                        communityPostForm
                    } else if purpose == .addSpot {
                        placeSubmissionForm
                    } else {
                        contributePhotosForm
                    }
                }
                .padding(.top, VFSpace.md)
                .padding(.horizontal, 20)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(editingPost == nil ? purpose.navigationTitle : "글 수정")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerSubmitBar
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                loadPhotos(from: newItems)
            }
            .onChange(of: placeSearchText) { _, newValue in
                if suppressPlaceSearch {
                    suppressPlaceSearch = false
                    return
                }
                schedulePlaceSearch(for: newValue)
            }
            .onDisappear {
                placeFinder.clear()
                submissionPreparationTask?.cancel()
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusedField = nil
                }
            )
            .alert("촬영 정보 공개", isPresented: $showExifConsent) {
                Button("공개하기") {
                    isExifPublic = true
                }
                Button("공개하지 않기", role: .cancel) {
                    isExifPublic = false
                }
            } message: {
                Text("사진에서 촬영 정보를 찾았어요. 카메라와 촬영 설정을 게시물에 공개하시겠어요?")
            }
            .sheet(item: $metadataEditorTarget) { target in
                CommunityPhotoExifEditor(
                    initialMetadata: metadata(for: target.id),
                    onSave: { metadata in
                        updateMetadata(metadata, for: target.id)
                    }
                )
            }
            .sheet(isPresented: $isCaptureLocationPickerPresented) {
                CommunityCaptureLocationPicker(spots: spots) { location in
                    selectedCaptureLocation = location
                }
            }
            .sheet(isPresented: $isMapPlacePickerPresented) {
                CommunityMapPlacePicker { spot in
                    clearPlaceDependentOptions()
                    selectedSearchedSpot = spot
                    selectedSpotID = spot.id
                    suppressPlaceSearch = true
                    placeSearchText = spot.name
                    hasAcknowledgedSubmissionGuidelines = false
                }
            }
        }
    }

    private var communityPostForm: some View {
        Group {
            ComposerFormSection(title: "제목", detail: "") {
                TextField("제목을 입력하세요", text: $title)
                    .vfText(.body)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .message
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        AppColors.mutedSurface,
                        in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
                    )
            }

            ComposerFormSection(title: "본문", detail: "") {
                messageField
            }

            photoSection

            photoPrivacySection

            ComposerFormSection(title: "관련 출사지", detail: "") {
                if isSpotLocked, let selectedSpot {
                    selectedPlaceRow(selectedSpot)
                } else {
                    placeSearchSection
                }
            }

            placeGallerySharingSection
            communityCrowdSection
        }
    }

    private var placeSubmissionForm: some View {
        Group {
            ComposerFormSection(
                title: "장소명",
                detail: ""
            ) {
                if isSpotLocked, let selectedSpot {
                    selectedPlaceRow(selectedSpot)
                } else {
                    placeSearchSection
                }
            }

            if selectedSpot != nil {
                photoSection

                ComposerFormSection(
                    title: purpose.messageSectionTitle,
                    detail: ""
                ) {
                    messageField
                }

                ComposerFormSection(
                    title: "태그",
                    detail: ""
                ) {
                    CustomTagInputSection(tags: $customTags, text: $customTagText)
                }

                if editingPost == nil {
                    submissionConsentSection
                }
            }
        }
    }

    private var contributePhotosForm: some View {
        Group {
            ComposerFormSection(
                title: "장소명",
                detail: ""
            ) {
                if let selectedSpot {
                    selectedPlaceRow(selectedSpot)
                }
            }

            if selectedSpot != nil {
                photoSection
            }
        }
    }

    private var messageField: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $message)
                .vfText(.body)
                .focused($focusedField, equals: .message)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150, maxHeight: 240)
                .padding(.horizontal, MessageEditorMetrics.outerHorizontalPadding)
                .padding(.vertical, MessageEditorMetrics.outerVerticalPadding)
                .background(AppColors.mutedSurface)

            if message.isEmpty {
                Text(purpose.messagePlaceholder)
                    .vfText(.body)
                    .foregroundStyle(AppColors.secondaryText.opacity(0.7))
                    .padding(.horizontal, MessageEditorMetrics.contentHorizontalPadding)
                    .padding(.top, MessageEditorMetrics.contentTopPadding)
                    .allowsHitTesting(false)
            }
        }
        .background(
            AppColors.mutedSurface,
            in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
        )
    }

    private var composerSubmitBar: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                submit()
            } label: {
                // 주 동작이므로 앰버입니다.
                // 전에는 AppColors.primary 였는데 다크에서 흰색이라
                // 제출 버튼이 화면에서 가장 밝은 면이 됐습니다.
                // VFDesign 의 앰버 허용 목록에 "주 동작" 이 있습니다.
                Text(submitButtonTitle)
                    .vfText(.headline)
                    .foregroundStyle(canSubmit ? AppColors.onAccent : AppColors.secondaryText.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                    .background(
                        canSubmit ? AppColors.accent : AppColors.mutedSurface,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(AppColors.background)
    }

    @ViewBuilder
    private func selectedPlaceRow(_ spot: PhotoSpot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "location")
                    // Dynamic Type 제외: 고정 38pt 원 안의 아이콘.
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 38, height: 38)
                    .background(AppColors.mutedSurface, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .vfText(.headline.weight(.bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text(spot.region)
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                CommunityPlaceSelectionCheck()
            }

            if purpose == .addSpot, selectedSpotAlreadyRegistered {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .vfIcon(13, relativeTo: .caption)
                    Text("이미 등록된 장소예요. 중복 등록 대신 장소 상세에서 확인해주세요.")
                        .vfText(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AppColors.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
            }
        }
        .padding(.vertical, 2)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: purpose.isPlaceSubmissionFlow ? VFSpace.sm : VFSpace.md) {
            if purpose.isPlaceSubmissionFlow {
                HStack(alignment: .top, spacing: VFSpace.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("사진")
                            .vfText(.headline)
                            .foregroundStyle(AppColors.primary)

                        Text("최대 5장까지 등록할 수 있어요")
                            .vfText(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                    }

                    Spacer(minLength: VFSpace.sm)

                    HStack(spacing: 8) {
                        Text("\(addSpotPhotoCount) / \(PlaceSubmissionService.maxPhotoCount)")
                            .vfText(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .monospacedDigit()

                        if addSpotPhotoCount > 0,
                           addSpotPhotoCount < PlaceSubmissionService.maxPhotoCount {
                            PhotosPicker(
                                selection: $selectedPhotoItems,
                                maxSelectionCount: remainingAddSpotPhotoCount,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label("추가", systemImage: "plus")
                                    .vfText(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.primary)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 36)
                                    .vfGlass(in: Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("사진 추가")
                        }
                    }
                }

                addSpotPhotoPickerSection
            } else {
                HStack(alignment: .center, spacing: VFSpace.sm) {
                    Text("사진")
                        .vfText(.headline)
                        .foregroundStyle(AppColors.primary)

                    Spacer(minLength: VFSpace.sm)

                    HStack(spacing: 8) {
                        Text("\(communityPhotoCount) / \(Self.maxCommunityPhotoCount)")
                            .vfText(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .monospacedDigit()

                        if communityPhotoCount > 0,
                           communityPhotoCount < Self.maxCommunityPhotoCount {
                            PhotosPicker(
                                selection: $selectedPhotoItems,
                                maxSelectionCount: remainingCommunityPhotoCount,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label("추가", systemImage: "plus")
                                    .vfText(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.primary)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 36)
                                    .vfGlass(in: Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("사진 추가")
                        }
                    }
                }

                photoPickerSection
            }
        }
        .padding(.bottom, VFSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addSpotPhotoPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if addSpotPhotoCount == 0 {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: PlaceSubmissionService.maxPhotoCount,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    placePhotoPlaceholder
                }
                .buttonStyle(.plain)
                .accessibilityLabel("사진 추가")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(retainedRemoteAttachments.enumerated()), id: \.element.id) { index, attachment in
                            addSpotPhotoThumbnail(
                                isRepresentative: index == 0,
                                onRemove: { removePhoto(id: attachment.id) }
                            ) {
                                CommunityAttachedPhotoView(
                                    attachment: attachment,
                                    isTappableForPreview: false
                                )
                            }
                        }

                        ForEach(Array(photoDrafts.enumerated()), id: \.element.id) { index, draft in
                            addSpotPhotoThumbnail(
                                isRepresentative: retainedRemoteAttachments.isEmpty && index == 0,
                                onRemove: { removePhoto(id: draft.id) }
                            ) {
                                CommunityAttachedPhotoView(
                                    photoData: draft.data,
                                    isTappableForPreview: false
                                )
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if photoLoadFailed {
                Text("사진을 불러오지 못했어요. 다른 사진을 선택해주세요.")
                    .vfText(.caption)
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    private var placePhotoPlaceholder: some View {
        RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
            .fill(AppColors.mutedSurface)
            .aspectRatio(VFPhoto.carouselAspect, contentMode: .fit)
            .overlay {
                VStack(spacing: VFSpace.sm) {
                    Image(systemName: "photo")
                        .vfIcon(24, weight: .regular)

                    Text("사진을 추가하세요")
                        .vfText(.callout)
                }
                .foregroundStyle(AppColors.secondaryText)
            }
            .contentShape(RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous))
    }

    private func addSpotPhotoThumbnail<Content: View>(
        isRepresentative: Bool,
        onRemove: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            content()
                .frame(width: 178, height: 178)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.38), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("사진 제거")

            if isRepresentative {
                VStack {
                    Spacer()

                    HStack {
                        Text("대표")
                            .vfText(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.42), in: Capsule())

                        Spacer(minLength: 0)
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 178, height: 178)
    }

    private var captureLocationSection: some View {
        ComposerFormSection(
            title: "촬영 위치",
            detail: selectedCaptureLocation == nil
                ? "선택 사항 · EXIF GPS와 별개로 직접 추가"
                : "게시물에 함께 표시됩니다"
        ) {
            if let selectedCaptureLocation {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .vfIcon(17, weight: .medium)
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 38, height: 38)
                        .background(AppColors.accentSoft, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedCaptureLocation.name)
                            .vfText(.callout.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                            .lineLimit(1)

                        Text(selectedCaptureLocation.address ?? selectedCaptureLocation.region ?? "직접 추가한 촬영 위치")
                            .vfText(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Button {
                        self.selectedCaptureLocation = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.secondaryText.opacity(0.7))
                            .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("촬영 위치 제거")
                }
                .padding(.vertical, 2)
            } else {
                Button {
                    focusedField = nil
                    isCaptureLocationPickerPresented = true
                } label: {
                    Label("촬영 위치 추가", systemImage: "mappin.and.ellipse")
                        .vfText(.callout.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.touchTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var photoPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !photoDrafts.isEmpty || !retainedRemoteAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(retainedRemoteAttachments.enumerated()), id: \.element.id) { index, attachment in
                            addSpotPhotoThumbnail(
                                isRepresentative: index == 0,
                                onRemove: { removePhoto(id: attachment.id) }
                            ) {
                                CommunityAttachedPhotoView(
                                    attachment: attachment,
                                    isTappableForPreview: false
                                )
                            }
                        }

                        ForEach(Array(photoDrafts.enumerated()), id: \.element.id) { index, draft in
                            addSpotPhotoThumbnail(
                                isRepresentative: retainedRemoteAttachments.isEmpty && index == 0,
                                onRemove: { removePhoto(id: draft.id) }
                            ) {
                                CommunityAttachedPhotoView(
                                    photoData: draft.data,
                                    isTappableForPreview: false
                                )
                            }
                        }
                    }
                }

            } else {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: remainingCommunityPhotoCount,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    placePhotoPlaceholder
                }
                .buttonStyle(.plain)
                .accessibilityLabel("사진 추가")
            }

            if photoLoadFailed {
                Text("사진을 불러오지 못했어요. 다른 사진을 선택해주세요.")
                    .vfText(.caption)
                    .foregroundStyle(AppColors.primary)
            }

        }
    }

    private var submissionConsentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Button {
                hasAcknowledgedSubmissionGuidelines.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: hasAcknowledgedSubmissionGuidelines ? "checkmark.circle.fill" : "circle")
                        .vfIcon(19, relativeTo: .subheadline)

                    Text("사진 권리와 장소 등록 안내를 확인했어요")
                        .vfText(.subhead.weight(.semibold))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(hasAcknowledgedSubmissionGuidelines ? AppColors.primary : AppColors.secondaryText)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityValue(hasAcknowledgedSubmissionGuidelines ? "확인됨" : "확인 필요")
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var photoPrivacySection: some View {
        if !photoDrafts.isEmpty || !retainedRemoteAttachments.isEmpty {
            ComposerFormSection(
                title: "촬영정보",
                detail: ""
            ) {
                VStack(alignment: .leading, spacing: VFSpace.sm) {
                    Toggle("공개하기", isOn: $isExifPublic)
                        .tint(AppColors.accent)

                    if isExifPublic {
                        ForEach(photoDrafts) { draft in
                            CommunityComposerMetadataRow(
                                draft: draft,
                                onEdit: {
                                    metadataEditorTarget = MetadataEditorTarget(id: draft.id)
                                }
                            )
                        }

                        ForEach(retainedRemoteAttachments) { attachment in
                            CommunityComposerRemoteMetadataRow(
                                attachment: attachment,
                                onEdit: {
                                    metadataEditorTarget = MetadataEditorTarget(id: attachment.id)
                                }
                            )
                        }
                    } else {
                        Text("촬영정보는 게시물에 표시되지 않아요. 다시 켜면 입력한 정보가 복원됩니다.")
                            .vfText(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var placeGallerySharingSection: some View {
        if purpose == .fieldReport,
           selectedSpot != nil,
           !photoDrafts.isEmpty || !retainedRemoteAttachments.isEmpty {
            ComposerFormSection(
                title: "출사지 갤러리 공유",
                detail: ""
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("선택한 사진만 장소 상세 갤러리에 추가돼요.")
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)

                    ForEach(Array(retainedRemoteAttachments.enumerated()), id: \.element.id) { index, attachment in
                        galleryShareRow(
                            title: "사진 \(index + 1)",
                            isOn: galleryShareBinding(for: attachment.id)
                        ) {
                            CommunityAttachedPhotoView(
                                attachment: attachment,
                                isTappableForPreview: false
                            )
                        }
                    }

                    ForEach(Array(photoDrafts.enumerated()), id: \.element.id) { index, draft in
                        galleryShareRow(
                            title: "사진 \(retainedRemoteAttachments.count + index + 1)",
                            isOn: galleryShareBinding(for: draft.id)
                        ) {
                            CommunityAttachedPhotoView(
                                photoData: draft.data,
                                isTappableForPreview: false
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var communityCrowdSection: some View {
        if purpose == .fieldReport, selectedSpot != nil {
            ComposerFormSection(title: "현장 혼잡도", detail: "") {
                CommunityCrowdSelectionControl(selection: $selectedCommunityCrowd)
            }
        }
    }

    private func galleryShareRow<Content: View>(
        title: String,
        isOn: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                content()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))

                Text(title)
                    .vfText(.callout.weight(.medium))
                    .foregroundStyle(AppColors.primary)
            }
        }
        .tint(AppColors.accent)
        .frame(minHeight: AppLayout.touchTarget)
    }

    private func galleryShareBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                photoDrafts.first(where: { $0.id == id })?.sharesToPlaceGallery
                    ?? retainedRemoteAttachments.first(where: { $0.id == id })?.sharesToPlaceGallery
                    ?? false
            },
            set: { value in
                if let index = photoDrafts.firstIndex(where: { $0.id == id }) {
                    photoDrafts[index].sharesToPlaceGallery = value
                    return
                }

                guard let index = retainedRemoteAttachments.firstIndex(where: { $0.id == id }) else { return }
                let attachment = retainedRemoteAttachments[index]
                retainedRemoteAttachments[index] = CommunityPhotoAttachment(
                    id: attachment.id,
                    imageData: attachment.imageData,
                    remoteURL: attachment.remoteURL,
                    metadata: attachment.metadata,
                    location: attachment.location,
                    sharesToPlaceGallery: value
                )
            }
        )
    }

    private var selectedSpot: PhotoSpot? {
        if purpose == .fieldReport {
            guard !selectedSpotID.isEmpty else { return nil }

            if let selectedSearchedSpot,
               selectedSearchedSpot.id == selectedSpotID {
                return selectedSearchedSpot
            }

            return spots.first { $0.id == selectedSpotID }
        }

        if let editingPost,
           !editingPost.spotID.isEmpty,
           let spot = spots.first(where: { $0.id == editingPost.spotID }) {
            return spot
        }

        if (locksSelectedSpot || purpose.isPhotoContribution),
           let initialSpot {
            return initialSpot
        }

        if let selectedSearchedSpot {
            return selectedSearchedSpot
        }

        return spots.first { $0.id == selectedSpotID }
    }

    private var isSpotLocked: Bool {
        locksSelectedSpot || purpose.isPhotoContribution || (purpose == .addSpot && editingPost != nil)
    }

    private var canSubmit: Bool {
        guard !isPreparingSubmission, hasChanges else {
            return false
        }

        if purpose.isPhotoContribution {
            return selectedSpot != nil && addSpotPhotoCount > 0
        }

        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if purpose == .addSpot {
            guard selectedSpot != nil, !selectedSpotAlreadyRegistered else { return false }
            if editingPost == nil, !hasAcknowledgedSubmissionGuidelines {
                return false
            }
            return true
        }

        return true
    }

    private var hasChanges: Bool {
        guard let editingPost else {
            return true
        }

        let existingAttachments = editingPost.publicPhotoAttachments
        let existingPublicMetadata = Dictionary(
            existingAttachments.map { ($0.id, $0.metadata) },
            uniquingKeysWith: { _, latest in latest }
        )
        let currentPublicMetadata = Dictionary(
            (
                photoDrafts.map { ($0.id, isExifPublic ? $0.exif : nil) }
                + retainedRemoteAttachments.map { ($0.id, isExifPublic ? $0.metadata : nil) }
            ),
            uniquingKeysWith: { _, latest in latest }
        )
        let existingExifPublic = existingAttachments.contains { $0.metadata != nil }
        let exifChanged = isExifPublic != existingExifPublic
            || currentPublicMetadata != existingPublicMetadata
        let existingGalleryShares = Dictionary(
            existingAttachments.map { ($0.id, $0.sharesToPlaceGallery) },
            uniquingKeysWith: { _, latest in latest }
        )
        let currentGalleryShares = Dictionary(
            (
                photoDrafts.map { ($0.id, $0.sharesToPlaceGallery) }
                + retainedRemoteAttachments.map { ($0.id, $0.sharesToPlaceGallery) }
            ),
            uniquingKeysWith: { _, latest in latest }
        )
        let gallerySharingChanged = currentGalleryShares != existingGalleryShares
        let existingCrowd: CommunityPost.Crowd? = editingPost.hasStatusInfo ? editingPost.crowd : nil

        return title.trimmingCharacters(in: .whitespacesAndNewlines) != (editingPost.title ?? "")
            || message.trimmingCharacters(in: .whitespacesAndNewlines) != editingPost.message
            || (selectedSpot?.id ?? "") != editingPost.spotID
            || selectedCaptureLocation != editingPost.captureLocation
            || selectedCommunityCrowd != existingCrowd
            || selectedTags != Set(editingPost.tags)
            || photoDrafts.count + retainedRemoteAttachments.count != editingPost.publicPhotoAttachments.count
            || selectedPhotoData != editingPost.photoData
            || exifChanged
            || gallerySharingChanged
    }

    private var orderedSelectedTags: [String] {
        switch purpose {
        case .fieldReport:
            return statusTags.filter { selectedTags.contains($0) }
        case .addSpot:
            return customTags
        case .contributePhotos:
            return []
        }
    }

    private var communityPhotoCount: Int {
        photoDrafts.count + retainedRemoteAttachments.count
    }

    private var remainingCommunityPhotoCount: Int {
        max(Self.maxCommunityPhotoCount - communityPhotoCount, 0)
    }

    private var submitButtonTitle: String {
        if editingPost != nil {
            return "변경사항 저장"
        }

        switch purpose {
        case .fieldReport:
            return "공유하기"
        case .addSpot:
            return selectedSpotAlreadyRegistered ? "이미 등록된 장소" : "장소 추가하기"
        case .contributePhotos:
            return "사진 등록하기"
        }
    }

    private var selectedSpotAlreadyRegistered: Bool {
        guard purpose == .addSpot,
              let selectedSpot else {
            return false
        }

        return spots.contains { existing in
            PlaceIdentityMatcher.matches(
                PlaceIdentity(spot: selectedSpot),
                PlaceIdentity(spot: existing)
            )
        }
    }

    private var placeSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ═══════════════════════════════════════════════════════
            //  검색 버튼을 없앴습니다.
            //
            //  [문제였던 상황]
            //  장소명을 입력하고 오른쪽 화살표 버튼을 눌러야 결과가
            //  나왔습니다. 글을 쓰러 온 사람이 장소를 고르기까지
            //  입력 -> 버튼 -> 결과 확인 -> 선택 네 단계를 밟았습니다.
            //  지도 검색은 이미 입력하는 즉시 좁혀지는데, 같은 앱 안에서
            //  두 검색이 다르게 동작했습니다.
            //
            //  [지금]
            //  입력하는 즉시 아래에 결과가 뜨고, 누르면 바로 선택됩니다.
            //  로컬 시드(static 캐시)는 즉시 필터하고,
            //  원격 검색만 입력이 멈춘 뒤 350ms 후에 한 번 호출합니다.
            //  키 입력마다 네트워크를 때리지 않기 위해서입니다.
            // ═══════════════════════════════════════════════════════
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .vfIcon(15, weight: .medium)
                    .foregroundStyle(AppColors.secondaryText)

                TextField("장소명 또는 주소 검색", text: $placeSearchText)
                    .vfText(.callout)
                    .tint(AppColors.accent)
                    .focused($focusedField, equals: .placeSearch)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        // 확인을 누르면 첫 결과를 고릅니다.
                        guard let first = placeFinder.results.first else { return }
                        handlePlaceSearchResult(first)
                    }

                if !placeSearchText.isEmpty {
                    Button {
                        placeSearchText = ""
                        placeFinder.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.secondaryText.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))

            if let selectedSpot, !isSelectedPlaceResultVisible {
                if purpose == .fieldReport, !isSpotLocked {
                    Button {
                        clearRelatedSpotSelection()
                    } label: {
                        selectedPlaceRow(selectedSpot)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("관련 출사지 \(selectedSpot.name), 선택됨")
                    .accessibilityHint("다시 탭하면 선택을 해제합니다")
                    .padding(.top, 2)
                } else {
                    selectedPlaceRow(selectedSpot)
                        .padding(.top, 2)
                }
            }

            if !placeFinder.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(placeFinder.results) { result in
                        Button {
                            handlePlaceSearchResult(result)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: result.isKnown ? "camera.aperture" : "mappin.and.ellipse")
                                    // Dynamic Type 제외: 고정 28pt 폭 안의 결과 아이콘. 옆 글자의 세로 정렬 기준이다.
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.secondaryText)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .vfText(.callout)
                                        .foregroundStyle(AppColors.primary)
                                        .lineLimit(1)

                                    Text(result.category)
                                        .vfText(.caption.weight(.medium))
                                        .foregroundStyle(AppColors.secondaryText)
                                        .lineLimit(1)

                                    Text(result.address)
                                        .vfText(.caption)
                                        .foregroundStyle(AppColors.secondaryText)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                if let badgeTitle = result.availability.badgeTitle {
                                    Text(badgeTitle)
                                        .vfText(.caption.weight(.semibold))
                                        .foregroundStyle(AppColors.secondaryText)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppColors.mutedSurface, in: Capsule())
                                }

                                if purpose == .fieldReport,
                                   isSelectedPlaceSearchResult(result) {
                                    CommunityPlaceSelectionCheck()
                                }

                                if purpose != .fieldReport {
                                    Image(systemName: "chevron.right")
                                        .vfIcon(11, weight: .bold)
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                            }
                            .padding(.horizontal, 2)
                            .frame(minHeight: 70)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if result.id != placeFinder.results.last?.id {
                            Divider()
                                .overlay(AppColors.divider)
                                .padding(.leading, 40)
                        }
                    }
                }
            }

            // 로컬 결과가 먼저 보여도 네이버 실제 장소검색은 이어서 진행됩니다.
            // 그래서 결과가 이미 있어도 작은 진행 상태를 남깁니다.
            if placeFinder.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("장소를 찾는 중…")
                        .vfText(.caption)
                }
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("장소 검색 중")
            }

            if placeFinder.hasNoResults {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .vfIcon(14, relativeTo: .caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("검색 결과가 없습니다")
                            .vfText(.callout.weight(.medium))
                        Text("장소명이나 도로명 주소를 바꿔 다시 검색해보세요.")
                            .vfText(.caption)
                    }
                }
                .foregroundStyle(AppColors.secondaryText)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)

                if purpose == .addSpot {
                    Button {
                        focusedField = nil
                        isMapPlacePickerPresented = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .vfIcon(14, relativeTo: .caption)
                            Text("찾는 장소가 없나요? 지도에서 위치 지정")
                                .vfText(.caption.weight(.semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .vfIcon(10, weight: .bold)
                        }
                        .foregroundStyle(AppColors.primary)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.touchTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let placeSearchMessage = placeFinder.message {
                Text(placeSearchMessage)
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        if purpose.isPhotoContribution {
            guard let spot = selectedSpot,
                  purpose.photoContributionPlaceID == spot.id else { return }
        } else if purpose == .addSpot {
            guard selectedSpot != nil else { return }
        }

        let drafts = photoDrafts
        let retainedAttachments = retainedRemoteAttachments
        let shouldPublishExif = purpose == .fieldReport && isExifPublic
        let canShareToPlaceGallery = purpose == .fieldReport && selectedSpot != nil
        let submissionPurpose = purpose
        let submissionSpot = selectedSpot
        let submissionTitle = title
        let submissionLocation = selectedCaptureLocation
        let submissionCrowd = selectedCommunityCrowd
        let submissionPlaceCrowd = crowd
        let submissionTags = orderedSelectedTags
        let fallbackPhotoData = selectedPhotoData

        isPreparingSubmission = true
        submissionPreparationTask?.cancel()
        submissionPreparationTask = Task { @MainActor in
            let attachments = await Task.detached(priority: .userInitiated) {
                Self.makePublicAttachments(
                    drafts: drafts,
                    retainedAttachments: retainedAttachments,
                    shouldPublishExif: shouldPublishExif,
                    canShareToPlaceGallery: canShareToPlaceGallery
                )
            }.value

            guard !Task.isCancelled else {
                isPreparingSubmission = false
                return
            }

            if submissionPurpose.isPhotoContribution, let submissionSpot {
                onSubmit(
                    CommunityPostDraft(
                        spot: submissionSpot,
                        title: nil,
                        message: "",
                        photoAttachments: attachments
                    )
                )
            } else if submissionPurpose == .addSpot, let submissionSpot {
                onSubmit(
                    CommunityPostDraft(
                        spot: submissionSpot,
                        message: trimmedMessage,
                        crowd: submissionPlaceCrowd,
                        tags: submissionTags,
                        photoData: attachments.first?.imageData ?? fallbackPhotoData,
                        photoAttachments: attachments
                    )
                )
            } else {
                onSubmit(
                    CommunityPostDraft(
                        spot: submissionSpot,
                        title: submissionTitle,
                        captureLocation: submissionLocation,
                        message: trimmedMessage,
                        photoAttachments: attachments,
                        crowd: submissionCrowd
                    )
                )
            }

            isPreparingSubmission = false
            submissionPreparationTask = nil
            dismiss()
        }
    }

    private func schedulePlaceSearch(for rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            placeFinder.clear()
            return
        }

        placeFinder.search(
            query,
            near: nil,
            knownSpots: spots
        )
    }

    private func handlePlaceSearchResult(_ result: PlaceSearchResult) {
        if purpose == .fieldReport {
            // 관련 출사지는 새 Place를 생성하지 않고, 검색 결과의
            // stable ID/name만 게시글에 연결합니다. 등록된 결과는
            // 기존 Place Detail과 연결되고, 외부 결과도 자유 글의
            // 선택 정보로만 저장됩니다.
            if isSelectedPlaceSearchResult(result) {
                clearRelatedSpotSelection()
            } else {
                selectPlaceSearchResult(result, allowNonNewAvailability: true)
            }
            return
        }

        guard purpose == .addSpot else { return }

        switch result.availability {
        case .registered:
            placeFinder.clear()
            focusedField = nil
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                onShowRegisteredSpot(result.spot)
            }
        case .new:
            selectPlaceSearchResult(result)
        }
    }

    private func selectPlaceSearchResult(
        _ result: PlaceSearchResult,
        allowNonNewAvailability: Bool = false
    ) {
        guard allowNonNewAvailability || result.availability == .new else { return }
        // Community 관련 출사지 선택에서는 결과 목록을 유지해야
        // 선택한 row가 즉시 check 상태로 다시 그려지고, 같은 row를
        // 다시 눌러 해제하거나 다른 장소로 바꿀 수 있습니다.
        if purpose != .fieldReport {
            placeFinder.clear()
        }

        // PhotoSpot 은 이름·주소뿐 아니라 mapQuery와 위도/경도를 함께 가집니다.
        // 선택값을 그대로 draft 에 넘기므로 이후 Naver Map 마커도 같은 좌표를 씁니다.
        let spot = result.spot
        clearPlaceDependentOptions()
        selectedSearchedSpot = spot
        selectedSpotID = spot.id
        // 선택한 장소 이름을 검색창에 반영하되, 입력 이벤트로 같은 검색을
        // 다시 시작해 선택 목록이 즉시 덮어써지지 않도록 한 번 억제합니다.
        suppressPlaceSearch = true
        placeSearchText = result.name
        hasAcknowledgedSubmissionGuidelines = false
    }

    private func isSelectedPlaceSearchResult(_ result: PlaceSearchResult) -> Bool {
        purpose == .fieldReport && selectedSpotID == result.id
    }

    private var isSelectedPlaceResultVisible: Bool {
        guard purpose == .fieldReport, !selectedSpotID.isEmpty else { return false }
        return placeFinder.results.contains { $0.id == selectedSpotID }
    }

    private func clearRelatedSpotSelection() {
        selectedSearchedSpot = nil
        selectedSpotID = ""
        clearPlaceDependentOptions()
    }

    private func clearPlaceDependentOptions() {
        guard purpose == .fieldReport else { return }
        selectedCommunityCrowd = nil
        for index in photoDrafts.indices {
            photoDrafts[index].sharesToPlaceGallery = false
        }
        for index in retainedRemoteAttachments.indices {
            let attachment = retainedRemoteAttachments[index]
            retainedRemoteAttachments[index] = CommunityPhotoAttachment(
                id: attachment.id,
                imageData: attachment.imageData,
                remoteURL: attachment.remoteURL,
                metadata: attachment.metadata,
                location: attachment.location,
                sharesToPlaceGallery: false
            )
        }
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            let tag = normalizedTag(value)
            guard !tag.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
                return
            }
            result.append(tag)
        }
    }

    private static func normalizedTag(_ value: String) -> String {
        var tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") {
            tag.removeFirst()
        }
        return tag
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private func loadPhotos(from items: [PhotosPickerItem]) {
        photoLoadFailed = false
        guard !items.isEmpty else { return }

        Task {
            var loaded: [CommunityPhotoDraft] = []

            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let exif = purpose == .fieldReport
                        ? CommunityPhotoEXIFReader.inspect(data: data)?.exif
                        : nil
                    loaded.append(
                        CommunityPhotoDraft(
                            id: item.itemIdentifier ?? UUID().uuidString,
                            data: data,
                            exif: exif
                        )
                    )
                } catch {
                    await MainActor.run {
                        photoLoadFailed = true
                    }
                }
            }

            await MainActor.run {
                let previousIDs = Set(photoDrafts.map(\.id))
                if purpose.isPlaceSubmissionFlow {
                    var merged = photoDrafts
                    for draft in loaded where !merged.contains(where: {
                        $0.id == draft.id || $0.data == draft.data
                    }) {
                        merged.append(draft)
                    }

                    let availableSlots = max(
                        PlaceSubmissionService.maxPhotoCount - retainedRemoteAttachments.count,
                        0
                    )
                    photoDrafts = Array(merged.prefix(availableSlots))
                } else {
                    var merged = photoDrafts.filter { previousIDs.contains($0.id) }
                    for draft in loaded {
                        if let index = merged.firstIndex(where: { $0.id == draft.id }) {
                            merged[index] = draft
                        } else {
                            merged.append(draft)
                        }
                    }
                    photoDrafts = Array(merged.prefix(Self.maxCommunityPhotoCount))
                }

                selectedPhotoData = photoDrafts.first?.data
                selectedPhotoItems = []
                if purpose == .fieldReport {
                    promptForPrivacyIfNeeded(for: loaded)
                }
            }
        }
    }

    private func removePhoto(id: String) {
        retainedRemoteAttachments.removeAll { $0.id == id }
        photoDrafts.removeAll { $0.id == id }
        selectedPhotoData = photoDrafts.first?.data
        selectedPhotoItems = []
    }

    private var addSpotPhotoCount: Int {
        photoDrafts.count + retainedRemoteAttachments.count
    }

    private var remainingAddSpotPhotoCount: Int {
        max(PlaceSubmissionService.maxPhotoCount - addSpotPhotoCount, 0)
    }

    nonisolated private static func makePublicAttachments(
        drafts: [CommunityPhotoDraft],
        retainedAttachments: [CommunityPhotoAttachment],
        shouldPublishExif: Bool,
        canShareToPlaceGallery: Bool
    ) -> [CommunityPhotoAttachment] {
        let preservedAttachments = retainedAttachments.map { attachment in
            CommunityPhotoAttachment(
                id: attachment.id,
                imageData: nil,
                remoteURL: attachment.remoteURL,
                metadata: shouldPublishExif ? attachment.metadata : nil,
                location: nil,
                sharesToPlaceGallery: canShareToPlaceGallery && attachment.sharesToPlaceGallery
            )
        }
        let newAttachments = drafts.map { draft in
            draft.publicAttachment(
                exifVisibility: shouldPublishExif ? .publicInfo : .privateOnly,
                sharesToPlaceGallery: canShareToPlaceGallery && draft.sharesToPlaceGallery
            )
        }
        return preservedAttachments + newAttachments
    }

    private func promptForPrivacyIfNeeded(for drafts: [CommunityPhotoDraft]) {
        guard purpose == .fieldReport else { return }

        let newExifIDs = drafts.compactMap { draft -> String? in
            guard draft.exif != nil, !promptedExifPhotoIDs.contains(draft.id) else { return nil }
            return draft.id
        }
        promptedExifPhotoIDs.formUnion(newExifIDs)

        if !newExifIDs.isEmpty {
            showExifConsent = true
        }
    }

    private func metadata(for id: String) -> CommunityPhotoExif {
        photoDrafts.first(where: { $0.id == id })?.exif
            ?? retainedRemoteAttachments.first(where: { $0.id == id })?.metadata
            ?? .empty
    }

    private func updateMetadata(_ metadata: CommunityPhotoExif, for id: String) {
        let normalizedMetadata: CommunityPhotoExif? = metadata.isEmpty ? nil : metadata

        if let index = photoDrafts.firstIndex(where: { $0.id == id }) {
            photoDrafts[index].exif = normalizedMetadata
            return
        }

        guard let index = retainedRemoteAttachments.firstIndex(where: { $0.id == id }) else { return }
        let attachment = retainedRemoteAttachments[index]
        retainedRemoteAttachments[index] = CommunityPhotoAttachment(
            id: attachment.id,
            imageData: attachment.imageData,
            remoteURL: attachment.remoteURL,
            metadata: normalizedMetadata,
            location: attachment.location,
            sharesToPlaceGallery: attachment.sharesToPlaceGallery
        )
    }

    private static func drafts(
        from post: CommunityPost?,
        includeExif: Bool = true
    ) -> [CommunityPhotoDraft] {
        guard let post else { return [] }
        return post.publicPhotoAttachments.compactMap { attachment in
            guard let data = attachment.imageData else { return nil }
            return CommunityPhotoDraft(
                id: attachment.id,
                data: data,
                exif: includeExif ? attachment.metadata : nil,
                sharesToPlaceGallery: attachment.sharesToPlaceGallery
            )
        }
    }
}

private struct CommunityCrowdSelectionControl: View {
    @Binding var selection: CommunityPost.Crowd?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CommunityPost.Crowd.allCases) { crowd in
                VFCrowdLevelButton(
                    crowd: crowd,
                    isSelected: selection == crowd
                ) {
                    selection = selection == crowd ? nil : crowd
                }
            }
        }
    }
}

private struct CommunityComposerMetadataRow: View {
    let draft: CommunityPhotoDraft
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CommunityAttachedPhotoView(
                photoData: draft.data,
                cacheKey: draft.id,
                imageDetail: .thumbnail,
                isTappableForPreview: false
            )
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(draft.exif?.compactSummary ?? "촬영정보 추가")
                    .vfText(.caption)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Button("촬영정보 수정") {
                    onEdit()
                }
                .vfText(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
    }
}

private struct CommunityComposerRemoteMetadataRow: View {
    let attachment: CommunityPhotoAttachment
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CommunityAttachedPhotoView(attachment: attachment, isTappableForPreview: false)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.metadata?.compactSummary ?? "촬영정보 추가")
                    .vfText(.caption)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Button("촬영정보 수정") {
                    onEdit()
                }
                .vfText(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
    }
}

struct CommunityPhotoExifEditor: View {
    private enum Field: Hashable {
        case cameraMake
        case cameraModel
        case lensMake
        case lensModel
        case focalLength
        case focalLength35mm
        case aperture
        case exposure
        case iso
        case capturedAt
    }

    let initialMetadata: CommunityPhotoExif
    let onSave: (CommunityPhotoExif) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var cameraMake: String
    @State private var cameraModel: String
    @State private var lensMake: String
    @State private var lensModel: String
    @State private var focalLength: String
    @State private var focalLength35mm: String
    @State private var aperture: String
    @State private var exposure: String
    @State private var iso: String
    @State private var capturedAt: String

    init(
        initialMetadata: CommunityPhotoExif,
        onSave: @escaping (CommunityPhotoExif) -> Void
    ) {
        self.initialMetadata = initialMetadata
        self.onSave = onSave
        _cameraMake = State(initialValue: initialMetadata.cameraMake ?? "")
        _cameraModel = State(initialValue: initialMetadata.cameraModel ?? "")
        _lensMake = State(initialValue: initialMetadata.lensMake ?? "")
        _lensModel = State(initialValue: initialMetadata.lensModel ?? "")
        _focalLength = State(initialValue: Self.number(initialMetadata.focalLengthMillimeters))
        _focalLength35mm = State(initialValue: initialMetadata.focalLength35mm.map(String.init) ?? "")
        _aperture = State(initialValue: Self.number(initialMetadata.aperture))
        _exposure = State(initialValue: Self.exposureText(initialMetadata.exposureTime))
        _iso = State(initialValue: initialMetadata.iso.map(String.init) ?? "")
        _capturedAt = State(initialValue: initialMetadata.capturedAtDisplay ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("EXIF에서 읽은 값은 초기값으로만 사용됩니다. 게시물에 공개할 값은 직접 수정할 수 있어요.")
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    editorField("카메라 제조사", text: $cameraMake, field: .cameraMake, placeholder: "예: Fujifilm")
                    editorField("카메라 모델", text: $cameraModel, field: .cameraModel, placeholder: "예: X-M5")
                    editorField("렌즈 제조사", text: $lensMake, field: .lensMake, placeholder: "렌즈 제조사 추가")
                    editorField("렌즈 모델", text: $lensModel, field: .lensModel, placeholder: "예: XF 27mm F2.8")
                    editorField("초점거리", text: $focalLength, field: .focalLength, placeholder: "예: 27", keyboard: .decimalPad, suffix: "mm")
                    editorField("35mm 환산 초점거리", text: $focalLength35mm, field: .focalLength35mm, placeholder: "선택 사항", keyboard: .numberPad, suffix: "mm")
                    editorField("조리개", text: $aperture, field: .aperture, placeholder: "예: 2.8", keyboard: .decimalPad, prefix: "f/")
                    editorField("셔터스피드", text: $exposure, field: .exposure, placeholder: "예: 1/250s", keyboard: .numbersAndPunctuation)
                    editorField("ISO", text: $iso, field: .iso, placeholder: "예: 800", keyboard: .numberPad, prefix: "ISO ")
                    editorField("촬영일시", text: $capturedAt, field: .capturedAt, placeholder: "yyyy.MM.dd HH:mm")
                }
                .padding(.horizontal, 20)
                .padding(.top, VFSpace.md)
                .padding(.bottom, VFSpace.xl)
            }
            .background(AppColors.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusedField = nil
                }
            )
            .navigationTitle("촬영정보 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func editorField(
        _ title: String,
        text: Binding<String>,
        field: Field,
        placeholder: String,
        keyboard: UIKeyboardType = .default,
        prefix: String? = nil,
        suffix: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .vfText(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)

            HStack(spacing: 0) {
                if let prefix {
                    Text(prefix)
                        .vfText(.body)
                        .foregroundStyle(AppColors.secondaryText)
                }

                TextField(placeholder, text: text)
                    .vfText(.body)
                    .tint(AppColors.accent)
                    .keyboardType(keyboard)
                    .focused($focusedField, equals: field)

                if let suffix {
                    Text(suffix)
                        .vfText(.body)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(minHeight: 48)
            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))
        }
    }

    private func save() {
        onSave(
            CommunityPhotoExif(
                cameraMake: normalized(cameraMake),
                cameraModel: normalized(cameraModel),
                lensMake: normalized(lensMake),
                lensModel: normalized(lensModel),
                focalLengthMillimeters: Double(focalLength.cleanedNumeric),
                focalLength35mm: Int(focalLength35mm.cleanedNumeric),
                aperture: Double(aperture.cleanedNumeric),
                exposureTime: parsedExposure(exposure),
                iso: Int(iso.cleanedNumeric),
                capturedAt: parsedDate(capturedAt)
            )
        )
        dismiss()
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parsedExposure(_ value: String) -> Double? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "s", with: "")
        if trimmed.hasPrefix("1/"), let denominator = Double(trimmed.dropFirst(2)), denominator > 0 {
            return 1 / denominator
        }
        return Double(trimmed)
    }

    private func parsedDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy.MM.dd HH:mm", "yyyy.MM.dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return date
            }
        }
        return nil
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.4g", value)
    }

    private static func exposureText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        if value < 1 { return "1/\(Int((1 / value).rounded()))s" }
        return "\(number(value))s"
    }
}

private extension String {
    var cleanedNumeric: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "mm", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "f/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "ISO", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CommunityCaptureLocationPicker: View {
    let spots: [PhotoSpot]
    let onSelect: (CommunityCaptureLocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var placeFinder = PlaceFinder(resultLimit: 8)
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("등록된 출사지를 선택하거나 장소명·주소를 검색해 촬영 위치로만 추가할 수 있어요. 새 출사지로 등록되지는 않습니다.")
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("등록된 출사지")
                            .vfText(.headline)
                            .foregroundStyle(AppColors.primary)

                        LazyVStack(spacing: 0) {
                            ForEach(spots.prefix(12)) { spot in
                                locationRow(
                                    name: spot.name,
                                    detail: spot.region,
                                    icon: "camera.aperture"
                                ) {
                                    select(CommunityCaptureLocation(
                                        placeID: spot.id,
                                        name: spot.name,
                                        region: spot.region,
                                        address: spot.region
                                    ))
                                }
                            }
                        }
                    } else if placeFinder.results.isEmpty, !placeFinder.isSearching {
                        Text("검색 결과가 없습니다")
                            .vfText(.subhead)
                            .foregroundStyle(AppColors.secondaryText)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(placeFinder.results) { result in
                                locationRow(
                                    name: result.name,
                                    detail: result.address,
                                    icon: result.isKnown ? "camera.aperture" : "mappin.and.ellipse"
                                ) {
                                    select(CommunityCaptureLocation(
                                        placeID: result.isKnown ? result.spot.id : nil,
                                        name: result.name,
                                        region: result.spot.region,
                                        address: result.address
                                    ))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, VFSpace.md)
                .padding(.bottom, VFSpace.xl)
            }
            .background(AppColors.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query, prompt: "장소명 또는 주소 검색")
            .onChange(of: query) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    placeFinder.clear()
                } else {
                    placeFinder.search(trimmed, near: nil, knownSpots: spots)
                }
            }
            .navigationTitle("촬영 위치 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func locationRow(
        name: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .vfIcon(16, weight: .medium)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 34, height: 34)
                    .background(AppColors.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .vfText(.callout.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text(detail)
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .vfIcon(11, weight: .bold)
                    .foregroundStyle(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().overlay(AppColors.divider)
        }
    }

    private func select(_ location: CommunityCaptureLocation) {
        onSelect(location)
        dismiss()
    }
}

struct CommunityMapPlacePicker: View {
    let onSelect: (PhotoSpot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var coordinate = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    @State private var isResolvingAddress = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CommunityMapPickerRepresentable(coordinate: $coordinate)
                    .ignoresSafeArea()

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .padding(.bottom, 152)
                    .allowsHitTesting(false)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .vfIcon(16, weight: .medium)
                            .foregroundStyle(AppColors.accent)

                        Text("지도에서 촬영 위치를 지정하세요")
                            .vfText(.callout.weight(.semibold))
                            .foregroundStyle(AppColors.primary)

                        Spacer(minLength: 0)
                    }

                    Button {
                        resolveAndSelect()
                    } label: {
                        HStack(spacing: 8) {
                            if isResolvingAddress {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("이 위치로 계속")
                                .vfText(.headline)
                        }
                        .foregroundStyle(AppColors.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppColors.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolvingAddress)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("지도에서 위치 지정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func resolveAndSelect() {
        isResolvingAddress = true

        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            let addressParts = [
                placemark?.administrativeArea,
                placemark?.locality,
                placemark?.subLocality,
                placemark?.thoroughfare
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

            let address = addressParts.joined(separator: " ")
            let trimmedPlacemarkName = placemark?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedPlacemarkName?.isEmpty == false
                ? trimmedPlacemarkName!
                : "지도에서 지정한 촬영 포인트"
            let region = address.isEmpty ? "지도에서 지정한 위치" : address
            let stableID = "manual-\(Int((coordinate.latitude * 100_000).rounded()))-\(Int((coordinate.longitude * 100_000).rounded()))"

            let spot = PhotoSpot(
                id: stableID,
                name: name,
                region: region,
                summary: "지도에서 직접 지정한 촬영 포인트예요.",
                hashtags: ["촬영 포인트"],
                eventTitle: "사용자 지정 장소",
                eventPeriod: "상시",
                feeInfo: "확인 필요",
                openingHours: "확인 필요",
                bestTime: "현장 상황에 따라 확인",
                crowdLevel: "확인 필요",
                lensSuggestion: "선호 화각",
                weatherFit: "현장 상황 확인",
                parkingInfo: "확인 필요",
                nearbyParkingInfo: "확인 필요",
                communityTitle: "사용자 지정 장소",
                communitySubtitle: "장소 제보 전 임시 선택",
                mapQuery: "\(name) \(region)",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                theme: .viewpoint,
                category: "spot"
            )

            await MainActor.run {
                isResolvingAddress = false
                onSelect(spot)
                dismiss()
            }
        }
    }
}

private struct CommunityMapPickerRepresentable: UIViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(coordinate: $coordinate)
    }

    func makeUIView(context: Context) -> NMFNaverMapView {
        let naverMapView = NMFNaverMapView(frame: .zero)
        naverMapView.showLocationButton = false
        naverMapView.showZoomControls = false
        naverMapView.showCompass = false
        naverMapView.showScaleBar = false
        naverMapView.mapView.mapType = .basic
        naverMapView.mapView.isNightModeEnabled = colorScheme == .dark
        naverMapView.mapView.logoAlign = .leftBottom
        naverMapView.mapView.logoMargin = UIEdgeInsets(top: 0, left: 14, bottom: 8, right: 0)
        naverMapView.mapView.addCameraDelegate(delegate: context.coordinator)
        naverMapView.mapView.moveCamera(
            NMFCameraUpdate(
                scrollTo: NMGLatLng(lat: coordinate.latitude, lng: coordinate.longitude),
                zoomTo: 13
            )
        )
        return naverMapView
    }

    func updateUIView(_ naverMapView: NMFNaverMapView, context: Context) {
        naverMapView.mapView.isNightModeEnabled = colorScheme == .dark
    }

    final class Coordinator: NSObject, NMFMapViewCameraDelegate {
        private var coordinate: Binding<CLLocationCoordinate2D>

        init(coordinate: Binding<CLLocationCoordinate2D>) {
            self.coordinate = coordinate
            super.init()
        }

        func mapViewCameraIdle(_ mapView: NMFMapView) {
            let target = mapView.cameraPosition.target
            coordinate.wrappedValue = CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
//  폼 섹션

// ═══════════════════════════════════════════════════════════════════
//  폼 섹션
//
//  [바꾼 것]
//  1. "01 02 03 04" 번호를 뗐습니다.
//     번호는 정해진 순서를 끝까지 밟으라는 신호입니다. 관공서 서식의
//     언어이고, 사진을 올리러 온 사람에게 절차를 먼저 보여줍니다.
//     게다가 목적(현장 정보 / 새 장소)에 따라 섹션 순서와 개수가
//     달라지므로 번호가 매번 어긋났습니다.
//  2. 섹션마다 있던 Divider() 를 뗐습니다.
//     VFDesign 의 원칙은 "기본 그룹핑 수단은 여백" 입니다.
//     구분선 4개가 짧은 폼을 표처럼 만들었습니다.
// ═══════════════════════════════════════════════════════════════════

struct ComposerFormSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)

                if !detail.isEmpty {
                    Text(detail)
                        .vfText(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            content
        }
        .padding(.bottom, VFSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CrowdSelector: View {
    @Binding var selectedCrowd: CommunityPost.Crowd

    var body: some View {
        HStack(spacing: VFSpace.sm) {
            ForEach(CommunityPost.Crowd.allCases) { item in
                Button {
                    VFHaptics.selection()
                    selectedCrowd = item
                } label: {
                    // 선택 상태를 앰버로 바꿨습니다.
                    // 전에는 AppColors.primary 였는데 다크에서 그 값은 흰색이라
                    // 선택된 칸이 흰 판이 되어 화면에서 가장 밝은 요소가 됐습니다.
                    // 칩 선택은 VFDesign 이 앰버를 허용한 자리입니다.
                        Text(item.displayName)
                        .vfText(.callout)
                        .foregroundStyle(selectedCrowd == item ? AppColors.onAccent : AppColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .frame(minHeight: AppLayout.touchTarget)
                        .background(
                            selectedCrowd == item ? AppColors.accent : AppColors.mutedSurface,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("혼잡도 \(item.displayName)")
                .accessibilityValue(selectedCrowd == item ? "선택됨" : "")
            }
        }
        .animation(VFMotion.quick, value: selectedCrowd)
    }
}

struct FlexibleTagGrid: View {
    let tags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 7)], spacing: 7) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    if selectedTags.contains(tag) {
                        selectedTags.remove(tag)
                    } else {
                        selectedTags.insert(tag)
                    }
                } label: {
                    Text(tag)
                        .vfText(.caption)
                        .foregroundStyle(selectedTags.contains(tag) ? AppColors.onAccent : AppColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .frame(minHeight: 38)
                        .background(
                            selectedTags.contains(tag) ? AppColors.accent : AppColors.mutedSurface,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CustomTagInputSection: View {
    @Binding var tags: [String]
    @Binding var text: String

    private let maxTagCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "number")
                    .vfIcon(15)
                    .foregroundStyle(AppColors.secondaryText)

                TextField("예: 야경, 한강, 필름감성", text: $text)
                    .vfText(.callout.weight(.regular))
                    .submitLabel(.done)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addTagsFromInput)
                    .onChange(of: text) { _, newValue in
                        guard newValue.contains(",") || newValue.contains("\n") else { return }
                        addTagsFromInput()
                    }

                Button(action: addTagsFromInput) {
                    Image(systemName: "plus")
                        // Dynamic Type 제외: 고정 32pt 태그 추가 버튼. 프레임이 안 커지므로 기호도 안 커진다.
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canAddTag ? AppColors.primary : AppColors.secondaryText.opacity(0.45))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAddTag)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))

            if !tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 7)], spacing: 7) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            remove(tag)
                        } label: {
                            HStack(spacing: 5) {
                                Text("#\(tag)")
                                    .lineLimit(1)

                                Image(systemName: "xmark")
                                    .vfIcon(9, weight: .bold, relativeTo: .caption)
                            }
                            .vfText(.caption)
                            .foregroundStyle(AppColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .frame(minHeight: 38)
                            .background(AppColors.mutedSurface, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var canAddTag: Bool {
        !parsedTags(from: text).isEmpty && tags.count < maxTagCount
    }

    private func addTagsFromInput() {
        let newTags = parsedTags(from: text)
        guard !newTags.isEmpty else {
            text = ""
            return
        }

        var nextTags = tags
        for tag in newTags {
            guard nextTags.count < maxTagCount,
                  !nextTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
                continue
            }
            nextTags.append(tag)
        }

        tags = nextTags
        text = ""
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    private func parsedTags(from value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map(normalizedTag)
            .filter { !$0.isEmpty && $0.count <= 20 }
    }

    private func normalizedTag(_ value: String) -> String {
        var tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") {
            tag.removeFirst()
        }
        return tag
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}

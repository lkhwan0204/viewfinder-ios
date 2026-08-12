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
    private var feedPosts: [CommunityPost] {
        posts.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if posts.isEmpty {
                    EmptyCommunityView()
                        .padding(.top, VFSpace.xl)
                        .vfScreenMargin()
                } else {
                    // 사진 사이 간격을 넓게 둡니다.
                    // 카드 표면이 없어졌으므로 글과 글을 나누는 유일한 수단이
                    // 여백입니다. 12pt 로는 앞 글의 액션 줄과 다음 글의
                    // 작성자 줄이 한 덩어리로 읽힙니다.
                    LazyVStack(alignment: .leading, spacing: VFSpace.xl) {
                        ForEach(feedPosts) { post in
                            CommunityPostCard(
                                post: post,
                                spot: spot(for: post),
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
                                onSelectSpot: onSelectSpot
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
                    .accessibilityLabel("현장 정보 작성")
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

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        spots.first { $0.id == post.spotID }
    }
}

struct CommunityPostCard: View {
    let post: CommunityPost
    let spot: PhotoSpot?
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
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            authorLine

            NavigationLink {
                detailView(focusCommentComposer: false)
            } label: {
                photoWithPlaceName
            }
            .buttonStyle(.plain)

            VFCrowdBadge(level: VFCrowdLevel.from(post.crowd.rawValue))

            if !post.message.isEmpty {
                Text(post.message)
                    .vfText(.body)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 사진 + 사진 위 장소 이름.
    ///
    /// 장소 이름만 올립니다. 혼잡도까지 사진 위에 얹으면
    /// 상세 화면에서 걷어낸 문제("사진 위에 또 현장정보")를 반복하게 됩니다.
    /// 혼잡도는 사진 아래 자기 줄을 가집니다.
    @ViewBuilder
    private var photoWithPlaceName: some View {
        ZStack(alignment: .bottomLeading) {
            if let photoData = post.photoData {
                CommunityAttachedPhotoView(
                    photoData: photoData,
                    aspectRatio: VFPhoto.carouselAspect,
                    showsScrim: true,
                    isTappableForPreview: false
                )
            } else if let spot {
                VFPhotoTile(
                    spot: spot,
                    aspectRatio: VFPhoto.carouselAspect,
                    showsScrim: true
                )
            } else {
                RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
                    .fill(AppColors.mutedSurface)
                    .aspectRatio(VFPhoto.carouselAspect, contentMode: .fit)
            }

            Text(post.spotName)
                .vfText(.title2)
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                .padding(VFSpace.md)
        }
    }

    private var authorLine: some View {
        HStack(alignment: .center, spacing: VFSpace.sm) {
            CommunityAuthorAvatar(authorName: post.authorName, size: 28)

            Text(post.authorName)
                .vfText(.caption)
                .foregroundStyle(AppColors.primary)
                .lineLimit(1)

            VFMetaLine(
                items: post.updatedAt == nil
                    ? [communityRelativeTimeText(for: post.createdAt)]
                    : [communityRelativeTimeText(for: post.createdAt), "수정됨"]
            )

            Spacer(minLength: 4)

            if post.authorID != currentUserID {
                Button {
                    onToggleFollow(post)
                } label: {
                    // 앰버를 쓰지 않습니다.
                    // 피드에 글이 여러 개면 화면에 앰버 팔로우 버튼이
                    // 그만큼 깔립니다. "화면당 2곳 이하" 규칙이 깨지고,
                    // 좋아요한 하트의 앰버가 묻힙니다.
                    Text(isFollowing ? "팔로잉" : "팔로우")
                        .vfText(.caption)
                        .foregroundStyle(isFollowing ? AppColors.secondaryText : AppColors.primary)
                        .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFollowing ? "팔로우 취소" : "팔로우")
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: 32, height: 32)
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
            currentUserID: currentUserID,
            isLiked: isLiked,
            likeCount: likeCount,
            isFollowing: isFollowing,
            comments: comments,
            focusCommentComposerOnAppear: focusCommentComposer,
            onToggleLike: onToggleLike,
            onToggleFollow: onToggleFollow,
            onAddComment: onAddComment,
            onSelectSpot: onSelectSpot
        )
    }
}

private struct CommunityAuthorAvatar: View {
    let authorName: String
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .frame(width: size, height: size)
            .background(avatarColor, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            }
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

private struct CommunityPostDetailView: View {
    let post: CommunityPost
    let spot: PhotoSpot?
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

    @State private var draft = ""
    @FocusState private var isCommentFieldFocused: Bool
    private let commentComposerAnchorID = "community-comment-composer"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    authorHeader
                    placeTitle

                    Text(post.message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let photoData = post.photoData {
                        CommunityAttachedPhotoView(photoData: photoData, height: 280)
                    }

                    detailActionRow(proxy: proxy)

                    Rectangle()
                        .fill(AppColors.divider)
                        .frame(height: 1)

                    commentSection

                    Color.clear
                        .frame(height: 1)
                        .id(commentComposerAnchorID)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) {
                commentComposer
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("게시글")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard focusCommentComposerOnAppear else { return }
                focusCommentComposer(using: proxy)
            }
        }
    }

    private var authorHeader: some View {
        HStack(spacing: 10) {
            CommunityAuthorAvatar(authorName: post.authorName)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.primary)

                Text(communityRelativeTimeText(for: post.createdAt))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)

            if post.authorID != currentUserID {
                Button {
                    onToggleFollow(post)
                } label: {
                    Text(isFollowing ? "팔로잉" : "팔로우")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isFollowing ? AppColors.secondaryText : AppColors.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var placeTitle: some View {
        if let spot {
            Button {
                onSelectSpot(spot)
            } label: {
                placeTitleText
            }
            .buttonStyle(.plain)
        } else {
            placeTitleText
        }
    }

    private var placeTitleText: some View {
        Text(post.spotName)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailActionRow(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 22) {
            Button {
                onToggleLike(post)
            } label: {
                Label("\(likeCount)", systemImage: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? communityLikeTint : AppColors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? "좋아요 취소" : "좋아요")

            Button {
                focusCommentComposer(using: proxy)
            } label: {
                Label("댓글 \(comments.count)", systemImage: "bubble.left")
                    .foregroundStyle(AppColors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("댓글 작성")

            ShareLink(item: shareText) {
                Label("공유", systemImage: "square.and.arrow.up")
                    .foregroundStyle(AppColors.secondaryText)
            }
            .accessibilityLabel("공유")
        }
        .font(.system(size: 14, weight: .semibold))
    }

    @ViewBuilder
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("댓글 \(comments.count)")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColors.primary)

            if comments.isEmpty {
                Text("첫 댓글을 남겨보세요.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
            } else {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(comment.authorName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppColors.primary)

                            Text(communityRelativeTimeText(for: comment.createdAt))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                        }

                        Text(comment.message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var commentComposer: some View {
        HStack(spacing: 10) {
            TextField("댓글 추가...", text: $draft)
                .font(.system(size: 14, weight: .medium))
                .focused($isCommentFieldFocused)
                .submitLabel(.send)
                .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(AppColors.primary)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(AppColors.cardBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 1)
        }
    }

    private var shareText: String {
        "\(post.authorName)님의 출사지 정보\n\(post.spotName)\n\(post.message)"
    }

    private func submit() {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        if onAddComment(trimmedDraft, post) {
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

struct CommunityInlinePostCard: View {
    let post: CommunityPost
    let currentUserID: String
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommunityPostMetaHeader(post: post)

            Text(post.message)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(AppColors.primary.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            CommunityStatusRow(crowd: post.crowd, tags: communityDisplayTags(post.tags, excluding: nil, crowd: post.crowd, limit: 2))

            if let photoData = post.photoData {
                CommunityAttachedPhotoView(photoData: photoData, height: 92, maxWidth: 178)
            }

            if post.authorID == currentUserID {
                CommunityPostOwnerActions(post: post, onEdit: onEdit, onDelete: onDelete)
            }
        }
        .padding(12)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.divider.opacity(0.7), lineWidth: 1)
        )
    }
}

struct CommunityPostMetaHeader: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 7) {
                Text(post.authorName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.primary.opacity(0.78))
                    .lineLimit(1)

                Text("·")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.secondaryText.opacity(0.65))

                Text(communityRelativeTimeText(for: post.createdAt))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)

                if post.updatedAt != nil {
                    Text("수정됨")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.65))
                }

                Spacer(minLength: 0)
            }

            Text(communityWrittenTimeText(for: post.createdAt))
                .font(.system(size: 11, weight: .semibold))
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
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(crowd.tint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(crowd.fill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(crowd.tint.opacity(0.16), lineWidth: 1)
            )
    }
}

private func communityDisplayTags(
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.primary.opacity(0.72))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
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
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onDelete(post)
            } label: {
                Label("삭제", systemImage: "trash")
                    .font(.system(size: 11, weight: .bold))
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
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func image(from data: Data) -> UIImage? {
        let key = "\(data.count)-\(data.hashValue)" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }
}

struct CommunityAttachedPhotoView: View {
    let photoData: Data
    /// 고정 높이. 비율을 쓰려면 nil 로 두고 aspectRatio 를 지정합니다.
    var height: CGFloat?
    var maxWidth: CGFloat?
    /// 가로 세로 비율. 피드에서는 VFPhoto.carouselAspect(3:2)를 씁니다.
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

    @State private var isPreviewPresented = false

    var body: some View {
        if let image = CommunityPhotoDecoder.image(from: photoData) {
            if isTappableForPreview {
                Button {
                    isPreviewPresented = true
                } label: {
                    photo(image)
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $isPreviewPresented) {
                    CommunityPhotoPreview(photoData: photoData)
                }
            } else {
                photo(image)
            }
        }
    }

    private func photo(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: maxWidth ?? .infinity)
            .modifier(CommunityPhotoSizing(height: height, aspectRatio: aspectRatio))
            .clipped()
            .overlay {
                if showsScrim {
                    VFScrim(edge: .bottom, strength: 1.0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 고정 높이와 비율 중 하나만 적용합니다.
private struct CommunityPhotoSizing: ViewModifier {
    let height: CGFloat?
    let aspectRatio: CGFloat?

    func body(content: Content) -> some View {
        if let aspectRatio {
            content.aspectRatio(aspectRatio, contentMode: .fill)
        } else if let height {
            content.frame(height: height)
        } else {
            content
        }
    }
}

struct CommunityPhotoPreview: View {
    let photoData: Data
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(AppColors.cardBackground.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
    }
}

struct EmptyCommunityView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(AppColors.secondaryText)

            Text("아직 올라온 현장 정보가 없어요")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Text("첫 현장 정보를 남겨보세요.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.vertical, 54)
        .frame(maxWidth: .infinity)
    }
}

enum CommunityComposerPurpose: Equatable {
    case fieldReport
    case addSpot

    var navigationTitle: String {
        switch self {
        case .fieldReport:
            return "현장 정보"
        case .addSpot:
            return "장소 추가"
        }
    }

    var messageSectionTitle: String {
        switch self {
        case .fieldReport:
            return "현재 상황"
        case .addSpot:
            return "추천 이유"
        }
    }

    var messagePlaceholder: String {
        switch self {
        case .fieldReport:
            return "예: 현재 공사 중이에요 / 주차장이 만차예요 / 노을 보기 좋아요"
        case .addSpot:
            return "예: 저녁빛이 좋은 골목이고 오래된 간판이 많아 필름 사진에 잘 어울려요"
        }
    }
}

struct CommunityComposerView: View {
    let spots: [PhotoSpot]
    let initialSpot: PhotoSpot?
    let locksSelectedSpot: Bool
    let editingPost: CommunityPost?
    let purpose: CommunityComposerPurpose
    let onSubmit: (CommunityPostDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSpotID: String
    @State private var selectedSearchedSpot: PhotoSpot?
    @State private var placeSearchText: String
    @State private var placeSearchResults: [VerifiedPhotoSpot] = []
    @State private var isPlaceSearching = false
    @State private var placeSearchMessage: String?
    @State private var message = ""
    @State private var crowd: CommunityPost.Crowd = .normal
    @State private var selectedTags: Set<String> = []
    @State private var customTags: [String]
    @State private var customTagText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var photoLoadFailed = false
    @State private var hasAcknowledgedSubmissionGuidelines = false

    private let statusTags = ["노을 좋음", "꽃 만개", "안개 있음", "사람 적음", "야경 좋음", "사진 찍기 좋음", "비 분위기 좋음", "반영 예쁨", "단풍 절정", "조명 좋음"]
    private let placeSearchService = PlaceSearchService()

    init(
        spots: [PhotoSpot],
        selectedSpot: PhotoSpot?,
        locksSelectedSpot: Bool = false,
        editingPost: CommunityPost? = nil,
        purpose: CommunityComposerPurpose = .fieldReport,
        onSubmit: @escaping (CommunityPostDraft) -> Void
    ) {
        self.spots = spots
        self.initialSpot = selectedSpot
        self.locksSelectedSpot = locksSelectedSpot
        self.editingPost = editingPost
        self.purpose = purpose
        self.onSubmit = onSubmit
        _selectedSpotID = State(initialValue: editingPost?.spotID ?? selectedSpot?.id ?? "")
        _selectedSearchedSpot = State(initialValue: nil)
        _placeSearchText = State(initialValue: editingPost?.spotName ?? selectedSpot?.name ?? "")
        _message = State(initialValue: editingPost?.message ?? "")
        _crowd = State(initialValue: editingPost?.crowd ?? .normal)
        _selectedTags = State(initialValue: Set(editingPost?.tags ?? []))
        _customTags = State(initialValue: purpose == .addSpot ? Self.normalizedTags(editingPost?.tags ?? []) : [])
        _customTagText = State(initialValue: "")
        _selectedPhotoData = State(initialValue: editingPost?.photoData)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ComposerFormSection(
                        number: "01",
                        title: "장소",
                        detail: isSpotLocked ? "선택된 출사지" : placeSectionDetail
                    ) {
                        if isSpotLocked, let selectedSpot {
                            selectedPlaceRow(selectedSpot)
                        } else {
                            placeSearchSection
                        }
                    }

                    if selectedSpot != nil {
                        ComposerFormSection(
                            number: sectionNumber(2),
                            title: purpose.messageSectionTitle,
                            detail: messageSectionDetail
                        ) {
                            TextField(purpose.messagePlaceholder, text: $message, axis: .vertical)
                                .font(.system(size: 16, weight: .regular))
                                .lineSpacing(4)
                                .lineLimit(5, reservesSpace: true)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(
                                    AppColors.mutedSurface,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.divider, lineWidth: 1)
                                }
                        }

                        if purpose == .fieldReport || editingPost != nil {
                            ComposerFormSection(
                                number: sectionNumber(3),
                                title: "현장 상태",
                                detail: "현재 혼잡도와 상태를 선택하세요"
                            ) {
                                CrowdSelector(selectedCrowd: $crowd)
                                    .padding(.bottom, 14)
                                FlexibleTagGrid(tags: statusTags, selectedTags: $selectedTags)
                            }
                        } else {
                            ComposerFormSection(
                                number: sectionNumber(3),
                                title: "태그",
                                detail: "직접 입력한 해시태그가 홈 검색에 반영돼요"
                            ) {
                                CustomTagInputSection(tags: $customTags, text: $customTagText)
                            }
                        }

                        ComposerFormSection(
                            number: sectionNumber(4),
                            title: "사진",
                            detail: photoSectionDetail
                        ) {
                            photoPickerSection
                        }

                        if purpose == .addSpot, editingPost == nil {
                            submissionConsentSection
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .semibold))
                            Text(emptySelectionText)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                    }
                }
                .padding(.horizontal, 20)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(editingPost == nil ? purpose.navigationTitle : "현장 정보 수정")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerSubmitBar
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                loadPhoto(from: newItem)
            }
        }
    }

    private var composerSubmitBar: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                submit()
            } label: {
                Text(submitButtonTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSubmit ? AppColors.background : AppColors.secondaryText.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        canSubmit ? AppColors.primary : AppColors.mutedSurface,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 38, height: 38)
                    .background(AppColors.mutedSurface, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text(spot.region)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.background)
                    .frame(width: 26, height: 26)
                    .background(AppColors.primary, in: Circle())
            }

            if purpose == .addSpot, selectedSpotAlreadyRegistered {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selectedRegisteredSpotNeedsPhoto ? "photo.badge.plus" : "checkmark.seal")
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        selectedRegisteredSpotNeedsPhoto
                            ? "등록된 장소지만 대표 사진이 비어 있어요. 직접 촬영한 사진을 제보할 수 있어요."
                            : "이미 등록된 장소예요. 중복 등록 대신 커뮤니티에서 현장 정보를 남겨주세요."
                    )
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AppColors.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 2)
    }

    private var photoPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedPhotoData {
                ZStack(alignment: .topTrailing) {
                    CommunityAttachedPhotoView(photoData: selectedPhotoData, height: 220)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.68), in: Circle())
                    }
                    .padding(10)
                }

                Button {
                    self.selectedPhotoData = nil
                    selectedPhotoItem = nil
                } label: {
                    Label("사진 제거", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .buttonStyle(.plain)
            } else {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 23, weight: .regular))

                        Text("사진 선택")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 122)
                    .background(AppColors.mutedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                AppColors.divider,
                                style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            if photoLoadFailed {
                Text("사진을 불러오지 못했어요. 다른 사진을 선택해주세요.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.primary)
            }

        }
    }

    private var submissionConsentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("등록한 장소와 사진은 검토를 마친 뒤 공개됩니다.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)

            Button {
                hasAcknowledgedSubmissionGuidelines.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: hasAcknowledgedSubmissionGuidelines ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19, weight: .semibold))

                    Text("사진 권리와 등록 검토 안내를 확인했어요")
                        .font(.system(size: 14, weight: .semibold))

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

    private var selectedSpot: PhotoSpot? {
        if let editingPost,
           let spot = spots.first(where: { $0.id == editingPost.spotID }) {
            return spot
        }

        if locksSelectedSpot,
           let initialSpot {
            return initialSpot
        }

        if let selectedSearchedSpot {
            return registeredSpot(matching: selectedSearchedSpot) ?? selectedSearchedSpot
        }

        return spots.first { $0.id == selectedSpotID }
    }

    private var isSpotLocked: Bool {
        locksSelectedSpot || editingPost != nil
    }

    private var canSubmit: Bool {
        guard selectedSpot != nil,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hasChanges else {
            return false
        }

        if purpose == .addSpot,
           editingPost == nil,
           !hasAcknowledgedSubmissionGuidelines {
            return false
        }

        guard purpose == .addSpot, selectedSpotAlreadyRegistered else {
            return true
        }

        return selectedRegisteredSpotNeedsPhoto && selectedPhotoData != nil
    }

    private var hasChanges: Bool {
        guard let editingPost else {
            return true
        }

        return message.trimmingCharacters(in: .whitespacesAndNewlines) != editingPost.message
            || crowd != editingPost.crowd
            || selectedTags != Set(editingPost.tags)
            || selectedPhotoData != editingPost.photoData
    }

    private var orderedSelectedTags: [String] {
        switch purpose {
        case .fieldReport:
            return statusTags.filter { selectedTags.contains($0) }
        case .addSpot:
            return customTags
        }
    }

    private var placeSectionDetail: String {
        switch purpose {
        case .fieldReport:
            return "현장 정보를 남길 출사지를 검색하세요"
        case .addSpot:
            return "추가할 실제 장소를 검색하세요"
        }
    }

    private var messageSectionDetail: String {
        switch purpose {
        case .fieldReport:
            return "지금 현장에서 확인한 내용을 남겨주세요"
        case .addSpot:
            return "왜 출사지로 좋은지 짧게 설명해주세요"
        }
    }

    private var photoSectionDetail: String {
        switch purpose {
        case .fieldReport:
            return "현장 분위기가 잘 보이는 사진을 선택하세요"
        case .addSpot:
            return selectedRegisteredSpotNeedsPhoto
                ? "이 장소에 표시할 직접 촬영 대표 사진을 선택하세요"
                : "출사지 분위기가 잘 보이는 대표 사진을 선택하세요"
        }
    }

    private var emptySelectionText: String {
        switch purpose {
        case .fieldReport:
            return "장소를 선택하면 다음 항목이 표시됩니다."
        case .addSpot:
            return "실제 장소를 검색해서 선택하면 등록 항목이 표시됩니다."
        }
    }

    private var submitButtonTitle: String {
        if editingPost != nil {
            return "변경사항 저장"
        }

        switch purpose {
        case .fieldReport:
            return "공유하기"
        case .addSpot:
            if selectedRegisteredSpotNeedsPhoto {
                return "사진 검토 요청 보내기"
            }
            return selectedSpotAlreadyRegistered ? "이미 등록된 장소" : "검토 요청 보내기"
        }
    }

    private func sectionNumber(_ base: Int) -> String {
        base < 10 ? "0\(base)" : "\(base)"
    }

    private var selectedSpotAlreadyRegistered: Bool {
        guard purpose == .addSpot,
              let selectedSpot else {
            return false
        }

        let selectedKey = normalizedPlaceKey(selectedSpot)
        return spots.contains { existing in
            existing.id == selectedSpot.id
                || existing.mapQuery == selectedSpot.mapQuery
                || normalizedPlaceKey(existing) == selectedKey
        }
    }

    private var selectedRegisteredSpotNeedsPhoto: Bool {
        selectedSpotAlreadyRegistered && selectedSpot?.hasReliableDisplayImage == false
    }

    private func registeredSpot(matching candidate: PhotoSpot) -> PhotoSpot? {
        let candidateKey = normalizedPlaceKey(candidate)
        return spots.first { existing in
            existing.id == candidate.id
                || existing.mapQuery == candidate.mapQuery
                || normalizedPlaceKey(existing) == candidateKey
        }
    }

    private func normalizedPlaceKey(_ spot: PhotoSpot) -> String {
        "\(spot.name)-\(spot.region)-\(spot.mapQuery)"
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
    }

    private var placeSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)

                    TextField("장소명 또는 주소 검색", text: $placeSearchText)
                        .font(.system(size: 15, weight: .regular))
                        .submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(startPlaceSearch)

                    if !placeSearchText.isEmpty {
                        Button {
                            placeSearchText = ""
                            placeSearchResults = []
                            placeSearchMessage = nil
                            selectedSearchedSpot = nil
                            selectedSpotID = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColors.secondaryText.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 48)
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.divider, lineWidth: 1)
                }

                Button(action: startPlaceSearch) {
                    Group {
                        if isPlaceSearching {
                            ProgressView()
                                .controlSize(.small)
                                .tint(AppColors.background)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundStyle(AppColors.background)
                    .frame(width: 48, height: 48)
                    .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(
                    placeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isPlaceSearching
                )
            }

            if let selectedSpot {
                selectedPlaceRow(selectedSpot)
                    .padding(.top, 2)
            }

            if !placeSearchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(placeSearchResults) { result in
                        Button {
                            selectPlaceSearchResult(result)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "location")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.primary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppColors.primary)
                                        .lineLimit(1)

                                    Text(result.address)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppColors.secondaryText)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            .padding(.horizontal, 2)
                            .frame(minHeight: 62)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if result.id != placeSearchResults.last?.id {
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
            }

            if let placeSearchMessage {
                Text(placeSearchMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func submit() {
        guard canSubmit, let spot = selectedSpot else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        onSubmit(
            CommunityPostDraft(
                spot: spot,
                message: trimmedMessage,
                crowd: crowd,
                tags: orderedSelectedTags,
                photoData: selectedPhotoData
            )
        )
        dismiss()
    }

    private func startPlaceSearch() {
        let query = placeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isPlaceSearching else { return }

        selectedSearchedSpot = nil
        selectedSpotID = ""
        placeSearchResults = []
        placeSearchMessage = nil
        isPlaceSearching = true

        Task {
            do {
                let remoteResults = try await placeSearchService.search(query: query, userLocation: nil)
                let localResults = LocalSeedDataService().verifiedSpots(matching: query, limit: 6)
                let results = mergedPlaceResults(remoteResults + localResults)

                await MainActor.run {
                    placeSearchResults = results
                    placeSearchMessage = results.isEmpty ? "검색 결과가 없어요. 장소명이나 지역명을 함께 입력해보세요." : nil
                    isPlaceSearching = false
                }
            } catch {
                let localResults = LocalSeedDataService().verifiedSpots(matching: query, limit: 6)
                let searchErrorMessage = placeSearchFailureMessage(for: error, hasLocalResults: !localResults.isEmpty)
                await MainActor.run {
                    placeSearchResults = localResults
                    placeSearchMessage = searchErrorMessage
                    isPlaceSearching = false
                }
            }
        }
    }

    private func placeSearchFailureMessage(for error: Error, hasLocalResults: Bool) -> String {
        let message = error.localizedDescription

        if message.contains("네이버 실제 장소검색 설정") {
            return hasLocalResults
                ? "네이버 실제 장소검색 설정이 필요해 등록된 출사지를 먼저 보여드려요."
                : "네이버 실제 장소검색 설정이 아직 완료되지 않았어요."
        }

        return hasLocalResults
            ? "실제 장소 검색 연결이 원활하지 않아 등록된 출사지를 먼저 보여드려요."
            : "실제 장소 검색에 연결하지 못했어요. 잠시 후 다시 시도해주세요."
    }

    private func selectPlaceSearchResult(_ result: VerifiedPhotoSpot) {
        let spot = result.photoSpot
        selectedSearchedSpot = spot
        selectedSpotID = spot.id
        placeSearchText = result.name
        placeSearchResults = []
        placeSearchMessage = nil
        hasAcknowledgedSubmissionGuidelines = false
    }

    private func mergedPlaceResults(_ results: [VerifiedPhotoSpot]) -> [VerifiedPhotoSpot] {
        results.reduce(into: []) { merged, result in
            let key = "\(result.name)-\(result.address)"
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            guard !merged.contains(where: {
                "\($0.name)-\($0.address)"
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased() == key
            }) else { return }
            merged.append(result)
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

    private func loadPhoto(from item: PhotosPickerItem?) {
        photoLoadFailed = false
        guard let item else { return }

        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        selectedPhotoData = data
                    }
                }
            } catch {
                await MainActor.run {
                    photoLoadFailed = true
                }
            }
        }
    }
}

struct ComposerFormSection<Content: View>: View {
    let number: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.secondaryText)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(AppColors.primary)

                    Text(detail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            content
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct CrowdSelector: View {
    @Binding var selectedCrowd: CommunityPost.Crowd

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CommunityPost.Crowd.allCases) { item in
                Button {
                    selectedCrowd = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedCrowd == item ? AppColors.background : AppColors.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            selectedCrowd == item ? AppColors.primary : AppColors.mutedSurface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedCrowd == item ? AppColors.primary : AppColors.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedTags.contains(tag) ? AppColors.background : AppColors.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            selectedTags.contains(tag) ? AppColors.primary : AppColors.mutedSurface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedTags.contains(tag) ? AppColors.primary : AppColors.divider, lineWidth: 1)
                        )
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)

                TextField("예: 야경, 한강, 필름감성", text: $text)
                    .font(.system(size: 15, weight: .regular))
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canAddTag ? AppColors.primary : AppColors.secondaryText.opacity(0.45))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canAddTag)
            }
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.divider, lineWidth: 1)
            }

            if tags.isEmpty {
                Text("입력한 태그는 검색 키워드로 사용됩니다. 예: 야경 검색 시 #야경 장소가 노출돼요.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 7)], spacing: 7) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            remove(tag)
                        } label: {
                            HStack(spacing: 5) {
                                Text("#\(tag)")
                                    .lineLimit(1)

                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.divider, lineWidth: 1)
                            }
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

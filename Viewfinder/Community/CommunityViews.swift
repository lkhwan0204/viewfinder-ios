import PhotosUI
import SwiftUI
import UIKit

struct CommunityTabView: View {
    let posts: [CommunityPost]
    let spots: [PhotoSpot]
    let currentUserID: String
    let likedPostIDs: Set<String>
    let followedAuthorIDs: Set<String>
    let commentsByPostID: [String: [CommunityComment]]
    let onCompose: () -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    let onEditPost: (CommunityPost) -> Void
    let onDeletePost: (CommunityPost) -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if posts.isEmpty {
                        EmptyCommunityView()
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(posts) { post in
                                CommunityPostCard(
                                    post: post,
                                    spot: spot(for: post),
                                    currentUserID: currentUserID,
                                    isLiked: likedPostIDs.contains(post.id),
                                    isFollowing: followedAuthorIDs.contains(post.authorID),
                                    comments: commentsByPostID[post.id] ?? [],
                                    onEdit: onEditPost,
                                    onDelete: onDeletePost,
                                    onToggleLike: onToggleLike,
                                    onToggleFollow: onToggleFollow,
                                    onAddComment: onAddComment
                                ) { spot in
                                    onSelectSpot(spot)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("커뮤니티")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.primary)

                Text("출사지 현장 상황을 빠르게 남겨요")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)

            Button(action: onCompose) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("현장 정보 작성")
        }
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
    let isFollowing: Bool
    let comments: [CommunityComment]
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    @State private var isCommentSheetPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            placeHeader

            Text(post.message)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(AppColors.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let photoData = post.photoData {
                CommunityAttachedPhotoView(photoData: photoData, height: 210)
            }

            authorHeader
            actionRow
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.divider.opacity(0.8))
                .frame(height: 1)
        }
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
        .sheet(isPresented: $isCommentSheetPresented) {
            CommunityCommentSheet(
                post: post,
                comments: comments,
                onSubmit: { message in
                    onAddComment(message, post)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var placeHeader: some View {
        if let spot {
            Button {
                onSelectSpot(spot)
            } label: {
                placeText
            }
            .buttonStyle(.plain)
        } else {
            placeText
        }
    }

    private var placeText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(post.spotName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.primary)
                .multilineTextAlignment(.leading)

            Text(placeDescription)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeDescription: String {
        guard let spot else {
            return "출사지 현장 정보"
        }

        let tags = spot.hashtags
            .map(HomeSpotDisplayFormatter.tag)
            .filter { !$0.isEmpty }
            .prefix(2)

        return ([HomeSpotDisplayFormatter.region(for: spot)] + tags)
            .joined(separator: " · ")
    }

    private var authorHeader: some View {
        HStack(spacing: 10) {
            CommunityAuthorAvatar(authorName: post.authorName)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

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

    private var actionRow: some View {
        HStack(spacing: 20) {
            Button {
                onToggleLike(post)
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? AppColors.primary : AppColors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? "좋아요 취소" : "좋아요")

            Button {
                isCommentSheetPresented = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")

                    if !comments.isEmpty {
                        Text("\(comments.count)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(AppColors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("댓글")

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(AppColors.secondaryText)
            }
            .accessibilityLabel("공유")
        }
        .font(.system(size: 19, weight: .medium))
    }

    private var shareText: String {
        "\(post.authorName)님의 출사지 정보\n\(post.spotName)\n\(post.message)"
    }
}

private struct CommunityAuthorAvatar: View {
    let authorName: String

    var body: some View {
        Text(String(authorName.prefix(1)))
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(AppColors.primary)
            .frame(width: 42, height: 42)
            .background(AppColors.mutedSurface, in: Circle())
            .overlay {
                Circle()
                    .stroke(AppColors.divider, lineWidth: 1)
            }
    }
}

private struct CommunityCommentSheet: View {
    let post: CommunityPost
    let comments: [CommunityComment]
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if comments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)

                        Text("첫 댓글을 남겨보세요")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppColors.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(comments) { comment in
                                VStack(alignment: .leading, spacing: 4) {
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
                                }
                            }
                        }
                        .padding(16)
                    }
                }

                HStack(spacing: 10) {
                    TextField("댓글 추가...", text: $draft)
                        .font(.system(size: 14, weight: .medium))

                    Button {
                        submit()
                    } label: {
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
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(post.spotName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        onSubmit(trimmedDraft)
        draft = ""
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

            CommunityStatusRow(crowd: post.crowd, tags: Array(post.tags.prefix(2)))

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

struct CommunityAttachedPhotoView: View {
    let photoData: Data
    let height: CGFloat
    var maxWidth: CGFloat?
    @State private var isPreviewPresented = false

    var body: some View {
        if let image = UIImage(data: photoData) {
            Button {
                isPreviewPresented = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
                    .frame(height: height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.divider.opacity(0.8), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $isPreviewPresented) {
                CommunityPhotoPreview(photoData: photoData)
            }
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
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 48, height: 48)
                .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("아직 올라온 현장 정보가 없어요")
                .font(.system(size: 17, weight: .bold))

            Text("빛, 혼잡도, 꽃 상태처럼 지금 촬영에 도움이 되는 분위기를 남겨보세요.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

enum CommunityComposerPurpose: Equatable {
    case fieldReport
    case shareSpot

    var navigationTitle: String {
        switch self {
        case .fieldReport:
            return "현장 정보"
        case .shareSpot:
            return "출사지 공유"
        }
    }

    var messageSectionTitle: String {
        switch self {
        case .fieldReport:
            return "현재 상황"
        case .shareSpot:
            return "추천 한마디"
        }
    }

    var messagePlaceholder: String {
        switch self {
        case .fieldReport:
            return "예: 현재 공사 중이에요 / 주차장이 만차예요 / 노을 보기 좋아요"
        case .shareSpot:
            return "예: 골목의 오래된 간판과 저녁빛을 함께 담기 좋아요"
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
    @State private var message = ""
    @State private var crowd: CommunityPost.Crowd = .normal
    @State private var selectedTags: Set<String> = []
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var photoLoadFailed = false

    private let statusTags = ["노을 좋음", "꽃 만개", "안개 있음", "사람 적음", "야경 좋음", "사진 찍기 좋음", "비 분위기 좋음", "반영 예쁨", "단풍 절정", "조명 좋음"]

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
        _selectedSpotID = State(initialValue: editingPost?.spotID ?? selectedSpot?.id ?? spots.first?.id ?? "")
        _message = State(initialValue: editingPost?.message ?? "")
        _crowd = State(initialValue: editingPost?.crowd ?? .normal)
        _selectedTags = State(initialValue: Set(editingPost?.tags ?? []))
        _selectedPhotoData = State(initialValue: editingPost?.photoData)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ComposerCardSection(title: "장소 정보") {
                        if isSpotLocked, let selectedSpot {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(selectedSpot.name) 현장 정보")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundStyle(AppColors.primary)

                                Text(selectedSpot.region)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        } else {
                            Picker("장소 선택", selection: $selectedSpotID) {
                                ForEach(spots) { spot in
                                    Text(spot.name).tag(spot.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    ComposerCardSection(title: purpose.messageSectionTitle) {
                        TextField(purpose.messagePlaceholder, text: $message, axis: .vertical)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(3, reservesSpace: true)
                            .padding(12)
                            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if purpose == .fieldReport || editingPost != nil {
                        ComposerCardSection(title: "혼잡도") {
                            CrowdSelector(selectedCrowd: $crowd)
                        }

                        ComposerCardSection(title: "상태 태그") {
                            FlexibleTagGrid(tags: statusTags, selectedTags: $selectedTags)
                        }
                    }

                    ComposerCardSection(title: "사진") {
                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedPhotoData == nil ? "photo" : "photo.badge.checkmark")
                                    Text(selectedPhotoData == nil ? "사진 첨부" : "사진 변경")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(AppColors.secondaryText.opacity(0.65))
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppColors.primary)
                                .padding(12)
                                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            if let selectedPhotoData {
                                CommunityAttachedPhotoView(photoData: selectedPhotoData, height: 150)

                                Button(role: .destructive) {
                                    self.selectedPhotoData = nil
                                    selectedPhotoItem = nil
                                } label: {
                                    Label("사진 제거", systemImage: "xmark.circle")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }

                            if photoLoadFailed {
                                Text("사진을 불러오지 못했어요. 다른 사진을 선택해줘.")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColors.crowdCrowded)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(editingPost == nil ? purpose.navigationTitle : "현장 정보 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(editingPost == nil ? "등록" : "저장") {
                        submit()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .disabled(!canSubmit)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                loadPhoto(from: newItem)
            }
        }
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

        return spots.first { $0.id == selectedSpotID }
    }

    private var isSpotLocked: Bool {
        locksSelectedSpot || editingPost != nil
    }

    private var canSubmit: Bool {
        selectedSpot != nil
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasChanges
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
        statusTags.filter { selectedTags.contains($0) }
    }

    private func submit() {
        guard let spot = selectedSpot else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

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

struct ComposerCardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColors.primary)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.divider.opacity(0.85), lineWidth: 1)
        )
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selectedCrowd == item ? item.tint : AppColors.primary.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            selectedCrowd == item ? item.fill : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedCrowd == item ? item.tint.opacity(0.16) : AppColors.divider, lineWidth: 1)
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selectedTags.contains(tag) ? AppColors.accent : AppColors.primary.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                        .background(
                            selectedTags.contains(tag) ? AppColors.accentSoft : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedTags.contains(tag) ? AppColors.accent.opacity(0.32) : AppColors.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

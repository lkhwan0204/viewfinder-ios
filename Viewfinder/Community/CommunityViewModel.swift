import Foundation

enum CommunityFeedState: Equatable {
    case initialLoading
    case loaded
    case empty
    case failed
    case refreshing
}

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var feedState: CommunityFeedState = .initialLoading
    @Published private(set) var deletingPostIDs: Set<String> = []
    @Published private(set) var likedPostIDs: Set<String> = []
    @Published private(set) var followedAuthorIDs: Set<String> = []
    @Published private(set) var commentsByPostID: [String: [CommunityComment]] = [:]
    @Published var isComposerPresented = false
    @Published var selectedSpotForComposer: PhotoSpot?
    @Published var editingPostForComposer: CommunityPost?

    private let service: CommunityService
    private let remoteStore: FirebaseCommunityPostStore?
    private let placePhotoGalleryStore: PlacePhotoGalleryStore
    private let crowdReportStore: CrowdReportStore
    private var isLoadingRemotePosts = false
    private var hasLoadedFeed = false
    private var localPostRevision = 0

    init(
        service: CommunityService = MockCommunityService(),
        remoteStore: FirebaseCommunityPostStore? = FirebaseCommunityPostStore(),
        placePhotoGalleryStore: PlacePhotoGalleryStore? = nil,
        crowdReportStore: CrowdReportStore? = nil
    ) {
        self.service = service
        self.remoteStore = remoteStore
        self.placePhotoGalleryStore = placePhotoGalleryStore ?? .shared
        self.crowdReportStore = crowdReportStore ?? .shared
        // Mock posts are only shown when a caller explicitly opts out of the
        // remote store (for previews). A real empty Firestore feed must be empty.
        posts = remoteStore == nil ? service.fetchPosts() : []
        feedState = remoteStore == nil
            ? (posts.isEmpty ? .empty : .loaded)
            : .initialLoading
        hasLoadedFeed = remoteStore == nil

        guard remoteStore != nil else { return }
        Task { [weak self] in
            await self?.loadRemotePosts()
        }
    }

    func posts(for spot: PhotoSpot) -> [CommunityPost] {
        // 장소명이나 본문이 아니라 CommunityPost가 저장한 관련 장소 ID로만 연결합니다.
        // Firestore의 relatedSpotID와 구버전 spotID는 모델의 relatedSpotID가
        // 호환해서 읽으므로, Place Detail에서도 동일한 기준을 사용합니다.
        posts.filter { $0.relatedSpotID == spot.id }
    }

    func isLiked(_ post: CommunityPost) -> Bool {
        likedPostIDs.contains(post.id)
    }

    func toggleLike(_ post: CommunityPost) {
        if likedPostIDs.contains(post.id) {
            likedPostIDs.remove(post.id)
        } else {
            likedPostIDs.insert(post.id)
        }
    }

    func isFollowing(_ post: CommunityPost) -> Bool {
        followedAuthorIDs.contains(post.authorID)
    }

    func toggleFollow(_ post: CommunityPost) {
        if followedAuthorIDs.contains(post.authorID) {
            followedAuthorIDs.remove(post.authorID)
        } else {
            followedAuthorIDs.insert(post.authorID)
        }
    }

    func comments(for post: CommunityPost) -> [CommunityComment] {
        commentsByPostID[post.id] ?? []
    }

    func addComment(_ message: String, to post: CommunityPost, author: AuthUser) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        commentsByPostID[post.id, default: []].append(
            CommunityComment(
                id: UUID().uuidString,
                authorName: author.displayName,
                message: trimmedMessage,
                createdAt: Date()
            )
        )
    }

    func beginComposing(spot: PhotoSpot? = nil) {
        selectedSpotForComposer = spot
        editingPostForComposer = nil
        isComposerPresented = true
    }

    func beginEditing(_ post: CommunityPost) {
        selectedSpotForComposer = nil
        editingPostForComposer = post
        isComposerPresented = true
    }

    func finishComposing() {
        selectedSpotForComposer = nil
        editingPostForComposer = nil
        isComposerPresented = false
    }

    func composerSpot(in spots: [PhotoSpot]) -> PhotoSpot? {
        if let editingPostForComposer {
            return spots.first { $0.id == editingPostForComposer.spotID }
        }

        return selectedSpotForComposer
    }

    private var isSavingPost = false

    func addPost(_ draft: CommunityPostDraft, author: AuthUser, id: String) async throws {
        guard !isSavingPost else { throw FirebaseCommunityError.emptyResponse }
        guard let remoteStore else { throw FirebaseCommunityError.notConfigured }
        isSavingPost = true
        defer { isSavingPost = false }
        let post = try await remoteStore.addPost(draft, author: author, id: id)
        // The post is already public at this point, even if the optional
        // crowd-report write fails. Reflect the server's post state now.
        mergeRemotePosts([post])
        localPostRevision += 1
        hasLoadedFeed = true
        feedState = .loaded
        placePhotoGalleryStore.applyLocalContribution(post: post)
        try await saveCrowdReport(for: post, draft: draft, authorID: author.id)

        // Place Gallery 동기화는 게시물 본체의 성공 조건이 아닙니다.
        // 특히 관련 출사지가 없는 자유 글에서는 placePhotos 조회가 필요하지
        // 않으므로, 게시 성공 후 백그라운드에서만 처리합니다.
        if post.relatedSpotID != nil,
           post.photoAttachments.contains(where: \.sharesToPlaceGallery) {
            let galleryStore = placePhotoGalleryStore
            Task { await galleryStore.syncCommunityContribution(post: post) }
        }
    }

    func updatePost(_ post: CommunityPost, draft: CommunityPostDraft) async throws {
        guard !isSavingPost else { throw FirebaseCommunityError.emptyResponse }
        guard let remoteStore else { throw FirebaseCommunityError.notConfigured }
        isSavingPost = true
        defer { isSavingPost = false }
        let updated = try await remoteStore.updatePost(post, draft: draft)
        mergeRemotePosts([updated])
        localPostRevision += 1
        hasLoadedFeed = true
        feedState = .loaded
        placePhotoGalleryStore.removeLocalContribution(postID: post.id)
        placePhotoGalleryStore.applyLocalContribution(post: updated)
        do {
            if post.relatedSpotID != draft.relatedSpotID || draft.crowd == nil {
                try await crowdReportStore.removeCommunityReportConfirmed(postID: post.id)
            }
            if Self.editRefreshesLiveCrowd(
                postCreatedAt: post.createdAt,
                now: Date(),
                freshnessWindow: CrowdReportStore.freshnessWindow
            ) {
                try await saveCrowdReport(for: updated, draft: draft, authorID: post.authorID)
            }
        } catch {
            throw FirebaseCommunityError.crowdReportPending
        }
        let galleryStore = placePhotoGalleryStore
        Task { await galleryStore.syncCommunityContribution(post: updated) }
    }

    func deletePost(_ post: CommunityPost, currentUserID: String?) async throws {
        guard currentUserID == post.authorID else { throw FirebaseCommunityError.notAuthorized }
        guard let remoteStore else { throw FirebaseCommunityError.notConfigured }
        guard deletingPostIDs.insert(post.id).inserted else {
            throw FirebaseCommunityError.alreadyInProgress
        }
        defer { deletingPostIDs.remove(post.id) }

        // Keep the post visible until Firestore confirms the hard delete.
        try await remoteStore.deletePost(post)
        service.deletePost(id: post.id)
        posts.removeAll { $0.id == post.id }
        localPostRevision += 1
        hasLoadedFeed = true
        feedState = posts.isEmpty ? .empty : .loaded
        placePhotoGalleryStore.removeLocalContribution(postID: post.id)
        crowdReportStore.removeCommunityReport(postID: post.id)
        if editingPostForComposer?.id == post.id {
            editingPostForComposer = nil
        }
        let galleryStore = placePhotoGalleryStore
        Task {
            await galleryStore.removeCommunityContribution(postID: post.id)
        }
    }

    func refreshPosts() {
        guard !isLoadingRemotePosts else { return }
        Task { [weak self] in
            await self?.loadRemotePosts()
        }
    }

    private func loadRemotePosts() async {
        guard let remoteStore, !isLoadingRemotePosts else { return }
        isLoadingRemotePosts = true
        feedState = hasLoadedFeed ? .refreshing : .initialLoading
        let startingRevision = localPostRevision
        var shouldReload = false
        defer {
            isLoadingRemotePosts = false
            if shouldReload { refreshPosts() }
        }

        do {
            let remotePosts = try await remoteStore.fetchPosts()
            hasLoadedFeed = true
            if startingRevision == localPostRevision {
                posts = remotePosts
                feedState = posts.isEmpty ? .empty : .loaded
            } else {
                // A post changed while this query was in flight. Fetch again
                // after it completes instead of applying an older snapshot.
                feedState = posts.isEmpty ? .empty : .loaded
                shouldReload = true
            }
        } catch {
            feedState = .failed
            AppLog.persistence.error(
                "Community post fetch failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func mergeRemotePosts(_ remotePosts: [CommunityPost]) {
        var merged = posts
        for remotePost in remotePosts {
            if let index = merged.firstIndex(where: { $0.id == remotePost.id }) {
                merged[index] = remotePost
            } else {
                merged.append(remotePost)
            }
        }
        posts = merged.sorted { $0.createdAt > $1.createdAt }
    }

    /// 글의 혼잡도는 "작성 당시" 정보예요. 글을 고칠 때마다 혼잡도 제보를 다시 저장하면
    /// 제보 시각이 지금이 되어, 며칠 전 혼잡도가 장소 상세 "현재 혼잡도"에 다시 올라옵니다.
    /// 그래서 현장 정보가 유효한 시간(1시간) 안에 쓴 글을 고칠 때만 현재 혼잡도에 반영해요.
    /// 옛 글은 글에 적힌 혼잡도만 바뀝니다.
    static func editRefreshesLiveCrowd(
        postCreatedAt: Date,
        now: Date,
        freshnessWindow: TimeInterval
    ) -> Bool {
        postCreatedAt >= now.addingTimeInterval(-freshnessWindow)
    }

    private func saveCrowdReport(
        for post: CommunityPost,
        draft: CommunityPostDraft,
        authorID: String
    ) async throws {
        guard let crowd = draft.crowd,
              let placeID = draft.spot?.id else {
            return
        }

        do {
            try await crowdReportStore.submitCommunityReport(
                placeID: placeID,
                crowd: crowd,
                authorID: authorID,
                postID: post.id
            )
        } catch {
            throw FirebaseCommunityError.crowdReportPending
        }
    }
}

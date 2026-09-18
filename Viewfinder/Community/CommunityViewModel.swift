import Foundation

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published private(set) var posts: [CommunityPost] = []
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
        posts = service.fetchPosts()

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

    func addPost(_ draft: CommunityPostDraft, author: AuthUser) {
        let localPost = service.addPost(draft, author: author)
        refreshLocalPosts()
        publishLocalPostEffects(localPost, draft: draft, authorID: author.id)
        selectedSpotForComposer = nil
        editingPostForComposer = nil
        isComposerPresented = false

        guard let remoteStore else { return }
        Task { [weak self] in
            do {
                let remotePost = try await remoteStore.addPost(draft, author: author, id: localPost.id)
                await MainActor.run {
                    self?.replace(localPost, with: remotePost)
                }
                await self?.placePhotoGalleryStore.syncCommunityContribution(post: remotePost)
            } catch {
                AppLog.persistence.error(
                    "Community post upload failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func updatePost(_ post: CommunityPost, draft: CommunityPostDraft) {
        let localPost = service.updatePost(id: post.id, draft: draft)
        refreshLocalPosts()
        if let localPost {
            placePhotoGalleryStore.removeLocalContribution(postID: post.id)
            // 같은 Community 글의 혼잡도 제보는 안정적인 report ID로 upsert합니다.
            // 새 선택값이 있는 수정에서는 먼저 삭제하지 않아 원격 삭제 작업이
            // 새 제보를 뒤늦게 지우는 경합을 피합니다.
            if draft.crowd == nil || draft.spot == nil {
                crowdReportStore.removeCommunityReport(postID: post.id)
            }
            publishLocalPostEffects(localPost, draft: draft, authorID: post.authorID)
        }
        selectedSpotForComposer = nil
        editingPostForComposer = nil
        isComposerPresented = false

        guard let remoteStore, localPost != nil else { return }
        Task { [weak self] in
            do {
                let remotePost = try await remoteStore.updatePost(post, draft: draft)
                await MainActor.run {
                    self?.replace(post, with: remotePost)
                }
                await self?.placePhotoGalleryStore.syncCommunityContribution(post: remotePost)
            } catch {
                AppLog.persistence.error(
                    "Community post update failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func deletePost(_ post: CommunityPost) {
        service.deletePost(id: post.id)
        refreshLocalPosts()
        placePhotoGalleryStore.removeLocalContribution(postID: post.id)
        crowdReportStore.removeCommunityReport(postID: post.id)
        if editingPostForComposer?.id == post.id {
            editingPostForComposer = nil
        }
        isComposerPresented = false

        guard let remoteStore else { return }
        Task { [weak self] in
            do {
                try await remoteStore.deletePost(post)
                guard let self else { return }
                await self.placePhotoGalleryStore.removeCommunityContribution(postID: post.id)
            } catch {
                AppLog.persistence.error(
                    "Community post delete failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func loadRemotePosts() async {
        guard let remoteStore else { return }

        do {
            let remotePosts = try await remoteStore.fetchPosts()
            mergeRemotePosts(remotePosts)
        } catch {
            // Firebase가 아직 연결되지 않은 개발 환경에서도
            // 기존 로컬 피드는 그대로 사용할 수 있어야 합니다.
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

    private func replace(_ original: CommunityPost, with replacement: CommunityPost) {
        guard let index = posts.firstIndex(where: { $0.id == original.id }) else {
            posts.insert(replacement, at: 0)
            return
        }
        posts[index] = replacement
    }

    private func refreshLocalPosts() {
        let existingByID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        let localPosts = service.fetchPosts().map { existingByID[$0.id] ?? $0 }
        let localIDs = Set(localPosts.map(\.id))
        let remoteOnlyPosts = posts.filter { !localIDs.contains($0.id) }
        posts = (localPosts + remoteOnlyPosts).sorted { $0.createdAt > $1.createdAt }
    }

    private func publishLocalPostEffects(
        _ post: CommunityPost,
        draft: CommunityPostDraft,
        authorID: String
    ) {
        placePhotoGalleryStore.applyLocalContribution(post: post)

        guard let crowd = draft.crowd,
              let placeID = draft.spot?.id else {
            return
        }

        crowdReportStore.submit(
            placeID: placeID,
            crowd: crowd,
            authorID: authorID,
            source: .community,
            communityPostID: post.id
        )
    }
}

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

    init(service: CommunityService = MockCommunityService()) {
        self.service = service
        posts = service.fetchPosts()
    }

    func posts(for spot: PhotoSpot) -> [CommunityPost] {
        posts.filter { $0.spotID == spot.id }
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

    func composerSpot(in spots: [PhotoSpot]) -> PhotoSpot? {
        if let editingPostForComposer {
            return spots.first { $0.id == editingPostForComposer.spotID }
        }

        return selectedSpotForComposer
    }

    func addPost(_ draft: CommunityPostDraft, author: AuthUser) {
        _ = service.addPost(draft, author: author)
        posts = service.fetchPosts()
        selectedSpotForComposer = nil
        editingPostForComposer = nil
        isComposerPresented = false
    }

    func updatePost(_ post: CommunityPost, draft: CommunityPostDraft) {
        _ = service.updatePost(id: post.id, draft: draft)
        posts = service.fetchPosts()
        selectedSpotForComposer = nil
        editingPostForComposer = nil
        isComposerPresented = false
    }

    func deletePost(_ post: CommunityPost) {
        service.deletePost(id: post.id)
        posts = service.fetchPosts()
        if editingPostForComposer?.id == post.id {
            editingPostForComposer = nil
        }
        isComposerPresented = false
    }
}

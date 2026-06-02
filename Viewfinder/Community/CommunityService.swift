import Foundation

protocol CommunityService {
    func fetchPosts() -> [CommunityPost]
    func addPost(_ draft: CommunityPostDraft, author: AuthUser) -> CommunityPost
    func updatePost(id: String, draft: CommunityPostDraft) -> CommunityPost?
    func deletePost(id: String)
}

final class MockCommunityService: CommunityService {
    private var posts: [CommunityPost] = [
        CommunityPost(
            id: "mock-seonyudo",
            spotID: "seed-seonyudo-park",
            spotName: "선유도공원",
            message: "해질녘 빛이 좋고 산책로는 비교적 여유 있어요.",
            crowd: .normal,
            tags: ["노을 좋음"],
            photoData: nil,
            authorID: "mock-local-seonyudo",
            authorName: "필름러버",
            createdAt: Date().addingTimeInterval(-18 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-banpo",
            spotID: "seed-banpo-fountain",
            spotName: "반포대교 달빛무지개분수",
            message: "분수 시간대에는 삼각대 자리 경쟁이 조금 있어요.",
            crowd: .crowded,
            tags: ["야경 좋음", "조명 좋음"],
            photoData: nil,
            authorID: "mock-local-banpo",
            authorName: "야경팀",
            createdAt: Date().addingTimeInterval(-42 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-bukchon",
            spotID: "seed-bukchon",
            spotName: "북촌한옥마을",
            message: "오전 골목은 조용한 편이고 생활지역 예절만 조심하면 좋아요.",
            crowd: .relaxed,
            tags: ["사람 적음", "사진 찍기 좋음"],
            photoData: nil,
            authorID: "mock-local-bukchon",
            authorName: "골목산책",
            createdAt: Date().addingTimeInterval(-2 * 60 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-seoul-forest-daisy",
            spotID: "seed-seoul-forest",
            spotName: "서울숲",
            message: "군락지 쪽 데이지가 피기 시작해서 낮은 앵글로 찍기 좋아요.",
            crowd: .normal,
            tags: ["데이지", "꽃 만개", "사진 찍기 좋음"],
            photoData: nil,
            authorID: "mock-local-seoul-forest",
            authorName: "꽃스냅",
            createdAt: Date().addingTimeInterval(-27 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-mullae-film",
            spotID: "seed-mullae-local-cafe-alley",
            spotName: "문래창작촌",
            message: "철공소 골목 쪽 로컬카페 외관이 필름감성으로 잘 나와요.",
            crowd: .relaxed,
            tags: ["필름감성", "로컬카페", "사람 적음"],
            photoData: nil,
            authorID: "mock-local-mullae",
            authorName: "문래스냅",
            createdAt: Date().addingTimeInterval(-51 * 60),
            updatedAt: nil
        ),
        CommunityPost(
            id: "mock-euljiro-night",
            spotID: "seed-euljiro-local-cafe-alley",
            spotName: "을지로 카페골목",
            message: "비 온 뒤 골목 조명이 반사돼서 야경 컷 분위기가 좋아요.",
            crowd: .normal,
            tags: ["야경 좋음", "비 분위기 좋음", "필름감성"],
            photoData: nil,
            authorID: "mock-local-euljiro",
            authorName: "을지로밤",
            createdAt: Date().addingTimeInterval(-70 * 60),
            updatedAt: nil
        )
    ]

    func fetchPosts() -> [CommunityPost] {
        posts.sorted { $0.createdAt > $1.createdAt }
    }

    func addPost(_ draft: CommunityPostDraft, author: AuthUser) -> CommunityPost {
        let post = CommunityPost(
            id: UUID().uuidString,
            spotID: draft.spot.id,
            spotName: draft.spot.name,
            message: draft.message,
            crowd: draft.crowd,
            tags: draft.tags,
            photoData: draft.photoData,
            authorID: author.id,
            authorName: author.displayName,
            createdAt: Date(),
            updatedAt: nil
        )
        posts.insert(post, at: 0)
        return post
    }

    func updatePost(id: String, draft: CommunityPostDraft) -> CommunityPost? {
        guard let index = posts.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let original = posts[index]
        let updated = CommunityPost(
            id: original.id,
            spotID: original.spotID,
            spotName: original.spotName,
            message: draft.message,
            crowd: draft.crowd,
            tags: draft.tags,
            photoData: draft.photoData,
            authorID: original.authorID,
            authorName: original.authorName,
            createdAt: original.createdAt,
            updatedAt: Date()
        )
        posts[index] = updated
        return updated
    }

    func deletePost(id: String) {
        posts.removeAll { $0.id == id }
    }
}

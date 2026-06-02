import SwiftUI

struct MyTabView: View {
    let user: AuthUser
    let savedSpots: [PhotoSpot]
    let posts: [CommunityPost]
    let spots: [PhotoSpot]
    let likedPostIDs: Set<String>
    let followedAuthorIDs: Set<String>
    let commentsByPostID: [String: [CommunityComment]]
    let onSelectSpot: (PhotoSpot) -> Void
    let onEditPost: (CommunityPost) -> Void
    let onDeletePost: (CommunityPost) -> Void
    let onToggleLike: (CommunityPost) -> Void
    let onToggleFollow: (CommunityPost) -> Void
    let onAddComment: (String, CommunityPost) -> Void
    let onSignOut: () -> Void

    private var myPosts: [CommunityPost] {
        posts.filter { $0.authorID == user.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    profileSection
                    savedSection
                    postSection

                    Button(action: onSignOut) {
                        Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        Capsule()
                            .stroke(AppColors.divider, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var profileSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppColors.primary)

                Text(user.email ?? "로그인된 프로필")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MySectionHeader(title: "저장한 장소", count: savedSpots.count)

            if savedSpots.isEmpty {
                MyEmptyState(
                    symbolName: "bookmark",
                    message: "저장한 출사지가 아직 없어요"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(savedSpots) { spot in
                        Button {
                            onSelectSpot(spot)
                        } label: {
                            SavedSpotRow(spot: spot)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var postSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MySectionHeader(title: "내 글", count: myPosts.count)

            if myPosts.isEmpty {
                MyEmptyState(
                    symbolName: "bubble.left.and.bubble.right",
                    message: "남긴 현장 정보가 아직 없어요"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(myPosts) { post in
                        CommunityPostCard(
                            post: post,
                            spot: spot(for: post),
                            currentUserID: user.id,
                            isLiked: likedPostIDs.contains(post.id),
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
            }
        }
    }

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        spots.first { $0.id == post.spotID }
    }
}

private struct MySectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.secondaryText)
        }
    }
}

private struct MyEmptyState: View {
    let symbolName: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)

            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SavedSpotsView: View {
    let spots: [PhotoSpot]
    let onSelect: (PhotoSpot) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("저장")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppColors.primary)

                    if spots.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(width: 40, height: 40)
                                .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text("아직 저장한 출사지가 없어요")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(spots) { spot in
                                Button {
                                    onSelect(spot)
                                } label: {
                                    SavedSpotRow(spot: spot)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }
}

struct SavedSpotRow: View {
    let spot: PhotoSpot

    var body: some View {
        HStack(spacing: 12) {
            PhotoSpotImageView(spot: spot, symbolSize: 20)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(spot.name)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(HomeSpotDisplayFormatter.region(for: spot))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text(HomeSpotDisplayFormatter.bestTime(spot.bestTime))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(spot.theme.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.secondaryText.opacity(0.65))
        }
        .padding(10)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

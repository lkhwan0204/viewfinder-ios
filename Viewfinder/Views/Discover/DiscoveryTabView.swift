import SwiftUI
import UIKit

struct DiscoveryTabView: View {
    let spots: [PhotoSpot]
    let recentPosts: [CommunityPost]
    let onShareSpot: () -> Void
    let onSelectSpot: (PhotoSpot) -> Void

    private let horizontalPadding: CGFloat = 20
    private let gridSpacing: CGFloat = 16

    private var gridCardWidth: CGFloat {
        let availableWidth = UIScreen.main.bounds.width - (horizontalPadding * 2) - gridSpacing
        return floor(availableWidth / 2)
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.fixed(gridCardWidth), spacing: gridSpacing, alignment: .top),
            GridItem(.fixed(gridCardWidth), spacing: gridSpacing, alignment: .top)
        ]
    }

    private var discoverySpots: [PhotoSpot] {
        spots.filter { spot in
            !RecommendationBlacklist.isBlacklistedRecommendation(spot)
                && !CafeRecommendationPolicy.isBlacklistedCafe(spot)
        }
    }

    private var recentlyAddedSpots: [PhotoSpot] {
        Array(discoverySpots.prefix(8))
    }

    private var trendingSpots: [PhotoSpot] {
        let postCounts = Dictionary(grouping: recentPosts, by: \.spotID)
            .mapValues(\.count)

        let fromPosts = discoverySpots
            .filter { postCounts[$0.id] != nil }
            .sorted { lhs, rhs in
                (postCounts[lhs.id] ?? 0) > (postCounts[rhs.id] ?? 0)
            }

        let usedIDs = Set(fromPosts.map(\.id))
        let fallback = discoverySpots.filter { !usedIDs.contains($0.id) }
        return Array((fromPosts + fallback).prefix(8))
    }

    private var fieldUpdatedSpots: [PhotoSpot] {
        let spotByID = Dictionary(uniqueKeysWithValues: discoverySpots.map { ($0.id, $0) })
        var seenIDs = Set<String>()

        return recentPosts
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { post -> PhotoSpot? in
                guard !seenIDs.contains(post.spotID),
                      let spot = spotByID[post.spotID] else {
                    return nil
                }
                seenIDs.insert(post.spotID)
                return spot
            }
    }

    private var quietSpots: [PhotoSpot] {
        Array(discoverySpots.filter { spot in
            let searchable = ([spot.crowdLevelCode] + spot.hashtags + spot.mood)
                .joined(separator: " ")
                .lowercased()
            return spot.isHiddenSpot
                || spot.crowdLevelCode.lowercased() == "low"
                || searchable.contains("사람 적음")
                || searchable.contains("한적")
                || searchable.contains("조용")
        }.prefix(8))
    }

    private var visiblePosts: [CommunityPost] {
        Array(recentPosts.sorted { $0.createdAt > $1.createdAt }.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 34) {
                    header
                    primaryActionSection
                    recentlyAddedSection
                    trendingSection
                    fieldUpdatedSection
                    quietSpotSection
                    recentFieldNotesSection
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
            .safeAreaPadding(.bottom, 24)
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("발견")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Text("사람들이 새로 찾고 저장하는 출사지")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
                .lineSpacing(3)
        }
    }

    private var primaryActionSection: some View {
        Button(action: onShareSpot) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))

                Text("출사지 공유")
                    .font(.system(size: 15, weight: .bold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(AppColors.primary)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DiscoverySectionHeader(title: "최근 발견된 장소", subtitle: "새로 아카이브된 출사지")

            if recentlyAddedSpots.isEmpty {
                DiscoveryEmptyCard(text: "아직 보여줄 출사지가 부족해요")
            } else {
                LazyVGrid(
                    columns: gridColumns,
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(recentlyAddedSpots) { spot in
                        Button {
                            onSelectSpot(spot)
                        } label: {
                            DiscoverySpotCard(spot: spot, width: gridCardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trendingSection: some View {
        if !trendingSpots.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                DiscoverySectionHeader(title: "지금 뜨는 장소", subtitle: "현장 제보와 저장 흐름이 모이는 곳")

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(trendingSpots) { spot in
                            Button {
                                onSelectSpot(spot)
                            } label: {
                                DiscoveryTrendCard(
                                    spot: spot,
                                    updateCount: recentPosts.filter { $0.spotID == spot.id }.count
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                .padding(.horizontal, -horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private var fieldUpdatedSection: some View {
        if !fieldUpdatedSpots.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                DiscoverySectionHeader(title: "현장 사진 업데이트", subtitle: "오늘 이야기가 올라온 장소")

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(fieldUpdatedSpots.prefix(8)) { spot in
                            Button {
                                onSelectSpot(spot)
                            } label: {
                                DiscoverySmallSpotCard(spot: spot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                .padding(.horizontal, -horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private var quietSpotSection: some View {
        if !quietSpots.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                DiscoverySectionHeader(title: "사람 적은 스팟", subtitle: "조용히 걷고 찍기 좋은 장소")

                LazyVGrid(
                    columns: gridColumns,
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(quietSpots) { spot in
                        Button {
                            onSelectSpot(spot)
                        } label: {
                            DiscoverySpotCard(spot: spot, width: gridCardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recentFieldNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiscoverySectionHeader(title: "최근 현장 정보", subtitle: "커뮤니티에 올라온 짧은 제보")

            if visiblePosts.isEmpty {
                DiscoveryEmptyCard(text: "아직 올라온 현장 정보가 없어요")
            } else {
                VStack(spacing: 8) {
                    ForEach(visiblePosts) { post in
                        DiscoveryCompactPostRow(post: post)
                    }
                }
            }
        }
    }

}

private struct DiscoverySectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
        }
    }
}

private struct DiscoverySpotCard: View {
    let spot: PhotoSpot
    let width: CGFloat

    private var imageHeight: CGFloat {
        width * 1.25
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoverySpotImageFrame(spot: spot, width: width, height: imageHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(metaText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
            .frame(height: 40, alignment: .topLeading)
        }
        .frame(width: width, height: imageHeight + 50, alignment: .topLeading)
        .clipped()
    }

    private var metaText: String {
        let tags = spot.hashtags
            .prefix(2)
            .map { $0.replacingOccurrences(of: "#", with: "") }
            .joined(separator: " · ")

        if tags.isEmpty {
            return HomeSpotDisplayFormatter.region(for: spot)
        }

        return "\(HomeSpotDisplayFormatter.region(for: spot)) · \(tags)"
    }
}

private struct DiscoverySpotImageFrame: View {
    let spot: PhotoSpot
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            AppColors.mutedSurface

            PhotoSpotImageView(spot: spot, symbolSize: 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct DiscoveryTrendCard: View {
    let spot: PhotoSpot
    let updateCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                PhotoSpotImageView(spot: spot, symbolSize: 20)
                    .frame(width: 82, height: 82)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if updateCount > 0 {
                    Text("제보 \(updateCount)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(7)
                }
            }
            .frame(width: 82, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(spot.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(HomeSpotDisplayFormatter.region(for: spot))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text(tagText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 254, height: 104)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }

    private var tagText: String {
        spot.hashtags.prefix(2).map { "#\($0.replacingOccurrences(of: "#", with: ""))" }.joined(separator: " ")
    }
}

private struct DiscoverySmallSpotCard: View {
    let spot: PhotoSpot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoSpotImageView(spot: spot, symbolSize: 18)
                .frame(width: 132, height: 96)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(spot.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(HomeSpotDisplayFormatter.region(for: spot))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: 132, alignment: .leading)
    }
}

private struct DiscoveryCompactPostRow: View {
    let post: CommunityPost

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.primarySoft)
                Image(systemName: "text.bubble")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(post.spotName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text(relativeText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                }

                Text(post.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
                    .lineSpacing(2)

                HStack(spacing: 6) {
                    Text("혼잡도 · \(post.crowd.displayText)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(post.crowd.tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(post.crowd.fill, in: Capsule())

                    ForEach(post.tags.prefix(1), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppColors.mutedSurface, in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }

    private var relativeText: String {
        if abs(post.createdAt.timeIntervalSinceNow) < 60 {
            return "방금 전"
        }
        return Self.relativeFormatter.localizedString(for: post.createdAt, relativeTo: Date())
    }

}

private struct DiscoveryEmptyCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColors.divider, lineWidth: 1)
            )
    }
}

import CoreLocation
import Foundation
import SwiftUI
import UIKit

final class HomeRecommendationsViewModel: ObservableObject {
    @Published private(set) var todayRecommendations: [GPTRecommendedSpot] = []
    @Published private(set) var sectionRecommendations: [HomeRecommendationKind: [GPTRecommendedSpot]] = [:]

    private let service: HomeRecommendationService
    private var communityPosts: [CommunityPost] = []
    private var userLocation: CLLocationCoordinate2D?
    private var weatherContext: RecommendationWeatherContext?
    private var lastGeneratedLocation: CLLocationCoordinate2D?
    private let locationRefreshThresholdMeters: CLLocationDistance = 1_500

    init(service: HomeRecommendationService = HomeRecommendationService()) {
        self.service = service
        generateOnce()
    }

    var visibleSpots: [PhotoSpot] {
        let sectionSpots = sectionRecommendations.values.flatMap { $0.map(\.spot) }
        return (todayRecommendations.map(\.spot) + sectionSpots).reduce(into: [PhotoSpot]()) { result, spot in
            guard !result.contains(where: { $0.id == spot.id }) else { return }
            result.append(spot)
        }
    }

    func updateCommunityContext(posts: [CommunityPost]) {
        communityPosts = posts
        generateOnce()
    }

    func updateLocationContext(userLocation: CLLocationCoordinate2D?) {
        guard shouldRefreshRecommendations(for: userLocation) else {
            return
        }

        self.userLocation = userLocation
        generateOnce()
    }

    func updateWeatherContext(_ context: RecommendationWeatherContext?) {
        guard weatherContext != context else { return }
        weatherContext = context
        generateOnce()
    }

    private func generateOnce() {
        let snapshot = service.makeSnapshot(
            communityPosts: communityPosts,
            userLocation: userLocation,
            weatherContext: weatherContext,
            referenceDate: Date()
        )
        lastGeneratedLocation = userLocation
        todayRecommendations = snapshot.todayRecommendations
        sectionRecommendations = snapshot.sections
    }

    private func shouldRefreshRecommendations(for newLocation: CLLocationCoordinate2D?) -> Bool {
        guard let newLocation else {
            return userLocation != nil
        }

        guard let lastGeneratedLocation else {
            return true
        }

        let old = CLLocation(latitude: lastGeneratedLocation.latitude, longitude: lastGeneratedLocation.longitude)
        let new = CLLocation(latitude: newLocation.latitude, longitude: newLocation.longitude)
        return new.distance(from: old) >= locationRefreshThresholdMeters
    }
}

private struct HomeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HomeFeedView: View {
    let searchableSpots: [PhotoSpot]
    let recommendedSpots: [PhotoSpot]
    let communityPosts: [CommunityPost]
    let preloadedRecommendations: [GPTRecommendedSpot]
    let sectionRecommendations: [HomeRecommendationKind: [GPTRecommendedSpot]]
    let loadingSectionIDs: Set<String>
    let isPreloadingRecommendations: Bool
    let currentLocationTitle: String
    let weatherSnapshot: WeatherSnapshot?
    let weatherLoadFailed: Bool
    let savedSpotIDs: Set<String>
    @ObservedObject var searchViewModel: PhotoSpotSearchViewModel
    let userLocation: CLLocationCoordinate2D?
    let onAddAISpot: (PhotoSpot) -> Void
    let onShowDetail: (PhotoSpot) -> Void
    let onShowSearchDetail: (PhotoSpot) -> Void
    let onToggleSave: (PhotoSpot) -> Void
    let onOpenMap: (PhotoSpot?) -> Void
    let onShowWeather: () -> Void
    let onShowCurrentLocation: () -> Void
    let onTabBarVisibilityChange: (Bool) -> Void
    private let searchProvider: any SearchProvider = LocalKeywordSearchProvider()
    @State private var isSearchResultsPresented = false
    @State private var keywordSearchResults = KeywordSearchResults.empty
    @State private var previousScrollOffset: CGFloat?
    @State private var isTabBarHidden = false
    @FocusState private var isSearchFocused: Bool

    private var recommendations: [GPTRecommendedSpot] {
        let rawRecommendations: [GPTRecommendedSpot]

        if !preloadedRecommendations.isEmpty {
            rawRecommendations = preloadedRecommendations
        } else {
            rawRecommendations = recommendedSpots.map {
                GPTRecommendedSpot(
                    spot: $0,
                    reason: $0.eventPeriod,
                    scoreLabel: "오늘 추천",
                    isGeneratedByGPT: true
                )
            }
        }

        return imagePrioritizedRecommendations(rawRecommendations)
    }

    private var categories: [HomeRecommendationKind] {
        HomeRecommendationKind.allCases
    }

    private var verifiedRecommendations: [GPTRecommendedSpot] {
        searchViewModel.verifiedSpots.map { verifiedSpot in
            GPTRecommendedSpot(
                spot: verifiedSpot.photoSpot,
                reason: verifiedSpot.reason,
                scoreLabel: scoreLabel(for: verifiedSpot.source),
                isGeneratedByGPT: verifiedSpot.source != "local"
            )
        }
    }

    private var keywordSpotRecommendations: [GPTRecommendedSpot] {
        keywordSearchResults.spots.map {
            GPTRecommendedSpot(
                spot: $0,
                reason: $0.eventPeriod,
                scoreLabel: "앱 데이터",
                isGeneratedByGPT: false
            )
        }
    }

    private var combinedSearchRecommendations: [GPTRecommendedSpot] {
        (keywordSpotRecommendations + verifiedRecommendations).reduce(into: [GPTRecommendedSpot]()) { result, recommendation in
            guard !result.contains(where: {
                $0.spot.id == recommendation.spot.id || $0.spot.mapQuery == recommendation.spot.mapQuery
            }) else {
                return
            }

            result.append(recommendation)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 38) {
                    searchAndContext
                    todaySection

                    ForEach(categories) { category in
                        let categoryRecommendations = recommendations(for: category)
                        if !categoryRecommendations.isEmpty {
                            HomeCategorySection(
                                category: category,
                                recommendations: categoryRecommendations,
                                isLoading: loadingSectionIDs.contains(category.id),
                                savedSpotIDs: savedSpotIDs,
                                onToggleSave: onToggleSave,
                                onSelect: onShowDetail
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 38)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: HomeScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("home-feed-scroll")).minY
                            )
                    }
                }
            }
            .coordinateSpace(name: "home-feed-scroll")
            .onPreferenceChange(HomeScrollOffsetPreferenceKey.self, perform: updateTabBarVisibility)
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $isSearchResultsPresented) {
                HomeSearchResultsView(
                    query: searchViewModel.searchText,
                    spotRecommendations: combinedSearchRecommendations,
                    communityPosts: keywordSearchResults.communityPosts,
                    spots: searchableSpots,
                    message: searchViewModel.message,
                    isLoading: searchViewModel.isLoading,
                    onDismiss: {
                        isSearchResultsPresented = false
                    },
                    onRequestAI: {
                        Task {
                            await searchViewModel.requestAIRecommendations(userLocation: userLocation)
                        }
                    },
                    onSelectSpot: { spot in
                        onAddAISpot(spot)
                        isSearchResultsPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            onShowSearchDetail(spot)
                        }
                    },
                    onSelectCommunityPost: { post in
                        guard let spot = spot(for: post) else { return }
                        isSearchResultsPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            onShowSearchDetail(spot)
                        }
                    }
                )
            }
            .onAppear {
                updateTabBarVisibility(0)
            }
        }
    }

    private func updateTabBarVisibility(_ offset: CGFloat) {
        defer {
            previousScrollOffset = offset
        }

        guard offset < -12 else {
            setTabBarHidden(false)
            return
        }

        guard let previousScrollOffset else { return }
        let delta = offset - previousScrollOffset

        if delta < -4 {
            setTabBarHidden(true)
        } else if delta > 4 {
            setTabBarHidden(false)
        }
    }

    private func setTabBarHidden(_ shouldHide: Bool) {
        guard isTabBarHidden != shouldHide else { return }
        isTabBarHidden = shouldHide
        onTabBarVisibilityChange(shouldHide)
    }

    private var brandHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.cardBackground)
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.divider.opacity(0.9), lineWidth: 1)
                    )

                Image(systemName: "viewfinder")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("뷰파인더")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(AppColors.primary)

                Text("오늘의 프레임을 찾는 출사 큐레이션")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var searchAndContext: some View {
        VStack(spacing: 14) {
            homeSearchBar

            if searchViewModel.isLoading {
                SearchStatusRow(
                    message: "검색 중이에요",
                    isLoading: true,
                    isError: false
                )
            }

            HStack(spacing: 10) {
                Button(action: onShowWeather) {
                    HomeContextPill(
                        symbolName: weatherSnapshot?.symbolName ?? "cloud.sun.fill",
                        title: "오늘 날씨",
                        value: weatherSnapshot?.displayText ?? (weatherLoadFailed ? "날씨 정보를 불러올 수 없음" : "날씨 확인 중"),
                        tint: AppColors.primary
                    )
                }
                .buttonStyle(.plain)

                Button(action: onShowCurrentLocation) {
                    HomeContextPill(
                        symbolName: "location.fill",
                        title: "현재 위치",
                        value: currentLocationTitle,
                        tint: AppColors.primary
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var homeSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(AppColors.secondaryText)

            TextField("출사지, 지역, 분위기 검색", text: $searchViewModel.searchText)
                .font(.system(size: 16, weight: .medium))
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isSearchFocused)
                .onSubmit(performSearch)

            if !searchViewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchViewModel.isLoading {
                Button(action: performSearch) {
                    if searchViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("검색")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.primary)
                .disabled(searchViewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchViewModel.isLoading)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .stroke(isSearchFocused ? AppColors.primary.opacity(0.24) : AppColors.divider, lineWidth: 1)
        )
    }

    private func performSearch() {
        let query = searchViewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        keywordSearchResults = searchProvider.search(
            query: query,
            spots: searchableSpots,
            communityPosts: communityPosts
        )

        Task {
            await searchViewModel.search(userLocation: userLocation)
            await MainActor.run {
                keywordSearchResults = searchProvider.search(
                    query: query,
                    spots: searchableSpots,
                    communityPosts: communityPosts
                )
                isSearchFocused = false
                isSearchResultsPresented = true
            }
        }
    }

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        searchableSpots.first { $0.id == post.spotID }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HomeSectionHeader(title: "오늘 추천 출사지", symbolName: "viewfinder", tint: AppColors.primary.opacity(0.78))

            if recommendations.isEmpty {
                NearbyRecommendationEmptyView(message: "주변 출사지 데이터가 부족해요")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(recommendations.prefix(8)) { recommendation in
                            Button {
                                onShowDetail(recommendation.spot)
                            } label: {
                                FeaturedSpotCard(
                                    recommendation: recommendation,
                                    isSaved: savedSpotIDs.contains(recommendation.spot.id),
                                    onToggleSave: {
                                        onToggleSave(recommendation.spot)
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .padding(.horizontal, -20)
            }
        }
    }

    private func recommendations(for category: HomeRecommendationKind) -> [GPTRecommendedSpot] {
        imagePrioritizedRecommendations(sectionRecommendations[category] ?? [])
    }

    private func imagePrioritizedRecommendations(_ recommendations: [GPTRecommendedSpot]) -> [GPTRecommendedSpot] {
        recommendations
            .enumerated()
            .sorted { left, right in
                let leftHasImage = hasDisplayImage(left.element.spot)
                let rightHasImage = hasDisplayImage(right.element.spot)

                if leftHasImage != rightHasImage {
                    return leftHasImage && !rightHasImage
                }

                return left.offset < right.offset
            }
            .map(\.element)
    }

    private func hasDisplayImage(_ spot: PhotoSpot) -> Bool {
        spot.hasReliableDisplayImage
    }

    private func scoreLabel(for source: String) -> String {
        switch source {
        case "local":
            return "기본 데이터"
        case "kakao":
            return "카카오 검증"
        case "naver":
            return "네이버 검증"
        default:
            return "검증 완료"
        }
    }
}

private struct NearbyRecommendationEmptyView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 30, height: 30)
                .background(AppColors.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(message)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}

struct HomeContextPill: View {
    let symbolName: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}

struct HomeSearchResultsView: View {
    let query: String
    let spotRecommendations: [GPTRecommendedSpot]
    let communityPosts: [CommunityPost]
    let spots: [PhotoSpot]
    let message: String?
    let isLoading: Bool
    let onDismiss: () -> Void
    let onRequestAI: () -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    let onSelectCommunityPost: (CommunityPost) -> Void

    private var hasResults: Bool {
        !spotRecommendations.isEmpty || !communityPosts.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("검색 결과")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(AppColors.primary)

                            Text(query.isEmpty ? "출사지" : query)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(width: 36, height: 36)
                                .background(AppColors.primarySoft, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if isLoading {
                        SearchStatusRow(message: "검색 중이에요", isLoading: true, isError: false)
                    } else if !hasResults {
                        EmptySearchResultView(
                            message: message ?? "\(query) 출사지 데이터가 아직 부족해요.",
                            onRequestAI: onRequestAI
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            if !spotRecommendations.isEmpty {
                                SearchResultSectionHeader(title: "출사지 결과", count: spotRecommendations.count)

                                LazyVStack(spacing: 10) {
                                    ForEach(spotRecommendations) { recommendation in
                                        Button {
                                            onSelectSpot(recommendation.spot)
                                        } label: {
                                            HomeSearchResultCard(recommendation: recommendation)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !communityPosts.isEmpty {
                                SearchResultSectionHeader(title: "커뮤니티 글 결과", count: communityPosts.count)

                                LazyVStack(spacing: 10) {
                                    ForEach(communityPosts) { post in
                                        Button {
                                            onSelectCommunityPost(post)
                                        } label: {
                                            CommunityPostSearchResultCard(
                                                post: post,
                                                spot: spot(for: post)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        spots.first { $0.id == post.spotID }
    }
}

struct SearchResultSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(AppColors.primarySoft, in: Capsule())

            Spacer(minLength: 0)
        }
    }
}

struct HomeSearchResultCard: View {
    let recommendation: GPTRecommendedSpot

    private var spot: PhotoSpot {
        recommendation.spot
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SpotVisualTile(spot: spot, width: 96, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text(spot.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(spot.region)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)

                Text(spot.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ForEach(spot.hashtags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(spot.theme.primary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}

struct CommunityPostSearchResultCard: View {
    let post: CommunityPost
    let spot: PhotoSpot?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let spot {
                SpotVisualTile(spot: spot, width: 74, height: 74)
            } else {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 74, height: 74)
                    .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(post.spotName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.7))

                    Text(communityRelativeTimeText(for: post.createdAt))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }

                Text(post.message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.primary.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                CommunityStatusRow(crowd: post.crowd, tags: post.statusTags)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}

struct EmptySearchResultView: View {
    let message: String
    let onRequestAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 44, height: 44)
                .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRequestAI) {
                Label("AI 추천 받기", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(AppColors.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SearchStatusRow: View {
    let message: String
    let isLoading: Bool
    let isError: Bool

    var body: some View {
        HStack(spacing: 9) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isError ? AppColors.crowdCrowded : AppColors.primary)
            }

            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isError ? AppColors.crowdCrowded : AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            (isError ? AppColors.crowdCrowded.opacity(0.10) : AppColors.mutedSurface),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

struct HomeSectionHeader: View {
    let title: String
    let symbolName: String
    let tint: Color
    var showsMore: Bool = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Spacer(minLength: 0)

            if showsMore {
                HStack(spacing: 4) {
                    Text("더보기")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
            }
        }
    }
}

struct FeaturedSpotCard: View {
    let recommendation: GPTRecommendedSpot
    let isSaved: Bool
    let onToggleSave: () -> Void

    private var spot: PhotoSpot {
        recommendation.spot
    }

    private var displayRegion: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SpotVisualTile(spot: spot, width: 232, height: 330, cornerRadius: 22)

            LinearGradient(
                colors: [
                    .black.opacity(0.02),
                    .black.opacity(0.16),
                    .black.opacity(0.70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 9) {
                Text(spot.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.82)

                Text(displayRegion)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)

                Text(recommendation.reason)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)

            VStack {
                HStack {
                    Spacer(minLength: 0)

                    Button {
                        onToggleSave()
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSaved ? AppColors.accent : .white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.18), in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.28), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(width: 232, height: 330)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 4)
    }
}

struct HomeCategorySection: View {
    let category: HomeRecommendationKind
    let recommendations: [GPTRecommendedSpot]
    let isLoading: Bool
    let savedSpotIDs: Set<String>
    let onToggleSave: (PhotoSpot) -> Void
    let onSelect: (PhotoSpot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HomeSectionHeader(title: category.title, symbolName: category.symbolName, tint: category.accentColor, showsMore: recommendations.count > 3)

            if recommendations.isEmpty || isLoading {
                SkeletonRail()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(recommendations) { recommendation in
                            Button {
                                onSelect(recommendation.spot)
                            } label: {
                                CompactSpotCard(
                                    recommendation: recommendation,
                                    isSaved: savedSpotIDs.contains(recommendation.spot.id),
                                    onToggleSave: {
                                        onToggleSave(recommendation.spot)
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .padding(.horizontal, -20)
            }
        }
    }
}

struct CompactSpotCard: View {
    let recommendation: GPTRecommendedSpot
    let isSaved: Bool
    let onToggleSave: () -> Void

    private var spot: PhotoSpot {
        recommendation.spot
    }

    private var detailText: String {
        let region = HomeSpotDisplayFormatter.region(for: spot)
        let reason = recommendation.reason
            .replacingOccurrences(of: "커뮤니티에서 ", with: "")
            .replacingOccurrences(of: " 이야기가 자주 올라오는 출사지예요", with: "")
            .replacingOccurrences(of: " 이야기가 자주 올라오는", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !reason.isEmpty else { return region }
        return "\(region) · \(reason)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SpotVisualTile(spot: spot, width: 166, height: 166, cornerRadius: 17)
                .overlay(alignment: .topTrailing) {
                    Button {
                        onToggleSave()
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSaved ? AppColors.accent : .white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.18), in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.30), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(9)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(spot.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
                    .lineSpacing(1.1)
                    .minimumScaleFactor(0.82)

                Text(detailText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: 166, alignment: .top)
        .contentShape(Rectangle())
    }
}

enum HomeSpotDisplayFormatter {
    private static let replacements: [(String, String)] = [
        ("afternoon", "오후"),
        ("morning", "오전"),
        ("dawn", "새벽"),
        ("goldenHour", "골든아워"),
        ("blueHour", "블루아워"),
        ("sunset", "노을"),
        ("night", "야경"),
        ("rainy", "비 오는 날"),
        ("rain", "비 오는 날"),
        ("walk", "산책"),
        ("picnic", "피크닉"),
        ("portrait", "인물사진"),
        ("coupleSnap", "커플스냅"),
        ("park", "공원"),
        ("film", "필름감성"),
        ("filmMood", "필름무드"),
        ("hidden", "숨은 명소"),
        ("cafe", "카페"),
        ("city", "도시"),
        ("green", "초록"),
        ("flower", "꽃"),
        ("flowerfield", "꽃밭"),
        ("forest", "숲길"),
        ("railroad", "철도"),
        ("retro", "레트로"),
        ("street", "거리"),
        ("autumn", "가을"),
        ("river", "강변"),
        ("lake", "호수"),
        ("calm", "차분함"),
        ("bright", "밝은 분위기"),
        ("architecture", "건축"),
        ("museum", "미술관")
    ]

    static func bestTime(_ value: String) -> String {
        let formatted = formattedTokenString(value)
        return formatted.isEmpty ? "촬영 시간 확인 필요" : formatted
    }

    static func tag(_ value: String) -> String {
        formattedTokenString(value)
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func region(for spot: PhotoSpot) -> String {
        let preferred = spot.recommendationRegions.first { region in
            !["서울", "부산", "경기", "경기도"].contains(region)
        }

        if let preferred {
            return preferred
        }

        if let fallbackRegion = spot.recommendationRegions.first {
            return fallbackRegion
        }

        let compactAddress = spot.region
            .replacingOccurrences(of: "서울특별시", with: "서울")
            .replacingOccurrences(of: "부산광역시", with: "부산")
            .replacingOccurrences(of: "광주광역시", with: "광주")
            .replacingOccurrences(of: "대구광역시", with: "대구")
            .replacingOccurrences(of: "인천광역시", with: "인천")
            .split(separator: " ")
            .prefix(2)
            .joined(separator: " ")

        return compactAddress.isEmpty ? spot.region : compactAddress
    }

    private static func formattedTokenString(_ value: String) -> String {
        var formatted = value
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for (raw, display) in replacements {
            formatted = formatted.replacingOccurrences(
                of: raw,
                with: display,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }

        return formatted
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SpotVisualTile: View {
    let spot: PhotoSpot
    var width: CGFloat? = nil
    let height: CGFloat
    var cornerRadius: CGFloat = 18

    private var resolvedWidth: CGFloat {
        width ?? 170
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoSpotImageView(
                spot: spot,
                symbolSize: height > 80 ? 32 : 23
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )

        }
        .frame(width: resolvedWidth, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

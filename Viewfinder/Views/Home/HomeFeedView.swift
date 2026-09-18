import CoreLocation
import Foundation
import SwiftUI

private final class HomeTabBarVisibilityState {
    var previousDragTranslation: CGFloat?
}

private struct HomePullOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HomePullThresholdModifier: ViewModifier {
    let threshold: CGFloat
    let onThresholdChange: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                let pullDistance = geometry.contentInsets.top - geometry.contentOffset.y
                return pullDistance >= threshold
            } action: { _, isThresholdReached in
                onThresholdChange(isThresholdReached)
            }
        } else {
            content
        }
    }
}

private struct HomeRecommendationLoadingView: View {
    var body: some View {
        AppLoadingOverlay(title: "새로운 출사지 추천 중")
    }
}

/// 장소의 주 테마와 분리된 촬영 시즌 보조 필터입니다.
/// 일반적인 봄/여름/가을/겨울은 모든 장소를 과도하게 묶으므로,
/// 벚꽃·단풍·설경처럼 실제 촬영 시즌 신호가 있을 때만 노출합니다.
private enum HomeSeasonFilter: String, CaseIterable, Identifiable, Hashable {
    case cherryBlossom
    case autumnLeaves
    case snow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cherryBlossom:
            return "벚꽃"
        case .autumnLeaves:
            return "단풍"
        case .snow:
            return "설경"
        }
    }

    var symbol: String {
        switch self {
        case .cherryBlossom:
            return "🌸"
        case .autumnLeaves:
            return "🍁"
        case .snow:
            return "❄️"
        }
    }

    /// 시즌 기간은 이 한 곳에서 조정하면 됩니다. 새 시즌을 추가할 때도
    /// 케이스와 해당 월만 함께 정의하면 필터 UI가 자동으로 따라옵니다.
    var activeMonths: Set<Int> {
        switch self {
        case .cherryBlossom:
            return [3, 4, 5]
        case .autumnLeaves:
            return [10, 11]
        case .snow:
            return [12, 1, 2]
        }
    }

    func isActive(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        activeMonths.contains(calendar.component(.month, from: date))
    }

    func matches(_ spot: PhotoSpot) -> Bool {
        let seasonalText = (
            spot.season
                + spot.hashtags
                + spot.mood
                + [spot.summary]
        )
            .joined(separator: " ")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        switch self {
        case .cherryBlossom:
            return ["벚꽃", "벚꽃시즌", "cherryblossom"].contains {
                seasonalText.contains($0)
            }
        case .autumnLeaves:
            return ["단풍", "낙엽", "가을단풍", "autumnleaves"].contains {
                seasonalText.contains($0)
            }
        case .snow:
            return ["설경", "눈꽃", "눈길", "눈온", "snowy", "winterlandscape"].contains {
                seasonalText.contains($0)
            }
        }
    }
}

/// 이미 로드된 장소를 현재 사용할 수 있는 인기 신호로 정렬합니다.
///
/// 출사지별 조회수·전체 저장 수·방문 수는 아직 제공되지 않으므로 임의의
/// 가중치 점수를 만들지 않고, 신호를 우선순위대로 비교합니다. 향후 백엔드가
/// 실제 인기 지표를 제공하면 이 타입의 신호와 정렬 규칙만 교체하면 됩니다.
private struct HomePopularityScorer {
    private struct RankedCandidate {
        let recommendation: RecommendedSpot
        let communityPostCount: Int
        let likeCount: Int
        let latestInteractionAt: Date
        let sourceOrder: Int
    }

    func rank(
        _ recommendations: [RecommendedSpot],
        communityPosts: [CommunityPost]
    ) -> [RecommendedSpot] {
        let postsBySpot = Dictionary(grouping: communityPosts, by: { $0.spotID })

        return recommendations
            .enumerated()
            .map { sourceOrder, recommendation in
                let matchingPosts = postsBySpot[recommendation.spot.id] ?? []

                return RankedCandidate(
                    recommendation: recommendation,
                    communityPostCount: matchingPosts.count,
                    likeCount: matchingPosts.reduce(0) { $0 + $1.likeCount },
                    latestInteractionAt: matchingPosts.map(\.createdAt).max() ?? .distantPast,
                    sourceOrder: sourceOrder
                )
            }
            .sorted { left, right in
                if left.communityPostCount != right.communityPostCount {
                    return left.communityPostCount > right.communityPostCount
                }

                if left.likeCount != right.likeCount {
                    return left.likeCount > right.likeCount
                }

                if left.latestInteractionAt != right.latestInteractionAt {
                    return left.latestInteractionAt > right.latestInteractionAt
                }

                return left.sourceOrder < right.sourceOrder
            }
            .map(\.recommendation)
    }
}

struct HomeFeedView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let searchableSpots: [PhotoSpot]
    let geographicCandidateSpots: [PhotoSpot]
    let recommendedSpots: [PhotoSpot]
    let communityPosts: [CommunityPost]
    let preloadedRecommendations: [RecommendedSpot]
    let recommendationState: HomeRecommendationState
    let sectionRecommendations: [HomeRecommendationKind: [RecommendedSpot]]
    let expandedSectionRecommendations: [HomeRecommendationKind: [RecommendedSpot]]
    let loadingSectionIDs: Set<String>
    let isPreloadingRecommendations: Bool
    let currentLocationTitle: String
    let weatherSnapshot: WeatherSnapshot?
    let weatherLoadFailed: Bool
    let weatherIsLoading: Bool
    let savedSpotIDs: Set<String>
    @ObservedObject var searchViewModel: PhotoSpotSearchViewModel
    let userLocation: CLLocationCoordinate2D?
    let onAddAISpot: (PhotoSpot) -> Void
    let onShowDetail: (PhotoSpot) -> Void
    let onShowSearchDetail: (PhotoSpot) -> Void
    let onReportMissingPhoto: (PhotoSpot) -> Void
    let onAddPlace: () -> Void
    let onToggleSave: (PhotoSpot) -> Void
    let onOpenMap: (PhotoSpot?) -> Void
    let onShowWeather: () -> Void
    let onShowCurrentLocation: () -> Void
    let onTabBarVisibilityChange: (Bool) -> Void
    let onTabBarDragChange: (CGFloat) -> Void
    let onTabBarDragEnd: (CGFloat) -> Void
    let onRefreshRecommendations: () async -> Void
    private let searchProvider: any SearchProvider = LocalKeywordSearchProvider()
    @Binding var isSearchResultsPresented: Bool
    let onSearchDismissed: () -> Void
    let onPerformSearchAction: (@escaping () -> Void) -> Void
    @State private var searchScrollAnchor: String?
    @State private var searchReturnAnchor: String?
    @StateObject private var searchPlaceFinder = PlaceFinder(resultLimit: 6)
    @State private var selectedCategory: HomeRecommendationKind?
    @State private var selectedTheme: SpotTheme?
    @State private var selectedSeason: HomeSeasonFilter?
    @State private var keywordSearchResults = KeywordSearchResults.empty
    @State private var tabBarVisibilityState = HomeTabBarVisibilityState()
    @State private var isRefreshArmed = false
    @State private var isRefreshingRecommendations = false
    private let popularityScorer = HomePopularityScorer()

    private let refreshTriggerOffset: CGFloat = 210
    private let homeScrollCoordinateSpace = "homeDiscoveryScroll"

    private struct DiscoverySnapshot {
        let heroRecommendations: [RecommendedSpot]
        let popularRecommendations: [RecommendedSpot]
        let topFiveRecommendations: [RecommendedSpot]
        let availableThemes: [SpotTheme]
        let availableSeasons: [HomeSeasonFilter]
        let activeTheme: SpotTheme?
        let activeSeason: HomeSeasonFilter?
        let themeRecommendations: [RecommendedSpot]
    }

    private var recommendations: [RecommendedSpot] {
        let rawRecommendations: [RecommendedSpot]

        if !preloadedRecommendations.isEmpty {
            rawRecommendations = preloadedRecommendations
        } else {
            rawRecommendations = recommendedSpots.map {
                RecommendedSpot(
                    spot: $0,
                    reason: $0.eventPeriod
                )
            }
        }

        return homeRailRecommendations(rawRecommendations)
    }

    private var hasRecommendationFailure: Bool {
        if case .failed = recommendationState {
            return true
        }
        return false
    }

    /// 한 번의 View 갱신에서 인기 정렬과 테마 필터 결과를 한 번만 계산합니다.
    /// Hero/TOP 5/테마 영역의 기존 데이터 규칙은 그대로 유지합니다.
    private func makeDiscoverySnapshot(
        heroRecommendations: [RecommendedSpot],
        referenceDate: Date = Date()
    ) -> DiscoverySnapshot {
        let geographicCandidateIDs = Set(geographicCandidateSpots.map(\.id))
        let scopedHeroRecommendations = heroRecommendations.filter {
            geographicCandidateIDs.contains($0.spot.id)
        }
        let seeded = scopedHeroRecommendations
            + categories.flatMap { recommendations(for: $0) }
            + geographicCandidateSpots.map { RecommendedSpot(spot: $0, reason: $0.summary) }
        let allLoadedRecommendations = uniqueRecommendations(seeded)
            .filter { geographicCandidateIDs.contains($0.spot.id) }
            .filter { hasDisplayImage($0.spot) }
        let rankedCandidates = popularityScorer.rank(
            allLoadedRecommendations,
            communityPosts: communityPosts
        )
        let postsBySpot = Dictionary(grouping: communityPosts, by: { $0.spotID })
        let popularRecommendations = rankedCandidates.map { recommendation in
            let matchingPosts = postsBySpot[recommendation.spot.id] ?? []
            let likeCount = matchingPosts.reduce(0) { $0 + $1.likeCount }
            let reason: String

            if !matchingPosts.isEmpty {
                reason = likeCount > 0
                    ? "제보 \(matchingPosts.count) · 반응 \(likeCount)"
                    : "최근 제보 \(matchingPosts.count)"
            } else {
                reason = ""
            }

            return RecommendedSpot(spot: recommendation.spot, reason: reason)
        }
        let availableThemeValues = Set(popularRecommendations.map { $0.spot.theme })

        // SpotTheme.allCases가 최종 표시 순서를 소유합니다.
        // 데이터가 없는 테마만 숨기고, 테마 선택은 TOP 5와 분리된 전체 후보를 사용합니다.
        let availableThemes = SpotTheme.allCases.filter { availableThemeValues.contains($0) }
        let availableSeasons = HomeSeasonFilter.allCases.filter { season in
            season.isActive(on: referenceDate)
                && popularRecommendations.contains { season.matches($0.spot) }
        }

        let resolvedTheme: SpotTheme?
        if selectedSeason != nil {
            // 시즌을 고른 동안에는 일반 테마의 기본 선택이 끼어들지 않게 합니다.
            resolvedTheme = nil
        } else if let selectedTheme, availableThemes.contains(selectedTheme) {
            resolvedTheme = selectedTheme
        } else {
            // "전체" 없이 진입하므로 첫 번째로 사용 가능한 테마를 기본 선택합니다.
            resolvedTheme = availableThemes.first
        }

        let resolvedSeason = selectedSeason.flatMap { season in
            availableSeasons.contains(season) ? season : nil
        }
        let filteredRecommendations: [RecommendedSpot]
        if let resolvedTheme {
            filteredRecommendations = popularRecommendations.filter {
                $0.spot.theme == resolvedTheme
            }
        } else if let resolvedSeason {
            filteredRecommendations = popularRecommendations.filter {
                resolvedSeason.matches($0.spot)
            }
        } else {
            filteredRecommendations = popularRecommendations
        }

        return DiscoverySnapshot(
            heroRecommendations: scopedHeroRecommendations,
            popularRecommendations: popularRecommendations,
            topFiveRecommendations: Array(popularRecommendations.prefix(5)),
            availableThemes: availableThemes,
            availableSeasons: availableSeasons,
            activeTheme: resolvedTheme,
            activeSeason: resolvedSeason,
            themeRecommendations: uniqueThemeRecommendations(filteredRecommendations)
        )
    }

    private func uniqueRecommendations(_ items: [RecommendedSpot]) -> [RecommendedSpot] {
        var seenIDs = Set<String>()
        return items.filter { item in
            seenIDs.insert(item.spot.id).inserted
        }
    }

    /// 테마 영역은 서로 다른 데이터 원천이 합쳐질 수 있으므로 장소 ID뿐 아니라
    /// 지도 검색어도 함께 비교합니다. 같은 장소가 다른 ID로 들어와도 2-card 레이아웃에
    /// 중복으로 노출되지 않게 하는 테마 전용 dedupe입니다.
    private func uniqueThemeRecommendations(_ items: [RecommendedSpot]) -> [RecommendedSpot] {
        var seenIDs = Set<String>()
        var seenMapQueries = Set<String>()

        return items.filter { item in
            guard !seenIDs.contains(item.spot.id),
                  !seenMapQueries.contains(item.spot.mapQuery) else {
                return false
            }

            seenIDs.insert(item.spot.id)
            seenMapQueries.insert(item.spot.mapQuery)
            return true
        }
    }

    private var categories: [HomeRecommendationKind] {
        HomeRecommendationKind.allCases
    }

    private var verifiedRecommendations: [RecommendedSpot] {
        searchViewModel.verifiedSpots.map { verifiedSpot in
            RecommendedSpot(
                spot: verifiedSpot.photoSpot,
                reason: verifiedSpot.reason
            )
        }
    }

    private var keywordSpotRecommendations: [RecommendedSpot] {
        keywordSearchResults.spots.map {
            RecommendedSpot(
                spot: $0,
                reason: $0.eventPeriod
            )
        }
    }

    private var combinedSearchRecommendations: [RecommendedSpot] {
        var seenIDs = Set<String>()
        var seenMapQueries = Set<String>()

        let results = (keywordSpotRecommendations + verifiedRecommendations).filter { recommendation in
            guard !seenIDs.contains(recommendation.spot.id),
                  !seenMapQueries.contains(recommendation.spot.mapQuery) else {
                return false
            }

            seenIDs.insert(recommendation.spot.id)
            seenMapQueries.insert(recommendation.spot.mapQuery)
            return true
        }

        return PlaceNameSearchRanking.ranked(
            results,
            query: searchViewModel.searchText,
            name: \.spot.name
        )
    }

    var body: some View {
        NavigationStack {
            homeContent
            .background(AppColors.feedBackground.ignoresSafeArea())
            // nav bar 를 완전히 제거합니다. 사진이 상태바까지 올라가야 하고,
            // 검색 버튼은 사진 위에 떠 있는 유리 컨트롤이어야 합니다.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedCategory) { category in
                HomeCategoryListView(
                    category: category,
                    recommendations: expandedRecommendations(for: category),
                    savedSpotIDs: savedSpotIDs,
                    onToggleSave: onToggleSave,
                    onSelect: onShowDetail,
                    onReportMissingPhoto: onReportMissingPhoto
                )
            }
            .onAppear {
                tabBarVisibilityState.previousDragTranslation = nil
                isRefreshArmed = false
                onTabBarVisibilityChange(false)
            }
        }
        .accessibilityHidden(isSearchResultsPresented)
        .fullScreenCover(isPresented: $isSearchResultsPresented, onDismiss: onSearchDismissed) {
            HomeSearchResultsView(
                query: $searchViewModel.searchText,
                scrollAnchor: $searchScrollAnchor,
                returnAnchor: searchReturnAnchor,
                placeFinder: searchPlaceFinder,
                spotRecommendations: combinedSearchRecommendations,
                communityPosts: keywordSearchResults.communityPosts,
                spots: searchableSpots,
                message: searchViewModel.message,
                isLoading: searchViewModel.isLoading,
                onSubmitSearch: performSearch,
                onDismiss: {
                    searchReturnAnchor = nil
                    isSearchResultsPresented = false
                },
                onSelectSpot: { spot in
                    performSearchAction(returningTo: spot.id) {
                        onAddAISpot(spot)
                        onShowSearchDetail(spot)
                    }
                },
                onReportMissingPhoto: { spot in
                    performSearchAction(returningTo: spot.id) { onReportMissingPhoto(spot) }
                },
                onAddPlace: {
                    performSearchAction(action: onAddPlace)
                },
                onSelectCommunityPost: { post in
                    guard let spot = spot(for: post) else { return }
                    performSearchAction {
                        onShowSearchDetail(spot)
                    }
                },
                onQueryChange: performLocalKeywordSearch
            )
        }
    }

    private func performSearchAction(returningTo fallbackAnchor: String? = nil, action: @escaping () -> Void) {
        // ScrollView may clear its binding while the cover is dismissed.
        // Keep the return destination independently until the search reappears.
        searchReturnAnchor = searchScrollAnchor ?? fallbackAnchor
        onPerformSearchAction(action)
    }

    private var homeContent: some View {
        // Hero 크기를 추측하지 않고 측정합니다.
        // containerRelativeFrame 이 기대와 다르게 해석되어 카드가 화면 절반 폭으로
        // 렌더되었고, Hero 에 사진 두 장이 반쪽씩 보이는 문제가 있었습니다.
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let heroHeight = (proxy.size.height + topInset) * VFPhoto.heroHeightRatio

            discoveryPage(
                heroSize: CGSize(width: proxy.size.width, height: heroHeight),
                topInset: topInset
            )
        }
        .background(AppColors.feedBackground)
    }

    private func discoveryPage(heroSize: CGSize, topInset: CGFloat) -> some View {
        let discovery = makeDiscoverySnapshot(heroRecommendations: recommendations)
        let shouldShowInitialRecommendationSkeleton = recommendationState == .initialLoading
            && discovery.heroRecommendations.isEmpty
            && discovery.popularRecommendations.isEmpty

        return ScrollView(showsIndicators: false) {
            // Hero와 TOP 5는 기존 흐름을 유지하고, 테마 탐색은 별도 챕터로 분리합니다.
            LazyVStack(alignment: .leading, spacing: 0) {
                if shouldShowInitialRecommendationSkeleton {
                    HomeInitialLoadingSkeleton(
                        heroSize: heroSize,
                        topInset: topInset
                    )
                    .transition(.opacity)
                } else if hasRecommendationFailure && discovery.popularRecommendations.isEmpty {
                    HomeRecommendationFailureView(onRetry: onRefreshRecommendations)
                        .vfScreenMargin()
                        .padding(.top, topInset + VFSpace.lg)
                        .transition(.opacity)
                } else if recommendationState == .locationUnavailable {
                    HomeLocationUnavailableView(
                        onRetry: onRefreshRecommendations,
                        onSearch: { isSearchResultsPresented = true }
                    )
                    .vfScreenMargin()
                    .padding(.top, topInset + VFSpace.lg)
                    .transition(.opacity)
                } else {
                    if discovery.popularRecommendations.isEmpty {
                        HomeRegionalEmptyView(
                            onAddPlace: onAddPlace,
                            onSearch: { isSearchResultsPresented = true }
                        )
                        .vfScreenMargin()
                        .padding(.top, topInset + VFSpace.lg)
                    } else {
                        VStack(alignment: .leading, spacing: VFSpace.md) {
                            if !discovery.heroRecommendations.isEmpty {
                                todaySection(
                                    heroSize: heroSize,
                                    topInset: topInset,
                                    recommendations: discovery.heroRecommendations
                                )
                            }

                            if !discovery.popularRecommendations.isEmpty {
                                HomeSpotRailSection(
                                    title: discovery.popularRecommendations.count >= 5
                                        ? "인기 출사지 TOP 5"
                                        : "인기 출사지",
                                    recommendations: discovery.topFiveRecommendations,
                                    onSelect: onShowDetail,
                                    showsRank: true
                                )
                            }
                        }
                    }

                    if !discovery.popularRecommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("테마별 출사지")
                                .vfText(.title2)
                                .foregroundStyle(AppColors.primary)
                                .vfScreenMargin()
                                .accessibilityAddTraits(.isHeader)

                            HomeThemeFilterSection(
                                themes: discovery.availableThemes,
                                seasons: discovery.availableSeasons,
                                selectedTheme: discovery.activeTheme,
                                selectedSeason: discovery.activeSeason,
                                onSelectTheme: { theme in
                                    withAnimation(VFMotion.quick) {
                                        selectedTheme = theme
                                        selectedSeason = nil
                                    }
                                },
                                onSelectSeason: { season in
                                    withAnimation(VFMotion.quick) {
                                        selectedTheme = nil
                                        selectedSeason = season
                                    }
                                }
                            )
                            .padding(.top, VFSpace.sm)

                            HomeSpotRailSection(
                                title: "테마별 출사지",
                                recommendations: discovery.themeRecommendations,
                                onSelect: onShowDetail,
                                showsRank: false,
                                showsTitle: false
                            )
                            .padding(.top, VFSpace.md)
                            // 테마가 바뀌면 새 레일을 만들어 이전 테마의 가로 위치를
                            // 남기지 않고 첫 카드부터 다시 탐색하게 합니다.
                            .id(
                                discovery.activeTheme?.rawValue
                                    ?? discovery.activeSeason?.rawValue
                                    ?? "none"
                            )
                        }
                        .padding(.top, VFSpace.xxl)
                    }
                }
            }
            // 마지막 카드가 floating 탭바에 가리지 않도록 최소 여유만 둡니다.
            // 테마 카드 2장 레이아웃에서는 기존 120pt가 카드 아래 불필요한 빈 공간으로
            // 보였으므로 64pt로 줄였습니다.
            .padding(.bottom, 64)
            .background(alignment: .top) {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HomePullOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(homeScrollCoordinateSpace)).minY
                    )
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: recommendationState)
        .coordinateSpace(name: homeScrollCoordinateSpace)
        .modifier(
            HomePullThresholdModifier(
                threshold: refreshTriggerOffset,
                onThresholdChange: handleRefreshThresholdChange
            )
        )
        .onPreferenceChange(HomePullOffsetPreferenceKey.self) { offset in
            guard #unavailable(iOS 18.0) else {
                return
            }
            handleRefreshThresholdChange(offset >= refreshTriggerOffset)
        }
        .overlay(alignment: .top) {
            Image(systemName: "arrow.down")
                // Dynamic Type 제외: 고정 32pt 당겨서 새로고침 표시.
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .vfGlass()
                .padding(.top, topInset + VFSpace.sm)
            .offset(y: isRefreshArmed ? 0 : -12)
            .opacity(isRefreshArmed ? 1 : 0)
            .allowsHitTesting(false)
            .animation(.smooth(duration: 0.20), value: isRefreshArmed)
        }
        .overlay {
            if isRefreshingRecommendations {
                HomeRecommendationLoadingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        // 사진이 상태바까지 올라갑니다.
        .ignoresSafeArea(edges: .top)
        // 스크롤한 본문이 상태바와 겹쳐 읽히는 것을 시스템 재료로 막습니다.
        .modifier(VFTopScrollEdgeEffect())
        .background(AppColors.feedBackground)
    }

    private var tabBarVisibilityDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard recommendationState != .initialLoading else { return }
                let verticalTranslation = value.translation.height
                let horizontalTranslation = value.translation.width

                guard abs(verticalTranslation) > abs(horizontalTranslation) * 1.2 else {
                    tabBarVisibilityState.previousDragTranslation = nil
                    return
                }

                let previousTranslation = tabBarVisibilityState.previousDragTranslation ?? verticalTranslation
                let delta = verticalTranslation - previousTranslation
                tabBarVisibilityState.previousDragTranslation = verticalTranslation

                guard abs(delta) > 0.1 else { return }
                onTabBarDragChange(delta)
            }
            .onEnded { value in
                guard recommendationState != .initialLoading else { return }
                let projectedDelta = value.predictedEndTranslation.height - value.translation.height
                tabBarVisibilityState.previousDragTranslation = nil
                onTabBarDragEnd(projectedDelta)
            }
    }

    private func handleRefreshThresholdChange(_ isThresholdReached: Bool) {
        guard !isRefreshingRecommendations else { return }

        if isThresholdReached {
            guard !isRefreshArmed else { return }
            withAnimation(.smooth(duration: 0.18)) {
                isRefreshArmed = true
            }
            return
        }

        guard isRefreshArmed else { return }
        startRefreshRecommendations()
    }

    @MainActor
    private func startRefreshRecommendations() {
        guard !isRefreshingRecommendations else { return }

        withAnimation(.smooth(duration: 0.18)) {
            isRefreshArmed = false
            isRefreshingRecommendations = true
        }

        Task {
            await onRefreshRecommendations()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.18)) {
                    isRefreshingRecommendations = false
                }
            }
        }
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
                    // Dynamic Type 제외: 48pt 로고 판 안의 기호. 판이 안 커지므로 기호도 안 커진다.
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("뷰파인더")
                    .vfText(.title1.weight(.bold))
                    .foregroundStyle(AppColors.primary)

                Text("오늘의 프레임을 찾는 출사 큐레이션")
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// 로컬 키워드 검색만 실행합니다.
    ///
    /// performSearch 는 로컬 검색 뒤에 AI 검색까지 이어서 돌립니다.
    /// AI 는 돈과 시간이 드니 키 입력마다 부를 수 없습니다.
    /// 입력 중에는 이 함수만 돌리고, AI 는 결과가 없을 때 사용자가
    /// 명시적으로 요청하도록 남겨둡니다.
    private func performLocalKeywordSearch() {
        let query = searchViewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            keywordSearchResults = .empty
            return
        }

        keywordSearchResults = searchProvider.search(
            query: query,
            spots: searchableSpots,
            communityPosts: communityPosts
        )

    }

    private func performSearch() {
        let query = searchViewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !searchViewModel.isLoading else { return }

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
                isSearchResultsPresented = true
            }
        }
    }

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        searchableSpots.first { $0.id == post.spotID }
    }

    // Phase 2A: 272x352 고정 카드 카로셀을 full-bleed Hero 로 교체했습니다.
    // 섹션 헤더("오늘의 프레임")는 제거했습니다 — 사진이 헤더 역할을 합니다.
    private func todaySection(
        heroSize: CGSize,
        topInset: CGFloat,
        recommendations: [RecommendedSpot]
    ) -> some View {
        HomeHeroSection(
            recommendations: recommendations,
            userLocation: userLocation,
            cardSize: heroSize,
            topInset: topInset,
            contextText: heroContextText,
            contextSymbolName: heroContextSymbol,
            contextIsLoading: weatherIsLoading
                || (weatherSnapshot == nil && userLocation != nil && !weatherLoadFailed),
            onShowContext: onShowWeather,
            heroReasonTimeText: heroReasonTimeText,
            savedSpotIDs: savedSpotIDs,
            onToggleSave: onToggleSave,
            onSelect: onShowDetail,
            onSearch: { isSearchResultsPresented = true }
        )
    }

    /// Hero 좌상단 캡슐의 짧은 요약입니다.
    /// 다음 일출·일몰 선택 로직은 유지하되, 홈에서는 카운트다운 대신
    /// 절대 시각을 보여줍니다. 상세 화면이 카운트다운을 담당합니다.
    /// 예) "일몰 19:14 · 32° · 맑음"
    private var heroContextText: String? {
        guard let snapshot = weatherSnapshot else { return nil }

        let condition = snapshot.condition == "구름 조금" ? "구름 적음" : snapshot.condition
        return [snapshot.nextSunEvent?.shortLabel, snapshot.displayText, condition]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }

    /// Hero에서는 카운트다운을 장소 맥락으로만 짧게 사용합니다.
    /// 예) "성수 · 32분 · 블루아워"
    private var heroReasonTimeText: String? {
        weatherSnapshot?.nextSunEvent?.countdownDurationLabel
    }

    /// 일몰 전이면 sunset, 일몰 후면 sunrise 아이콘.
    private var heroContextSymbol: String {
        weatherSnapshot?.nextSunEvent?.symbolName
            ?? weatherSnapshot?.symbolName
            ?? "sun.max"
    }

    private func recommendations(for category: HomeRecommendationKind) -> [RecommendedSpot] {
        homeRailRecommendations(sectionRecommendations[category] ?? [])
    }

    private func expandedRecommendations(for category: HomeRecommendationKind) -> [RecommendedSpot] {
        imagePrioritizedRecommendations(
            expandedSectionRecommendations[category] ?? sectionRecommendations[category] ?? []
        )
    }

    private func imagePrioritizedRecommendations(_ recommendations: [RecommendedSpot]) -> [RecommendedSpot] {
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

    private func homeRailRecommendations(_ recommendations: [RecommendedSpot]) -> [RecommendedSpot] {
        imagePrioritizedRecommendations(recommendations)
            .filter { hasDisplayImage($0.spot) }
    }

    private func hasDisplayImage(_ spot: PhotoSpot) -> Bool {
        spot.hasReliableDisplayImage
    }

}

private struct HomeLocationUnavailableView: View {
    let onRetry: () async -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            AppStatePanel(
                symbolName: "location.slash",
                title: "현재 위치를 확인하면 주변 출사지를 추천해드려요",
                message: "위치 권한을 확인하거나 검색으로 장소를 찾아보세요.",
                actionTitle: "다시 확인하기",
                action: {
                    Task { await onRetry() }
                }
            )

            Button("출사지 검색", action: onSearch)
                .vfText(.callout)
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, VFSpace.md + 2)
                .frame(minHeight: AppLayout.touchTarget)
                .background(AppColors.accentSoft, in: Capsule())
                .buttonStyle(.plain)
                .padding(.leading, VFSpace.lg + VFSpace.xs)
        }
    }
}

private struct HomeRegionalEmptyView: View {
    let onAddPlace: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.sm) {
            Text("이 지역의 출사지를 아직 찾지 못했어요")
                .vfText(.headline)
                .foregroundStyle(AppColors.primary)

            Text("좋은 장소를 발견했다면 직접 추가해보세요")
                .vfText(.body)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: VFSpace.sm) {
                Button("장소 추가하기", action: onAddPlace)
                Button("출사지 검색", action: onSearch)
            }
            .vfText(.callout)
            .foregroundStyle(AppColors.accent)
        }
        .padding(.vertical, VFSpace.lg)
    }
}

struct NearbyRecommendationEmptyView: View {
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        AppStatePanel(
            symbolName: "location.magnifyingglass",
            title: message,
            message: "현재 위치와 등록된 장소를 기준으로 다시 확인해보세요.",
            actionTitle: actionTitle,
            action: action
        )
    }
}

/// 추천 요청이 아직 끝나지 않았을 때만 보여주는 홈 전용 Skeleton입니다.
/// 실제 Hero/TOP 5/테마 레일의 순서와 대략적인 크기를 그대로 예약해 두어
/// 데이터가 도착할 때 화면이 위아래로 크게 점프하지 않게 합니다.
private struct HomeInitialLoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDimmed = false
    let heroSize: CGSize
    let topInset: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeLoadingHeroPlaceholder(
                size: heroSize,
                topInset: topInset
            )

            HomeLoadingPageIndicator()
                .frame(maxWidth: .infinity)
                .frame(height: VFSpace.lg)

            HomeLoadingRailSection(title: "인기 출사지 TOP 5")
                .padding(.top, VFSpace.md)

            VStack(alignment: .leading, spacing: 0) {
                Text("테마별 출사지")
                    .vfText(.title2)
                    .foregroundStyle(AppColors.primary)
                    .vfScreenMargin()

                HomeLoadingFilterRow()
                    .padding(.top, VFSpace.sm)
                HomeLoadingRailSection(title: nil)
                    .padding(.top, VFSpace.md)
            }
            .padding(.top, VFSpace.xxl)
        }
        .opacity(isDimmed ? 0.78 : 1)
        .task(id: reduceMotion || scenePhase != .active) {
            guard !reduceMotion, scenePhase == .active else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isDimmed = false }
                return
            }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.6)) { isDimmed.toggle() }
                do { try await Task.sleep(for: .milliseconds(1600)) }
                catch { return }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("홈 콘텐츠를 불러오는 중")
    }
}

private struct HomeLoadingHeroPlaceholder: View {
    let size: CGSize
    let topInset: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [AppColors.mutedSurface.opacity(0.55), AppColors.mutedSurface, AppColors.feedBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            HStack(spacing: VFSpace.sm) {
                Capsule()
                    .fill(AppColors.secondaryText.opacity(0.14))
                    .frame(width: min(190, size.width * 0.46), height: 38)

                Spacer(minLength: VFSpace.sm)

                Circle()
                    .fill(AppColors.secondaryText.opacity(0.14))
                    .frame(width: 38, height: 38)
            }
            .padding(.horizontal, VFSpace.lg - VFSpace.xs)
            .padding(.top, topInset + VFSpace.sm)

            VStack(alignment: .leading, spacing: VFSpace.sm) {
                Text("출사지 이름")
                    .vfText(.display)
                    .redacted(reason: .placeholder)
                Text("거리 · 촬영 조건")
                    .vfText(.mono)
                    .redacted(reason: .placeholder)
            }
            .foregroundStyle(AppColors.secondaryText.opacity(0.22))
            .padding(.horizontal, VFSpace.lg)
            .padding(.bottom, VFSpace.xxl + VFSpace.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

private struct HomeLoadingRailSection: View {
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            if let title {
                Text(title)
                    .vfText(.title2)
                    .foregroundStyle(AppColors.primary)
                    .vfScreenMargin()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: VFSpace.md) {
                    ForEach(0..<2, id: \.self) { _ in
                        HomeLoadingPhotoCard()
                            .containerRelativeFrame(.horizontal) { length, _ in
                                length * (title == nil ? 0.42 : 0.46)
                            }
                    }
                }
                .padding(.horizontal, VFSpace.lg)
            }
            .scrollClipDisabled()
        }
    }
}

private struct HomeLoadingPhotoCard: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
                .fill(LinearGradient(
                    colors: [AppColors.mutedSurface.opacity(0.45), AppColors.mutedSurface],
                    startPoint: .top,
                    endPoint: .bottom
                ))

            VStack(alignment: .leading, spacing: VFSpace.xs) {
                Text("출사지 이름")
                    .vfText(.headline)
                    .lineLimit(1)
                Text("지역 · 촬영 조건")
                    .vfText(.mono)
                    .lineLimit(1)
            }
            .foregroundStyle(AppColors.secondaryText.opacity(0.22))
            .redacted(reason: .placeholder)
            .padding(.horizontal, VFSpace.md + 2)
            .padding(.bottom, VFSpace.md)
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
    }
}

private struct HomeLoadingFilterRow: View {
    private let widths: [CGFloat] = [86, 94, 98]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: VFSpace.sm) {
                ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                    Capsule()
                        .fill(AppColors.mutedSurface)
                        .frame(width: width, height: 30)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, VFSpace.lg)
        }
        .scrollClipDisabled()
    }
}

private struct HomeLoadingPageIndicator: View {
    var body: some View {
        HStack(spacing: VFSpace.sm) {
            Circle()
                .fill(AppColors.secondaryText.opacity(0.36))
                .frame(width: 5, height: 5)
            Capsule()
                .fill(AppColors.secondaryText.opacity(0.58))
                .frame(width: 13, height: 5)
            Circle()
                .fill(AppColors.secondaryText.opacity(0.36))
                .frame(width: 5, height: 5)
        }
        .accessibilityHidden(true)
    }
}

private struct HomeRecommendationFailureView: View {
    let onRetry: () async -> Void

    var body: some View {
        AppStatePanel(
            symbolName: "arrow.clockwise",
            title: "추천을 불러오지 못했어요",
            message: "잠시 후 다시 시도해주세요.",
            actionTitle: "다시 시도",
            action: {
                Task {
                    await onRetry()
                }
            }
        )
    }
}

struct HomeSearchResultsView: View {
    @Binding var query: String
    @Binding var scrollAnchor: String?
    let returnAnchor: String?
    @ObservedObject var placeFinder: PlaceFinder
    let spotRecommendations: [RecommendedSpot]
    let communityPosts: [CommunityPost]
    let spots: [PhotoSpot]
    let message: String?
    let isLoading: Bool
    let onSubmitSearch: () -> Void
    let onDismiss: () -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    let onReportMissingPhoto: (PhotoSpot) -> Void
    let onAddPlace: () -> Void
    let onSelectCommunityPost: (CommunityPost) -> Void
    /// 입력하는 즉시 실행되는 로컬 키워드 검색.
    /// AI 검색(onSubmitSearch)과 분리했습니다.
    let onQueryChange: () -> Void
    @FocusState private var isSearchFocused: Bool
    @AppStorage("viewfinder.homeSearch.recentQueries") private var recentQueryStorage = ""

    private enum Layout {
        static let searchContentInset: CGFloat = 16
        static let historyTopSpacing: CGFloat = 24
    }

    // ═══════════════════════════════════════════════════════════════
    //  홈 검색이 세 갈래로 나뉩니다.
    //
    //  [문제였던 상황]
    //  안내 문구가 "앱의 출사지와 실제 장소를 함께 찾아드려요" 라고
    //  약속하는데, 실제 장소는 찾지 않았습니다.
    //  지도와 제보 화면은 네이버 실제 장소검색을 쓰는데 홈만 안 썼습니다.
    //
    //  그리고 검색이 화살표 버튼을 눌러야 실행됐습니다.
    //  performSearch 가 로컬 검색과 AI 검색을 한 번에 하기 때문입니다.
    //  AI 는 돈과 시간이 드니 키 입력마다 부를 수 없었습니다.
    //
    //  [나눈 기준]
    //    로컬 키워드   즉시. 동기 함수이고 비용이 없습니다.
    //    실제 장소     입력이 멈춘 뒤 350ms. PlaceFinder 가 담당합니다.
    //    AI 추천       명시적으로 요청할 때만. 결과가 없을 때 권합니다.
    // ═══════════════════════════════════════════════════════════════

    /// 앱에 없는 장소만 남깁니다.
    /// 등록된 장소는 위쪽 "출사지 결과" 에 이미 나옵니다.
    private var unknownPlaces: [PlaceSearchResult] {
        placeFinder.results.filter { !$0.isKnown }
    }

    private var hasResults: Bool {
        !spotRecommendations.isEmpty || !communityPosts.isEmpty || !unknownPlaces.isEmpty
    }

    private var recentQueries: [String] {
        recentQueryStorage
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: VFSpace.md) {
                        Text("출사지 검색")
                            .vfText(.title1.weight(.bold))
                            .foregroundStyle(AppColors.primary)
                            .accessibilityAddTraits(.isHeader)

                        Spacer(minLength: 0)

                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                // 작은 보조 액션으로 보이되, 바깥 hit target은 유지합니다.
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(width: 36, height: 36)
                                .background(AppColors.primarySoft, in: Circle())
                                .clipShape(Circle())
                                .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: AppLayout.touchTarget, height: AppLayout.touchTarget)
                        .contentShape(Rectangle())
                        .accessibilityLabel("닫기")
                    }
                    .padding(.bottom, VFSpace.md)

                    VFSearchField(
                        text: $query,
                        isFocused: $isSearchFocused,
                        onSubmit: submitSearch,
                        onClear: {
                            query = ""
                            placeFinder.clear()
                            onQueryChange()
                        },
                        style: .surface
                    )

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HomeSearchStartContent(
                            recentQueries: recentQueries,
                            onSelectQuery: applySearchTerm,
                            onClearRecentQueries: { recentQueryStorage = "" },
                            onDeleteRecentQuery: deleteRecentQuery,
                            onFocusSearch: { isSearchFocused = true }
                        )
                        .padding(.horizontal, Layout.searchContentInset)
                        .padding(.top, Layout.historyTopSpacing)
                    } else if isLoading || (placeFinder.isSearching && !hasResults) {
                        SearchStatusRow(message: "검색 중이에요", isLoading: true, isError: false)
                            .padding(.top, VFSpace.md)
                    } else if !hasResults {
                        // 실제 장소 검색이 실패했으면 그 사실을 먼저 말합니다.
                        // "데이터가 부족해요" 로만 끝내면 앱이 아는 범위가
                        // 좁은 것인지 서버에 못 닿은 것인지 알 수 없습니다.
                        EmptySearchResultView(
                            message: message
                                ?? placeFinder.message
                                ?? "'\(query)' 로 찾을 수 있는 장소가 없어요",
                            onAddPlace: onAddPlace
                        )
                        .padding(.top, VFSpace.md)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            if !spotRecommendations.isEmpty {
                                SearchResultSectionHeader(title: "출사지 결과", count: spotRecommendations.count)

                                LazyVStack(spacing: 8) {
                                    ForEach(spotRecommendations) { recommendation in
                                        HomeSearchResultCard(
                                            recommendation: recommendation,
                                            onSelect: { onSelectSpot(recommendation.spot) },
                                            onReportMissingPhoto: { onReportMissingPhoto(recommendation.spot) }
                                        )
                                        .id(recommendation.id)
                                    }
                                }
                                .scrollTargetLayout()
                            }

                            if !unknownPlaces.isEmpty {
                                SearchResultSectionHeader(
                                    title: "등록되지 않은 장소",
                                    count: unknownPlaces.count
                                )

                                // 우리 데이터에 없는 실제 장소입니다.
                                // 출사지 결과보다 아래에 둡니다.
                                // 큐레이션된 출사지가 먼저 와야 합니다.
                                LazyVStack(spacing: 0) {
                                    ForEach(unknownPlaces) { result in
                                        Button {
                                            onSelectSpot(result.spot)
                                        } label: {
                                            HomeUnknownPlaceRow(result: result)
                                        }
                                        .buttonStyle(.plain)

                                        if result.id != unknownPlaces.last?.id {
                                            Divider()
                                                .overlay(AppColors.divider)
                                                .padding(.leading, 44)
                                        }
                                    }
                                }
                            }

                            if !communityPosts.isEmpty {
                                SearchResultSectionHeader(title: "커뮤니티 글 결과", count: communityPosts.count)

                                LazyVStack(spacing: 8) {
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
                        .padding(.top, VFSpace.md)
                    }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .onChange(of: query) { _, newValue in
                        scrollAnchor = nil
                        // 로컬 키워드 검색은 즉시. 동기 함수라 비용이 없습니다.
                        onQueryChange()

                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            placeFinder.clear()
                            return
                        }

                        // 실제 장소 검색은 디바운스됩니다.
                        placeFinder.search(trimmed, near: nil, knownSpots: spots)
                    }
                    .padding(.bottom, 28)
                }
            .scrollPosition(id: $scrollAnchor, anchor: .top)
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.feedBackground.ignoresSafeArea())
            // Phase 1: 스크롤한 본문이 상태바와 겹쳐 읽히는 문제를 수정합니다.
            .navigationBarHidden(true)
            .vfTopScrollEdge()
            .task {
                guard let returnAnchor else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                scrollProxy.scrollTo(returnAnchor, anchor: .top)
            }
            }
        }
    }

    private func submitSearch() {
        isSearchFocused = false
        storeRecentQuery(query)
        onSubmitSearch()
    }

    private func applySearchTerm(_ term: String) {
        query = term
        storeRecentQuery(term)
        isSearchFocused = false
    }

    private func storeRecentQuery(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = recentQueries.filter {
            $0.localizedCaseInsensitiveCompare(trimmed) != .orderedSame
        }
        updated.insert(trimmed, at: 0)
        recentQueryStorage = updated.prefix(5).joined(separator: "\n")
    }

    private func deleteRecentQuery(_ query: String) {
        recentQueryStorage = recentQueries
            .filter { $0 != query }
            .joined(separator: "\n")
    }

    private func spot(for post: CommunityPost) -> PhotoSpot? {
        spots.first { $0.id == post.spotID }
    }
}


/// 앱에 등록되지 않은 실제 장소 한 줄.
///
/// 출사지 카드와 다르게 생겨야 합니다. 사진도 큐레이션 정보도 없고,
/// "여기 이런 곳이 있다" 는 사실만 있습니다.
/// 카드처럼 그리면 같은 무게로 읽혀서 등록된 출사지와 구별되지 않습니다.
struct HomeUnknownPlaceRow: View {
    let result: PlaceSearchResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                // Dynamic Type 제외: 고정 32pt 프레임 안의 기호.
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 32, height: 32)
                .background(AppColors.mutedSurface, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .vfText(.callout)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(result.address)
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .vfIcon(11, weight: .bold, relativeTo: .caption)
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct SearchResultSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .vfText(.headline.weight(.bold))
                .foregroundStyle(AppColors.primary)

            Text("\(count)")
                .vfText(.caption.weight(.bold))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .frame(minHeight: 22)
                .background(AppColors.primarySoft, in: Capsule())

            Spacer(minLength: 0)
        }
    }
}

struct HomeSearchResultCard: View {
    let recommendation: RecommendedSpot
    let onSelect: () -> Void
    let onReportMissingPhoto: () -> Void

    private var spot: PhotoSpot {
        recommendation.spot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                cardContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(spot.name), 장소 상세 보기")

            if !spot.hasReliableDisplayImage {
                Button(action: onReportMissingPhoto) {
                    Label("대표 사진 제보", systemImage: "photo.badge.plus")
                        .vfText(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: AppLayout.touchTarget)
                        .background(AppColors.mutedSurface, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 108)
            }
        }
        .padding(8)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColors.divider, lineWidth: 1))
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            if spot.hasReliableDisplayImage {
                SpotVisualTile(spot: spot, width: 96, height: 96)
            } else {
                MissingSpotPhotoPrompt(layout: .compact)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.divider, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(spot.name)
                    .vfText(.headline.weight(.bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(spot.region)
                    .vfText(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)

                Text(spot.summary)
                    .vfText(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ForEach(spot.hashtags.prefix(2), id: \.self) { tag in
                        Text("#\(tag.replacingOccurrences(of: "#", with: ""))")
                            .vfText(.caption.weight(.bold))
                            .foregroundStyle(spot.theme.primary)
                            .lineLimit(1)
                    }
                }

            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .contentShape(Rectangle())
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
                    // Dynamic Type 제외: 사진 자리를 대신하는 74pt 기호. 사진 크기와 같아야 한다.
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 74, height: 74)
                    .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(post.title ?? post.relatedSpotName ?? "커뮤니티 글")
                        .vfText(.headline.weight(.bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text("·")
                        .vfText(.caption.weight(.bold))
                        .foregroundStyle(AppColors.secondaryText.opacity(0.7))

                    Text(communityRelativeTimeText(for: post.createdAt))
                        .vfText(.caption.weight(.bold))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }

                Text(post.message)
                    .vfText(.subhead.weight(.semibold))
                    .foregroundStyle(AppColors.primary.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if post.hasStatusInfo {
                    CommunityStatusRow(crowd: post.crowd, tags: post.statusTags)
                }
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

/// 검색 결과가 없을 때.
///
/// "AI로 추천 받기" 버튼을 없앴습니다.
/// 그 버튼은 PhotoSpotSearchViewModel.requestAIRecommendations 를 불렀고,
/// 그 함수 본문은 canRequestAI = false 한 줄이었습니다. 누르면 아무 일도
/// 일어나지 않았습니다.
///
/// 버튼을 되살리는 대신 없앴습니다. AI 로 장소를 만들어내는 방식은
/// 관광지만 나오는 문제가 있어서 접었습니다. 지금 이 앱에서 장소를
/// 찾는 방법은 두 가지입니다. 앱에 등록된 출사지(여기)와 네이버 지도
/// 실제 장소(PlaceFinder). 둘 다 결과가 없으면 그냥 없는 것입니다.
///
/// 행동 버튼이 없는 빈 화면인 것은 아직 아쉽습니다. 원래는 여기서
/// "이 장소 제보하기" 로 이어져야 합니다. 제보 화면을 여는 경로가
/// ContentView 에 있어서 배선이 필요하고, 이 정리와는 별개의 작업입니다.
struct EmptySearchResultView: View {
    let message: String
    let onAddPlace: () -> Void

    var body: some View {
        AppStatePanel(
            symbolName: "magnifyingglass",
            title: "검색 결과가 없어요",
            message: message,
            actionTitle: "새 장소 알려주기",
            action: onAddPlace
        )
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
                    .vfIcon(13, weight: .bold, relativeTo: .subheadline)
                    .foregroundStyle(isError ? AppColors.crowdCrowded : AppColors.primary)
            }

            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(isError ? AppColors.crowdCrowded : AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            (isError ? AppColors.crowdCrowded.opacity(0.10) : AppColors.mutedSurface),
            in: RoundedRectangle(cornerRadius: AppLayout.controlCornerRadius, style: .continuous)
        )
    }
}

struct HomeSectionHeader: View {
    let title: String
    /// Phase 2A 부터 렌더링하지 않습니다.
    /// 섹션마다 아이콘을 붙이면 모든 섹션이 같은 무게가 되어 강조가 사라집니다.
    /// 또한 섹션 아이콘이 브랜드 앰버를 쓰고 있어서 한 화면에 앰버가 4종류로
    /// 늘어났습니다. (탭 + 검색 버튼 + 섹션 아이콘 + 북마크)
    let symbolName: String
    /// Phase 2A 부터 렌더링하지 않습니다.
    let tint: Color
    var showsMore: Bool = false
    var onMore: (() -> Void)? = nil

    var body: some View {
        VFSectionTitle(
            title: title,
            showsMore: showsMore && onMore != nil,
            onMore: onMore
        )
    }
}

struct FeaturedSpotCard: View {
    let recommendation: RecommendedSpot
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
            SpotVisualTile(
                spot: spot,
                width: 272,
                height: 352,
                cornerRadius: AppLayout.cardCornerRadius,
                showsReadabilityGradient: false
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.02),
                    .black.opacity(0.10),
                    .black.opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(spot.name)
                    .font(AppTypography.prominentCardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.82)

                Text(displayRegion)
                    .font(AppTypography.metadata.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)

                Text(recommendation.reason)
                    .font(AppTypography.metadata)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)

            VStack {
                HStack {
                    Spacer(minLength: 0)
                    VFSaveButton(isSaved: isSaved, action: onToggleSave)
                }

                Spacer(minLength: 0)
            }
            .padding(VFSpace.sm)
        }
        .frame(width: 272, height: 352)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous))
        // 검정 4% 테두리와 검정 5% 그림자를 제거했습니다.
        //
        // 라이트 배경 시절에 카드를 띄우기 위해 넣은 값입니다.
        // 검정 캔버스에서는 둘 다 보이지 않습니다. 검정 위의 검정입니다.
        // Phase 1 에서 카드 테두리·그림자를 걷어냈는데 이 카드만
        // 남아 있었습니다. 보이지 않는 코드는 지웁니다.
    }
}

/// Hero 아래 추천 섹션의 사진 우선 레이아웃입니다.
///
/// 모든 섹션이 같은 카드 레일을 반복하지 않되, 와이드 레일 / 모자이크 /
/// 컴팩트 그리드 세 패턴만 사용해 하나의 피드처럼 읽히게 합니다.
struct HomeCategorySection: View {
    let category: HomeRecommendationKind
    let recommendations: [RecommendedSpot]
    let hasMore: Bool
    let isLoading: Bool
    var userLocation: CLLocationCoordinate2D? = nil
    let onSelect: (PhotoSpot) -> Void
    let onShowMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.lg) {
            HomeSectionHeader(
                title: category.title,
                symbolName: category.symbolName,
                tint: category.accentColor,
                showsMore: hasMore,
                onMore: onShowMore
            )
            .vfScreenMargin()

            if recommendations.isEmpty || isLoading {
                SkeletonRail()
                    .vfScreenMargin()
            } else {
                recommendationLayout
            }
        }
    }

    private var layout: HomeRecommendationLayout {
        switch category {
        case .sunset, .night:
            return .wideRail
        case .seasonal:
            return .editorialMosaic
        case .cafe, .rainy, .walk, .film, .hidden:
            return .compactGrid
        }
    }

    @ViewBuilder
    private var recommendationLayout: some View {
        switch layout {
        case .wideRail:
            HomeLandscapeRecommendationRail(
                recommendations: recommendations,
                onSelect: onSelect
            )
        case .editorialMosaic:
            HomeEditorialRecommendationMosaic(
                recommendations: recommendations,
                onSelect: onSelect
            )
        case .compactGrid:
            HomeCompactRecommendationGrid(
                recommendations: recommendations,
                onSelect: onSelect
            )
        }
    }
}

private enum HomeRecommendationLayout {
    case wideRail
    case editorialMosaic
    case compactGrid
}

/// 노을·야경처럼 사진의 넓은 분위기를 먼저 보여줘야 하는 테마용 3:2 레일.
private struct HomeLandscapeRecommendationRail: View {
    let recommendations: [RecommendedSpot]
    let onSelect: (PhotoSpot) -> Void

    private static let cardWidthRatio: CGFloat = 0.78

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: VFSpace.md) {
                ForEach(recommendations.prefix(5)) { recommendation in
                    HomePhotoCard(
                        recommendation: recommendation,
                        aspectRatio: VFPhoto.carouselAspect,
                        onSelect: { onSelect(recommendation.spot) }
                    )
                    .containerRelativeFrame(.horizontal) { length, _ in
                        max(0, length * Self.cardWidthRatio)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, VFSpace.lg)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

/// 계절처럼 편집된 한 묶음으로 보여줄 수 있는 테마용 대표 사진 + 보조 사진 2장.
private struct HomeEditorialRecommendationMosaic: View {
    let recommendations: [RecommendedSpot]
    let onSelect: (PhotoSpot) -> Void

    private static let height: CGFloat = 248
    private static let featuredWidthRatio: CGFloat = 0.62

    private var secondaryRecommendations: [RecommendedSpot] {
        Array(recommendations.dropFirst().prefix(2))
    }

    @ViewBuilder
    var body: some View {
        if let featured = recommendations.first, secondaryRecommendations.count == 2 {
            GeometryReader { proxy in
                let gap = VFSpace.md
                let featuredWidth = (proxy.size.width - gap) * Self.featuredWidthRatio
                let secondaryWidth = proxy.size.width - gap - featuredWidth
                let secondaryHeight = (Self.height - gap) / 2

                HStack(spacing: gap) {
                    HomePhotoCard(
                        recommendation: featured,
                        aspectRatio: featuredWidth / Self.height,
                        onSelect: { onSelect(featured.spot) }
                    )
                    .frame(width: featuredWidth, height: Self.height)

                    VStack(spacing: gap) {
                        ForEach(secondaryRecommendations) { recommendation in
                            HomePhotoCard(
                                recommendation: recommendation,
                                aspectRatio: secondaryWidth / secondaryHeight,
                                showsMeta: false,
                                onSelect: { onSelect(recommendation.spot) }
                            )
                            .frame(width: secondaryWidth, height: secondaryHeight)
                        }
                    }
                }
            }
            .frame(height: Self.height)
            .vfScreenMargin()
        } else {
            // 추천 수가 적어 모자이크가 성립하지 않을 때도 사진을 억지로 비우지 않습니다.
            HomeLandscapeRecommendationRail(
                recommendations: recommendations,
                onSelect: onSelect
            )
        }
    }
}

/// 사진이 충분히 많은 낮은 우선순위 테마용 2열 그리드.
/// 텍스트 영역을 따로 만들지 않고, 사진 위 캡션만으로 장소를 식별합니다.
private struct HomeCompactRecommendationGrid: View {
    let recommendations: [RecommendedSpot]
    let onSelect: (PhotoSpot) -> Void

    private static let aspectRatio: CGFloat = 4 / 5

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: VFSpace.md),
            GridItem(.flexible(), spacing: VFSpace.md)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: VFSpace.md) {
            ForEach(recommendations.prefix(4)) { recommendation in
                HomePhotoCard(
                    recommendation: recommendation,
                    aspectRatio: Self.aspectRatio,
                    onSelect: { onSelect(recommendation.spot) }
                )
            }
        }
        .vfScreenMargin()
    }
}

/// Hero 아래에서 장소 콘텐츠만 거르는 한 줄 필터입니다.
/// 여섯 개 주 테마와 시즌을 같은 선택 축으로 보여주되, 둘을 동시에 적용하지는 않습니다.
private struct HomeThemeFilterSection: View {
    let themes: [SpotTheme]
    let seasons: [HomeSeasonFilter]
    let selectedTheme: SpotTheme?
    let selectedSeason: HomeSeasonFilter?
    let onSelectTheme: (SpotTheme) -> Void
    let onSelectSeason: (HomeSeasonFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: VFSpace.sm) {
                if !seasons.isEmpty {
                    ForEach(seasons) { season in
                        filterChip(
                            title: season.title,
                            symbol: season.symbol,
                            isSelected: selectedSeason == season,
                            accessibilityLabel: "시즌 \(season.title)"
                        ) {
                            VFHaptics.selection()
                            onSelectSeason(season)
                        }
                    }
                }

                ForEach(themes) { theme in
                    filterChip(
                        title: theme.title,
                        isSelected: selectedTheme == theme,
                        accessibilityLabel: "\(theme.title) 테마"
                    ) {
                        VFHaptics.selection()
                        onSelectTheme(theme)
                    }
                }
            }
            .padding(.horizontal, VFSpace.lg)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
    }

    private func filterChip(
        title: String,
        symbol: String? = nil,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: VFSpace.xs) {
                if let symbol {
                    Text(symbol)
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                }

                Text(title)
                    .vfText(.subhead.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.primary)
            .padding(.horizontal, VFSpace.sm + 2)
            .frame(minHeight: 34)
            .contentShape(Capsule())
            .vfGlass(
                tint: isSelected ? AppColors.accent : nil,
                interactive: true
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppLayout.touchTarget)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "선택됨" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(VFMotion.quick, value: isSelected)
    }
}

/// TOP 5와 테마별 장소를 같은 카드 언어로 보여주는 가로 레일입니다.
private struct HomeSpotRailSection: View {
    let title: String
    let recommendations: [RecommendedSpot]
    let onSelect: (PhotoSpot) -> Void
    var showsRank = false
    var showsTitle = true

    private var displayRecommendations: [RecommendedSpot] {
        recommendations
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            if showsTitle {
                Text(title)
                    .vfText(.title2)
                    .foregroundStyle(AppColors.primary)
                    .vfScreenMargin()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: VFSpace.md) {
                    ForEach(Array(displayRecommendations.enumerated()), id: \.element.id) { index, recommendation in
                        HomePhotoCard(
                            recommendation: recommendation,
                            aspectRatio: 4.0 / 5.0,
                            metaItems: [
                                HomeSpotDisplayFormatter.region(for: recommendation.spot),
                                recommendation.reason
                            ].filter { !$0.isEmpty },
                            onSelect: { onSelect(recommendation.spot) }
                        )
                        .overlay(alignment: .topLeading) {
                            if showsRank {
                                HomePopularRankBadge(
                                    rank: index + 1
                                )
                                .padding(.top, VFSpace.sm)
                                .padding(.leading, VFSpace.sm)
                            }
                        }
                        .accessibilityLabel(
                            showsRank
                                ? "인기 순위 " + String(index + 1) + "위, " + recommendation.spot.name + ", " + HomeSpotDisplayFormatter.region(for: recommendation.spot)
                                : recommendation.spot.name + ", " + HomeSpotDisplayFormatter.region(for: recommendation.spot)
                        )
                        .containerRelativeFrame(.horizontal) { length, _ in
                            length * (!showsRank && displayRecommendations.count > 2 ? 0.42 : 0.46)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, VFSpace.lg)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

private struct HomePopularRankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.94))
            .frame(width: 24, height: 24)
            .background(
                Color.black.opacity(0.46),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.52), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

private struct HomeSecondarySpotCard: View {
    let recommendation: RecommendedSpot
    let width: CGFloat
    let isSaved: Bool
    let onToggleSave: () -> Void

    private var spot: PhotoSpot { recommendation.spot }

    private var supportingText: String {
        let region = HomeSpotDisplayFormatter.region(for: spot)
        let cleanedReason = recommendation.reason
            .replacingOccurrences(of: "커뮤니티에서 ", with: "")
            .replacingOccurrences(of: " 이야기가 자주 올라오는 출사지예요", with: "")
            .replacingOccurrences(of: " 이야기가 자주 올라오는", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedReason.isEmpty else { return region }
        return "\(region) · \(cleanedReason)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SpotVisualTile(spot: spot, width: width, height: 132, cornerRadius: AppLayout.mediaCornerRadius)
                .overlay(alignment: .topTrailing) {
                    VFSaveButton(isSaved: isSaved, action: onToggleSave, diameter: 32)
                        .padding(VFSpace.xs)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(spot.name)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(supportingText)
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
                    .lineSpacing(1.5)
            }
            .frame(minHeight: 54, alignment: .top)
        }
        .frame(width: width, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

struct HomeCategoryListView: View {
    let category: HomeRecommendationKind
    let recommendations: [RecommendedSpot]
    let savedSpotIDs: Set<String>
    let onToggleSave: (PhotoSpot) -> Void
    let onSelect: (PhotoSpot) -> Void
    let onReportMissingPhoto: (PhotoSpot) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(recommendations) { recommendation in
                    HomeCategoryListRow(
                        recommendation: recommendation,
                        isSaved: savedSpotIDs.contains(recommendation.spot.id),
                        onToggleSave: {
                            onToggleSave(recommendation.spot)
                        },
                        onSelect: {
                            onSelect(recommendation.spot)
                        },
                        onReportMissingPhoto: {
                            onReportMissingPhoto(recommendation.spot)
                        }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct HomeCategoryListRow: View {
    let recommendation: RecommendedSpot
    let isSaved: Bool
    let onToggleSave: () -> Void
    let onSelect: () -> Void
    let onReportMissingPhoto: () -> Void

    private var spot: PhotoSpot {
        recommendation.spot
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Button(action: onSelect) {
                    if spot.hasReliableDisplayImage {
                        SpotVisualTile(spot: spot, width: 112, height: 112, cornerRadius: 14)
                    } else {
                        MissingSpotPhotoPrompt(layout: .compact)
                            .frame(width: 112, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppColors.divider, lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)

                if spot.hasReliableDisplayImage {
                    Button(action: onToggleSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            // Dynamic Type 제외: 사진 위 고정 31pt 저장 버튼.
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 31, height: 31)
                            .contentShape(Rectangle())
                            .background(.black.opacity(0.26), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                // ═══════════════════════════════════════════════════
                //  탭 제스처를 글자 블록에만 걸었습니다.
                //
                //  [문제였던 상황]
                //  contentShape + onTapGesture 가 바깥 VStack 에 걸려
                //  있었고, 그 안에 "대표 사진 제보" 버튼이 들어 있었습니다.
                //  제보 버튼을 누르면 제보 화면과 장소 상세가 같이
                //  열렸습니다.
                //
                //  홈 Hero 에서 날씨·검색 버튼이 카드 탭과 겹쳤던 것과
                //  같은 문제입니다. 여기는 사진이 없는 장소에서만
                //  버튼이 나타나기 때문에 눈에 덜 띄었습니다.
                //
                //  [해결]
                //  탭 영역을 글자 세 줄로 좁혔습니다. 버튼은 바깥에
                //  남으므로 겹치지 않습니다.
                // ═══════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 7) {
                    Text(spot.name)
                        .vfText(.headline)
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(2)

                    Text(HomeSpotDisplayFormatter.region(for: spot))
                        .vfText(.subhead.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)

                    Text(recommendation.reason)
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)

                if !spot.hasReliableDisplayImage {
                    Button(action: onReportMissingPhoto) {
                        Text("대표 사진 제보")
                            .vfText(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(minHeight: 28)
                            .background(AppColors.mutedSurface, in: Capsule())
                            .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.divider)
                .frame(height: 0.5)
        }
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

    /// Hero 와 "지금 찍기 좋은" 레일에 같은 촬영 언어를 씁니다.
    /// 날씨 수치가 아니라 지금 카메라를 들 이유만 짧게 남깁니다.
    static func shootingTag(for spot: PhotoSpot) -> String {
        let searchableText = ([spot.bestTime, spot.summary, spot.category] + spot.mood + spot.weather)
            .joined(separator: " ")
            .lowercased()

        if searchableText.contains("골든") || searchableText.contains("노을") {
            return "골든아워 최적"
        }
        if searchableText.contains("야경") || searchableText.contains("야간") {
            return "야간 촬영 추천"
        }
        if searchableText.contains("비") {
            return "비 오는 날 추천"
        }
        return "오늘 빛 좋음"
    }

    /// Hero에서 장소명 바로 아래에 쓰는 짧은 촬영 구간입니다.
    /// 기존 shootingTag는 다른 레일과 공유하므로, Hero의 정보 밀도만 여기서 조정합니다.
    static func heroShootingCondition(for spot: PhotoSpot) -> String? {
        let searchableText = (
            [spot.bestTime, spot.summary, spot.category, spot.eventTitle, spot.eventPeriod]
            + spot.hashtags
            + spot.mood
            + spot.weather
        )
            .joined(separator: " ")
            .lowercased()

        if searchableText.contains("블루") || searchableText.contains("bluehour") {
            return "블루아워"
        }
        if searchableText.contains("골든")
            || searchableText.contains("노을")
            || searchableText.contains("해질녘")
            || searchableText.contains("goldenhour")
            || searchableText.contains("sunset") {
            return "골든아워"
        }
        if searchableText.contains("야경")
            || searchableText.contains("야간")
            || searchableText.contains("night") {
            return "야경"
        }
        if searchableText.contains("비")
            || searchableText.contains("rain") {
            return "비 오는 날"
        }
        if searchableText.contains("오전")
            || searchableText.contains("아침")
            || searchableText.contains("morning")
            || searchableText.contains("dawn") {
            return "오전 빛"
        }
        if searchableText.contains("저녁")
            || searchableText.contains("evening") {
            return "저녁 빛"
        }

        return "오늘 빛 좋음"
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
    var showsReadabilityGradient: Bool = true

    private var resolvedWidth: CGFloat {
        width ?? 170
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoSpotImageView(
                spot: spot,
                symbolSize: height > 80 ? 32 : 23,
                // 타일 높이에 맞춰 요청 해상도를 고릅니다.
                // 작은 리스트 썸네일이 900px 이미지를 디코딩하지 않게 합니다.
                targetPixelWidth: height > 160
                    ? VFPhotoDetail.card.pixelWidth
                    : VFPhotoDetail.thumbnail.pixelWidth
            )

            if showsReadabilityGradient {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

        }
        .frame(width: resolvedWidth, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

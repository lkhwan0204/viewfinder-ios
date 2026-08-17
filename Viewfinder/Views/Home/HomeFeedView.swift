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

struct HomeFeedView: View {
    let searchableSpots: [PhotoSpot]
    let recommendedSpots: [PhotoSpot]
    let communityPosts: [CommunityPost]
    let preloadedRecommendations: [RecommendedSpot]
    let sectionRecommendations: [HomeRecommendationKind: [RecommendedSpot]]
    let expandedSectionRecommendations: [HomeRecommendationKind: [RecommendedSpot]]
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
    let onReportMissingPhoto: (PhotoSpot) -> Void
    let onToggleSave: (PhotoSpot) -> Void
    let onOpenMap: (PhotoSpot?) -> Void
    let onShowWeather: () -> Void
    let onShowCurrentLocation: () -> Void
    let onTabBarVisibilityChange: (Bool) -> Void
    let onTabBarDragChange: (CGFloat) -> Void
    let onTabBarDragEnd: (CGFloat) -> Void
    let onRefreshRecommendations: () async -> Void
    private let searchProvider: any SearchProvider = LocalKeywordSearchProvider()
    @State private var isSearchResultsPresented = false
    @State private var selectedCategory: HomeRecommendationKind?
    @State private var keywordSearchResults = KeywordSearchResults.empty
    @State private var tabBarVisibilityState = HomeTabBarVisibilityState()
    @State private var isRefreshArmed = false
    @State private var isRefreshingRecommendations = false

    private let refreshTriggerOffset: CGFloat = 210
    private let homeScrollCoordinateSpace = "homeDiscoveryScroll"

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
        (keywordSpotRecommendations + verifiedRecommendations).reduce(into: [RecommendedSpot]()) { result, recommendation in
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
            homeContent
            .background(AppColors.background.ignoresSafeArea())
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
        // ═══════════════════════════════════════════════════════════
        //  검색 화면을 NavigationStack 밖으로 옮겼습니다.
        //
        //  [증상]
        //  검색 버튼은 눌립니다. 로그로 확인했습니다.
        //  isSearchResultsPresented 를 true 로 바꾸는 코드도 실행됩니다.
        //  그런데 화면이 나타나지 않습니다.
        //
        //  [왜 이 자리였는지 의심하는가]
        //  전에는 이 모디파이어가 NavigationStack 의 내용(homeContent)에
        //  붙어 있었고, 같은 뷰에 navigationDestination 도 붙어 있었습니다.
        //  한 뷰가 내비게이션 목적지와 전체 화면 제시를 동시에 들고 있는
        //  구조입니다.
        //
        //  제시(presentation)는 NavigationStack 자체에 붙이는 것이
        //  안전합니다. 스택 안의 내용은 내비게이션에 따라 밀려나고 다시
        //  그려지는 자리이고, 제시는 그 위에 떠야 하기 때문입니다.
        //
        //  이 변경만으로 고쳐지지 않을 수도 있으므로 상태 변화를 찍는
        //  로그를 함께 넣었습니다. false -> true 만 찍히고 화면이 안 나오면
        //  제시 자체의 문제이고, true -> false 가 곧바로 이어지면 무언가
        //  상태를 되돌리고 있다는 뜻입니다. 원인이 정반대입니다.
        // ═══════════════════════════════════════════════════════════
        .onChange(of: isSearchResultsPresented) { oldValue, newValue in
            print("[VF-SEARCH] 1b. isSearchResultsPresented \(oldValue) -> \(newValue)")
        }
        .fullScreenCover(isPresented: $isSearchResultsPresented) {
            HomeSearchResultsView(
                query: $searchViewModel.searchText,
                spotRecommendations: combinedSearchRecommendations,
                communityPosts: keywordSearchResults.communityPosts,
                spots: searchableSpots,
                message: searchViewModel.message,
                isLoading: searchViewModel.isLoading,
                onSubmitSearch: performSearch,
                onDismiss: {
                    isSearchResultsPresented = false
                },
                debugTrace: { line in
                    print("[VF-SEARCH] \(line)")
                },
                onSelectSpot: { spot in
                    onAddAISpot(spot)
                    isSearchResultsPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        onShowSearchDetail(spot)
                    }
                },
                onReportMissingPhoto: onReportMissingPhoto,
                onSelectCommunityPost: { post in
                    guard let spot = spot(for: post) else { return }
                    isSearchResultsPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        onShowSearchDetail(spot)
                    }
                },
                onQueryChange: performLocalKeywordSearch
            )
        }
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
        .background(AppColors.background)
    }

    private func discoveryPage(heroSize: CGSize, topInset: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            // Phase 2A
            // - 화면 전체에 걸던 horizontal padding 을 제거했습니다.
            //   Hero 가 화면 경계를 넘어가야 하므로 마진은 섹션별로 적용합니다.
            // - 날씨/위치 칩(contextRow)을 제거했습니다.
            //   사진 앱의 첫 픽셀이 날씨 위젯이면 안 됩니다.
            //   온도는 행동을 유발하지 않는 정보였습니다. (Phase 2B 에서 골든아워로 대체)
            // - 섹션마다 레이아웃을 다르게 해서 스크롤에 리듬을 만듭니다.
            //   기존에는 4개 섹션이 전부 같은 2열 균일 레일이라 스크롤이 단조로웠습니다.
            // 섹션 간 간격은 32(xl)입니다. 48(xxl)은 "챕터 분리" 값이라
            // 섹션 사이에 쓰면 첫 카드가 탭바 아래로 밀려 캡션이 가려집니다.
            LazyVStack(alignment: .leading, spacing: VFSpace.xl) {
                todaySection(heroSize: heroSize, topInset: topInset)

                ForEach(categories.prefix(4)) { category in
                    let categoryRecommendations = recommendations(for: category)
                    if !categoryRecommendations.isEmpty {
                        HomeCategorySection(
                            category: category,
                            recommendations: categoryRecommendations,
                            hasMore: category == .cafe || expandedRecommendations(for: category).count > categoryRecommendations.count,
                            isLoading: loadingSectionIDs.contains(category.id),
                            userLocation: userLocation,
                            onSelect: onShowDetail,
                            onShowMore: {
                                selectedCategory = category
                            }
                        )
                    }
                }

                Button(action: { onOpenMap(nil) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "map")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("지도에서 더 많은 출사지 찾기")
                                .font(AppTypography.bodyStrong)
                            Text("분위기와 현재 위치를 기준으로 둘러보세요")
                                .font(AppTypography.metadata)
                                .foregroundStyle(AppColors.secondaryText)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .foregroundStyle(AppColors.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCardSurface()
                }
                .buttonStyle(.plain)
                .accessibilityHint("지도 탭으로 이동합니다")
                .vfScreenMargin()
            }
            // Phase 2A: 기존 38pt 로는 floating 탭바를 덮지 못해
            // 마지막 카드의 캡션이 탭바 아래로 삐져나와 읽혔습니다.
            .padding(.bottom, 120)
            .background(alignment: .top) {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HomePullOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(homeScrollCoordinateSpace)).minY
                    )
                }
            }
        }
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
        .background(AppColors.background)
    }

    private var tabBarVisibilityDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
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

        print("""
        [VF-SEARCH] 4. 로컬 검색 '\(query)' \
        검색대상=\(searchableSpots.count)곳 \
        결과=\(keywordSearchResults.spots.count)곳 \
        글=\(keywordSearchResults.communityPosts.count)개
        """)
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
    private func todaySection(heroSize: CGSize, topInset: CGFloat) -> some View {
        HomeHeroSection(
            recommendations: recommendations,
            userLocation: userLocation,
            communityPosts: communityPosts,
            cardSize: heroSize,
            topInset: topInset,
            contextText: heroContextText,
            contextSymbolName: heroContextSymbol,
            onShowContext: onShowWeather,
            onSelect: onShowDetail,
            onSearch: { isSearchResultsPresented = true }
        )
    }

    /// Hero 좌상단 pill 문자열.
    ///
    /// 이전에는 "구로동 25°" 였습니다. 온도는 사진가의 행동을 유발하지 않습니다.
    /// 정말 필요한 정보는 "지금 나가면 빛이 좋은가" 이므로
    /// 다음 해 이벤트를 앞에 두고 온도를 뒤에 붙입니다.
    /// 예) "일몰까지 2시간 10분 · 24°"
    private var heroContextText: String? {
        guard let snapshot = weatherSnapshot else { return nil }

        let temperature = snapshot.displayText

        guard let event = snapshot.nextSunEvent else {
            return temperature
        }

        return "\(event.label)  ·  \(temperature)"
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

struct NearbyRecommendationEmptyView: View {
    let message: String

    var body: some View {
        AppStatePanel(
            symbolName: "location.magnifyingglass",
            title: message,
            message: "현재 위치와 등록된 장소를 기준으로 다시 확인해보세요."
        )
    }
}

struct HomeSearchResultsView: View {
    @Binding var query: String
    let spotRecommendations: [RecommendedSpot]
    let communityPosts: [CommunityPost]
    let spots: [PhotoSpot]
    let message: String?
    let isLoading: Bool
    let onSubmitSearch: () -> Void
    let onDismiss: () -> Void
    /// 홈 검색이 어디서 멈추는지 찾기 위한 임시 통로.
    /// 원인을 잡으면 이 파라미터와 호출부를 함께 지웁니다.
    let debugTrace: (String) -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    let onReportMissingPhoto: (PhotoSpot) -> Void
    let onSelectCommunityPost: (CommunityPost) -> Void
    /// 입력하는 즉시 실행되는 로컬 키워드 검색.
    /// AI 검색(onSubmitSearch)과 분리했습니다.
    let onQueryChange: () -> Void
    @FocusState private var isSearchFocused: Bool

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
    @StateObject private var placeFinder = PlaceFinder(resultLimit: 6)

    /// 앱에 없는 장소만 남깁니다.
    /// 등록된 장소는 위쪽 "출사지 결과" 에 이미 나옵니다.
    private var unknownPlaces: [PlaceSearchResult] {
        placeFinder.results.filter { !$0.isKnown }
    }

    private var hasResults: Bool {
        !spotRecommendations.isEmpty || !communityPosts.isEmpty || !unknownPlaces.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("출사지 검색")
                                .vfText(.title1.weight(.bold))
                                .foregroundStyle(AppColors.primary)

                            Text("장소, 지역, 분위기로 찾아보세요")
                                .vfText(.subhead.weight(.semibold))
                                .foregroundStyle(AppColors.secondaryText)
                        }

                        Spacer(minLength: 0)

                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                // Dynamic Type 제외: 고정 36pt 닫기 버튼.
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(width: 36, height: 36)
                                .background(AppColors.primarySoft, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .vfIcon(18, weight: .regular)
                            .foregroundStyle(AppColors.secondaryText)

                        TextField("출사지, 지역, 분위기 검색", text: $query)
                            .vfText(.body.weight(.medium))
                            .submitLabel(.search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isSearchFocused)
                            .onSubmit(onSubmitSearch)

                        // 화살표 버튼을 없앴습니다.
                        // 이제 입력하는 즉시 로컬 검색과 실제 장소 검색이
                        // 돌아가므로 누를 것이 없습니다.
                        if !query.isEmpty {
                            Button {
                                query = ""
                                placeFinder.clear()
                                onQueryChange()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .vfIcon(16, weight: .regular)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("검색어 지우기")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 54)
                    // Phase 1 에서 걷어낸 1pt 테두리가 여기만 남아 있었습니다.
                    .background(AppColors.mutedSurface, in: Capsule())

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("검색어를 입력하면 앱의 출사지와 실제 장소를 함께 찾아드려요.")
                            .vfText(.subhead.weight(.medium))
                            .foregroundStyle(AppColors.secondaryText)
                            .padding(.top, 8)
                    } else if isLoading || (placeFinder.isSearching && !hasResults) {
                        SearchStatusRow(message: "검색 중이에요", isLoading: true, isError: false)
                    } else if !hasResults {
                        // 실제 장소 검색이 실패했으면 그 사실을 먼저 말합니다.
                        // "데이터가 부족해요" 로만 끝내면 앱이 아는 범위가
                        // 좁은 것인지 서버에 못 닿은 것인지 알 수 없습니다.
                        EmptySearchResultView(
                            message: message
                                ?? placeFinder.message
                                ?? "'\(query)' 로 찾을 수 있는 장소가 없어요"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            if !spotRecommendations.isEmpty {
                                SearchResultSectionHeader(title: "출사지 결과", count: spotRecommendations.count)

                                LazyVStack(spacing: 10) {
                                    ForEach(spotRecommendations) { recommendation in
                                        HomeSearchResultCard(
                                            recommendation: recommendation,
                                            onSelect: { onSelectSpot(recommendation.spot) },
                                            onReportMissingPhoto: { onReportMissingPhoto(recommendation.spot) }
                                        )
                                    }
                                }
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
                .onChange(of: query) { _, newValue in
                    debugTrace("3. onChange 입력='\(newValue)' spots후보=\(spots.count)")

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
                .onChange(of: spotRecommendations.count) { _, count in
                    debugTrace("5. 출사지 결과=\(count) 커뮤니티=\(communityPosts.count) 미등록장소=\(unknownPlaces.count) hasResults=\(hasResults)")
                }
                .onChange(of: placeFinder.results.count) { _, count in
                    debugTrace("6. PlaceFinder 결과=\(count) 검색중=\(placeFinder.isSearching) 메시지=\(placeFinder.message ?? "없음")")
                }
                .padding(.bottom, 28)
            }
            .background(AppColors.background.ignoresSafeArea())
            // Phase 1: 스크롤한 본문이 상태바와 겹쳐 읽히는 문제를 수정합니다.
            .vfTopEdgeFade()
            .navigationBarHidden(true)
            .onAppear {
                debugTrace("2. 검색 화면 열림. 입력='\(query)' isLoading=\(isLoading) 메시지=\(message ?? "없음")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isSearchFocused = true
                }
            }
        }
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
        if spot.hasReliableDisplayImage {
            cardContent
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
        } else {
            cardContent
        }
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
                    ForEach(spot.hashtags.prefix(3), id: \.self) { tag in
                        Text("#\(tag.replacingOccurrences(of: "#", with: ""))")
                            .vfText(.caption.weight(.bold))
                            .foregroundStyle(spot.theme.primary)
                            .lineLimit(1)
                    }
                }

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
                    // Dynamic Type 제외: 사진 자리를 대신하는 74pt 기호. 사진 크기와 같아야 한다.
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 74, height: 74)
                    .background(AppColors.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(post.spotName)
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

    var body: some View {
        AppStatePanel(
            symbolName: "magnifyingglass",
            title: "검색 결과가 없어요",
            message: message
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

/// 섹션 카드 규격.
///
/// 이전에는 섹션마다 레이아웃을 번갈아(3:2 카로셀 / 2:1+1:1 모자이크) 배치해서
/// 리듬을 만들려 했습니다. 그런데 실제 화면에서는 리듬이 아니라
/// "규격이 안 맞는 것"으로 읽혔고, 캡션 없는 정사각 타일은 어디인지 알 수 없었습니다.
/// 통일이 분화보다 낫다고 판단해 전 섹션 동일 규격으로 돌아갑니다.
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
                showcaseRail
            }
        }
    }

    private var showcaseRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: VFSpace.md) {
                ForEach(recommendations.prefix(5)) { recommendation in
                    card(for: recommendation, aspectRatio: VFPhoto.carouselAspect)
                        .containerRelativeFrame(.horizontal) { length, _ in
                            max(0, length * VFPhoto.railWidthRatio)
                        }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, VFSpace.lg)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }

    private func card(
        for recommendation: RecommendedSpot,
        aspectRatio: CGFloat
    ) -> some View {
        HomePhotoCard(
            recommendation: recommendation,
            aspectRatio: aspectRatio,
            onSelect: { onSelect(recommendation.spot) }
        )
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

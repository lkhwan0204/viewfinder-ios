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
    let preloadedRecommendations: [GPTRecommendedSpot]
    let sectionRecommendations: [HomeRecommendationKind: [GPTRecommendedSpot]]
    let expandedSectionRecommendations: [HomeRecommendationKind: [GPTRecommendedSpot]]
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

        return homeRailRecommendations(rawRecommendations)
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
                    onReportMissingPhoto: onReportMissingPhoto,
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
                tabBarVisibilityState.previousDragTranslation = nil
                isRefreshArmed = false
                onTabBarVisibilityChange(false)
            }
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

    private var contextRow: some View {
        HStack(spacing: 10) {
            Button(action: onShowWeather) {
                HomeContextPill(
                    symbolName: weatherSnapshot?.symbolName ?? "cloud.sun.fill",
                    title: weatherPillTitle,
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

    private var weatherPillTitle: String {
        let trimmed = currentLocationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "현재 위치 기반" else {
            return "오늘 날씨"
        }

        let parts = trimmed.split(separator: " ").map(String.init)
        let neighborhood = parts.last { part in
            ["동", "읍", "면", "리"].contains { part.hasSuffix($0) }
        }

        if let neighborhood {
            return "\(neighborhood) 날씨"
        }

        if let last = parts.last {
            return "\(last) 날씨"
        }

        return "오늘 날씨"
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

    private func recommendations(for category: HomeRecommendationKind) -> [GPTRecommendedSpot] {
        homeRailRecommendations(sectionRecommendations[category] ?? [])
    }

    private func expandedRecommendations(for category: HomeRecommendationKind) -> [GPTRecommendedSpot] {
        imagePrioritizedRecommendations(
            expandedSectionRecommendations[category] ?? sectionRecommendations[category] ?? []
        )
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

    private func homeRailRecommendations(_ recommendations: [GPTRecommendedSpot]) -> [GPTRecommendedSpot] {
        imagePrioritizedRecommendations(recommendations)
            .filter { hasDisplayImage($0.spot) }
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
        .appCardSurface(cornerRadius: AppLayout.cardCornerRadius)
    }
}

struct HomeSearchResultsView: View {
    @Binding var query: String
    let spotRecommendations: [GPTRecommendedSpot]
    let communityPosts: [CommunityPost]
    let spots: [PhotoSpot]
    let message: String?
    let isLoading: Bool
    let onSubmitSearch: () -> Void
    let onDismiss: () -> Void
    let onRequestAI: () -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    let onReportMissingPhoto: (PhotoSpot) -> Void
    let onSelectCommunityPost: (CommunityPost) -> Void
    @FocusState private var isSearchFocused: Bool

    private var hasResults: Bool {
        !spotRecommendations.isEmpty || !communityPosts.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("출사지 검색")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(AppColors.primary)

                            Text("장소, 지역, 분위기로 찾아보세요")
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

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.secondaryText)

                        TextField("출사지, 지역, 분위기 검색", text: $query)
                            .font(.system(size: 16, weight: .medium))
                            .submitLabel(.search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isSearchFocused)
                            .onSubmit(onSubmitSearch)

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else if !query.isEmpty {
                            Button(action: onSubmitSearch) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AppColors.primary)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.divider, lineWidth: 1)
                    }

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("검색어를 입력하면 앱의 출사지와 실제 장소를 함께 찾아드려요.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                            .padding(.top, 8)
                    } else if isLoading {
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
                                        HomeSearchResultCard(
                                            recommendation: recommendation,
                                            onSelect: { onSelectSpot(recommendation.spot) },
                                            onReportMissingPhoto: { onReportMissingPhoto(recommendation.spot) }
                                        )
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
            // Phase 1: 스크롤한 본문이 상태바와 겹쳐 읽히는 문제를 수정합니다.
            .vfTopEdgeFade()
            .navigationBarHidden(true)
            .onAppear {
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
                        Text("#\(tag.replacingOccurrences(of: "#", with: ""))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(spot.theme.primary)
                            .lineLimit(1)
                    }
                }

                if !spot.hasReliableDisplayImage {
                    Button(action: onReportMissingPhoto) {
                        Text("대표 사진 제보")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
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
        AppStatePanel(
            symbolName: "magnifyingglass",
            title: "검색 결과가 없어요",
            message: message,
            actionTitle: "AI로 추천 받기",
            action: onRequestAI
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
                    .font(.system(size: 13, weight: .bold))
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
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .stroke(.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
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
    let recommendations: [GPTRecommendedSpot]
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
        for recommendation: GPTRecommendedSpot,
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
    let recommendation: GPTRecommendedSpot
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
    let recommendations: [GPTRecommendedSpot]
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
    let recommendation: GPTRecommendedSpot
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
                Text(spot.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(2)

                Text(HomeSpotDisplayFormatter.region(for: spot))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text(recommendation.reason)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
                    .lineSpacing(2)

                if !spot.hasReliableDisplayImage {
                    Button(action: onReportMissingPhoto) {
                        Text("대표 사진 제보")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(AppColors.mutedSurface, in: Capsule())
                            .overlay(Capsule().stroke(AppColors.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

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
        VStack(alignment: .leading, spacing: 10) {
            SpotVisualTile(spot: spot, width: 172, height: 146, cornerRadius: 18)
                .overlay(alignment: .topTrailing) {
                    Button {
                        onToggleSave()
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSaved ? AppColors.accent : .white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.20), in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.30), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(9)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(2)
                    .lineSpacing(1.1)
                    .minimumScaleFactor(0.82)

                Text(detailText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .frame(minHeight: 62, alignment: .top)
        }
        .frame(width: 172, alignment: .top)
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

import CoreLocation
import Foundation
import OSLog
import SwiftUI
import UIKit

struct ContentView: View {
    private enum AppTab: Hashable {
        case home
        case map
        case add
        case community
        case my

        var title: String {
            switch self {
            case .home:
                return "홈"
            case .map:
                return "지도"
            case .add:
                // 라벨을 비웁니다.
                //
                // 탭 바는 "내가 지금 어디에 있는가" 를 나타내는 장소 스위처입니다.
                // 제보는 장소가 아니라 동작인데, 다른 4개와 똑같은 아이콘 + 라벨로
                // 생겨서 "이건 화면인가 버튼인가" 하는 인지 부하가 있었습니다.
                // 라벨을 없애고 채워진 원형 플러스로 바꿔 동작임을 드러냅니다.
                // ("장소제보" 4글자가 다른 라벨을 눌러 타이포도 답답했습니다)
                return ""
            case .community:
                return "커뮤니티"
            case .my:
                return "마이"
            }
        }

        var assetName: String {
            switch self {
            case .home:
                return "tab_home"
            case .map:
                return "tab_map"
            case .add:
                return "tab_add"
            case .community:
                return "tab_community"
            case .my:
                return "tab_my"
            }
        }
    }

    @State private var selectedTab: AppTab = .home
    @State private var lastContentTab: AppTab = .home
    @State private var selectedSpot = PhotoSpotSampleData.spots[0]
    @State private var selectedSpotRevision = 0
    @State private var aiSpots: [PhotoSpot] = []
    @State private var detailPresentation: SpotDetailPresentation?
    /// 중앙 액션 버튼을 눌렀을 때 뜨는 2택 시트.
    @State private var isContributeChooserPresented = false
    @State private var isWeatherDetailPresented = false
    @State private var composerPurpose: CommunityComposerPurpose = .fieldReport
    @State private var submittedSpotsState: AsyncLoadState = .idle
    @State private var appErrorMessage: String?
    @State private var submissionConfirmation: PlaceSubmissionReceipt?
    @State private var authenticationDestination: AuthenticationDestination?
    @State private var pendingAuthenticatedAction: ((AuthUser) -> Void)?
    @StateObject private var homeRecommendations = HomeRecommendationsViewModel()
    @StateObject private var locationReader = RecommendationLocationReader()
    @StateObject private var mapState = MapExperienceState()
    @StateObject private var weatherStore = WeatherStore()
    @StateObject private var searchViewModel = PhotoSpotSearchViewModel()
    @StateObject private var savedSpotStore = SavedSpotStore()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var communityViewModel = CommunityViewModel()
    @StateObject private var placeSubmissionStore = PlaceSubmissionStore()
    private let localSeedDataService = LocalSeedDataService()
    private let mapRecommendationEngine = MapRecommendationEngine()
    private let placeSubmissionService = PlaceSubmissionService()
    private let fallbackWeatherCoordinate = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)

    private var recommendedSpots: [PhotoSpot] {
        uniqueSpots(homeRecommendations.visibleSpots + aiSpots)
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
    }

    private var mapPinSpots: [PhotoSpot] {
        switch mapState.mode {
        case .saved:
            return savedMapListSpots

        case .explicitSpot:
            if let explicitMapSpot = mapState.explicitSpot,
               !RecommendationBlacklist.isBlacklistedRecommendation(explicitMapSpot) {
                return [explicitMapSpot]
            }
            return []

        case .recommendations:
            guard !mapState.isRecommendationLoading else {
                return []
            }

            return uniqueSpots(currentMapRecommendation.spots).filter {
                $0.imageURL != nil
                    && !CafeRecommendationPolicy.isBlacklistedCafe($0)
                    && !RecommendationBlacklist.isBlacklistedRecommendation($0)
            }
        }
    }

    private var currentMapRecommendation: MapRecommendationResult {
        mapRecommendationEngine.recommendations(
            near: locationReader.coordinate,
            from: recommendedSpots,
            categoryFilter: mapState.categoryFilter
        )
    }

    private var mapRecommendationEmptyMessage: String? {
        guard mapState.mode == .recommendations,
              !mapState.isRecommendationLoading,
              mapPinSpots.isEmpty else {
            return nil
        }

        return locationReader.coordinate == nil
            ? "현재 위치를 가져오면 주변 출사지를 추천할게요"
            : "주변 출사지 데이터가 부족해요"
    }

    private var visibleMapSavedSpotIDs: Set<String> {
        mapState.mode == .saved ? savedSpotStore.savedSpotIDs : []
    }

    private var savedSpots: [PhotoSpot] {
        let allSpots = uniqueSpots(localSeedDataService.allPhotoSpots() + recommendedSpots + aiSpots)
        return allSpots.filter { savedSpotStore.contains($0) }
    }

    private var savedMapListSpots: [PhotoSpot] {
        uniqueSpots(savedSpots)
            .filter { mapState.savedListFilter.matches($0) }
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
    }

    private var selectableSpots: [PhotoSpot] {
        uniqueSpots(localSeedDataService.allPhotoSpots() + recommendedSpots + aiSpots)
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
    }

    private var discoverSpots: [PhotoSpot] {
        uniqueSpots(localSeedDataService.allPhotoSpots() + recommendedSpots + aiSpots)
            .filter { spot in
                spot.hasReliableDisplayImage
                    && !RecommendationBlacklist.isBlacklistedRecommendation(spot)
                    && !CafeRecommendationPolicy.isBlacklistedCafe(spot)
            }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                playTabSelectionHaptic()

                guard newTab != .add else {
                    // 기여에는 두 종류가 있고 성격이 완전히 다릅니다.
                    //   현장 정보  가볍고 잦음. 지금 그 자리에 있으면 됩니다.
                    //   장소 제보  무겁고 드묾. 아직 없는 장소를 알아야 합니다.
                    // 이전에는 중앙 버튼이 곧바로 "장소 추가" 로 갔습니다.
                    // 앱을 살아있게 만드는 잦은 기여(현장 정보)가
                    // 커뮤니티 화면 우상단 작은 아이콘에만 있었습니다.
                    // 둘 중에 고르게 해서 잦은 기여를 앞에 둡니다.
                    //
                    // 로그인은 여기서 요구하지 않습니다.
                    // 무엇을 할 수 있는지 먼저 보여주고, 고른 다음에 확인합니다.
                    let returnTab = lastContentTab
                    selectedTab = .add
                    DispatchQueue.main.async {
                        selectedTab = returnTab
                        isContributeChooserPresented = true
                    }
                    return
                }

                lastContentTab = newTab
                if newTab == .map {
                    activateMapRecommendationsForTabEntry()
                }
                selectedTab = newTab
            }
        )
    }

    private func playTabSelectionHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    var body: some View {
        mainContent
        .task {
            await Task.yield()
            homeRecommendations.prepareIfNeeded()
        }
        .fullScreenCover(
            item: $authenticationDestination,
            onDismiss: resumePendingAuthenticatedActionIfPossible
        ) { _ in
            LoginView(authViewModel: authViewModel)
        }
    }

    private var mainContent: some View {
        nativeTabContent
        .background(AppColors.background.ignoresSafeArea())
        .tint(AppColors.accent)
        // 상세는 모든 진입 경로에서 시트로 띄웁니다.
        //
        // 한동안 사진 진입을 fullScreenCover + zoom transition 으로 시도했지만
        // 되돌렸습니다. 이유는 세 가지입니다.
        //  1. 전환 중 대표 사진(1600px) 디코딩이 겹쳐 애니메이션이 끊겼습니다.
        //  2. 전체 화면은 드래그로 닫을 수 없어 닫기 버튼이 필요한데,
        //     이 화면은 하단 액션 바와 내부 시트를 이미 갖고 있어 컨트롤이 과해집니다.
        //  3. zoom transition 은 push 네비게이션과 궁합이 맞습니다.
        //     모달 위에 얹으면 계층이 모호해집니다.
        // 잘 만든 시트 하나가 끊기는 zoom 보다 낫다고 판단했습니다.
        // 상세를 push 구조로 바꾸거나 이미지 디코딩을 최적화한 뒤 재검토할 여지는 남깁니다.
        .sheet(item: $detailPresentation) { presentation in
            detailView(for: presentation)
                .presentationDetents(presentation.source.detents)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isContributeChooserPresented) {
            ContributeChooserView(
                onFieldReport: {
                    isContributeChooserPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                        performAuthenticatedAction { _ in
                            presentComposer(.fieldReport)
                        }
                    }
                },
                onAddSpot: {
                    isContributeChooserPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                        performAuthenticatedAction { _ in
                            presentComposer(.addSpot)
                        }
                    }
                }
            )
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $communityViewModel.isComposerPresented) {
            CommunityComposerView(
                spots: selectableSpots,
                selectedSpot: communityViewModel.composerSpot(in: selectableSpots),
                locksSelectedSpot: composerPurpose == .addSpot
                    && communityViewModel.composerSpot(in: selectableSpots) != nil,
                editingPost: communityViewModel.editingPostForComposer,
                purpose: composerPurpose,
                onSubmit: { draft in
                    guard let authenticatedUser = authViewModel.currentUser else {
                        requestAuthentication()
                        return
                    }

                    if composerPurpose == .addSpot {
                        let spot = submittedSpot(from: draft)
                        submitAddedSpot(spot, draft: draft, submitter: authenticatedUser)
                        communityViewModel.finishComposing()
                    } else if let post = communityViewModel.editingPostForComposer {
                        communityViewModel.updatePost(post, draft: draft)
                    } else {
                        communityViewModel.addPost(draft, author: authenticatedUser)
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isWeatherDetailPresented) {
            WeatherDetailView(
                snapshot: weatherStore.snapshot,
                locationTitle: weatherStore.locationTitle
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "작업을 완료하지 못했어요",
            isPresented: Binding(
                get: { appErrorMessage != nil },
                set: { if !$0 { appErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {
                appErrorMessage = nil
            }
        } message: {
            Text(appErrorMessage ?? "잠시 후 다시 시도해주세요.")
        }
        .alert(
            "장소 제보를 받았어요",
            isPresented: Binding(
                get: { submissionConfirmation != nil },
                set: { if !$0 { submissionConfirmation = nil } }
            )
        ) {
            Button("확인", role: .cancel) {
                submissionConfirmation = nil
            }
        } message: {
            Text(submissionConfirmation?.confirmationMessage ?? "검토가 끝난 뒤 공개됩니다.")
        }
        .onReceive(locationReader.$coordinate) { newCoordinate in
            guard let newCoordinate else { return }

            homeRecommendations.updateLocationContext(userLocation: newCoordinate)

            Task {
                await weatherStore.updateLocationTitle(for: newCoordinate)
                await weatherStore.load(for: newCoordinate)
            }

            if mapState.mode == .recommendations {
                mapState.finishRecommendations()
                logMapRecommendationResult()
            }
        }
        .onReceive(locationReader.$state) { state in
            guard mapState.mode == .recommendations,
                  case .failed(let message) = state else {
                return
            }
            mapState.finishRecommendations(errorMessage: message)
        }
        .onReceive(weatherStore.$snapshot) { snapshot in
            homeRecommendations.updateWeatherContext(snapshot?.recommendationContext)
        }
        .onReceive(searchViewModel.$verifiedSpots) { verifiedSpots in
            mergeAISpots(from: verifiedSpots.map(\.photoSpot))
        }
        .onReceive(communityViewModel.$posts) { posts in
            homeRecommendations.updateCommunityContext(posts: posts)
        }
        .task {
            await loadSubmittedSpotsIfNeeded()
        }
        .task {
            locationReader.requestLocation()
            await weatherStore.load(
                for: fallbackWeatherCoordinate,
                fallbackTitle: "서울특별시"
            )
        }
        .onChange(of: selectedTab) { _, newTab in
            setHomeTabBarHidden(false)

            if newTab != .add {
                lastContentTab = newTab
            }

            if newTab == .map {
                if mapState.shouldFocusUserOnSelection {
                    mapState.activateRecommendations()
                    selectedSpotRevision = 0
                    locationReader.requestLocation()
                    mapState.userLocationFocusRevision += 1
                }
                mapState.shouldFocusUserOnSelection = true
            }
        }
    }

    @ViewBuilder
    private var nativeTabContent: some View {
        TabView(selection: tabSelection) {
            HomeFeedView(
                searchableSpots: selectableSpots,
                recommendedSpots: recommendedSpots,
                communityPosts: communityViewModel.posts,
                preloadedRecommendations: homeRecommendations.todayRecommendations,
                sectionRecommendations: homeRecommendations.sectionRecommendations,
                expandedSectionRecommendations: homeRecommendations.expandedSectionRecommendations,
                loadingSectionIDs: [],
                isPreloadingRecommendations: false,
                currentLocationTitle: weatherStore.locationTitle,
                weatherSnapshot: weatherStore.snapshot,
                weatherLoadFailed: weatherStore.hasFailed,
                savedSpotIDs: savedSpotStore.savedSpotIDs,
                searchViewModel: searchViewModel,
                userLocation: locationReader.coordinate,
                onAddAISpot: addAISpot,
                onShowDetail: { showDetail($0, source: .home) },
                onShowSearchDetail: { showDetail($0, source: .search) },
                onReportMissingPhoto: { spot in
                    performAuthenticatedAction { _ in
                        presentComposer(.addSpot, spot: spot)
                    }
                },
                onToggleSave: { savedSpotStore.toggle($0) },
                onOpenMap: openMap,
                onShowWeather: { isWeatherDetailPresented = true },
                onShowCurrentLocation: showCurrentLocationOnMap,
                onTabBarVisibilityChange: { shouldHide in
                    updateTabBarVisibility(shouldHide, source: .home)
                },
                onTabBarDragChange: { delta in
                    guard selectedTab == .home else { return }
                    NativeTabBarVisibilityController.shared.updateInteraction(by: delta)
                },
                onTabBarDragEnd: { projectedDelta in
                    guard selectedTab == .home else { return }
                    NativeTabBarVisibilityController.shared.finishInteraction(
                        projectedDelta: projectedDelta
                    )
                },
                onRefreshRecommendations: {
                    await homeRecommendations.refresh()
                }
            )
            .tag(AppTab.home)
            .tabItem {
                tabItemLabel(for: .home)
            }

            mapLayer
                .tag(AppTab.map)
                .tabItem {
                    tabItemLabel(for: .map)
                }

            Color.clear
                .tag(AppTab.add)
                .tabItem {
                    tabItemLabel(for: .add)
                }

            CommunityTabView(
                posts: communityViewModel.posts,
                spots: selectableSpots,
                currentUserID: authViewModel.currentUser?.id ?? "",
                likedPostIDs: communityViewModel.likedPostIDs,
                followedAuthorIDs: communityViewModel.followedAuthorIDs,
                commentsByPostID: communityViewModel.commentsByPostID,
                onTabBarVisibilityChange: { shouldHide in
                    updateTabBarVisibility(shouldHide, source: .community)
                },
                onCompose: {
                    performAuthenticatedAction { _ in
                        presentComposer(.fieldReport)
                    }
                },
                onSelectSpot: { showDetail($0, source: .community) },
                onEditPost: { post in
                    performAuthenticatedAction { _ in
                        composerPurpose = .fieldReport
                        communityViewModel.beginEditing(post)
                    }
                },
                onDeletePost: { post in
                    performAuthenticatedAction { _ in
                        communityViewModel.deletePost(post)
                    }
                },
                onToggleLike: { post in
                    performAuthenticatedAction { _ in
                        communityViewModel.toggleLike(post)
                    }
                },
                onToggleFollow: { post in
                    performAuthenticatedAction { _ in
                        communityViewModel.toggleFollow(post)
                    }
                },
                onAddComment: { message, post in
                    performAuthenticatedAction(resumeAfterLogin: false) { user in
                        communityViewModel.addComment(message, to: post, author: user)
                    }
                }
            )
            .tag(AppTab.community)
            .tabItem {
                tabItemLabel(for: .community)
            }

            MyTabView(
                user: authViewModel.currentUser,
                savedSpots: savedSpots,
                submissionReceipts: placeSubmissionStore.receipts,
                posts: communityViewModel.posts,
                spots: selectableSpots,
                likedPostIDs: communityViewModel.likedPostIDs,
                followedAuthorIDs: communityViewModel.followedAuthorIDs,
                commentsByPostID: communityViewModel.commentsByPostID,
                onTabBarVisibilityChange: { shouldHide in
                    updateTabBarVisibility(shouldHide, source: .my)
                },
                onSelectSpot: { showDetail($0, source: .saved) },
                onEditPost: { post in
                    performAuthenticatedAction { _ in
                        composerPurpose = .fieldReport
                        communityViewModel.beginEditing(post)
                    }
                },
                onDeletePost: { post in
                    performAuthenticatedAction { _ in
                        communityViewModel.deletePost(post)
                    }
                },
                onToggleLike: { post in
                    performAuthenticatedAction { _ in
                        communityViewModel.toggleLike(post)
                    }
                },
                onToggleFollow: { post in
                    performAuthenticatedAction { _ in
                        communityViewModel.toggleFollow(post)
                    }
                },
                onAddComment: { message, post in
                    performAuthenticatedAction(resumeAfterLogin: false) { user in
                        communityViewModel.addComment(message, to: post, author: user)
                    }
                },
                onRequestSignIn: {
                    requestAuthentication()
                },
                onExploreSpots: {
                    setHomeTabBarHidden(false)
                    lastContentTab = .home
                    selectedTab = .home
                },
                onSignOut: {
                    authViewModel.signOut()
                }
            )
            .tag(AppTab.my)
            .tabItem {
                tabItemLabel(for: .my)
            }
        }
        .background {
            NativeTabBarAnimator()
            .allowsHitTesting(false)
        }
        .animation(nil, value: selectedTab)
    }

    private func tabItemLabel(for tab: AppTab) -> some View {
        Group {
            if tab == .add {
                Label {
                    Text(tab.title)
                } icon: {
                    contributeTabIcon
                }
                // 라벨이 비어 있으므로 VoiceOver 용 이름을 따로 줍니다.
                .accessibilityLabel("제보하기")
                .accessibilityHint("현장 정보 공유 또는 새 출사지 제보를 선택합니다")
            } else {
                Label {
                    Text(tab.title)
                } icon: {
                    Image(tab.assetName)
                        .renderingMode(.template)
                }
            }
        }
    }

    /// 중앙 액션 버튼 아이콘.
    ///
    /// 브랜드 오렌지로 미리 칠한 이미지를 alwaysOriginal 로 넘겨서
    /// 선택 여부와 무관하게 항상 오렌지로 보이게 합니다.
    /// (탭 바 아이콘은 기본적으로 tint 색으로 템플릿 렌더되기 때문입니다)
    /// 실패해도 tint 색으로 그려질 뿐이라 기능 손실은 없습니다.
    private var contributeTabIcon: Image {
        let configuration = UIImage.SymbolConfiguration(pointSize: 27, weight: .semibold)

        guard let symbol = UIImage(systemName: "plus.circle.fill", withConfiguration: configuration) else {
            return Image(systemName: "plus.circle.fill")
        }

        return Image(uiImage: symbol.withTintColor(AppColors.uiAccent, renderingMode: .alwaysOriginal))
    }

    private var mapLayer: some View {
        MapTabView(
            spots: mapPinSpots,
            selectedSpot: selectedSpot,
            selectedSpotRevision: selectedSpotRevision,
            focusUserLocationRevision: mapState.userLocationFocusRevision,
            userCoordinate: locationReader.coordinate,
            savedSpots: savedSpots,
            savedSpotIDs: visibleMapSavedSpotIDs,
            shouldShowNearbyMapPins: mapState.mode == .recommendations,
            isRecommendationLoading: mapState.isRecommendationLoading,
            isMapSavedFilterEnabled: mapState.mode == .saved,
            mapCategoryFilter: mapState.categoryFilter,
            emptyRecommendationMessage: mapRecommendationEmptyMessage,
            isSavedListPresented: Binding(
                get: { mapState.isSavedListPresented },
                set: { mapState.isSavedListPresented = $0 }
            ),
            savedListFilter: Binding(
                get: { mapState.savedListFilter },
                set: { mapState.savedListFilter = $0 }
            ),
            onSelectSpot: { selectedSpot = $0 },
            onShowDetail: { showDetail($0, source: .map) },
            onToggleRecommendations: toggleNearbyMapPins,
            onToggleSavedFilter: toggleSavedMapFilter,
            onSelectCategory: selectMapCategory,
            onSelectSavedCategory: selectSavedMapListFilter,
            onSelectSavedSpot: focusSavedSpotFromList
        )
        .onAppear {
            guard selectedTab == .map, mapState.shouldFocusUserOnSelection else { return }
            activateMapRecommendationsForTabEntry()
        }
    }

    private func presentComposer(_ purpose: CommunityComposerPurpose, spot: PhotoSpot? = nil) {
        setHomeTabBarHidden(false)
        composerPurpose = purpose
        communityViewModel.beginComposing(spot: spot)
    }

    private func requestAuthentication(afterLogin action: ((AuthUser) -> Void)? = nil) {
        if let authenticatedUser = authViewModel.currentUser {
            action?(authenticatedUser)
            return
        }

        pendingAuthenticatedAction = action
        authViewModel.prepareForSignInPresentation()
        Task { @MainActor in
            await Task.yield()

            if let authenticatedUser = authViewModel.currentUser {
                let pendingAction = pendingAuthenticatedAction
                pendingAuthenticatedAction = nil
                pendingAction?(authenticatedUser)
                return
            }

            authenticationDestination = .signIn
        }
    }

    @discardableResult
    private func performAuthenticatedAction(
        resumeAfterLogin: Bool = true,
        action: @escaping (AuthUser) -> Void
    ) -> Bool {
        guard let authenticatedUser = authViewModel.currentUser else {
            requestAuthentication(afterLogin: resumeAfterLogin ? action : nil)
            return false
        }

        action(authenticatedUser)
        return true
    }

    private func resumePendingAuthenticatedActionIfPossible() {
        guard authViewModel.currentUser != nil else {
            pendingAuthenticatedAction = nil
            return
        }

        let action = pendingAuthenticatedAction
        pendingAuthenticatedAction = nil
        DispatchQueue.main.async {
            guard let latestAuthenticatedUser = authViewModel.currentUser else { return }
            action?(latestAuthenticatedUser)
        }
    }

    private func updateTabBarVisibility(_ shouldHide: Bool, source: AppTab) {
        guard source == .home, selectedTab == .home else {
            return
        }
        setHomeTabBarHidden(shouldHide)
    }

    private func setHomeTabBarHidden(_ shouldHide: Bool) {
        NativeTabBarVisibilityController.shared.setHidden(shouldHide, animated: true)
    }

    private func activateMapRecommendationsForTabEntry() {
        mapState.activateRecommendations()
        selectedSpotRevision = 0
    }

    private func toggleNearbyMapPins() {
        withAnimation(.easeInOut(duration: 0.16)) {
            mapState.beginRecommendations()
            mapState.userLocationFocusRevision += 1
        }

        if locationReader.coordinate == nil {
            locationReader.requestLocation()
        } else {
            mapState.finishRecommendations()
            logMapRecommendationResult()
        }
    }

    private func toggleSavedMapFilter() {
        withAnimation(.easeInOut(duration: 0.16)) {
            let shouldEnableSavedPins = mapState.mode != .saved

            if shouldEnableSavedPins {
                mapState.showSavedSpots()
                if let firstSavedSpot = savedMapListSpots.first ?? savedSpots.first {
                    selectedSpot = firstSavedSpot
                    selectedSpotRevision += 1
                }
            } else {
                mapState.activateRecommendations(resetCategory: false)
                selectedSpotRevision = 0
            }
        }
    }

    private func selectSavedMapListFilter(_ filter: SavedMapListFilter) {
        withAnimation(.easeInOut(duration: 0.16)) {
            mapState.savedListFilter = filter
            mapState.showSavedSpots()
            mapState.savedListFilter = filter
            mapState.isSavedListPresented = true

            if let firstSpot = savedMapListSpots.first {
                selectedSpot = firstSpot
                selectedSpotRevision += 1
            }
        }
    }

    private func focusSavedSpotFromList(_ spot: PhotoSpot) {
        withAnimation(.easeInOut(duration: 0.16)) {
            selectedSpot = spot
            selectedSpotRevision += 1
            mapState.explicitSpot = nil
        }
    }

    private func selectMapCategory(_ filter: MapCategoryFilter) {
        withAnimation(.easeInOut(duration: 0.16)) {
            mapState.categoryFilter = filter

            if filter != .all {
                if mapState.mode != .recommendations {
                    mapState.beginRecommendations()
                }
                if locationReader.coordinate == nil {
                    locationReader.requestLocation()
                } else {
                    mapState.finishRecommendations()
                    logMapRecommendationResult()
                }
            }
        }
    }

    private func addAISpot(_ spot: PhotoSpot) {
        if let existingIndex = aiSpots.firstIndex(where: {
            $0.id == spot.id || $0.mapQuery == spot.mapQuery
        }) {
            aiSpots[existingIndex] = aiSpots[existingIndex].replacingDisplayImage(from: spot)
            return
        }

        guard !homeRecommendations.visibleSpots.contains(where: {
            $0.id == spot.id || $0.mapQuery == spot.mapQuery
        }) else {
            return
        }
        guard !RecommendationBlacklist.isBlacklistedRecommendation(spot) else {
            return
        }

        aiSpots.append(spot)
    }

    private func submittedSpot(from draft: CommunityPostDraft) -> PhotoSpot {
        let spot = draft.spot
        let trimmedMessage = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedTags = draft.tags.reduce(into: [String]()) { result, tag in
            let normalized = normalizedSubmissionTag(tag)
            guard !normalized.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else {
                return
            }
            result.append(normalized)
        }

        return PhotoSpot(
            id: spot.id,
            name: spot.name,
            region: spot.region,
            summary: trimmedMessage.isEmpty ? spot.summary : trimmedMessage,
            hashtags: submittedTags.isEmpty ? spot.hashtags : submittedTags,
            eventTitle: spot.eventTitle,
            eventPeriod: spot.eventPeriod,
            feeInfo: spot.feeInfo,
            openingHours: spot.openingHours,
            bestTime: spot.bestTime,
            crowdLevel: spot.crowdLevel,
            lensSuggestion: spot.lensSuggestion,
            weatherFit: spot.weatherFit,
            parkingInfo: spot.parkingInfo,
            nearbyParkingInfo: spot.nearbyParkingInfo,
            communityTitle: "사용자 추가 장소",
            communitySubtitle: trimmedMessage.isEmpty ? spot.communitySubtitle : trimmedMessage,
            mapQuery: spot.mapQuery,
            latitude: spot.latitude,
            longitude: spot.longitude,
            theme: spot.theme,
            imageURL: spot.imageURL,
            category: spot.category,
            season: spot.season,
            weather: spot.weather,
            mood: Array(Set(spot.mood + submittedTags)),
            crowdLevelCode: spot.crowdLevelCode,
            imageName: spot.imageName,
            imageCredit: spot.imageCredit,
            imageLicense: spot.imageLicense,
            imageSourceURL: spot.imageSourceURL,
            recommendationRegions: spot.recommendationRegions,
            isHiddenSpot: spot.isHiddenSpot
        )
    }

    private func normalizedSubmissionTag(_ value: String) -> String {
        var tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") {
            tag.removeFirst()
        }
        return tag
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private func submitAddedSpot(
        _ spot: PhotoSpot,
        draft: CommunityPostDraft,
        submitter: AuthUser
    ) {
        Task {
            do {
                let receipt = try await placeSubmissionService.submit(
                    spot: spot,
                    tags: draft.tags,
                    photoData: draft.photoData,
                    submitter: submitter
                )
                await MainActor.run {
                    placeSubmissionStore.record(receipt)
                    submissionConfirmation = receipt
                }
            } catch {
                AppLog.network.error(
                    "Place submission failed: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    appErrorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func loadSubmittedSpotsIfNeeded() async {
        guard submittedSpotsState != .loading,
              submittedSpotsState != .loaded else {
            return
        }
        submittedSpotsState = .loading

        do {
            let submittedSpots = try await placeSubmissionService.fetchSubmittedSpots()
            mergeAISpots(from: submittedSpots)
            placeSubmissionStore.markApproved(spotIDs: Set(submittedSpots.map(\.id)))
            submittedSpotsState = .loaded
        } catch {
            AppLog.network.error(
                "Submitted spots fetch failed: \(error.localizedDescription, privacy: .public)"
            )
            submittedSpotsState = .failed(message: error.localizedDescription)
        }
    }

    private func mergeAISpots(from spots: [PhotoSpot]) {
        for spot in spots {
            addAISpot(spot)
        }
    }

    /// 상세 화면 본문. 표시 방식과 분리해 둡니다.
    private func detailView(for presentation: SpotDetailPresentation) -> some View {
        SpotDetailView(
            authViewModel: authViewModel,
            spot: presentation.spot,
            source: presentation.source,
            isSaved: savedSpotStore.contains(presentation.spot),
            communityPosts: communityViewModel.posts(for: presentation.spot),
            currentUserID: authViewModel.currentUser?.id ?? "",
            spots: selectableSpots,
            userLocation: locationReader.coordinate,
            onToggleSave: {
                savedSpotStore.toggle(presentation.spot)
            },
            onOpenMap: {
                detailPresentation = nil
                openMap(presentation.spot)
            },
            onReportPhoto: {
                performAuthenticatedAction { _ in
                    detailPresentation = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        presentComposer(.addSpot, spot: presentation.spot)
                    }
                }
            },
            onSubmitCommunity: { draft in
                performAuthenticatedAction { user in
                    communityViewModel.addPost(draft, author: user)
                }
            },
            onUpdateCommunity: { post, draft in
                performAuthenticatedAction { _ in
                    communityViewModel.updatePost(post, draft: draft)
                }
            },
            onDeleteCommunity: { post in
                performAuthenticatedAction { _ in
                    communityViewModel.deletePost(post)
                }
            }
        )
    }

    private func showDetail(_ spot: PhotoSpot, source: SpotDetailSource) {
        detailPresentation = SpotDetailPresentation(spot: spot, source: source)
    }

    private func openMap(_ spot: PhotoSpot?) {
        if let spot {
            addAISpot(spot)
            selectedSpot = spot
            selectedSpotRevision += 1
            mapState.showExplicitSpot(spot)
        } else {
            activateMapRecommendationsForTabEntry()
        }

        selectedTab = .map
    }

    private func showCurrentLocationOnMap() {
        mapState.activateRecommendations(resetCategory: false)
        mapState.userLocationFocusRevision += 1
        selectedTab = .map
    }

    private func showHiddenSpotsOnMap() {
        mapState.shouldFocusUserOnSelection = false
        selectedTab = .map
        mapState.categoryFilter = .hidden
        mapState.beginRecommendations()
        mapState.shouldFocusUserOnSelection = false
        mapState.userLocationFocusRevision += 1
        if locationReader.coordinate == nil {
            locationReader.requestLocation()
        } else {
            mapState.finishRecommendations()
        }
    }

    private func logMapRecommendationResult() {
        let result = currentMapRecommendation
        let coordinateText = locationReader.coordinate.map {
            String(format: "%.5f, %.5f", $0.latitude, $0.longitude)
        } ?? "없음"
        let radiusText = result.radius.map { "\(Int($0 / 1_000))km" } ?? "기본"
        let finalNames = result.spots.map(\.name).joined(separator: ", ")
        AppLog.recommendations.info(
            "Map coordinate=\(coordinateText, privacy: .public) radius=\(radiusText, privacy: .public) candidates=\(result.candidateCount) final=[\(finalNames, privacy: .public)] fallback=\(result.fallbackUsed)"
        )
    }

    private func uniqueSpots(_ spots: [PhotoSpot]) -> [PhotoSpot] {
        spots.reduce(into: [PhotoSpot]()) { result, spot in
            if let existingIndex = result.firstIndex(where: {
                $0.id == spot.id || $0.mapQuery == spot.mapQuery
            }) {
                result[existingIndex] = result[existingIndex].replacingDisplayImage(from: spot)
                return
            }
            result.append(spot)
        }
    }

}


// ═══════════════════════════════════════════════════════════════════
// MARK: - ContributeChooserView
//
//  탭 바 중앙 버튼을 눌렀을 때 뜨는 2택 시트.
//
//  이 앱은 사용자 제보로 굴러가는 앱이라 중앙 자리를 유지하는 것이 맞습니다.
//  다만 기여에는 성격이 완전히 다른 두 종류가 있습니다.
//
//    현장 정보  가볍고 잦음. 지금 그 자리에 있으면 됩니다.
//              "27분 전 서울숲 데이지 피었어요" 같은 정보가 앱을 살아있게 만듭니다.
//    장소 제보  무겁고 드묾. 아직 없는 장소를 알아야 하고 검토도 필요합니다.
//
//  이전에는 중앙 버튼이 곧바로 "장소 추가" 로 갔고, 정작 잦은 기여인 현장 정보는
//  커뮤니티 화면 우상단 작은 아이콘에만 있었습니다. 가치와 노출이 반대였습니다.
//  그래서 잦은 기여를 위에 두고 고르게 합니다.
// ═══════════════════════════════════════════════════════════════════

private struct ContributeChooserView: View {
    let onFieldReport: () -> Void
    let onAddSpot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            Text("무엇을 알려주실래요?")
                .vfText(.title2)
                .foregroundStyle(AppColors.primary)
                .padding(.top, VFSpace.sm)

            ContributeChooserRow(
                symbolName: "dot.radiowaves.left.and.right",
                title: "현장 정보 공유",
                subtitle: "지금 이 장소의 혼잡도와 상황을 알려주세요",
                action: onFieldReport
            )

            ContributeChooserRow(
                symbolName: "mappin.and.ellipse",
                title: "새 출사지 제보",
                subtitle: "아직 등록되지 않은 장소를 알려주세요",
                action: onAddSpot
            )
        }
        .vfScreenMargin()
        .padding(.bottom, VFSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.background)
    }
}

private struct ContributeChooserRow: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VFSpace.md) {
                Image(systemName: symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        AppColors.accentSoft,
                        in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .vfText(.headline)
                        .foregroundStyle(AppColors.primary)

                    Text(subtitle)
                        .vfText(.subhead)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: VFSpace.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(VFSpace.md + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

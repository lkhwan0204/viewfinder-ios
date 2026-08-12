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
                // "장소제보"(4글자) -> "제보"(2글자)
                //
                // 한동안 라벨을 완전히 비워봤지만 되살렸습니다.
                // 중앙 + 는 학습된 패턴이지만, 그 패턴이 통하는 앱들(TikTok, Instagram)의
                // + 는 "사진 올리기" 라서 추측이 쉽습니다.
                // 이 앱의 기여는 "출사지 제보" 라서 훨씬 덜 자명합니다.
                //
                // 또 나머지 4개에는 라벨이 있는데 중앙만 없으면
                // "특별하다" 가 아니라 "빠졌다" 로 읽힐 위험이 있습니다.
                //
                // 원래 문제는 라벨의 존재가 아니라 길이였습니다.
                // 4글자가 다른 라벨을 눌러 타이포가 답답했습니다.
                // 2글자면 그 문제가 없고, 오렌지 색 덕분에
                // 여전히 목적지가 아니라 동작으로 읽힙니다.
                return "제보"
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
                    // 탭 바 중앙은 "새 출사지 제보" 전용입니다.
                    //
                    // 한동안 2택 시트(현장 정보 / 새 장소)를 띄웠지만 되돌렸습니다.
                    // 두 동작의 전제 조건이 다르기 때문입니다.
                    //
                    //   현장 정보 공유  장소가 이미 있어야 하는 동작입니다.
                    //                  탭 바는 앱 어디서든 누르는 버튼이라 장소 맥락이
                    //                  없어서, 여기서 시작하면 "어느 장소요?" 를
                    //                  먼저 골라야 하는 단계가 붙습니다.
                    //                  정작 이 기능은 내가 그 장소에 있을 때 쓰는 것입니다.
                    //   새 장소 제보    정의상 맥락이 없는 동작입니다.
                    //                  전역 버튼이 정확한 자리입니다.
                    //
                    // 현장 정보가 묻혀 있다는 진단은 맞았지만 처방이 틀렸습니다.
                    // 처방은 탭 바가 아니라 컨텍스트 노출입니다.
                    //   현재: 장소 상세의 현장 정보 섹션 (SpotDetailCommunitySection.onWrite)
                    //   추후: GPS 가 저장된 장소와 일치할 때 프롬프트,
                    //         검색 결과 0건일 때 제보 유도
                    let returnTab = lastContentTab
                    selectedTab = .add
                    DispatchQueue.main.async {
                        selectedTab = returnTab
                        performAuthenticatedAction { _ in
                            presentComposer(.addSpot)
                        }
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
                .accessibilityHint("새 출사지를 제보합니다")
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
    /// 한동안 plus.circle.fill(꽉 찬 원반)을 27pt 로 키워 썼는데 되돌렸습니다.
    /// 나머지 4개는 얇은 선 아이콘인데 중앙만 꽉 찬 원반이라
    /// 아이콘 패밀리가 깨지고 스티커를 붙인 것처럼 보였습니다.
    /// 반투명 유리 pill 안에 불투명한 원이 들어가 재료도 싸웠습니다.
    ///
    /// 원래 에셋(다른 탭과 같은 선 스타일, 같은 크기)을 그대로 쓰고
    /// 색만 브랜드 오렌지로 입힙니다.
    /// 형태로는 패밀리에 속하고, 색으로만 "동작" 임을 구분합니다.
    ///
    /// withTintColor + alwaysOriginal 이라 선택 여부와 무관하게 오렌지를 유지합니다.
    /// (탭 바 아이콘은 기본적으로 tint 색으로 템플릿 렌더됩니다)
    private var contributeTabIcon: Image {
        guard let asset = UIImage(named: AppTab.add.assetName) else {
            return Image(systemName: "plus")
        }

        let tinted = asset
            .withRenderingMode(.alwaysTemplate)
            .withTintColor(AppColors.uiAccent, renderingMode: .alwaysOriginal)

        return Image(uiImage: tinted)
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

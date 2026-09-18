import CoreLocation
import Foundation
import OSLog
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
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
                //
                // "제보"(2글자)로 줄였다가 "새 장소"(3글자)로 다시 고쳤습니다.
                // 커뮤니티 화면 우상단에도 작성 버튼이 있어서, 둘 다 "제보" 로
                // 읽히면 무엇이 다른지 알 수 없었습니다.
                // 이 앱에서는 현장 정보도 제보고 새 장소도 제보입니다.
                //
                // 대상 객체를 라벨에 넣어 구분합니다.
                //   탭 바      [+ 새 장소]          장소를 등록
                //   커뮤니티   [펜] 현장 정보 작성   정보를 작성
                // 객체(장소 / 정보), 동사(등록 / 작성), 아이콘(+ / 펜)
                // 세 층위에서 구분됩니다.
                return "새 장소"
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
    @State private var registeredHomeSpots: [PhotoSpot] = []
    @State private var homeWeatherCoordinate: CLLocationCoordinate2D?
    @State private var homeWeatherTask: Task<Void, Never>?
    @State private var detailPresentation: SpotDetailPresentation?
    @State private var isWeatherDetailPresented = false
    @State private var composerPurpose: CommunityComposerPurpose = .fieldReport
    @State private var submittedSpotsState: AsyncLoadState = .idle
    @State private var appErrorMessage: String?
    @State private var submissionConfirmation: PlaceSubmissionReceipt?
    @State private var photoContributionConfirmationSpot: PhotoSpot?
    @State private var contributedCoverPhotos: [String: PlacePhoto] = [:]
    @State private var authenticationDestination: AuthenticationDestination?
    @State private var loginPresentationContext: LoginPresentationContext = .general
    @State private var pendingAuthenticatedAction: ((AuthUser) -> Void)?
    @State private var isHomeSearchPresented = false
    @State private var shouldRestoreHomeSearch = false
    @State private var pendingHomeSearchAction: (() -> Void)?
    @State private var pendingDetailDismissAction: (() -> Void)?
    @StateObject private var homeRecommendations = HomeRecommendationsViewModel()
    @StateObject private var locationReader = RecommendationLocationReader()
    @StateObject private var mapState = MapExperienceState()
    @StateObject private var weatherStore = WeatherStore()
    @StateObject private var searchViewModel = PhotoSpotSearchViewModel()
    @StateObject private var savedSpotStore = SavedSpotStore()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var communityViewModel = CommunityViewModel()
    @StateObject private var placePhotoGalleryStore = PlacePhotoGalleryStore.shared
    @StateObject private var crowdReportStore = CrowdReportStore.shared
    @StateObject private var placeSubmissionStore = PlaceSubmissionStore()
    private let localSeedDataService = LocalSeedDataService()
    private let placeSubmissionService = PlaceSubmissionService()

    private var homePresentationState: HomeRecommendationState {
        if homeRecommendations.recommendationState == .empty {
            switch submittedSpotsState {
            case .idle, .loading:
                return .initialLoading
            case .failed(let message):
                return .failed(message: message)
            case .loaded:
                break
            }
        }
        return homeRecommendations.recommendationState
    }

    private var recommendedSpots: [PhotoSpot] {
        uniqueSpots(homeRecommendations.visibleSpots + aiSpots)
            .map { resolvedSpotWithContributedCover($0) }
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
    }

    /// 지도는 홈의 일부 추천 결과가 아니라 앱이 알고 있는 전체 장소를 후보로 사용합니다.
    /// 실제 marker 생성은 Naver Map의 현재 viewport 안으로 다시 좁혀집니다.
    private var allMapSpots: [PhotoSpot] {
        uniqueSpots(localSeedDataService.allPhotoSpots() + recommendedSpots + aiSpots)
            .map { resolvedSpotWithContributedCover($0) }
    }

    private var mapPinSpots: [PhotoSpot] {
        switch mapState.mode {
        case .saved:
            return sanitizedMapSpots(
                savedMapListSpots.filter { mapState.categoryFilter.matches($0) }
            )

        case .explicitSpot:
            if let explicitMapSpot = mapState.explicitSpot,
               !RecommendationBlacklist.isBlacklistedRecommendation(explicitMapSpot) {
                return [explicitMapSpot]
            }
            return []

        case .recommendations:
            let sourceSpots = mapState.isSavedFilterEnabled ? savedSpots : allMapSpots
            return sanitizedMapSpots(
                sourceSpots.filter { mapState.categoryFilter.matches($0) }
            )
        }
    }

    private func sanitizedMapSpots(_ spots: [PhotoSpot]) -> [PhotoSpot] {
        uniqueSpots(spots).filter {
            // 지도 핀은 원격 URL뿐 아니라 번들 에셋 사진도 표시할 수 있습니다.
            // imageURL만 검사하면 로컬 사진이 있는 출사지가 지도 추천에서 사라집니다.
            $0.hasReliableDisplayImage
                && !CafeRecommendationPolicy.isBlacklistedCafe($0)
                && !RecommendationBlacklist.isBlacklistedRecommendation($0)
        }
    }

    private var mapRecommendationEmptyMessage: String? {
        if mapState.isSavedFilterEnabled {
            // 저장 필터는 지도 위의 핀만 줄이는 조용한 필터입니다.
            // 저장 장소가 없어도 고정 문구나 빈 상태 카드를 띄우지 않습니다.
            return nil
        }

        guard mapState.mode == .recommendations,
              !mapState.isRecommendationLoading,
              mapPinSpots.isEmpty else {
            return nil
        }

        return locationReader.coordinate == nil
            ? "현재 위치를 가져오면 주변 출사지를 추천할게요"
            : "주변 출사지 데이터가 부족해요"
    }

    private var savedSpots: [PhotoSpot] {
        allMapSpots.filter { savedSpotStore.contains($0) }
    }

    private var savedMapListSpots: [PhotoSpot] {
        uniqueSpots(savedSpots)
            .filter { mapState.savedListFilter.matches($0) }
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
    }

    private var selectableSpots: [PhotoSpot] {
        allMapSpots
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
    }

    /// 시트나 전체 화면이 열린 동안 배경 탭이 VoiceOver 탐색에 남지 않게 합니다.
    /// 시각적 탭바 동작과 위치는 바꾸지 않고 접근성 트리만 격리합니다.
    private var isRootModalPresented: Bool {
        detailPresentation != nil
            || communityViewModel.isComposerPresented
            || isWeatherDetailPresented
            || authenticationDestination != nil
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
                        performAuthenticatedAction(loginPresentationContext: .addSpot) { _ in
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
            // Restore only after a trustworthy regional context is available.
            // Never infer today's country from the recommendation cache itself.
            if let recentCoordinate = locationReader.recentCoordinateForRecommendation() {
                homeRecommendations.updateLocationContext(userLocation: recentCoordinate)
                // `onReceive($coordinate)` does not replay a value that was
                // published before this view subscribed. Start the weather
                // request explicitly for the cached coordinate as well.
                refreshHomeWeatherIfNeeded(at: recentCoordinate)
            }
            let coordinate = await locationReader.coordinateForRecommendation(forceRefresh: true)
            homeRecommendations.updateLocationContext(userLocation: coordinate)
            if let coordinate {
                refreshHomeWeatherIfNeeded(at: coordinate)
            }
            homeRecommendations.prepareIfNeeded()
        }
        .fullScreenCover(
            item: $authenticationDestination,
            onDismiss: {
                resumePendingAuthenticatedActionIfPossible()
                loginPresentationContext = .general
            }
        ) { _ in
            LoginView(
                authViewModel: authViewModel,
                presentationContext: loginPresentationContext
            )
        }
    }

    private var mainContent: some View {
        nativeTabContent
        .accessibilityHidden(isRootModalPresented)
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
        .sheet(item: $detailPresentation, onDismiss: {
            let action = pendingDetailDismissAction
            pendingDetailDismissAction = nil
            action?()
            restoreHomeSearchIfPossible()
        }) { presentation in
            detailView(for: presentation)
                .presentationDetents(presentation.source.detents)
                .presentationDragIndicator(.visible)
        }

        .sheet(isPresented: $communityViewModel.isComposerPresented, onDismiss: restoreHomeSearchIfPossible) {
            CommunityComposerView(
                spots: selectableSpots,
                selectedSpot: communityViewModel.composerSpot(in: selectableSpots),
                locksSelectedSpot: (composerPurpose == .addSpot || composerPurpose.isPhotoContribution)
                    && communityViewModel.composerSpot(in: selectableSpots) != nil,
                editingPost: communityViewModel.editingPostForComposer,
                purpose: composerPurpose,
                onShowRegisteredSpot: { spot in
                    showDetail(spot, source: .search)
                },
                onSubmit: { draft in
                    guard let authenticatedUser = authViewModel.currentUser else {
                        requestAuthentication()
                        return
                    }

                    if composerPurpose.isPhotoContribution {
                        guard let placeID = composerPurpose.photoContributionPlaceID,
                              let spot = draft.spot,
                              spot.id == placeID else {
                            communityViewModel.finishComposing()
                            appErrorMessage = "사진을 등록할 장소를 찾지 못했어요."
                            return
                        }
                        submitPlacePhotoContribution(
                            spot: spot,
                            draft: draft,
                            submitter: authenticatedUser
                        )
                        communityViewModel.finishComposing()
                    } else if composerPurpose == .addSpot {
                        if let spot = submittedSpot(from: draft) {
                            submitAddedSpot(spot, draft: draft, submitter: authenticatedUser)
                        }
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
                locationTitle: weatherStore.locationTitle,
                loadState: weatherStore.state,
                onRefresh: {
                    guard let coordinate = locationReader.coordinate else { return }
                    await weatherStore.load(
                        for: coordinate,
                        force: true
                    )
                }
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
        .onChange(of: appErrorMessage) { _, message in
            if message == nil { restoreHomeSearchIfPossible() }
        }
        .alert(
            "장소가 추가됐어요",
            isPresented: Binding(
                get: { submissionConfirmation != nil },
                set: { if !$0 { submissionConfirmation = nil } }
            )
        ) {
            Button("확인", role: .cancel) {
                submissionConfirmation = nil
            }
        } message: {
            Text(submissionConfirmation?.confirmationMessage ?? "장소가 공개됐어요.")
        }
        .alert(
            "사진이 등록되었어요",
            isPresented: Binding(
                get: { photoContributionConfirmationSpot != nil },
                set: { if !$0 { photoContributionConfirmationSpot = nil } }
            )
        ) {
            Button("장소 보기") {
                guard let spot = photoContributionConfirmationSpot else { return }
                photoContributionConfirmationSpot = nil
                showDetail(spot, source: .community)
            }
            Button("확인", role: .cancel) {
                photoContributionConfirmationSpot = nil
            }
        } message: {
            Text("기존 장소에 사진이 추가되었어요.")
        }
        .onReceive(locationReader.$coordinate) { newCoordinate in
            guard let newCoordinate else { return }

            homeRecommendations.updateLocationContext(userLocation: newCoordinate)
            refreshHomeWeatherIfNeeded(at: newCoordinate)

            if mapState.mode == .recommendations {
                mapState.finishRecommendations()
            }
        }
        .onReceive(locationReader.$state) { state in
            if case .failed = state, locationReader.coordinate == nil {
                homeRecommendations.updateLocationContext(userLocation: nil)
                homeWeatherTask?.cancel()
                homeWeatherCoordinate = nil
                // A transient location failure should not erase a still-valid
                // weather snapshot that can keep the Home pill useful.
                weatherStore.invalidateLocationContext(preservingFreshSnapshot: true)
            }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                homeRecommendations.refreshTimeContextIfNeeded()
                locationReader.requestLocation()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            setHomeTabBarHidden(false)

            if newTab != .add {
                lastContentTab = newTab
            }

            if newTab == .home {
                locationReader.requestLocation()
            }

            if newTab == .map {
                if mapState.shouldFocusUserOnSelection {
                    mapState.activateRecommendations()
                    selectedSpotRevision = 0
                    locationReader.requestLocation()
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
                geographicCandidateSpots: homeRecommendations.geographicCandidateSpots.map {
                    resolvedSpotWithContributedCover($0)
                },
                recommendedSpots: recommendedSpots,
                communityPosts: communityViewModel.posts,
                preloadedRecommendations: homeRecommendations.todayRecommendations,
                recommendationState: homePresentationState,
                sectionRecommendations: homeRecommendations.sectionRecommendations,
                expandedSectionRecommendations: homeRecommendations.expandedSectionRecommendations,
                loadingSectionIDs: [],
                isPreloadingRecommendations: false,
                currentLocationTitle: weatherStore.locationTitle,
                weatherSnapshot: weatherStore.snapshot,
                weatherLoadFailed: weatherStore.hasFailed,
                weatherIsLoading: weatherStore.state.isLoading,
                savedSpotIDs: savedSpotStore.savedSpotIDs,
                searchViewModel: searchViewModel,
                userLocation: locationReader.coordinate,
                onAddAISpot: addAISpot,
                onShowDetail: { showDetail($0, source: .home) },
                onShowSearchDetail: { showDetail($0, source: .search) },
                onReportMissingPhoto: { spot in
                    performAuthenticatedAction(loginPresentationContext: .contributePhotos) { _ in
                        presentComposer(.contributePhotos(placeID: spot.id), spot: spot)
                    }
                },
                onAddPlace: {
                    performAuthenticatedAction(loginPresentationContext: .addSpot) { _ in
                        presentComposer(.addSpot)
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
                    if case .failed = submittedSpotsState {
                        await loadSubmittedSpotsIfNeeded()
                    }
                    let coordinate = await locationReader.coordinateForRecommendation(forceRefresh: true)
                    homeRecommendations.updateLocationContext(userLocation: coordinate)
                    if let coordinate {
                        refreshHomeWeatherIfNeeded(at: coordinate)
                    }
                    await homeRecommendations.refresh()
                },
                isSearchResultsPresented: $isHomeSearchPresented,
                onSearchDismissed: finishHomeSearchDismissal,
                onPerformSearchAction: performAfterHomeSearchDismissal
            )
            .tag(AppTab.home)
            .tabItem {
                tabItemLabel(for: .home)
            }
            .vfOpaqueTabBar()

            mapLayer
                .tag(AppTab.map)
                .tabItem {
                    tabItemLabel(for: .map)
                }
                .vfOpaqueTabBar()

            Color.clear
                .tag(AppTab.add)
                .tabItem {
                    tabItemLabel(for: .add)
                }
                .vfOpaqueTabBar()

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
                    performAuthenticatedAction(loginPresentationContext: .communityPost) { _ in
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
                },
                communityViewModel: communityViewModel
            )
            .tag(AppTab.community)
            .tabItem {
                tabItemLabel(for: .community)
            }
            .vfOpaqueTabBar()

            MyTabView(
                user: authViewModel.currentUser,
                savedSpots: savedSpots,
                submissionReceipts: placeSubmissionStore.receipts,
                posts: communityViewModel.posts,
                spots: selectableSpots,
                likedPostIDs: communityViewModel.likedPostIDs,
                followedAuthorIDs: communityViewModel.followedAuthorIDs,
                commentsByPostID: communityViewModel.commentsByPostID,
                communityViewModel: communityViewModel,
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
            .vfOpaqueTabBar()
        }
        // ═══════════════════════════════════════════════════════════
        //  탭바 배경을 SwiftUI 쪽에서 지정합니다. (시도 A)
        //
        //  [문제였던 상황]
        //  AppDelegate 에서 UITabBarAppearance 로
        //    configureWithOpaqueBackground()
        //    backgroundEffect = nil
        //    backgroundColor  = surface2
        //  까지 다 걸었는데, 실기 iOS 26 에서 탭바가 여전히 밝은 유리였고
        //  뒤의 지도 글자가 비쳤습니다. 검색바·칩은 #1C1C1F 불투명인데
        //  탭바만 밝아서 같은 화면에 두 가지 크롬이 있었습니다.
        //
        //  iOS 26 플로팅 탭바는 UITabBarAppearance 의 배경 설정을
        //  적용하지 않는 것으로 보입니다.
        //
        //  [시도]
        //  toolbarBackground 는 UIKit appearance 프록시가 아니라 SwiftUI 가
        //  자기 툴바 렌더링에 직접 거는 경로입니다. appearance 를 무시하는
        //  구현이라도 이쪽은 볼 가능성이 있습니다.
        //  AppDelegate 설정은 지우지 않고 둡니다. 둘은 배타적이지 않고,
        //  이전 OS 에서는 그쪽이 실제로 동작합니다.
        //
        //  이것도 실패하면 유리 성질을 이용하는 방향으로 갑니다.
        //  (탭바 뒤 콘텐츠를 어둡게 해서 유리가 따라 어두워지게)
        //  실패 여부를 추측하지 않도록 NativeTabBarSupport 에 배경을
        //  실제로 그리는 레이어가 무엇인지 찍는 진단을 넣었습니다.
        //
        //  TabView 자신과 각 탭 루트에 모두 걸었습니다.
        //  툴바 배경은 내비게이션 바와 마찬가지로 "지금 선택된 탭의
        //  콘텐츠" 기준으로 해석되기 때문에, 컨테이너에만 걸면 무시되고
        //  자식에 걸어야 반영되는 경우가 있습니다. 한 번의 빌드로
        //  판정하기 위해 양쪽 다 겁니다. 중복은 무해합니다.
        // ═══════════════════════════════════════════════════════════
        .vfOpaqueTabBar()
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
            shouldShowNearbyMapPins: mapState.mode == .recommendations,
            isRecommendationLoading: mapState.isRecommendationLoading,
            isMapSavedFilterEnabled: mapState.isSavedFilterEnabled,
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
            onShowDetail: { showDetail($0, source: .map) },
            onToggleRecommendations: toggleNearbyMapPins,
            onToggleSavedFilter: toggleSavedMapFilter,
            onSelectCategory: selectMapCategory,
            onSelectSavedCategory: selectSavedMapListFilter,
            onSelectSavedSpot: focusSavedSpotFromList,
            searchableSpots: selectableSpots,
            // 검색 결과 선택은 상세의 "지도에서 보기" 와 같은 경로입니다.
            // 그 장소를 지도에 명시적으로 올리고 카메라를 옮깁니다.
            onSelectSearchResult: openMap,
            onAddPlace: {
                performAuthenticatedAction(loginPresentationContext: .addSpot) { _ in
                    presentComposer(.addSpot)
                }
            },
            onFocusUserLocation: focusUserLocationOnMap
        )
        .onAppear {
            guard selectedTab == .map, mapState.shouldFocusUserOnSelection else { return }
            activateMapRecommendationsForTabEntry()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  할 수 없는 일을 제안하지 않습니다.
    //
    //  [문제였던 상황]
    //  장소 제보는 서버에 저장됩니다. 릴리스 빌드에서
    //  VIEWFINDER_RECOMMENDATION_ENDPOINT 가 비어 있으면(지금 상태입니다)
    //  이 기능은 동작하지 않습니다.
    //
    //  그런데 앱은 제보 양식을 그대로 열어줬습니다. 사용자는 장소를
    //  검색하고, 사진을 고르고, 태그를 넣고, 제출을 누른 뒤에야
    //  실패했습니다. 그리고 받는 문구가
    //  "장소 등록 서버 주소가 설정되지 않았어요" 였습니다.
    //
    //  문구를 다듬는 것으로는 부족합니다. 문구가 아무리 좋아도 작업을
    //  다 시킨 뒤에 버리는 것은 같습니다.
    //
    //  [지금]
    //  서버를 부를 수 없으면 양식을 열지 않고 먼저 말합니다.
    //  현장 정보(fieldReport)는 서버가 필요 없으므로 막지 않습니다.
    //  커뮤니티 글은 기기 안에서 관리됩니다.
    // ═══════════════════════════════════════════════════════════════
    private func presentComposer(_ purpose: CommunityComposerPurpose, spot: PhotoSpot? = nil) {
        if purpose == .addSpot, !AppBackendConfiguration.current.isConfigured {
            appErrorMessage = "장소 등록은 아직 준비 중이에요. 조금만 기다려주세요."
            return
        }

        setHomeTabBarHidden(false)
        composerPurpose = purpose
        communityViewModel.beginComposing(spot: spot)
    }

    private func performAfterHomeSearchDismissal(_ action: @escaping () -> Void) {
        guard pendingHomeSearchAction == nil else { return }
        shouldRestoreHomeSearch = true
        pendingHomeSearchAction = action
        isHomeSearchPresented = false
    }

    private func finishHomeSearchDismissal() {
        let action = pendingHomeSearchAction
        pendingHomeSearchAction = nil
        action?()
    }

    private func restoreHomeSearchIfPossible() {
        guard shouldRestoreHomeSearch,
              pendingHomeSearchAction == nil,
              pendingDetailDismissAction == nil,
              pendingAuthenticatedAction == nil,
              appErrorMessage == nil,
              !isRootModalPresented else { return }
        shouldRestoreHomeSearch = false
        guard selectedTab == .home else { return }
        isHomeSearchPresented = true
    }

    /// 장소 제보가 실패했을 때 사용자에게 할 말.
    ///
    /// 전에는 error.localizedDescription 을 그대로 띄웠습니다.
    /// PhotoSpotSearchError 가 문자열을 들고 있었고 그 문자열이 서버
    /// 응답이었기 때문에, 서버가 보낸 영문 메시지가 그대로 보일 수
    /// 있었습니다. 이제 그 타입은 문자열을 들고 있지 않지만, 남은 문제가
    /// 하나 있습니다. 그 타입은 자기가 검색에서 났는지 제보에서 났는지
    /// 모르므로 문구에 기능 이름을 넣을 수 없습니다.
    /// 그래서 기능 이름은 이 자리에서 붙입니다.
    private func submissionFailureMessage(for error: Error) -> String {
        if let submissionError = error as? PlaceSubmissionError {
            return submissionError.localizedDescription
        }

        guard let searchError = error as? PhotoSpotSearchError else {
            return "장소를 등록하지 못했어요. 잠시 후 다시 시도해주세요."
        }

        switch searchError {
        case .notConfigured:
            // 다시 시도를 권하지 않습니다. 주소가 없는 상태는 반복해도 같습니다.
            return "장소 등록은 아직 준비 중이에요. 조금만 기다려주세요."
        case .server, .malformedResponse, .empty:
            return "장소를 등록하지 못했어요. 잠시 후 다시 시도해주세요."
        }
    }

    private func requestAuthentication(
        afterLogin action: ((AuthUser) -> Void)? = nil,
        loginPresentationContext: LoginPresentationContext = .general
    ) {
        if let authenticatedUser = authViewModel.currentUser {
            action?(authenticatedUser)
            return
        }

        pendingAuthenticatedAction = action
        self.loginPresentationContext = loginPresentationContext
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
        loginPresentationContext: LoginPresentationContext = .general,
        action: @escaping (AuthUser) -> Void
    ) -> Bool {
        guard let authenticatedUser = authViewModel.currentUser else {
            requestAuthentication(
                afterLogin: resumeAfterLogin ? action : nil,
                loginPresentationContext: loginPresentationContext
            )
            return false
        }

        action(authenticatedUser)
        return true
    }

    private func resumePendingAuthenticatedActionIfPossible() {
        guard authViewModel.currentUser != nil else {
            pendingAuthenticatedAction = nil
            restoreHomeSearchIfPossible()
            return
        }

        let action = pendingAuthenticatedAction
        pendingAuthenticatedAction = nil
        DispatchQueue.main.async {
            guard let latestAuthenticatedUser = authViewModel.currentUser else { return }
            action?(latestAuthenticatedUser)
            restoreHomeSearchIfPossible()
        }
    }

    private func updateTabBarVisibility(_ shouldHide: Bool, source: AppTab) {
        guard source == .home, selectedTab == .home else {
            return
        }
        setHomeTabBarHidden(homePresentationState == .initialLoading ? false : shouldHide)
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
        }
    }

    private func toggleSavedMapFilter() {
        withAnimation(.easeInOut(duration: 0.16)) {
            let shouldEnableSavedPins = !mapState.isSavedFilterEnabled
            mapState.setSavedFilterEnabled(shouldEnableSavedPins)

            if !shouldEnableSavedPins, mapState.mode == .saved {
                mapState.activateRecommendations(resetCategory: false)
            }

            selectedSpotRevision = 0
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

            if mapState.isSavedFilterEnabled {
                mapState.finishRecommendations()
                selectedSpotRevision = 0
                return
            }

            if mapState.mode != .recommendations {
                mapState.activateRecommendations(resetCategory: false)
            }

            // 테마 변경은 이미 메모리에 있는 전국 seed 후보를 로컬 필터링합니다.
            // 위치 권한 확인이나 반경 추천 요청을 다시 시작하지 않습니다.
            mapState.finishRecommendations()
            selectedSpotRevision = 0
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

    private func resolvedSpotWithContributedCover(_ spot: PhotoSpot) -> PhotoSpot {
        guard let coverPhoto = contributedCoverPhotos[spot.id] else { return spot }
        return spot.replacingDisplayImage(with: coverPhoto)
    }

    private func submittedSpot(from draft: CommunityPostDraft) -> PhotoSpot? {
        guard let spot = draft.spot else { return nil }
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
            isHiddenSpot: spot.isHiddenSpot,
            provider: spot.provider,
            providerPlaceID: spot.providerPlaceID,
            galleryPhotos: spot.galleryPhotos
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
                let photoDatas = draft.photoAttachments.compactMap(\.imageData)
                let submission = try await placeSubmissionService.submit(
                    spot: spot,
                    tags: draft.tags,
                    photoData: draft.photoData,
                    submitter: submitter,
                    registeredSpots: selectableSpots,
                    photoDatas: photoDatas
                )
                await MainActor.run {
                    placeSubmissionStore.record(submission.receipt)
                    mergeAISpots(from: [submission.publishedSpot])
                    mergeRegisteredHomeSpots(from: [submission.publishedSpot])
                    submissionConfirmation = submission.receipt
                }
                let refreshedSpots: [PhotoSpot]
                do {
                    refreshedSpots = try await placeSubmissionService.fetchSubmittedSpots()
                } catch {
                    refreshedSpots = []
                    AppLog.network.error(
                        "Published submitted spot refresh failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                await MainActor.run {
                    mergeAISpots(from: refreshedSpots)
                    mergeRegisteredHomeSpots(from: refreshedSpots)
                }
            } catch {
                // 원인은 로그로, 사용자에게는 사용자 문구로.
                let diagnostic = (error as? PhotoSpotSearchError)?.diagnosticDescription
                    ?? error.localizedDescription
                AppLog.network.error(
                    "Place submission failed: \(diagnostic, privacy: .public)"
                )
                await MainActor.run {
                    appErrorMessage = submissionFailureMessage(for: error)
                }
            }
        }
    }

    private func submitPlacePhotoContribution(
        spot: PhotoSpot,
        draft: CommunityPostDraft,
        submitter: AuthUser
    ) {
        Task {
            do {
                let photos = try await placePhotoGalleryStore.contributePhotos(
                    for: spot,
                    attachments: draft.photoAttachments,
                    uploader: submitter
                )
                guard !photos.isEmpty else {
                    throw FirebaseCommunityError.emptyResponse
                }

                await MainActor.run {
                    if let firstPhoto = photos.first,
                       !spot.hasReliableDisplayImage {
                        contributedCoverPhotos[spot.id] = firstPhoto
                    }
                    photoContributionConfirmationSpot = spot
                }
            } catch {
                AppLog.persistence.error(
                    "Place photo contribution failed: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    appErrorMessage = "사진을 등록하지 못했어요. 잠시 후 다시 시도해주세요."
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
            mergeRegisteredHomeSpots(from: submittedSpots)
            submittedSpotsState = .loaded
        } catch {
            // 사용자 추가 장소를 가져오는 것은 배경 작업입니다.
            // 실패해도 앱은 시드 131곳으로 정상 동작하므로, 사용자에게
            // 서버 사정을 알릴 이유가 없습니다. 원인은 로그로만 갑니다.
            let diagnostic = (error as? PhotoSpotSearchError)?.diagnosticDescription
                ?? error.localizedDescription
            AppLog.network.error(
                "Submitted spots fetch failed: \(diagnostic, privacy: .public)"
            )
            submittedSpotsState = .failed(message: "등록된 장소를 불러오지 못했어요")
        }
    }

    private func mergeAISpots(from spots: [PhotoSpot]) {
        for spot in spots {
            addAISpot(spot)
        }
    }

    private func mergeRegisteredHomeSpots(from spots: [PhotoSpot]) {
        var merged = Dictionary(registeredHomeSpots.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for spot in spots { merged[spot.id] = spot }
        registeredHomeSpots = merged.values.sorted { $0.id < $1.id }
        homeRecommendations.updateAvailableSpots(
            uniqueSpots(localSeedDataService.allPhotoSpots() + registeredHomeSpots)
        )
    }

    private func refreshHomeWeatherIfNeeded(at coordinate: CLLocationCoordinate2D) {
        if let previous = homeWeatherCoordinate {
            let distance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            let weatherIsFresh = weatherStore.snapshot.map {
                Date().timeIntervalSince($0.fetchedAt) < 30 * 60
            } ?? false
            guard distance >= 15_000 || (!weatherIsFresh && weatherStore.state != .loading) else { return }
        }
        homeWeatherCoordinate = coordinate
        homeWeatherTask?.cancel()
        homeWeatherTask = Task {
            await weatherStore.load(for: coordinate)
            guard !Task.isCancelled else { return }
            await weatherStore.updateLocationTitle(for: coordinate)
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
            placePhotos: placePhotoGalleryStore.photos(for: presentation.spot),
            placePhotoGalleryStore: placePhotoGalleryStore,
            crowdReports: crowdReportStore.reports(for: presentation.spot),
            crowdReportStore: crowdReportStore,
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
                performAuthenticatedAction(loginPresentationContext: .contributePhotos) { _ in
                    pendingDetailDismissAction = {
                        presentComposer(
                            .contributePhotos(placeID: presentation.spot.id),
                            spot: presentation.spot
                        )
                    }
                    detailPresentation = nil
                }
            },
            onSubmitCrowdReport: { crowd in
                guard let user = authViewModel.currentUser else { return }
                crowdReportStore.toggle(
                    placeID: presentation.spot.id,
                    crowd: crowd,
                    authorID: user.id,
                    source: .placeDetail
                )
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
            },
            communityViewModel: communityViewModel,
            onToggleCommunityLike: { post in
                performAuthenticatedAction { _ in
                    communityViewModel.toggleLike(post)
                }
            },
            onToggleCommunityFollow: { post in
                performAuthenticatedAction { _ in
                    communityViewModel.toggleFollow(post)
                }
            },
            onAddCommunityComment: { message, post in
                performAuthenticatedAction(resumeAfterLogin: false) { user in
                    communityViewModel.addComment(message, to: post, author: user)
                }
            }
        )
    }

    private func showDetail(_ spot: PhotoSpot, source: SpotDetailSource) {
        // 마커를 빠르게 연속 탭해도 이미 표시 중인 상세 시트를 중복으로
        // 교체하거나 다시 띄우지 않습니다.
        guard detailPresentation == nil else { return }
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

    /// 지도의 내 위치 버튼.
    /// 추천 모드로 되돌리지 않습니다. 저장 목록을 보다가 눌러도
    /// 목록이 초기화되지 않고 카메라만 움직여야 합니다.
    private func focusUserLocationOnMap() {
        locationReader.requestLocation()
        mapState.userLocationFocusRevision += 1
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

    private func uniqueSpots(_ spots: [PhotoSpot]) -> [PhotoSpot] {
        var result: [PhotoSpot] = []
        var indexByID: [String: Int] = [:]
        var indexByMapQuery: [String: Int] = [:]

        for spot in spots {
            let existingIndex = [indexByID[spot.id], indexByMapQuery[spot.mapQuery]]
                .compactMap { $0 }
                .min()

            if let existingIndex {
                let existing = result[existingIndex]
                let replacement = existing.replacingDisplayImage(from: spot)

                if indexByID[existing.id] == existingIndex {
                    indexByID[existing.id] = nil
                }
                if indexByMapQuery[existing.mapQuery] == existingIndex {
                    indexByMapQuery[existing.mapQuery] = nil
                }

                result[existingIndex] = replacement
                indexByID[replacement.id] = existingIndex
                indexByMapQuery[replacement.mapQuery] = existingIndex
                continue
            }

            let index = result.count
            result.append(spot)
            indexByID[spot.id] = index
            indexByMapQuery[spot.mapQuery] = index
        }

        return result
    }

}

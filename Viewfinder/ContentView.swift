import CoreLocation
import Foundation
import OSLog
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TastePreferenceStore.completionKey) private var hasCompletedTasteOnboarding = false
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

        /// 선택된 탭에 쓰는 채운 아이콘입니다.
        ///
        /// 선택 색이 주황에서 흰색으로 바뀌면서, 색 차이만으로는 선택이
        /// 약해졌습니다. 선 아이콘 → 면 아이콘으로 형태도 함께 바꿔 구분합니다.
        /// + 탭은 누르면 바로 제보 화면으로 가서 선택 상태가 없으므로 그대로 둡니다.
        var selectedAssetName: String {
            switch self {
            case .add:
                return assetName
            case .home, .map, .community, .my:
                return assetName + "_selected"
            }
        }
    }

    @State private var selectedTab: AppTab = .home
    @State private var lastContentTab: AppTab = .home
    @State private var selectedSpot = PhotoSpotSampleData.spots[0]
    @State private var selectedSpotRevision = 0
    @State private var aiSpots: [PhotoSpot] = []
    @State private var homeWeatherCoordinate: CLLocationCoordinate2D?
    @State private var homeWeatherTask: Task<Void, Never>?
    @State private var homeWeatherTaskID: UUID?
    @State private var homeWeatherTaskContextKey: WeatherContextKey?
    @State private var homeWeatherTraceStartedAt: TimeInterval?
    @State private var homeWeatherTraceLocationLogged = false
    @State private var homeWeatherTraceContextLogged = false
    @State private var detailPresentation: SpotDetailPresentation?
    @State private var isWeatherDetailPresented = false
    @State private var isTasteResetPresented = false
    @State private var composerPurpose: CommunityComposerPurpose = .fieldReport
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
    @StateObject private var homeRecommendations: HomeRecommendationsViewModel
    @StateObject private var placesRepository: PlacesRepository
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

    init() {
        let placesRepository = PlacesRepository()
        _placesRepository = StateObject(wrappedValue: placesRepository)
        _homeRecommendations = StateObject(
            wrappedValue: HomeRecommendationsViewModel(initialSpots: placesRepository.places)
        )
    }

    private var homePresentationState: HomeRecommendationState {
        if homeRecommendations.recommendationState == .empty {
            switch placesRepository.state {
            case .initialLoading:
                return .initialLoading
            case .failed(let message):
                return .failed(message: message)
            case .cached, .loaded, .refreshing, .fallbackSeed:
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
        uniqueSpots(placesRepository.places + recommendedSpots + aiSpots)
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
            || isTasteResetPresented
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
        Group {
            if hasCompletedTasteOnboarding {
                launchedAppContent
            } else {
                TasteOnboardingView(
                    onComplete: completeTasteOnboarding,
                    onSkip: skipTasteOnboarding
                )
            }
        }
    }

    private var launchedAppContent: some View {
        mainContent
        .task {
            await placesRepository.loadIfNeeded()
        }
        .task {
            beginHomeWeatherTrace(trigger: "initial")
            // Restore only after a trustworthy regional context is available.
            // Never infer today's country from the recommendation cache itself.
            if let recentCoordinate = locationReader.recentCoordinateForRecommendation() {
                logHomeWeatherMilestone("location available", detail: "source=cached")
                homeRecommendations.updateLocationContext(userLocation: recentCoordinate)
                logHomeWeatherContextReady(source: "cached location")
                // `onReceive($coordinate)` does not replay a value that was
                // published before this view subscribed. Start the weather
                // request explicitly for the cached coordinate as well.
                refreshHomeWeatherIfNeeded(at: recentCoordinate)
            } else {
                logHomeWeather("waiting for location")
            }
            logHomeWeather("fresh location request started")
            let coordinate = await locationReader.coordinateForRecommendation(forceRefresh: true)
            homeRecommendations.updateLocationContext(userLocation: coordinate)
            if let coordinate {
                logHomeWeatherMilestone("location available", detail: "source=fresh location")
                logHomeWeatherContextReady(source: "fresh location")
                refreshHomeWeatherIfNeeded(at: coordinate)
            } else {
                logHomeWeather("location unavailable")
            }
            homeRecommendations.prepareIfNeeded()
            logHomeWeatherMilestone("recommendation generation prepared")
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
        .sheet(isPresented: $isTasteResetPresented) {
            TasteOnboardingView(
                initialSelection: TastePreferenceStore.load()?.selectedPhotoIDs ?? [],
                onComplete: completeTasteOnboarding,
                onSkip: skipTasteOnboarding
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func completeTasteOnboarding(_ preference: TastePreference) -> Bool {
        guard TastePreferenceStore.save(preference) else { return false }
        homeRecommendations.updateTastePreference(preference)
        hasCompletedTasteOnboarding = true
        isTasteResetPresented = false
        return true
    }

    private func skipTasteOnboarding() {
        TastePreferenceStore.skip()
        homeRecommendations.updateTastePreference(nil)
        hasCompletedTasteOnboarding = true
        isTasteResetPresented = false
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

        .sheet(isPresented: $communityViewModel.isComposerPresented, onDismiss: {
            communityViewModel.finishComposing()
            restoreHomeSearchIfPossible()
        }) {
            // 한 줄 글(장소 상세에서 혼잡도와 함께 올린 글)은 쓸 때처럼 혼잡도 · 한 줄만 고쳐요.
            // 커뮤니티 탭 · 마이 → 내 글 · 피드 카드의 수정이 모두 여기로 와요.
            if composerPurpose == .fieldReport,
               let post = communityViewModel.editingPostForComposer,
               post.isQuickCrowdNote {
                CommunityQuickNoteEditor(
                    post: post,
                    spot: placesRepository.places.first(where: { $0.id == post.relatedSpotID })
                ) { draft in
                    guard authViewModel.currentUser != nil else {
                        requestAuthentication()
                        throw FirebaseCommunityError.notConfigured
                    }
                    try await communityViewModel.updatePost(post, draft: draft)
                }
            } else {
                CommunityComposerView(
                    spots: composerPurpose == .fieldReport ? placesRepository.places : selectableSpots,
                    selectedSpot: communityViewModel.composerSpot(in: composerPurpose == .fieldReport ? placesRepository.places : selectableSpots),
                    locksSelectedSpot: (composerPurpose == .addSpot || composerPurpose.isPhotoContribution)
                        && communityViewModel.composerSpot(in: selectableSpots) != nil,
                    editingPost: communityViewModel.editingPostForComposer,
                    purpose: composerPurpose,
                    onShowRegisteredSpot: { spot in
                        showDetail(spot, source: .search)
                    },
                    onSubmit: { draft, submissionID in
                        guard let authenticatedUser = authViewModel.currentUser else {
                            requestAuthentication()
                            throw FirebaseCommunityError.notConfigured
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
                            guard let spot = submittedSpot(from: draft) else {
                                throw PlacesRepositoryError.invalidDocument
                            }
                            let savedSpot = try await placesRepository.createUserPlace(
                                spot,
                                createdBy: authenticatedUser.id
                            )
                            let receipt = PlaceSubmissionReceipt(
                                id: savedSpot.id,
                                name: savedSpot.name,
                                submittedAt: ISO8601DateFormatter().string(from: Date()),
                                alreadyApproved: false,
                                region: savedSpot.region,
                                mapQuery: savedSpot.mapQuery,
                                latitude: savedSpot.latitude,
                                longitude: savedSpot.longitude,
                                provider: savedSpot.provider,
                                providerPlaceID: savedSpot.providerPlaceID
                            )
                            placeSubmissionStore.record(receipt)
                            submissionConfirmation = receipt
                            communityViewModel.finishComposing()
                        } else if let post = communityViewModel.editingPostForComposer {
                            try await communityViewModel.updatePost(post, draft: draft)
                        } else {
                            try await communityViewModel.addPost(draft, author: authenticatedUser, id: submissionID)
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
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

            logHomeWeatherMilestone("location available", detail: "source=location update")
            homeRecommendations.updateLocationContext(userLocation: newCoordinate)
            logHomeWeatherContextReady(source: "location update")
            refreshHomeWeatherIfNeeded(at: newCoordinate)

            if mapState.mode == .recommendations {
                mapState.finishRecommendations()
            }
        }
        .onReceive(locationReader.$state) { state in
            if case .failed = state, locationReader.coordinate == nil {
                homeRecommendations.updateLocationContext(userLocation: nil)
                homeWeatherTask?.cancel()
                logHomeWeather("request cancel requested reason=location context invalidated")
                homeWeatherTask = nil
                homeWeatherTaskID = nil
                homeWeatherTaskContextKey = nil
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
        .onReceive(searchViewModel.$registeredSpots) { registeredSpots in
            mergeAISpots(from: registeredSpots)
        }
        .onChange(of: placesRepository.places) { _, places in
            homeRecommendations.updateAvailableSpots(
                uniqueSpots(places)
            )
        }
        .onReceive(communityViewModel.$posts) { posts in
            homeRecommendations.updateCommunityContext(posts: posts)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await placesRepository.refreshIfStale() }
                if selectedTab == .home {
                    beginHomeWeatherTrace(trigger: "foreground")
                }
                homeRecommendations.refreshTimeContextIfNeeded()
                locationReader.requestLocation()
                if let coordinate = locationReader.coordinate {
                    logHomeWeatherMilestone("location available", detail: "source=foreground")
                    homeRecommendations.updateLocationContext(userLocation: coordinate)
                    logHomeWeatherContextReady(source: "foreground location")
                    refreshHomeWeatherIfNeeded(at: coordinate)
                }
            } else {
                // 같은 위치 요청은 백그라운드 전환만으로 취소하지 않습니다.
                // Foreground에서 같은 context가 들어오면 기존 요청을 재사용합니다.
                logHomeWeather("weather request retained reason=scene inactive")
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            setHomeTabBarHidden(false)

            if newTab != .add {
                lastContentTab = newTab
            }

            if newTab == .home {
                beginHomeWeatherTrace(trigger: "home tab")
                locationReader.requestLocation()
                if let coordinate = locationReader.coordinate {
                    logHomeWeatherMilestone("location available", detail: "source=tab return")
                    homeRecommendations.updateLocationContext(userLocation: coordinate)
                    logHomeWeatherContextReady(source: "tab return")
                    refreshHomeWeatherIfNeeded(at: coordinate)
                } else {
                    logHomeWeather("waiting for location")
                }
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
                    if case .failed = placesRepository.state {
                        await placesRepository.refreshIfStale(minimumInterval: 0)
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
            // 탭바는 흰색 tint 를 받지만, 탭 화면 안의 버튼·토글은 브랜드 주황을 유지합니다.
            .tint(AppColors.accent)
            .tag(AppTab.home)
            .tabItem {
                tabItemLabel(for: .home)
            }
            .vfOpaqueTabBar()

            mapLayer
                .tint(AppColors.accent)
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
                spots: placesRepository.places,
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
                    try await communityViewModel.deletePost(post, currentUserID: authViewModel.currentUser?.id)
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
            .tint(AppColors.accent)
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
                spots: placesRepository.places,
                likedPostIDs: communityViewModel.likedPostIDs,
                followedAuthorIDs: communityViewModel.followedAuthorIDs,
                commentsByPostID: communityViewModel.commentsByPostID,
                communityViewModel: communityViewModel,
                onTabBarVisibilityChange: { shouldHide in
                    updateTabBarVisibility(shouldHide, source: .my)
                },
                onSelectSpot: { showDetail($0, source: .saved) },
                // 마이 → 저장한 출사지(첫 화면 사진 칸 · 모두 보기 격자)에서 길게 눌러 저장을 해제합니다.
                onToggleSave: { savedSpotStore.toggle($0) },
                onEditPost: { post in
                    performAuthenticatedAction { _ in
                        composerPurpose = .fieldReport
                        communityViewModel.beginEditing(post)
                    }
                },
                onDeletePost: { post in
                    try await communityViewModel.deletePost(post, currentUserID: authViewModel.currentUser?.id)
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
                // 마이 → 저장한 출사지 → "지도에서 보기"
                onShowSavedOnMap: showSavedSpotsOnMap,
                // 마이 → 추가한 장소 → 줄 끝 "…" (수정 · 삭제)
                onEditPlace: { showPlaceEditor($0) },
                onDeletePlace: { try await deleteUserPlace($0) },
                // 만든 사람이 확인되지 않는 장소(Firestore 로 옮기기 전에 추가한 곳 등)는 이 기기의 목록에서만 뺍니다.
                onRemovePlaceFromList: { placeSubmissionStore.remove(id: $0) },
                // 마이 → 빈 추가한 장소 · 내 글 화면에서 바로 작성으로 갑니다.
                // 탭바 + 버튼, 커뮤니티 글쓰기 버튼과 같은 경로입니다.
                onAddPlace: {
                    performAuthenticatedAction(loginPresentationContext: .addSpot) { _ in
                        presentComposer(.addSpot)
                    }
                },
                onCompose: {
                    performAuthenticatedAction(loginPresentationContext: .communityPost) { _ in
                        presentComposer(.fieldReport)
                    }
                },
                onResetTaste: {
                    isTasteResetPresented = true
                },
                onSignOut: {
                    authViewModel.signOut()
                }
            )
            .tint(AppColors.accent)
            .tag(AppTab.my)
            .tabItem {
                tabItemLabel(for: .my)
            }
            .vfOpaqueTabBar()
        }
        // 탭바 선택 색은 흰색(라이트 모드에서는 #111)입니다. (개선안 38)
        //
        // 가운데 + 아이콘이 늘 주황이라, 선택된 탭까지 주황이면 탭바에
        // 주황이 두 개가 되어 둘 다 선택된 것처럼 보였습니다.
        // 주황은 + (제보) 에만 남기고, 선택은 흰색 + 채운 아이콘으로 구분합니다.
        // AppDelegate 의 UITabBarAppearance 와 같은 값이며, appearance 를
        // 따르지 않는 OS 에서도 같은 색이 되도록 SwiftUI tint 로도 겁니다.
        .tint(AppColors.primary)
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
        // iOS 26 에서는 위 배경 강제를 적용하지 않고 시스템 유리 탭바를 씁니다. (개선안 38)
        .vfOpaqueTabBar()
        // iOS 26 시스템 탭바 줄이기를 끕니다. 스크롤할 때 숨기고 보이는 것은 아래
        // 컨트롤러가 합니다. 경위는 NativeTabBarSupport 의 VFTabBarScrollObserver 주석에 있습니다.
        .vfTabBarHidesOnScroll()
        .background {
            // 탭바를 찾아 숨김 · 보임 컨트롤러에 연결합니다. 모든 iOS 버전에서 붙입니다.
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
                    Image(selectedTab == tab ? tab.selectedAssetName : tab.assetName)
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

    private func presentComposer(_ purpose: CommunityComposerPurpose, spot: PhotoSpot? = nil) {
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
        guard shouldHide else {
            // 보이게 할 때는 스크롤 관찰자를 거칩니다. 관찰자가 기억하는 "숨김" 과
            // 실제 탭바가 어긋나면, 다음에 스크롤을 내려도 탭바가 숨지 않습니다.
            // (탭을 바꿀 때 · 작성 화면을 열 때 · 홈이 나타날 때 여기로 옵니다)
            VFTabBarScrollObserver.shared.reveal()
            return
        }
        NativeTabBarVisibilityController.shared.setHidden(true, animated: true)
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

    /// 마이 → "지도에서 보기". 지도 탭을 저장한 장소만 보이는 모드로 열고, 첫 장소로 옮긴 뒤
    /// 지도 탭의 저장 목록("내 보관함")을 올립니다.
    private func showSavedSpotsOnMap() {
        // 지도 위 테마 칩이 걸려 있으면 저장한 곳 일부가 숨으므로 모두 보이게 합니다.
        mapState.categoryFilter = .all
        mapState.savedListFilter = .all
        mapState.showSavedSpots()
        // 지도 탭으로 바꿀 때 추천 모드로 돌아가지 않게 합니다. (onChange(of: selectedTab) 참고)
        // openMap(_:) 이 장소 하나를 보여줄 때와 같은 방식입니다.
        mapState.shouldFocusUserOnSelection = false

        if let firstSpot = savedMapListSpots.first {
            selectedSpot = firstSpot
            selectedSpotRevision += 1
        }

        selectedTab = .map

        // 지도 탭이 화면에 올라온 뒤 목록 시트를 올립니다.
        // 탭이 바뀌는 중에 시트를 띄우면 뜨지 않을 수 있습니다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard selectedTab == .map, mapState.mode == .saved else { return }
            mapState.isSavedListPresented = true
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

    private func mergeAISpots(from spots: [PhotoSpot]) {
        for spot in spots {
            addAISpot(spot)
        }
    }

    private func refreshHomeWeatherIfNeeded(at coordinate: CLLocationCoordinate2D) {
        let requestedContextKey = WeatherContextKey(coordinate)

        if homeWeatherTaskID != nil,
           homeWeatherTaskContextKey == requestedContextKey {
            logHomeWeather("request coalesced context=\(requestedContextKey.logDescription) source=home task")
            return
        }

        if weatherStore.hasInFlightRequest(for: coordinate) {
            logHomeWeather("request coalesced context=\(requestedContextKey.logDescription) source=weather store")
            return
        }

        let hasDifferentHomeTask = homeWeatherTaskID != nil
            && homeWeatherTaskContextKey != requestedContextKey
        let hasDifferentStoreRequest = weatherStore.inFlightRequestContextKey.map {
            $0 != requestedContextKey
        } ?? false
        let hasDifferentInFlightContext = hasDifferentHomeTask || hasDifferentStoreRequest

        if let previous = homeWeatherCoordinate {
            let distance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            let weatherIsFresh = weatherStore.snapshot.map {
                Date().timeIntervalSince($0.fetchedAt) < 30 * 60
            } ?? false
            guard hasDifferentInFlightContext
                    || distance >= 15_000
                    || (!weatherIsFresh && weatherStore.state != .loading) else {
                logHomeWeatherMilestone(
                    "cache lookup finished",
                    detail: weatherIsFresh ? "result=fresh snapshot" : "result=request already loading"
                )
                logHomeWeather("weather request skipped distance=\(Int(distance))m fresh=\(weatherIsFresh) state=\(String(describing: weatherStore.state))")
                return
            }
        }

        if hasDifferentInFlightContext {
            let previousKey = homeWeatherTaskContextKey
                ?? weatherStore.inFlightRequestContextKey
            let requestID = weatherStore.inFlightRequestID.map(String.init) ?? "pending"
            logHomeWeather(
                "context changed \(previousKey?.logDescription ?? "unknown") -> \(requestedContextKey.logDescription)"
            )
            if homeWeatherTaskID != nil {
                logHomeWeather("request cancelled id=\(requestID) reason=context changed")
                homeWeatherTask?.cancel()
            }
        }

        homeWeatherCoordinate = coordinate
        let traceStartedAt = homeWeatherTraceStartedAt
        let taskID = UUID()
        homeWeatherTaskID = taskID
        homeWeatherTaskContextKey = requestedContextKey
        homeWeatherTask = Task { @MainActor in
            defer { finishHomeWeatherTask(id: taskID) }
            guard !Task.isCancelled else {
                logHomeWeather("request cancelled before task began reason=context changed")
                return
            }
            await weatherStore.load(for: coordinate, diagnosticStartedAt: traceStartedAt)
            guard !Task.isCancelled else { return }
            await weatherStore.updateLocationTitle(for: coordinate)
        }
    }

    private func finishHomeWeatherTask(id: UUID) {
        guard homeWeatherTaskID == id else { return }
        homeWeatherTask = nil
        homeWeatherTaskID = nil
        homeWeatherTaskContextKey = nil
    }

    private func beginHomeWeatherTrace(trigger: String) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        homeWeatherTraceStartedAt = startedAt
        homeWeatherTraceLocationLogged = false
        homeWeatherTraceContextLogged = false
        logHomeWeather("Home appeared", detail: "trigger=\(trigger)")
    }

    private func logHomeWeatherMilestone(_ name: String, detail: String? = nil) {
        if name == "location available" {
            guard !homeWeatherTraceLocationLogged else { return }
            homeWeatherTraceLocationLogged = true
        }
        logHomeWeather(name, detail: detail)
    }

    private func logHomeWeatherContextReady(source: String) {
        guard !homeWeatherTraceContextLogged else { return }
        homeWeatherTraceContextLogged = true
        logHomeWeatherMilestone("recommendation context ready", detail: "source=\(source)")
    }

    private func logHomeWeather(_ event: String, detail: String? = nil) {
#if DEBUG
        guard let startedAt = homeWeatherTraceStartedAt else { return }
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        let suffix = detail.map { " \($0)" } ?? ""
        AppLog.network.debug(
            "[HomeWeather] \(event) +\(String(format: "%.2f", elapsed))s\(suffix, privacy: .public)"
        )
#endif
    }

    /// 상세 화면 본문. 표시 방식과 분리해 둡니다.
    private func detailView(for presentation: SpotDetailPresentation) -> some View {
        let spot = placesRepository.place(id: presentation.spot.id) ?? presentation.spot
        return SpotDetailView(
            authViewModel: authViewModel,
            spot: spot,
            source: presentation.source,
            opensPlaceEditorOnAppear: presentation.opensPlaceEditor,
            isSaved: savedSpotStore.contains(spot),
            communityPosts: communityViewModel.posts(for: spot),
            placePhotos: placePhotoGalleryStore.photos(for: spot),
            placePhotoGalleryStore: placePhotoGalleryStore,
            crowdReports: crowdReportStore.reports(for: spot),
            crowdReportStore: crowdReportStore,
            currentUserID: authViewModel.currentUser?.id ?? "",
            spots: selectableSpots,
            userLocation: locationReader.coordinate,
            onToggleSave: {
                savedSpotStore.toggle(spot)
            },
            onOpenMap: {
                detailPresentation = nil
                openMap(spot)
            },
            onReportPhoto: {
                performAuthenticatedAction(loginPresentationContext: .contributePhotos) { _ in
                    pendingDetailDismissAction = {
                        presentComposer(
                            .contributePhotos(placeID: spot.id),
                            spot: spot
                        )
                    }
                    detailPresentation = nil
                }
            },
            onSubmitCrowdReport: { crowd in
                guard let user = authViewModel.currentUser else { return .ignored }
                return crowdReportStore.toggle(
                    placeID: spot.id,
                    crowd: crowd,
                    authorID: user.id,
                    source: .placeDetail
                )
            },
            onSubmitCommunity: { draft, submissionID in
                guard let user = authViewModel.currentUser else { throw FirebaseCommunityError.notConfigured }
                try await communityViewModel.addPost(draft, author: user, id: submissionID)
            },
            onUpdateCommunity: { post, draft in
                guard authViewModel.currentUser != nil else { throw FirebaseCommunityError.notConfigured }
                try await communityViewModel.updatePost(post, draft: draft)
            },
            onDeleteCommunity: { post in
                try await communityViewModel.deletePost(post, currentUserID: authViewModel.currentUser?.id)
            },
            onUpdatePlace: { updatedSpot in
                guard let user = authViewModel.currentUser else {
                    throw PlacesRepositoryError.notAuthenticated
                }
                _ = try await placesRepository.updateUserPlace(updatedSpot, updatedBy: user.id)
            },
            onDeletePlace: {
                try await deleteUserPlace(spot)
                detailPresentation = nil
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

    /// 마이 → 추가한 장소 → "…" → 수정.
    /// 장소 상세를 열고, 상세가 다 올라오면 상세의 장소 편집기를 엽니다.
    /// 편집기를 따로 만들지 않고 상세의 것을 그대로 써서, 저장 · 오류 처리가 한 곳에만 있습니다.
    private func showPlaceEditor(_ spot: PhotoSpot) {
        guard detailPresentation == nil else { return }
        detailPresentation = SpotDetailPresentation(spot: spot, source: .saved, opensPlaceEditor: true)
    }

    /// 내가 추가한 장소를 지웁니다. (공개 목록에서 숨김)
    /// 장소 상세의 "장소 삭제" 와 마이 → 추가한 장소 → "…" → 삭제 가 함께 씁니다.
    private func deleteUserPlace(_ spot: PhotoSpot) async throws {
        guard let user = authViewModel.currentUser else {
            throw PlacesRepositoryError.notAuthenticated
        }
        guard spot.isOwned(by: user.id) else {
            throw PlacesRepositoryError.notOwner
        }
        try await placesRepository.softDeleteUserPlace(id: spot.id, deletedBy: user.id)
        placeSubmissionStore.remove(id: spot.id)
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

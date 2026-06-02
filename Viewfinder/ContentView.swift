import CoreLocation
import Foundation
import SwiftUI

private struct MapRecommendationResult {
    let spots: [PhotoSpot]
    let radius: CLLocationDistance?
    let candidateCount: Int
    let fallbackUsed: Bool
}

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
                return "추가"
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
    @State private var selectedSpot = LocalSeedDataService().allPhotoSpots().first { $0.imageURL != nil } ?? PhotoSpotSampleData.spots[0]
    @State private var selectedSpotRevision = 0
    @State private var aiSpots: [PhotoSpot] = []
    @State private var detailPresentation: SpotDetailPresentation?
    @State private var isWeatherDetailPresented = false
    @State private var composerPurpose: CommunityComposerPurpose = .fieldReport
    @State private var isHomeTabBarHidden = false
    @State private var shouldShowNearbyMapPins = false
    @State private var isMapRecommendationLoading = false
    @State private var explicitMapSpot: PhotoSpot?
    @State private var shouldFocusUserOnMapSelection = true
    @State private var isMapSavedFilterEnabled = false
    @State private var isSavedMapListPresented = false
    @State private var savedMapListFilter: SavedMapListFilter = .all
    @State private var mapCategoryFilter: MapCategoryFilter = .all
    @State private var userLocationFocusRevision = 0
    @State private var currentLocationTitle = "현재 위치 기반"
    @State private var weatherSnapshot: WeatherSnapshot?
    @State private var weatherLoadFailed = false
    @State private var weatherCoordinateKey: String?
    @State private var weatherLastFetchDate: Date?
    @StateObject private var homeRecommendations = HomeRecommendationsViewModel()
    @StateObject private var locationReader = RecommendationLocationReader()
    @StateObject private var searchViewModel = PhotoSpotSearchViewModel()
    @StateObject private var savedSpotStore = SavedSpotStore()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var communityViewModel = CommunityViewModel()
    private let localSeedDataService = LocalSeedDataService()

    private var recommendedSpots: [PhotoSpot] {
        uniqueSpots(homeRecommendations.visibleSpots + aiSpots)
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
    }

    private var mapPinSpots: [PhotoSpot] {
        if isMapSavedFilterEnabled {
            return savedMapListSpots
        }

        guard shouldShowNearbyMapPins, !isMapRecommendationLoading else {
            if let explicitMapSpot,
               !RecommendationBlacklist.isBlacklistedRecommendation(explicitMapSpot) {
                return [explicitMapSpot]
            }
            return []
        }

        return uniqueSpots(currentMapRecommendation.spots).filter {
            $0.imageURL != nil
                && !CafeRecommendationPolicy.isBlacklistedCafe($0)
                && !RecommendationBlacklist.isBlacklistedRecommendation($0)
        }
    }

    private var currentMapRecommendation: MapRecommendationResult {
        guard let coordinate = locationReader.coordinate else {
            let fallbackSpots = recommendedSpots.filter {
                mapCategoryFilter.matches($0)
                    && !RecommendationBlacklist.isBlacklistedRecommendation($0)
            }
            return MapRecommendationResult(
                spots: fallbackSpots,
                radius: nil,
                candidateCount: fallbackSpots.count,
                fallbackUsed: true
            )
        }

        for radius in [10_000.0, 20_000.0, 30_000.0] {
            let nearbyLocalSpots = localSeedDataService.photoSpots(
                near: coordinate,
                within: radius,
                limit: 36
            )
            let nearbyGeneratedSpots = recommendedSpots.filter {
                distance(from: coordinate, to: $0) <= radius
            }
            let spots = uniqueSpots(nearbyLocalSpots + nearbyGeneratedSpots).filter { spot in
                mapCategoryFilter.matches(spot)
                    && !RecommendationBlacklist.isBlacklistedRecommendation(spot)
            }

            if !spots.isEmpty {
                let visibleSpots = Array(spots.prefix(6))
                return MapRecommendationResult(
                    spots: visibleSpots,
                    radius: radius,
                    candidateCount: spots.count,
                    fallbackUsed: false
                )
            }
        }

        return MapRecommendationResult(
            spots: [],
            radius: 30_000,
            candidateCount: 0,
            fallbackUsed: false
        )
    }

    private var mapRecommendationEmptyMessage: String? {
        guard shouldShowNearbyMapPins,
              !isMapRecommendationLoading,
              !isMapSavedFilterEnabled,
              mapPinSpots.isEmpty else {
            return nil
        }

        return locationReader.coordinate == nil
            ? "현재 위치를 가져오면 주변 출사지를 추천할게요"
            : "주변 출사지 데이터가 부족해요"
    }

    private var savedSpots: [PhotoSpot] {
        let allSpots = uniqueSpots(localSeedDataService.allPhotoSpots() + recommendedSpots + aiSpots)
        return allSpots.filter { savedSpotStore.contains($0) }
    }

    private var savedMapListSpots: [PhotoSpot] {
        uniqueSpots(savedSpots)
            .filter { savedMapListFilter.matches($0) }
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
    }

    private var selectableSpots: [PhotoSpot] {
        uniqueSpots(localSeedDataService.allPhotoSpots() + recommendedSpots + aiSpots)
            .filter(\.hasReliableDisplayImage)
    }

    private var discoverSpots: [PhotoSpot] {
        uniqueSpots(localSeedDataService.allPhotoSpots() + recommendedSpots + aiSpots)
            .filter { spot in
                spot.hasReliableDisplayImage
                    && !RecommendationBlacklist.isBlacklistedRecommendation(spot)
                    && !CafeRecommendationPolicy.isBlacklistedCafe(spot)
            }
    }

    private var currentUser: AuthUser {
        authViewModel.currentUser ?? .fallback
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                guard newTab != .add else {
                    presentComposer(.shareSpot)
                    return
                }

                selectedTab = newTab
            }
        )
    }

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                mainContent
            } else {
                LoginView(authViewModel: authViewModel)
            }
        }
    }

    private var mainContent: some View {
        nativeTabContent
        .background(AppColors.background.ignoresSafeArea())
        .tint(AppColors.primary)
        .toolbar(isHomeTabBarHidden && selectedTab == .home ? .hidden : .visible, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(AppColors.cardBackground, for: .tabBar)
        .sheet(item: $detailPresentation) { presentation in
            SpotDetailView(
                spot: presentation.spot,
                source: presentation.source,
                isSaved: savedSpotStore.contains(presentation.spot),
                communityPosts: communityViewModel.posts(for: presentation.spot),
                currentUserID: currentUser.id,
                spots: selectableSpots,
                onToggleSave: {
                    savedSpotStore.toggle(presentation.spot)
                },
                onOpenMap: {
                    detailPresentation = nil
                    openMap(presentation.spot)
                },
                onSubmitCommunity: { draft in
                    communityViewModel.addPost(draft, author: currentUser)
                },
                onUpdateCommunity: { post, draft in
                    communityViewModel.updatePost(post, draft: draft)
                },
                onDeleteCommunity: { post in
                    communityViewModel.deletePost(post)
                }
            )
            .presentationDetents(presentation.source.detents)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $communityViewModel.isComposerPresented) {
            CommunityComposerView(
                spots: selectableSpots,
                selectedSpot: communityViewModel.composerSpot(in: selectableSpots),
                locksSelectedSpot: false,
                editingPost: communityViewModel.editingPostForComposer,
                purpose: composerPurpose,
                onSubmit: { draft in
                    if let post = communityViewModel.editingPostForComposer {
                        communityViewModel.updatePost(post, draft: draft)
                    } else {
                        communityViewModel.addPost(draft, author: currentUser)
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isWeatherDetailPresented) {
            WeatherDetailView(
                snapshot: weatherSnapshot,
                locationTitle: currentLocationTitle
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            locationReader.requestLocation()
        }
        .onReceive(locationReader.$coordinate) { newCoordinate in
            guard let newCoordinate else { return }

            homeRecommendations.updateLocationContext(userLocation: newCoordinate)

            Task {
                await updateLocationContext(for: newCoordinate)
                await loadWeather(for: newCoordinate)
            }

            if shouldShowNearbyMapPins, !isMapRecommendationLoading {
                logMapRecommendationResult()
            }
        }
        .onReceive(searchViewModel.$verifiedSpots) { verifiedSpots in
            mergeAISpots(from: verifiedSpots.map(\.photoSpot))
        }
        .onReceive(communityViewModel.$posts) { posts in
            homeRecommendations.updateCommunityContext(posts: posts)
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .home {
                isHomeTabBarHidden = false
            }

            if newTab == .map {
                if shouldFocusUserOnMapSelection {
                    shouldShowNearbyMapPins = false
                    isMapRecommendationLoading = false
                    explicitMapSpot = nil
                    selectedSpotRevision = 0
                    userLocationFocusRevision += 1
                }
                shouldFocusUserOnMapSelection = true
            }
        }
        .onChange(of: isSavedMapListPresented) { _, isPresented in
            guard !isPresented else { return }
            isMapSavedFilterEnabled = false
            savedMapListFilter = .all
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
                loadingSectionIDs: [],
                isPreloadingRecommendations: false,
                currentLocationTitle: currentLocationTitle,
                weatherSnapshot: weatherSnapshot,
                weatherLoadFailed: weatherLoadFailed,
                savedSpotIDs: savedSpotStore.savedSpotIDs,
                searchViewModel: searchViewModel,
                userLocation: locationReader.coordinate,
                onAddAISpot: addAISpot,
                onShowDetail: { showDetail($0, source: .home) },
                onShowSearchDetail: { showDetail($0, source: .search) },
                onToggleSave: { savedSpotStore.toggle($0) },
                onOpenMap: openMap,
                onShowWeather: { isWeatherDetailPresented = true },
                onShowCurrentLocation: showCurrentLocationOnMap,
                onTabBarVisibilityChange: { shouldHide in
                    guard selectedTab == .home else { return }

                    withAnimation(.easeInOut(duration: 0.18)) {
                        isHomeTabBarHidden = shouldHide
                    }
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
                    VStack(spacing: 3) {
                        Image(AppTab.add.assetName)
                            .renderingMode(.template)

                        Text(AppTab.add.title)
                    }
                }

            CommunityTabView(
                posts: communityViewModel.posts,
                spots: selectableSpots,
                currentUserID: currentUser.id,
                likedPostIDs: communityViewModel.likedPostIDs,
                followedAuthorIDs: communityViewModel.followedAuthorIDs,
                commentsByPostID: communityViewModel.commentsByPostID,
                onCompose: {
                    presentComposer(.fieldReport)
                },
                onSelectSpot: { showDetail($0, source: .community) },
                onEditPost: { post in
                    composerPurpose = .fieldReport
                    communityViewModel.beginEditing(post)
                },
                onDeletePost: { post in
                    communityViewModel.deletePost(post)
                },
                onToggleLike: { post in
                    communityViewModel.toggleLike(post)
                },
                onToggleFollow: { post in
                    communityViewModel.toggleFollow(post)
                },
                onAddComment: { message, post in
                    communityViewModel.addComment(message, to: post, author: currentUser)
                }
            )
            .tag(AppTab.community)
            .tabItem {
                tabItemLabel(for: .community)
            }

            MyTabView(
                user: currentUser,
                savedSpots: savedSpots,
                posts: communityViewModel.posts,
                spots: selectableSpots,
                likedPostIDs: communityViewModel.likedPostIDs,
                followedAuthorIDs: communityViewModel.followedAuthorIDs,
                commentsByPostID: communityViewModel.commentsByPostID,
                onSelectSpot: { showDetail($0, source: .saved) },
                onEditPost: { post in
                    composerPurpose = .fieldReport
                    communityViewModel.beginEditing(post)
                },
                onDeletePost: { post in
                    communityViewModel.deletePost(post)
                },
                onToggleLike: { post in
                    communityViewModel.toggleLike(post)
                },
                onToggleFollow: { post in
                    communityViewModel.toggleFollow(post)
                },
                onAddComment: { message, post in
                    communityViewModel.addComment(message, to: post, author: currentUser)
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
        .animation(nil, value: selectedTab)
    }

    private func tabItemLabel(for tab: AppTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(tab.assetName)
                .renderingMode(.template)
        }
    }

    private var mapLayer: some View {
        MapTabView(
            spots: mapPinSpots,
            selectedSpot: selectedSpot,
            selectedSpotRevision: selectedSpotRevision,
            focusUserLocationRevision: userLocationFocusRevision,
            userCoordinate: locationReader.coordinate,
            savedSpots: savedSpots,
            savedSpotIDs: savedSpotStore.savedSpotIDs,
            shouldShowNearbyMapPins: shouldShowNearbyMapPins,
            isRecommendationLoading: isMapRecommendationLoading,
            isMapSavedFilterEnabled: isMapSavedFilterEnabled,
            mapCategoryFilter: mapCategoryFilter,
            emptyRecommendationMessage: mapRecommendationEmptyMessage,
            isSavedListPresented: $isSavedMapListPresented,
            savedListFilter: $savedMapListFilter,
            onSelectSpot: { selectedSpot = $0 },
            onShowDetail: { showDetail($0, source: .map) },
            onToggleRecommendations: toggleNearbyMapPins,
            onToggleSavedFilter: toggleSavedMapFilter,
            onSelectCategory: selectMapCategory,
            onSelectSavedCategory: selectSavedMapListFilter,
            onSelectSavedSpot: focusSavedSpotFromList
        )
    }

    private func presentComposer(_ purpose: CommunityComposerPurpose) {
        composerPurpose = purpose
        communityViewModel.beginComposing()
    }

    private func toggleNearbyMapPins() {
        withAnimation(.easeInOut(duration: 0.16)) {
            let shouldTurnOnRecommendations = !shouldShowNearbyMapPins
            shouldShowNearbyMapPins = shouldTurnOnRecommendations

            if shouldTurnOnRecommendations {
                isMapSavedFilterEnabled = false
                isSavedMapListPresented = false
                savedMapListFilter = .all
                isMapRecommendationLoading = true
                explicitMapSpot = nil
                locationReader.requestLocation()
                userLocationFocusRevision += 1
            } else {
                isMapRecommendationLoading = false
                selectedSpotRevision = 0
                explicitMapSpot = nil
                if detailPresentation?.source == .map {
                    detailPresentation = nil
                }
            }
        }

        if shouldShowNearbyMapPins {
            finishMapRecommendationLoadingAfterDelay()
        }
    }

    private func toggleSavedMapFilter() {
        withAnimation(.easeInOut(duration: 0.16)) {
            let shouldPresentSavedList = !isSavedMapListPresented
            isSavedMapListPresented = shouldPresentSavedList
            isMapSavedFilterEnabled = shouldPresentSavedList

            if shouldPresentSavedList {
                shouldShowNearbyMapPins = false
                isMapRecommendationLoading = false
                explicitMapSpot = nil
                if let firstSavedSpot = savedMapListSpots.first ?? savedSpots.first {
                    selectedSpot = firstSavedSpot
                    selectedSpotRevision += 1
                }
            } else {
                savedMapListFilter = .all
                selectedSpotRevision = 0
            }
        }
    }

    private func selectSavedMapListFilter(_ filter: SavedMapListFilter) {
        withAnimation(.easeInOut(duration: 0.16)) {
            savedMapListFilter = filter
            isSavedMapListPresented = true
            isMapSavedFilterEnabled = true
            shouldShowNearbyMapPins = false
            isMapRecommendationLoading = false
            explicitMapSpot = nil

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
            explicitMapSpot = nil
        }
    }

    private func selectMapCategory(_ filter: MapCategoryFilter) {
        withAnimation(.easeInOut(duration: 0.16)) {
            mapCategoryFilter = filter

            if filter != .all {
                if !shouldShowNearbyMapPins {
                    shouldShowNearbyMapPins = true
                    isMapSavedFilterEnabled = false
                    isSavedMapListPresented = false
                    savedMapListFilter = .all
                    isMapRecommendationLoading = true
                    explicitMapSpot = nil
                    finishMapRecommendationLoadingAfterDelay()
                }
                locationReader.requestLocation()
            }
        }
    }

    private func finishMapRecommendationLoadingAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await MainActor.run {
                guard shouldShowNearbyMapPins else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    isMapRecommendationLoading = false
                }
                logMapRecommendationResult()
            }
        }
    }

    private func addAISpot(_ spot: PhotoSpot) {
        guard !recommendedSpots.contains(where: { $0.id == spot.id || $0.mapQuery == spot.mapQuery }) else {
            return
        }
        guard !RecommendationBlacklist.isBlacklistedRecommendation(spot) else {
            return
        }

        aiSpots.append(spot)
    }

    private func mergeAISpots(from spots: [PhotoSpot]) {
        for spot in spots {
            addAISpot(spot)
        }
    }

    private func showDetail(_ spot: PhotoSpot, source: SpotDetailSource) {
        detailPresentation = SpotDetailPresentation(spot: spot, source: source)
    }

    private func openMap(_ spot: PhotoSpot?) {
        if let spot {
            addAISpot(spot)
            selectedSpot = spot
            explicitMapSpot = spot
            selectedSpotRevision += 1
            shouldShowNearbyMapPins = false
            isMapRecommendationLoading = false
            shouldFocusUserOnMapSelection = false
        }

        selectedTab = .map
    }

    private func showCurrentLocationOnMap() {
        shouldShowNearbyMapPins = false
        isMapRecommendationLoading = false
        explicitMapSpot = nil
        shouldFocusUserOnMapSelection = true
        userLocationFocusRevision += 1
        selectedTab = .map
    }

    private func showHiddenSpotsOnMap() {
        shouldFocusUserOnMapSelection = false
        selectedTab = .map
        mapCategoryFilter = .hidden
        isMapSavedFilterEnabled = false
        isSavedMapListPresented = false
        savedMapListFilter = .all
        shouldShowNearbyMapPins = true
        isMapRecommendationLoading = true
        explicitMapSpot = nil
        locationReader.requestLocation()
        userLocationFocusRevision += 1
        finishMapRecommendationLoadingAfterDelay()
    }

    @MainActor
    private func updateLocationContext(for coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return
        }

        let parts = [
            placemark.locality,
            placemark.subLocality
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) {
                    result.append(item)
                }
            }

        if !parts.isEmpty {
            currentLocationTitle = parts.joined(separator: " ")
        } else if let area = placemark.administrativeArea, !area.isEmpty {
            currentLocationTitle = area
        }
    }

    @MainActor
    private func loadWeather(for coordinate: CLLocationCoordinate2D) async {
        let key = "\(Int((coordinate.latitude * 100).rounded()))-\(Int((coordinate.longitude * 100).rounded()))"
        if weatherCoordinateKey == key,
           let weatherLastFetchDate,
           Date().timeIntervalSince(weatherLastFetchDate) < 30 * 60 {
            return
        }

        weatherCoordinateKey = key
        weatherLastFetchDate = Date()
        weatherLoadFailed = false

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,cloud_cover,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,cloud_cover"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "Asia/Seoul")
        ]

        guard let url = components?.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let fineDust = await loadFineDust(for: coordinate)
            let snapshot = WeatherSnapshot(
                condition: weatherDescription(for: decoded.current.weatherCode),
                temperature: Int(decoded.current.temperature2M.rounded()),
                highTemperature: Int((decoded.daily.temperature2MMax.first ?? decoded.current.temperature2M).rounded()),
                lowTemperature: Int((decoded.daily.temperature2MMin.first ?? decoded.current.temperature2M).rounded()),
                apparentTemperature: Int(decoded.current.apparentTemperature.rounded()),
                humidity: decoded.current.relativeHumidity2M,
                precipitation: decoded.current.precipitation,
                cloudCover: decoded.current.cloudCover,
                windSpeed: decoded.current.windSpeed10M,
                fineDust: fineDust,
                hourlyForecasts: hourlyForecasts(from: decoded)
            )
            weatherSnapshot = snapshot
            homeRecommendations.updateWeatherContext(snapshot.recommendationContext)
            weatherLoadFailed = false
        } catch {
            weatherSnapshot = nil
            homeRecommendations.updateWeatherContext(nil)
            weatherLoadFailed = true
        }
    }

    private func loadFineDust(for coordinate: CLLocationCoordinate2D) async -> FineDustSnapshot? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "hourly", value: "pm10,pm2_5"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "Asia/Seoul")
        ]

        guard let url = components?.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoAirQualityResponse.self, from: data)
            return FineDustSnapshot(
                pm10: decoded.hourly.pm10.compactMap { $0 }.first,
                pm25: decoded.hourly.pm25.compactMap { $0 }.first
            )
        } catch {
            return nil
        }
    }

    private func hourlyForecasts(from decoded: OpenMeteoResponse) -> [WeatherHourlyForecast] {
        let hourly = decoded.hourly
        let count = min(
            hourly.time.count,
            hourly.temperature2M.count,
            hourly.weatherCode.count,
            hourly.cloudCover.count
        )
        guard count > 0 else { return [] }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        return (0..<count)
            .compactMap { index -> WeatherHourlyForecast? in
                guard let date = formatter.date(from: hourly.time[index]),
                      date >= now.addingTimeInterval(-60 * 60) else {
                    return nil
                }

                let hour = calendar.component(.hour, from: date)
                return WeatherHourlyForecast(
                    timeLabel: "\(hour)시",
                    condition: weatherDescription(for: hourly.weatherCode[index]),
                    temperature: Int(hourly.temperature2M[index].rounded()),
                    precipitationProbability: hourly.precipitationProbability?[safe: index],
                    cloudCover: hourly.cloudCover[index]
                )
            }
            .prefix(12)
            .map { $0 }
    }

    private func weatherDescription(for code: Int) -> String {
        switch code {
        case 0:
            return "맑음"
        case 1...3:
            return "구름 조금"
        case 45, 48:
            return "안개"
        case 51...67, 80...82:
            return "비"
        case 71...77, 85...86:
            return "눈"
        case 95...99:
            return "천둥"
        default:
            return "날씨 확인"
        }
    }

    private func distance(from coordinate: CLLocationCoordinate2D, to spot: PhotoSpot) -> CLLocationDistance {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let destination = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        return destination.distance(from: origin)
    }

    private func logMapRecommendationResult() {
        let result = currentMapRecommendation
        let coordinateText = locationReader.coordinate.map {
            String(format: "%.5f, %.5f", $0.latitude, $0.longitude)
        } ?? "없음"
        let radiusText = result.radius.map { "\(Int($0 / 1_000))km" } ?? "기본"
        let finalNames = result.spots.map(\.name).joined(separator: ", ")
        print("[Viewfinder][MapRecommendations] coordinate=\(coordinateText) radius=\(radiusText) candidateCount=\(result.candidateCount) final=[\(finalNames)] fallbackUsed=\(result.fallbackUsed)")
    }

    private func uniqueSpots(_ spots: [PhotoSpot]) -> [PhotoSpot] {
        spots.reduce(into: [PhotoSpot]()) { result, spot in
            guard !result.contains(where: { $0.id == spot.id || $0.mapQuery == spot.mapQuery }) else {
                return
            }
            result.append(spot)
        }
    }

}

private extension WeatherSnapshot {
    var recommendationContext: RecommendationWeatherContext {
        RecommendationWeatherContext(
            condition: condition,
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            precipitation: precipitation,
            cloudCover: cloudCover,
            windSpeed: windSpeed,
            pm10: fineDust?.pm10,
            pm25: fineDust?.pm25
        )
    }
}

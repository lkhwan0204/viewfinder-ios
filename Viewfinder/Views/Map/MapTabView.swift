import CoreLocation
import SwiftUI

enum SavedMapListFilter: String, CaseIterable, Identifiable {
    case all

    // 저장 목록도 홈/지도와 같은 장소 주 테마를 사용합니다.
    case cityArchitecture
    case landscape
    case retroAlley
    case historyTradition
    case viewpoint
    case cafeIndoor

    // 기존 저장 목록 상태와 호출부 호환용입니다. 탭에는 노출하지 않습니다.
    case sunset
    case cafe
    case park
    case film
    case night
    case walk
    case flower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "전체"
        case .cityArchitecture:
            return "도심/건축"
        case .landscape:
            return "자연/풍경"
        case .retroAlley:
            return "골목/레트로"
        case .historyTradition:
            return "역사/전통"
        case .viewpoint:
            return "전망/뷰"
        case .cafeIndoor:
            return "실내/카페"
        case .sunset:
            return "노을"
        case .cafe:
            return "카페"
        case .park:
            return "공원"
        case .film:
            return "필름감성"
        case .night:
            return "야경"
        case .walk:
            return "산책"
        case .flower:
            return "꽃스팟"
        }
    }

    var headerTitle: String {
        switch self {
        case .all:
            return "저장한 출사지"
        case .cityArchitecture:
            return "도심/건축 출사지"
        case .landscape:
            return "자연/풍경 출사지"
        case .retroAlley:
            return "골목/레트로 출사지"
        case .historyTradition:
            return "역사/전통 출사지"
        case .viewpoint:
            return "전망/뷰 출사지"
        case .cafeIndoor:
            return "실내/카페 출사지"
        case .sunset:
            return "노을 명소"
        case .cafe:
            return "감성 카페"
        case .park:
            return "공원 출사"
        case .film:
            return "필름 감성 스팟"
        case .night:
            return "야경 명소"
        case .walk:
            return "산책 출사"
        case .flower:
            return "꽃스팟"
        }
    }

    func matches(_ spot: PhotoSpot) -> Bool {
        switch self {
        case .all:
            return true
        case .cityArchitecture:
            return MapCategoryFilter.cityArchitecture.matches(spot)
        case .landscape:
            return MapCategoryFilter.landscape.matches(spot)
        case .retroAlley:
            return MapCategoryFilter.retroAlley.matches(spot)
        case .historyTradition:
            return MapCategoryFilter.historyTradition.matches(spot)
        case .viewpoint:
            return MapCategoryFilter.viewpoint.matches(spot)
        case .cafeIndoor:
            return MapCategoryFilter.cafeIndoor.matches(spot)
        case .sunset:
            return MapCategoryFilter.sunset.matches(spot)
        case .cafe:
            return MapCategoryFilter.cafe.matches(spot)
        case .park:
            return MapCategoryFilter.park.matches(spot)
        case .film:
            return MapCategoryFilter.film.matches(spot)
        case .night:
            return MapCategoryFilter.night.matches(spot)
        case .walk:
            return MapCategoryFilter.walk.matches(spot)
        case .flower:
            let searchable = ([spot.name, spot.summary, spot.bestTime, spot.category]
                + spot.hashtags
                + spot.mood
                + spot.season)
                .joined(separator: " ")

            return containsAny(searchable, keywords: ["꽃", "벚꽃", "장미", "수국", "데이지", "유채", "튤립", "flower"])
        }
    }

    /// 저장 목록에 실제로 노출하는 필터입니다.
    /// 레거시 필터는 이전 상태값과 코드 호환을 위해 enum에만 남깁니다.
    static let displayed: [SavedMapListFilter] = [
        .all,
        .cityArchitecture,
        .landscape,
        .retroAlley,
        .historyTradition,
        .viewpoint,
        .cafeIndoor
    ]

    private func containsAny(_ value: String, keywords: [String]) -> Bool {
        keywords.contains { value.localizedCaseInsensitiveContains($0) }
    }
}

struct MapTabView: View {
    let spots: [PhotoSpot]
    let selectedSpot: PhotoSpot
    let selectedSpotRevision: Int
    let focusUserLocationRevision: Int
    let userCoordinate: CLLocationCoordinate2D?
    let savedSpots: [PhotoSpot]
    let shouldShowNearbyMapPins: Bool
    let isRecommendationLoading: Bool
    let isMapSavedFilterEnabled: Bool
    let mapCategoryFilter: MapCategoryFilter
    let emptyRecommendationMessage: String?
    @Binding var isSavedListPresented: Bool
    @Binding var savedListFilter: SavedMapListFilter
    let onShowDetail: (PhotoSpot) -> Void
    let onToggleRecommendations: () -> Void
    let onToggleSavedFilter: () -> Void
    let onSelectCategory: (MapCategoryFilter) -> Void
    let onSelectSavedCategory: (SavedMapListFilter) -> Void
    let onSelectSavedSpot: (PhotoSpot) -> Void
    /// 검색 대상. 지도에 찍힌 핀이 아니라 앱이 아는 모든 장소입니다.
    let searchableSpots: [PhotoSpot]
    /// 검색 결과를 골랐을 때. ContentView.openMap 으로 연결됩니다.
    let onSelectSearchResult: (PhotoSpot) -> Void
    /// 검색 결과가 없을 때 새 장소 제보로 이어집니다.
    let onAddPlace: () -> Void
    /// 내 위치로 카메라 이동.
    let onFocusUserLocation: () -> Void

    // 사용자가 마지막으로 탭한 핀. 앱 전역 selectedSpot 과 분리해
    // 지도 마커의 selected 시각 상태만 관리합니다.
    @State private var focusedSpotID: String?
    @State private var hasMoreThemeFilters = false
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    /// 앱이 아는 장소 + 네이버 실제 장소검색.
    /// 제보 화면과 같은 검색기를 씁니다.
    @StateObject private var placeFinder = PlaceFinder()

    // ═══════════════════════════════════════════════════════════════
    //  개수 표시를 없앴습니다.
    //
    //  "내 주변 출사지 6곳" 은 원래 진단용이었습니다.
    //  핀이 하나도 안 보이던 때, 데이터가 없는 것인지 렌더링이
    //  안 되는 것인지 구분하려고 넣었습니다.
    //  핀이 정상 동작하는 것을 확인했으므로 역할이 끝났습니다.
    //
    //  그리고 이 값은 사용자의 행동을 바꾸지 않습니다.
    //  6곳인지 7곳인지 알아도 할 일이 달라지지 않고, 핀이 화면에
    //  보이므로 개수는 눈으로 셀 수 있습니다.
    //
    //  결과가 없을 때와 찾는 중일 때만 남깁니다.
    //  그때는 화면이 비어 있어서, 왜 비었는지 말해주지 않으면
    //  고장으로 읽힙니다.
    // ═══════════════════════════════════════════════════════════════
    private var statusText: String? {
        guard !isMapSavedFilterEnabled else { return nil }
        if isRecommendationLoading {
            return "주변 출사지 찾는 중"
        }
        return emptyRecommendationMessage
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 검색 중인지. 포커스가 있거나 입력이 남아 있으면 검색 모드입니다.
    private var isSearching: Bool {
        isSearchFocused || !trimmedQuery.isEmpty
    }

    private var isMapSheetPresented: Bool {
        isSavedListPresented
    }

    private func commitSearchSelection(_ spot: PhotoSpot) {
        isSearchFocused = false
        searchQuery = ""

        // 상세를 닫고 돌아왔을 때 선택한 마커의 시각 상태를 유지합니다.
        // selectedSpotRevision 의 onChange 에만 의존하면
        // spots 갱신 순서에 따라 놓칠 수 있습니다.
        focusedSpotID = spot.id

        // 키보드가 내려가는 동안 카메라가 움직이면 두 움직임이 겹칩니다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            onSelectSearchResult(spot)

            // 카메라 이동이 시작된 뒤에 시트를 올립니다.
            // 동시에 하면 지도가 움직이는 것이 시트에 가려 보이지 않아,
            // 상세를 닫았을 때 위치가 갑자기 바뀐 것처럼 느껴집니다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                onShowDetail(spot)
            }
        }
    }

    var body: some View {
        ZStack {
            // ═══════════════════════════════════════════════════════
            //  상태바 가독성
            //
            //  [문제였던 상황]
            //  지도 타일은 앱 테마에 맞춰 밝고 어두워집니다. 하지만 지도는
            //  지역별로 명도가 크게 달라서, 상태바 글자를 타일 위에 바로
            //  올리면 라이트·다크 어느 쪽에서도 읽기 어려운 구간이 생깁니다.
            //
            //  상태바 스타일은 SwiftUI 에서 직접 바꿀 수 없고
            //  UIViewController 를 건드려야 합니다. 그 방법은 탭 전환
            //  시점에 따라 어긋나기 쉽고, 검증하지 못한 경로입니다.
            //
            //  대신 지도 위 상단에 현재 모드와 반대 명도의 아주 옅은 fade를
            //  깝니다. 상태바가 읽히고, 바로 아래 검색바와 이어져서 띠가
            //  따로 보이지 않습니다.
            // ═══════════════════════════════════════════════════════
        KoreaMapBackdropView(
                spots: spots,
                selectedSpot: selectedSpot,
                selectedSpotRevision: selectedSpotRevision,
                focusUserLocationRevision: focusUserLocationRevision,
                userCoordinate: userCoordinate,
                selectedPinID: focusedSpotID,
                onSelectSpot: { spot in
                    focusedSpotID = spot.id
                    onShowDetail(spot)
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                mapStatusBarFade
            }
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 8) {
                // ═══════════════════════════════════════════════════
                //  상단은 컨트롤, 하단은 지금 상황.
                //
                //  상태 pill 을 아래로 내렸습니다.
                //  검색바를 넣으면 상단이 검색 + 칩 + 상태 3줄이 되는데,
                //  상단 복잡함은 이미 한 번 지적받은 문제입니다.
                //  상태 pill 은 조작하는 것이 아니라 읽는 정보라
                //  하단의 보조 위치에 둡니다.
                // ═══════════════════════════════════════════════════
                HStack(spacing: 8) {
                    MapSearchField(
                        query: $searchQuery,
                        isFocused: $isSearchFocused,
                        onSubmit: {
                            // 확인을 누르면 첫 제안으로 이동합니다.
                            guard let first = placeFinder.results.first else { return }
                            commitSearchSelection(first.spot)
                        }
                    )

                    // 검색 중에만 나오는 취소.
                    // 저장 버튼이 있던 자리를 그대로 씁니다.
                    if isSearching {
                        Button {
                            searchQuery = ""
                            isSearchFocused = false
                            placeFinder.clear()
                        } label: {
                            Text("취소")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MapChrome.ink)
                                .padding(.horizontal, 13)
                                .frame(height: 44)
                                .mapChromeSurface(Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }

                }

                // 검색 중에는 칩 줄을 숨깁니다.
                // 제안 목록과 칩이 동시에 있으면 상단이 세 겹이 되고,
                // 지금 하려는 일(장소 찾기)과 무관한 컨트롤이 남습니다.
                if isSearching {
                    MapSearchSuggestions(
                        results: placeFinder.results,
                        query: trimmedQuery,
                        isSearching: placeFinder.isSearching,
                        message: placeFinder.message,
                        userCoordinate: userCoordinate,
                        onAddPlace: onAddPlace,
                        onSelect: { commitSearchSelection($0.spot) }
                    )
                } else {
                    mapControls
                }

                Spacer(minLength: 0)

                if let statusText, !isSearching {
                    MapStatusPill(text: statusText)
                        .padding(.horizontal, 4)
                        // 우측 버튼 폭과 12pt 간격을 비워 긴 상태 문구도 겹치지 않습니다.
                        .padding(.trailing, MapChrome.circleSize + 12)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            // safe area 하단에는 탭바 높이가 이미 포함되어 있습니다.
            // 여기에 92 를 더하면 하단 상태가 탭바에서 190pt 나 떨어져
            // 화면 중간에 떠 있게 됩니다. 탭바와의 간격만 남깁니다.
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(VFMotion.quick, value: isSearching)
        }
        .overlay(alignment: .bottomTrailing) {
            // 탭바가 제공하는 안전 영역에 고정해 상태 pill 유무에 영향받지 않습니다.
            if !isSearching {
                VStack(alignment: .trailing, spacing: 12) {
                    Button(action: onToggleSavedFilter) {
                        MapCircleButton(
                            symbolName: isMapSavedFilterEnabled ? "bookmark.fill" : "bookmark",
                            isActive: isMapSavedFilterEnabled
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("저장한 장소만 보기")
                    .accessibilityValue(isMapSavedFilterEnabled ? "켜짐" : "꺼짐")
                    .accessibilityHint("저장한 장소만 지도에 표시")
                    .accessibilityAddTraits(isMapSavedFilterEnabled ? .isSelected : [])

                    Button(action: onFocusUserLocation) {
                        MapCircleButton(symbolName: "location.fill", tint: AppColors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("내 위치로 이동")
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
        .accessibilityHidden(isMapSheetPresented)
        .onChange(of: searchQuery) { _, newValue in
            let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !query.isEmpty else {
                placeFinder.clear()
                return
            }

            placeFinder.search(
                query,
                near: userCoordinate,
                knownSpots: searchableSpots
            )
        }
        .onChange(of: selectedSpotRevision) { _, newValue in
            // 홈 상세에서 "지도에서 보기" 로 들어온 경우엔
            // 사용자가 명시적으로 그 장소를 지목한 것이므로 마커를 강조합니다.
            guard newValue > 0, spots.contains(where: { $0.id == selectedSpot.id }) else { return }
            focusedSpotID = selectedSpot.id
        }
        .sheet(isPresented: $isSavedListPresented) {
            NavigationStack {
                SavedMapBottomSheetView(
                    selectedFilter: $savedListFilter,
                    savedSpots: savedSpots,
                    userCoordinate: userCoordinate,
                    onSelectFilter: onSelectSavedCategory,
                    onSelectSpot: { spot in
                        onSelectSavedSpot(spot)
                        isSavedListPresented = false
                    }
                )
                .navigationTitle("저장한 출사지")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("완료") {
                            isSavedListPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.fraction(0.42), .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var mapStatusBarFade: some View {
        LinearGradient(
            stops: [
                .init(
                    color: colorScheme == .dark ? Color.black.opacity(0.38) : Color.white.opacity(0.70),
                    location: 0
                ),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 108)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // ═══════════════════════════════════════════════════════════════
    //  지도 상단 컨트롤
    //
    //  검색창 아래에는 전체 + 6개 canonical 테마만 둡니다.
    //  저장 필터는 이 레일 아래의 독립 행에서 테마와 함께 적용합니다.
    // ═══════════════════════════════════════════════════════════════
    @ViewBuilder
    private var mapControls: some View {
        GeometryReader { viewport in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MapCategoryFilter.mapDisplayed) { filter in
                    Button {
                        onSelectCategory(filter)
                    } label: {
                        MapFilterPill(
                            title: filter.title,
                            isSelected: filter == mapCategoryFilter
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(filter.title) 카테고리")
                    .accessibilityValue(filter == mapCategoryFilter ? "선택됨" : "")
                }
            }
            // 마지막 칩이 edge에 붙지 않고 끝까지 스크롤되도록 여유를 둡니다.
            .padding(.leading, 2)
            .padding(.trailing, 20)
            .background {
                GeometryReader { content in
                    Color.clear.preference(
                        key: MapFilterOverflowPreferenceKey.self,
                        value: content.frame(in: .named("mapThemeFilters")).maxX > viewport.size.width + 1
                    )
                }
            }
        }
        .coordinateSpace(name: "mapThemeFilters")
        .onPreferenceChange(MapFilterOverflowPreferenceKey.self) { hasMoreThemeFilters = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mask {
            HStack(spacing: 0) {
                Color.black
                    .frame(maxWidth: .infinity)
                LinearGradient(
                    colors: [.black, hasMoreThemeFilters ? .clear : .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 16)
            }
        }
        }
        .frame(height: MapChrome.controlHeight + 6)
    }
}

private struct MapFilterOverflowPreferenceKey: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct SavedMapBottomSheetView: View {
    @Binding var selectedFilter: SavedMapListFilter
    let savedSpots: [PhotoSpot]
    let userCoordinate: CLLocationCoordinate2D?
    let onSelectFilter: (SavedMapListFilter) -> Void
    let onSelectSpot: (PhotoSpot) -> Void

    private var filteredSpots: [PhotoSpot] {
        savedSpots
            .filter { selectedFilter.matches($0) }
            .sorted { lhs, rhs in
                guard let userCoordinate else {
                    return lhs.name < rhs.name
                }
                return distance(from: userCoordinate, to: lhs) < distance(from: userCoordinate, to: rhs)
            }
    }

    private var shareText: String {
        let names = filteredSpots.prefix(8).map(\.name).joined(separator: ", ")
        return names.isEmpty ? "저장한 출사지" : "저장한 출사지: \(names)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            categoryTabs

            if filteredSpots.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredSpots) { spot in
                            Button {
                                onSelectSpot(spot)
                            } label: {
                                SavedMapSpotListCard(
                                    spot: spot,
                                    distanceText: distanceText(for: spot)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(AppColors.background)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedFilter == .all ? "내 보관함" : selectedFilter.headerTitle)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.primary)

                Text("\(filteredSpots.count)개 장소")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 38, height: 38)
                    .background(AppColors.mutedSurface, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SavedMapListFilter.displayed) { filter in
                    Button {
                        selectedFilter = filter
                        onSelectFilter(filter)
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(filter == selectedFilter ? AppColors.accent : AppColors.primary)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(filter == selectedFilter ? AppColors.accentSoft : AppColors.mutedSurface, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(filter == selectedFilter ? AppColors.accent.opacity(0.42) : AppColors.divider, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)

            Text(selectedFilter == .all ? "저장한 출사지가 아직 없어요" : "이 카테고리에 저장한 장소가 없어요")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Text("마음에 드는 장소를 저장하면 지도 위에서 바로 모아볼 수 있어요")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 34)
    }

    private func distanceText(for spot: PhotoSpot) -> String? {
        guard let userCoordinate else { return nil }
        let meters = distance(from: userCoordinate, to: spot)
        if meters < 1_000 {
            return "\(Int(meters.rounded()))m"
        }
        return String(format: "%.1fkm", meters / 1_000)
    }

    private func distance(from coordinate: CLLocationCoordinate2D, to spot: PhotoSpot) -> CLLocationDistance {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
    }
}

private struct SavedMapSpotListCard: View {
    let spot: PhotoSpot
    let distanceText: String?

    private var regionText: String {
        HomeSpotDisplayFormatter.region(for: spot)
    }

    private var tagLine: String {
        let tags = spot.hashtags
            .prefix(2)
            .map { HomeSpotDisplayFormatter.tag($0) }
            .filter { !$0.isEmpty }
        return tags.joined(separator: " · ")
    }

    private var summaryText: String {
        let trimmedSummary = spot.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSummary.isEmpty ? "사진 구도가 좋은 저장 출사지" : trimmedSummary
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoSpotImageView(spot: spot, symbolSize: 20)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(spot.name)
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let distanceText {
                        Text(distanceText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }

                Text(regionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text(summaryText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppColors.primary.opacity(0.72))
                    .lineLimit(1)

                if !tagLine.isEmpty {
                    Text(tagLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}



// ═══════════════════════════════════════════════════════════════════
// MARK: - 지도 검색
//
//  [문제였던 상황]
//  지도에 검색이 없었습니다.
//  "성수동 가려는데 출사지 뭐 있지?" 를 지도에서 할 방법이 없어서
//  홈으로 나가 검색하고 상세로 들어가 "지도에서 보기" 를 눌러야 했습니다.
//
//  [시트가 아니라 인라인인 이유]
//  처음에 검색을 시트로 만들었는데, 시트는 지도를 덮습니다.
//  지도에서 장소를 찾는 행위는 "여기가 어디쯤인지 보면서" 하는 일입니다.
//  화면을 덮어버리면 그 맥락이 사라집니다.
//  검색바에서 바로 입력하고, 제안은 검색바 바로 아래에 띄웁니다.
//  지도는 계속 보이고, 제안을 누르면 그 자리로 이동합니다.
//
//  [홈 검색을 재사용하지 않은 이유]
//  HomeSearchResultsView 는 검색 뷰모델·AI 추천·커뮤니티 글까지
//  묶여 있습니다. 지도에서 필요한 것은 "장소를 찾아 그리로 이동" 하나입니다.
//  네트워크도 AI 도 필요하지 않고, 앱이 이미 아는 장소만 훑으면 됩니다.
// ═══════════════════════════════════════════════════════════════════

struct MapSearchField: View {
    @Binding var query: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        VFSearchField(text: $query, isFocused: $isFocused, onSubmit: onSubmit, style: .map)
    }
}

/// 검색바 바로 아래에 붙는 제안 목록.
///
/// 구글 자동완성처럼 입력하는 즉시 좁혀집니다.
/// 확인 버튼을 누를 필요가 없고, 결과를 보려고 화면을 바꾸지도 않습니다.
struct MapSearchSuggestions: View {
    let results: [PlaceSearchResult]
    let query: String
    let isSearching: Bool
    let message: String?
    let userCoordinate: CLLocationCoordinate2D?
    let onAddPlace: () -> Void
    let onSelect: (PlaceSearchResult) -> Void

    /// 한 번에 보여주는 최대 개수.
    /// 전부 펼치면 지도를 다 덮어서 시트를 없앤 의미가 사라집니다.
    private let visibleRowLimit = 5
    private let rowHeight: CGFloat = 56

    var body: some View {
        Group {
            if query.isEmpty {
                hintRow
            } else if results.isEmpty {
                statusRow
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MapChrome.panel,
            in: RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
                .stroke(MapChrome.hairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { result in
                    Button {
                        onSelect(result)
                    } label: {
                        MapSuggestionRow(
                            result: result,
                            userCoordinate: userCoordinate,
                            height: rowHeight
                        )
                    }
                    .buttonStyle(.plain)

                    if result.id != results.last?.id {
                        Rectangle()
                            .fill(MapChrome.hairline)
                            .frame(height: 0.5)
                            .padding(.leading, 60)
                    }
                }
            }
        }
        .frame(height: min(CGFloat(results.count), CGFloat(visibleRowLimit)) * rowHeight)
        .scrollDisabled(results.count <= visibleRowLimit)
    }

    private var hintRow: some View {
        Text("장소 이름이나 지역을 입력하세요")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MapChrome.inkDim)
            .padding(.horizontal, 14)
            .frame(height: 48, alignment: .leading)
    }

    /// 결과가 없을 때. 아직 찾는 중인지, 정말 없는지를 구분해서 말합니다.
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            if isSearching {
                Text("찾는 중…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MapChrome.ink)
            } else {
                Text("‘\(query)’ 결과가 없어요")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MapChrome.ink)

                Text(message ?? "장소 이름에 지역을 함께 넣어보세요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MapChrome.inkDim)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onAddPlace) {
                    Label("새 장소 알려주기", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(minHeight: AppLayout.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MapSuggestionRow: View {
    let result: PlaceSearchResult
    let userCoordinate: CLLocationCoordinate2D?
    let height: CGFloat

    var body: some View {
        HStack(spacing: 11) {
            // 앱에 등록된 장소는 사진을, 실제 장소 검색 결과는 핀 기호를
            // 보여줍니다. 아직 우리 데이터가 아닌 곳이라는 뜻입니다.
            if result.isKnown {
                PhotoSpotImageView(spot: result.spot, symbolSize: 15)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous))
            } else {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MapChrome.inkDim)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(MapChrome.ink)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(result.address)
                        .lineLimit(1)

                    if let distance = VFSpotDistance.text(from: userCoordinate, to: result.spot) {
                        Text("·")
                        Text(distance)
                    }
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(MapChrome.inkDim)
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(MapChrome.inkDim)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
        .frame(height: height)
        .contentShape(Rectangle())
    }
}

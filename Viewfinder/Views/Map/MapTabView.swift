import CoreLocation
import SwiftUI

enum SavedMapListFilter: String, CaseIterable, Identifiable {
    case all
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
    let savedSpotIDs: Set<String>
    let shouldShowNearbyMapPins: Bool
    let isRecommendationLoading: Bool
    let isMapSavedFilterEnabled: Bool
    let mapCategoryFilter: MapCategoryFilter
    let emptyRecommendationMessage: String?
    @Binding var isSavedListPresented: Bool
    @Binding var savedListFilter: SavedMapListFilter
    let onSelectSpot: (PhotoSpot) -> Void
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
    /// 내 위치로 카메라 이동.
    let onFocusUserLocation: () -> Void

    // 사용자가 실제로 고른 핀. 앱 전역 selectedSpot 과 다릅니다.
    //
    // [문제였던 상황]
    // 하단 프리뷰 카드가 전역 selectedSpot 을 그대로 보여줬습니다.
    // selectedSpot 은 홈에서 마지막으로 본 장소이기도 하므로,
    // 지도 탭에 처음 들어와 아무것도 누르지 않았는데도
    // "용산공원" 카드가 떠 있었습니다. 그 장소는 이 지도의 핀 목록에도
    // 없어서 카드를 눌러도 지도와 아무 관계가 없었고, 사진조차 없어서
    // 조리개 플레이스홀더만 보였습니다.
    //
    // 이제 카드는 이 지도에 실제로 핀이 찍혀 있는 장소만,
    // 그리고 사용자가 그 핀을 눌렀을 때만 나타납니다.
    @State private var focusedSpotID: String?
    @State private var cardDragY: CGFloat = 0
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool
    /// 앱이 아는 장소 + 네이버 실제 장소검색.
    /// 제보 화면과 같은 검색기를 씁니다.
    @StateObject private var placeFinder = PlaceFinder()

    private var previewSpot: PhotoSpot? {
        guard let focusedSpotID else { return nil }
        return spots.first { $0.id == focusedSpotID }
    }

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

    private func commitSearchSelection(_ spot: PhotoSpot) {
        isSearchFocused = false
        searchQuery = ""

        // 상세를 닫고 돌아왔을 때 카드가 그 자리에 있게 미리 지정합니다.
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
            //  앱이 다크 모드라 상태바 글자(시계·배터리)가 흰색인데
            //  지도는 밝습니다. 좌측 상단 시계가 거의 보이지 않았습니다.
            //
            //  상태바 스타일은 SwiftUI 에서 직접 바꿀 수 없고
            //  UIViewController 를 건드려야 합니다. 그 방법은 탭 전환
            //  시점에 따라 어긋나기 쉽고, 검증하지 못한 경로입니다.
            //
            //  대신 지도 위 상단에 아주 옅은 scrim 을 깝니다.
            //  흰 글자가 읽히고, 바로 아래 검은 검색바와 이어져서
            //  띠가 따로 보이지 않습니다. 앱에 이미 있는
            //  vfTopControlScrim(사진 위 컨트롤 보호용)과 같은 도구입니다.
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
                    onSelectSpot(spot)
                },
                onDeselect: { focusedSpotID = nil }
            )
            .ignoresSafeArea()
            .vfTopControlScrim(height: 108)
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 8) {
                // ═══════════════════════════════════════════════════
                //  상단은 컨트롤, 하단은 지금 상황.
                //
                //  상태 pill 을 아래로 내렸습니다.
                //  검색바를 넣으면 상단이 검색 + 칩 + 상태 3줄이 되는데,
                //  상단 복잡함은 이미 한 번 지적받은 문제입니다.
                //  상태 pill 은 조작하는 것이 아니라 읽는 것이므로
                //  카드가 나타나는 자리(하단)가 제자리입니다.
                //  선택하면 그 자리를 카드가 대신합니다.
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
                        onSelect: { commitSearchSelection($0.spot) }
                    )
                } else {
                    mapControls
                }

                Spacer(minLength: 0)

                // ═══════════════════════════════════════════════════
                //  지도 컨트롤을 우측 하단 한 스택으로 모았습니다.
                //
                //  [원래 문제]
                //  내 위치 버튼은 KoreaMapBackdropView 안에서
                //  .ignoresSafeArea() 된 좌표계에 bottom 104 로 있었고,
                //  카드는 safe area 를 지키는 이 VStack 에 bottom 92 로
                //  있었습니다. 서로 다른 좌표계라 높이가 어긋났고,
                //  카드 아래에 지도가 100pt 넘게 비어 보였습니다.
                //  지금은 둘 다 이 VStack 안에 있어 카드 바로 위에 쌓입니다.
                //
                //  저장 버튼이 세 번 자리를 옮겼습니다.
                //   1차 칩 줄 끝 -> 스크롤되는 줄에 붙어 소속이 불분명하고,
                //        칩(필터)과 성격이 다른데 나란히 있었습니다.
                //   2차 검색바 옆 -> 검색바가 전체 폭을 못 쓰고, 북마크가
                //        검색 필드에 붙어 "저장한 것 안에서 검색" 으로
                //        읽혔습니다.
                //   3차 우측 하단, 내 위치 버튼 위.
                //
                //  둘 다 44pt 원형이고, 둘 다 "보는 것을 바꾸는" 컨트롤
                //  입니다. 필터도 콘텐츠도 아닙니다.
                //  지도 앱들이 이 위치에 컨트롤을 쌓는 이유이기도 합니다.
                //  엄지가 닿고, 지도 콘텐츠 위지만 상단 정보와 겹치지
                //  않습니다.
                //
                //  검색 중에는 둘 다 숨깁니다. 제안 목록이 지도를 덮고
                //  있으므로 지도를 조작할 이유가 없습니다.
                //
                //  [떠 있는 컨트롤은 내 위치 하나입니다]
                //  저장 버튼이 여기 있었고, 자리를 네 번 옮겼는데 네 번 다
                //  어색했습니다. (칩 줄 끝 → 검색바 옆 → 우하단 → 좌하단)
                //
                //  자리가 아니라 층이 문제였습니다. 저장은 핀 집합을 바꾸는
                //  필터인데, 이 층은 카메라를 움직이는 층입니다. 성격이
                //  다른 것을 억지로 끼워넣었으니 어디에 놓아도 소속이
                //  없어 보였습니다. 그래서 칩 줄로 보냈습니다.
                //  (MapSavedFilterChip 주석에 판단 근거가 있습니다.)
                //
                //  이 층에 하나만 남으니 좌우를 나눌 이유도 없어졌고,
                //  우하단은 네이버 로고를 좌하단으로 옮겨서 비워둔
                //  자리입니다. 엄지가 닿는 쪽입니다.
                // ═══════════════════════════════════════════════════
                if !isSearching {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        Button(action: onFocusUserLocation) {
                            MapCircleButton(symbolName: "location.fill", tint: AppColors.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("내 위치로 이동")
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }

                if let previewSpot {
                    Button {
                        onShowDetail(previewSpot)
                    } label: {
                        MapSelectedSpotPreview(
                            spot: previewSpot,
                            isSaved: savedSpotIDs.contains(previewSpot.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(previewSpot.name) 상세 보기")
                    // 탭바와 좌우 여백을 맞춥니다. (칩은 12, 카드·탭바는 16)
                    // 카드가 탭바보다 4pt 넓어서 두 요소가 어긋나 보였습니다.
                    .padding(.horizontal, 4)
                    // 슬라이드가 아니라 페이드로 나타납니다.
                    //
                    // [문제였던 상황]
                    // .move(edge: .bottom) 이라 카드가 화면 밖에서 탭바를 통과해
                    // 올라왔습니다. 카드를 눌러 상세 시트가 올라올 때는
                    // 시트가 위로 올라오는 동시에 카드가 아래로 빠져
                    // 두 움직임이 서로 반대 방향으로 부딪혔습니다.
                    .transition(.opacity)
                    .offset(y: cardDragY)
                    // 아래로 밀어 선택 해제. 손가락을 따라 움직이게 해서
                    // 정해진 애니메이션이 재생되는 느낌을 없앱니다.
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                cardDragY = max(0, value.translation.height * 0.7)
                            }
                            .onEnded { value in
                                if value.translation.height > 44 {
                                    focusedSpotID = nil
                                    cardDragY = 0
                                } else {
                                    withAnimation(VFMotion.quick) { cardDragY = 0 }
                                }
                            }
                    )
                } else if let statusText, !isSearching {
                    MapStatusPill(text: statusText)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            // safe area 하단에는 탭바 높이가 이미 포함되어 있습니다.
            // 여기에 92 를 더하면 카드가 탭바에서 190pt 나 떨어져
            // 화면 중간에 떠 있게 됩니다. 탭바와의 간격만 남깁니다.
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // 카드가 "있다/없다" 에만 애니메이션을 씁니다.
            // 전에는 previewSpot?.id 를 기준으로 삼아서, 핀에서 다른 핀으로
            // 옮길 때 카드가 아래로 빠지고 다시 올라왔습니다.
            // 같은 자리에 내용만 바뀌어야 하는 상황이었습니다.
            .animation(VFMotion.quick, value: previewSpot == nil)
            .animation(VFMotion.quick, value: isSearching)
            .onChange(of: previewSpot?.id) { _, _ in
                cardDragY = 0
            }
        }
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
            // 사용자가 명시적으로 그 장소를 지목한 것이므로 카드를 띄웁니다.
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

    // ═══════════════════════════════════════════════════════════════
    //  지도 상단 컨트롤
    //
    //  [문제였던 상황]
    //  칩이 두 줄이었고 컨트롤이 9개였습니다.
    //   1행: [내 주변] [저장]
    //   2행: [전체] [노을] [야경] [감성카페] [산책] [필름감성] [숨은 명소]
    //  그중 "내 주변" 과 "전체" 가 동시에 앰버로 칠해져서
    //  무엇이 선택된 상태인지 읽히지 않았습니다. 서로 다른 축(모드 / 필터)인데
    //  같은 모양의 칩으로 나란히 있어서 관계도 알 수 없었습니다.
    //
    //  [바꾼 것]
    //  1. "저장" 은 필터가 아니라 목록을 여는 이동입니다.
    //     칩에서 빼서 우측 상단 원형 버튼으로 분리했습니다.
    //  2. "내 주변" 은 이 지도의 기본 상태입니다.
    //     기본값을 칩으로 보여줄 필요가 없어 제거하고,
    //     저장 버튼을 다시 누르면 내 주변으로 돌아오는 토글로 만들었습니다.
    //  3. 그래서 칩은 카테고리 한 줄만 남았습니다. 9개 → 8개, 2줄 → 1줄.
    //  4. 저장 모드에서는 카테고리 필터가 적용되지 않으므로 줄 자체를 숨깁니다.
    //     (저장 목록 시트가 자기 카테고리 탭을 따로 갖고 있습니다.)
    // ═══════════════════════════════════════════════════════════════
    /// 지도를 거르는 모든 수단이 모인 한 줄.
    ///
    /// [저장] + 카테고리 6개. 저장이 44pt 를 쓰고 남는 폭을 카테고리
    /// 칩이 균등하게 나눕니다. 저장이 켜지면 카테고리는 사라지고
    /// 저장 칩이 줄 전체로 늘어납니다. (MapSavedFilterChip 주석 참고)
    ///
    /// ScrollView 를 없앴습니다.
    ///
    /// [문제였던 상황]
    /// 칩이 자기 글자 폭대로 크기를 정해서 6개를 더해도 325pt 였고,
    /// 오른쪽에 68pt 가 남았습니다. 검색바는 전체 폭을 쓰는데 칩 줄만
    /// 중간에서 끝나 잘린 것처럼 보였습니다.
    /// 그리고 ScrollView 가 남아 있어서, 넘치지 않는데도 손가락을 대면
    /// 줄이 미세하게 밀렸습니다.
    ///
    /// [지금]
    /// 고정 폭 HStack 안에서 각 칩이 남는 폭을 균등하게 나눕니다.
    /// 스크롤이 구조적으로 불가능하고, 마지막 칩의 오른쪽 끝이
    /// 검색바 오른쪽 끝과 맞습니다.
    ///
    /// 접근성 큰 글자는 MapFilterPill 의 minimumScaleFactor 가 받습니다.
    /// 스크롤로 넘기게 하는 것보다, 여섯 개가 항상 한눈에 보이면서
    /// 글자만 살짝 작아지는 편이 낫습니다.
    @ViewBuilder
    private var mapControls: some View {
        HStack(spacing: 6) {
            Button {
                if isMapSavedFilterEnabled {
                    onToggleRecommendations()
                } else {
                    onToggleSavedFilter()
                    isSavedListPresented = true
                }
            } label: {
                MapSavedFilterChip(isActive: isMapSavedFilterEnabled)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMapSavedFilterEnabled ? "저장 목록 끄기" : "저장한 출사지 보기")

            if !isMapSavedFilterEnabled {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MapSelectedSpotPreview: View {
    let spot: PhotoSpot
    let isSaved: Bool

    var body: some View {
        HStack(spacing: 12) {
            PhotoSpotImageView(spot: spot, symbolSize: 22)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(spot.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MapChrome.ink)
                        .lineLimit(1)

                    if isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                            .accessibilityHidden(true)
                    }
                }

                Text(HomeSpotDisplayFormatter.region(for: spot))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(MapChrome.inkDim)
                    .lineLimit(1)

                Text(HomeSpotDisplayFormatter.bestTime(spot.bestTime))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MapChrome.inkDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MapChrome.inkDim)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 유리를 쓰지 않습니다. 밝은 지도 위에서 흰 글자가 묻히기 때문입니다.
        .mapChromeSurface(RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous))
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
                ForEach(SavedMapListFilter.allCases) { filter in
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFocused || !query.isEmpty ? MapChrome.ink : MapChrome.inkDim)

            TextField(
                "",
                text: $query,
                prompt: Text("장소 · 지역 검색")
                    .foregroundColor(MapChrome.inkDim)
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(MapChrome.ink)
            .tint(AppColors.accent)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isFocused)
            .onSubmit(onSubmit)

            if !query.isEmpty {
                Button {
                    query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(MapChrome.inkDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        // 밝은 지도 위이므로 유리를 쓰지 않습니다. 칩과 같은 표면입니다.
        .mapChromeSurface(Capsule())
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

                // 검색해서 없다는 것은 그 장소를 아는 사람이 지금 화면
                // 앞에 있다는 뜻입니다. 제보를 권하기 좋은 순간입니다.
                Text("알고 계신 곳이라면 ＋ 새 장소로 알려주세요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MapChrome.inkDim)
                    .padding(.top, 2)
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

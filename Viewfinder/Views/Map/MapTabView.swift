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
    @State private var isSearchPresented = false

    private var previewSpot: PhotoSpot? {
        guard let focusedSpotID else { return nil }
        return spots.first { $0.id == focusedSpotID }
    }

    private var statusText: String? {
        if isRecommendationLoading {
            return "주변 출사지 찾는 중"
        }
        if let emptyRecommendationMessage {
            return emptyRecommendationMessage
        }
        guard !spots.isEmpty else { return nil }
        if isMapSavedFilterEnabled {
            return "저장한 출사지 \(spots.count)곳"
        }
        // "이 지역" 이라고 말하지 않습니다.
        // 핀은 지도에 보이는 영역이 아니라 "내 위치" 기준으로 계산됩니다.
        // 지도를 부산으로 끌어도 핀은 서울 것 그대로입니다.
        // 영역 기준 재검색을 넣기 전까지는 문구가 사실을 말해야 합니다.
        return "내 주변 출사지 \(spots.count)곳"
    }

    /// 핀이 많으면 겹침 때문에 일부가 숨습니다. 그 차이를 설명합니다.
    /// 12곳은 기본 줌(12.2)에서 54pt 핀이 서로 붙기 시작하는 대략의 개수입니다.
    private var statusHint: String? {
        guard !isRecommendationLoading,
              emptyRecommendationMessage == nil,
              spots.count >= 12
        else { return nil }

        return "확대하면 더 보여요"
    }

    var body: some View {
        ZStack {
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
                MapSearchBar { isSearchPresented = true }
                    // 저장 목록 시트가 이미 ZStack 에 붙어 있습니다.
                    // 같은 뷰에 .sheet 를 두 개 달면 한쪽이 무시될 수 있어
                    // 검색 시트는 검색바에 직접 붙입니다.
                    .sheet(isPresented: $isSearchPresented) {
                        MapSearchSheet(
                            spots: searchableSpots,
                            userCoordinate: userCoordinate,
                            onSelect: { spot in
                                isSearchPresented = false
                                // 시트가 닫히는 동안 카메라를 움직이면
                                // 두 애니메이션이 겹쳐 어색합니다.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    onSelectSearchResult(spot)
                                }
                            }
                        )
                    }

                mapControls

                Spacer(minLength: 0)

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
                } else if let statusText {
                    MapStatusPill(text: statusText, hint: statusHint)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // 카드가 "있다/없다" 에만 애니메이션을 씁니다.
            // 전에는 previewSpot?.id 를 기준으로 삼아서, 핀에서 다른 핀으로
            // 옮길 때 카드가 아래로 빠지고 다시 올라왔습니다.
            // 같은 자리에 내용만 바뀌어야 하는 상황이었습니다.
            .animation(VFMotion.quick, value: previewSpot == nil)
            .onChange(of: previewSpot?.id) { _, _ in
                cardDragY = 0
            }
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
    private var mapControls: some View {
        HStack(alignment: .top, spacing: 10) {
            if isMapSavedFilterEnabled {
                Spacer(minLength: 0)
            } else {
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
                    .padding(.trailing, 6)
                }
            }

            Button {
                if isMapSavedFilterEnabled {
                    onToggleRecommendations()
                } else {
                    onToggleSavedFilter()
                    isSavedListPresented = true
                }
            } label: {
                MapCircleButton(
                    symbolName: isMapSavedFilterEnabled ? "bookmark.fill" : "bookmark",
                    isActive: isMapSavedFilterEnabled
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMapSavedFilterEnabled ? "저장 목록 끄기" : "저장한 출사지 보기")
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
//  "성수동 가려는데 출사지 뭐 있지?" 를 지도에서 할 방법이 없어서,
//  홈으로 나가 검색하고 상세로 들어가 "지도에서 보기" 를 눌러야 했습니다.
//  지도야말로 장소를 찾는 화면인데 진입점이 칩과 핀뿐이었습니다.
//
//  [홈 검색을 재사용하지 않은 이유]
//  HomeSearchResultsView 는 검색 뷰모델·AI 추천·커뮤니티 글까지
//  묶여 있습니다. 지도에서 필요한 것은 "장소를 찾아 그리로 이동" 하나입니다.
//  네트워크도 AI 도 필요하지 않고, 앱이 이미 아는 장소만 훑으면 됩니다.
//  기능을 덜 넣는 쪽이 지도의 목적에 맞습니다.
// ═══════════════════════════════════════════════════════════════════

struct MapSearchBar: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))

                Text("장소 · 지역 검색")
                    .font(.system(size: 14, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(MapChrome.ink)
            .padding(.horizontal, 14)
            .frame(height: 44)
            // 밝은 지도 위이므로 유리를 쓰지 않습니다. 칩과 같은 표면입니다.
            .mapChromeSurface(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("장소 또는 지역 검색")
    }
}

struct MapSearchSheet: View {
    let spots: [PhotoSpot]
    let userCoordinate: CLLocationCoordinate2D?
    let onSelect: (PhotoSpot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 이름 · 지역 · 지도 질의 · 추천 지역만 봅니다.
    ///
    /// summary(설명문)와 hashtags 는 일부러 뺐습니다.
    /// 넣으면 "한강" 으로 검색했을 때 설명에 한강이 언급된 카페가
    /// 한강공원보다 위에 올 수 있습니다.
    /// 장소를 찾는 검색에서는 무엇에 매칭됐는지가 예측 가능해야 합니다.
    private var results: [PhotoSpot] {
        guard !trimmedQuery.isEmpty else { return [] }

        let matched = spots.filter { spot in
            let fields = [spot.name, spot.region, spot.mapQuery] + spot.recommendationRegions
            return fields.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }

        guard let userCoordinate else {
            return matched.sorted { $0.name < $1.name }
        }

        return matched.sorted {
            VFSpotDistance.meters(from: userCoordinate, to: $0)
                < VFSpotDistance.meters(from: userCoordinate, to: $1)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                if trimmedQuery.isEmpty {
                    hintState
                } else if results.isEmpty {
                    emptyState
                } else {
                    resultList
                }
            }
            .background(AppColors.background)
            .navigationTitle("장소 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
        .onAppear {
            // 검색 시트를 열었다는 것은 이미 검색할 의사가 있다는 뜻입니다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isFocused = true
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)

            TextField("성수, 한강, 남산…", text: $query)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(AppColors.mutedSurface, in: Capsule())
        .padding(.horizontal, VFSpace.screenMargin)
        .padding(.top, VFSpace.sm)
        .padding(.bottom, VFSpace.md)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { spot in
                    Button {
                        onSelect(spot)
                    } label: {
                        MapSearchResultRow(spot: spot, userCoordinate: userCoordinate)
                    }
                    .buttonStyle(.plain)

                    if spot.id != results.last?.id {
                        Divider()
                            .overlay(AppColors.divider)
                            .padding(.leading, VFSpace.screenMargin + 62)
                    }
                }
            }
            .padding(.bottom, VFSpace.xl)
        }
    }

    private var hintState: some View {
        VStack(spacing: VFSpace.sm) {
            Spacer()

            Text("지역이나 장소 이름으로 찾아보세요")
                .vfText(.callout)
                .foregroundStyle(AppColors.secondaryText)

            Text("\(spots.count)곳을 검색합니다")
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText.opacity(0.7))

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: VFSpace.sm) {
            Spacer()

            Text("‘\(trimmedQuery)’ 결과가 없어요")
                .vfText(.headline)
                .foregroundStyle(AppColors.primary)

            // 여기서 제보를 권하는 것이 맞습니다.
            // 검색해서 없다는 것은 그 장소를 아는 사람이 지금 화면 앞에
              // 있다는 뜻입니다. 다만 탭바 중앙 "새 장소" 로 가는 안내만
            // 하고, 이 시트에서 제보 폼을 바로 띄우지는 않습니다.
            // 검색 흐름 위에 등록 흐름을 겹치면 되돌아올 자리가 없어집니다.
            Text("알고 계신 곳이라면 탭바의 ＋ 새 장소로 알려주세요")
                .vfText(.subhead)
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, VFSpace.screenMargin)
    }
}

private struct MapSearchResultRow: View {
    let spot: PhotoSpot
    let userCoordinate: CLLocationCoordinate2D?

    var body: some View {
        HStack(spacing: 12) {
            PhotoSpotImageView(spot: spot, symbolSize: 18)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.tile, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(spot.name)
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(HomeSpotDisplayFormatter.region(for: spot))
                        .lineLimit(1)

                    if let distance = VFSpotDistance.text(from: userCoordinate, to: spot) {
                        Text("·")
                        Text(distance)
                    }
                }
                .vfText(.caption)
                .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, VFSpace.screenMargin)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

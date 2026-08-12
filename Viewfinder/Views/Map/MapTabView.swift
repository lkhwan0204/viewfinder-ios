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
                mapControls

                if let statusText {
                    MapStatusPill(text: statusText)
                }

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

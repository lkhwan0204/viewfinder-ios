import CoreLocation
import SwiftUI

enum SavedMapListFilter: String, CaseIterable, Identifiable {
    case all
    case sunset
    case cafe
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

    var body: some View {
        ZStack(alignment: .top) {
            KoreaMapBackdropView(
                spots: spots,
                selectedSpot: selectedSpot,
                selectedSpotRevision: selectedSpotRevision,
                focusUserLocationRevision: focusUserLocationRevision,
                userCoordinate: userCoordinate,
                savedSpotIDs: savedSpotIDs,
                onSelectSpot: onSelectSpot,
                onShowDetail: onShowDetail
            )
            .ignoresSafeArea()

            HStack(spacing: 7) {
                Button(action: onToggleRecommendations) {
                    MapFilterPill(
                        title: isRecommendationLoading ? "주변 출사지 로딩" : "추천",
                        symbolName: "sparkles",
                        isSelected: shouldShowNearbyMapPins,
                        isLoading: isRecommendationLoading
                    )
                }
                .buttonStyle(.plain)

                Button(action: onToggleSavedFilter) {
                    MapFilterPill(
                        title: "저장",
                        symbolName: isMapSavedFilterEnabled ? "bookmark.fill" : "bookmark",
                        isSelected: isMapSavedFilterEnabled
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(MapCategoryFilter.allCases) { filter in
                        Button {
                            onSelectCategory(filter)
                        } label: {
                            if filter == mapCategoryFilter {
                                Label(filter.title, systemImage: "checkmark")
                            } else {
                                Text(filter.title)
                            }
                        }
                    }
                } label: {
                    MapFilterPill(
                        title: "테마: \(mapCategoryFilter.title)",
                        symbolName: "line.3.horizontal.decrease.circle",
                        isSelected: mapCategoryFilter != .all
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let emptyRecommendationMessage {
                VStack {
                    Spacer()

                    Text(emptyRecommendationMessage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(AppColors.cardBackground, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(AppColors.divider, lineWidth: 1)
                        )
                        .padding(.bottom, 96)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }

            if isSavedListPresented {
                SavedMapBottomSheetHost(
                    isPresented: $isSavedListPresented,
                    selectedFilter: $savedListFilter,
                    savedSpots: savedSpots,
                    userCoordinate: userCoordinate,
                    onSelectFilter: onSelectSavedCategory,
                    onSelectSpot: onSelectSavedSpot
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(5)
            }
        }
    }
}

private enum SavedMapSheetLevel {
    case collapsed
    case expanded
}

private struct SavedMapBottomSheetHost: View {
    @Binding var isPresented: Bool
    @Binding var selectedFilter: SavedMapListFilter
    let savedSpots: [PhotoSpot]
    let userCoordinate: CLLocationCoordinate2D?
    let onSelectFilter: (SavedMapListFilter) -> Void
    let onSelectSpot: (PhotoSpot) -> Void
    @State private var level: SavedMapSheetLevel = .collapsed
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let collapsedHeight = max(292, proxy.size.height * 0.36)
            let expandedHeight = max(collapsedHeight, proxy.size.height * 0.68)
            let sheetHeight = level == .expanded ? expandedHeight : collapsedHeight

            VStack {
                Spacer(minLength: 0)

                SavedMapBottomSheetView(
                    selectedFilter: $selectedFilter,
                    savedSpots: savedSpots,
                    userCoordinate: userCoordinate,
                    onSelectFilter: onSelectFilter,
                    onSelectSpot: onSelectSpot
                )
                .frame(height: sheetHeight)
                .offset(y: max(0, dragOffset))
                .gesture(sheetDragGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.88), value: level)
            .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.88), value: isPresented)
        }
        .onChange(of: isPresented) { _, newValue in
            if newValue {
                level = .collapsed
            }
        }
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                state = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height < -46 {
                    level = .expanded
                } else if value.translation.height > 82 {
                    if level == .expanded {
                        level = .collapsed
                    } else {
                        isPresented = false
                    }
                }
            }
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
            handle
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
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: -2)
    }

    private var handle: some View {
        Capsule()
            .fill(AppColors.secondaryText.opacity(0.28))
            .frame(width: 42, height: 5)
            .padding(.top, 9)
            .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedFilter.headerTitle)
                    .font(.system(size: 22, weight: .bold))
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

            Button {
            } label: {
                Text("편집")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(height: 38)
                    .padding(.horizontal, 13)
                    .background(AppColors.mutedSurface, in: Capsule())
            }
            .buttonStyle(.plain)
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

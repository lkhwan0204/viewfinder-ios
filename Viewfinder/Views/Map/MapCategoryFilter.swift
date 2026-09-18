import Foundation
import SwiftUI

enum MapCategoryFilter: String, CaseIterable, Identifiable {
    case all

    // 홈과 지도가 같은 장소 분류를 사용하도록 PhotoSpot.theme과 1:1로 대응합니다.
    case cityArchitecture
    case landscape
    case retroAlley
    case historyTradition
    case viewpoint
    case cafeIndoor

    // 기존 호출부와 이전 상태값을 위한 레거시 케이스입니다.
    // 지도 상단 칩에는 노출하지 않습니다.
    case sunset
    case night
    case cafe
    case park
    case walk
    case film
    case hidden

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
        case .night:
            return "야경"
        case .cafe:
            return "카페"
        case .park:
            return "공원"
        case .walk:
            return "산책"
        case .film:
            return "필름감성"
        case .hidden:
            return "숨은 명소"
        }
    }

    /// 지도 상단에 실제로 노출하는 필터입니다.
    /// `전체`는 테마가 아니라 전체 핀으로 돌아가는 지도 전용 리셋입니다.
    static let mapDisplayed: [MapCategoryFilter] = [
        .all,
        .cityArchitecture,
        .landscape,
        .retroAlley,
        .historyTradition,
        .viewpoint,
        .cafeIndoor
    ]

    /// canonical theme 필터인지 여부입니다. 레거시 필터는 호환용으로만 남깁니다.
    var theme: SpotTheme? {
        switch self {
        case .cityArchitecture:
            return .cityArchitecture
        case .landscape:
            return .landscape
        case .retroAlley:
            return .retroAlley
        case .historyTradition:
            return .historyTradition
        case .viewpoint:
            return .viewpoint
        case .cafeIndoor:
            return .cafeIndoor
        default:
            return nil
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .cityArchitecture:
            return "building.2.fill"
        case .landscape:
            return "leaf.fill"
        case .retroAlley:
            return "signpost.right.fill"
        case .historyTradition:
            return "building.columns.fill"
        case .viewpoint:
            return "binoculars.fill"
        case .cafeIndoor:
            return "house.fill"
        case .sunset:
            return "sunset.fill"
        case .night:
            return "moon.stars.fill"
        case .cafe:
            return "cup.and.saucer.fill"
        case .park:
            return "tree.fill"
        case .walk:
            return "figure.walk"
        case .film:
            return "film.fill"
        case .hidden:
            return "sparkles"
        }
    }

    func matches(_ spot: PhotoSpot) -> Bool {
        guard !RecommendationBlacklist.isBlacklistedRecommendation(spot) else {
            return false
        }

        switch self {
        case .all:
            return true
        case .cityArchitecture, .landscape, .retroAlley,
             .historyTradition, .viewpoint, .cafeIndoor:
            return spot.theme == theme
        case .sunset:
            return containsAny(spot.mood, keywords: ["노을", "sunset", "해질녘", "블루아워"])
                || containsAny(spot.hashtags, keywords: ["노을", "sunset", "해질녘", "남산타워뷰", "서울시티뷰"])
        case .night:
            return containsAny(spot.mood, keywords: ["야경", "night", "밤", "블루아워"])
                || containsAny(spot.hashtags, keywords: ["야경", "night", "밤", "한강야경", "도심야경"])
        case .cafe:
            return CafeRecommendationPolicy.isIndependentCafeCandidate(spot)
        case .park:
            return normalized(spot.category) == "park"
        case .walk:
            return ["walk", "trail"].contains(normalized(spot.category))
        case .film:
            let strongFilmSignals = ["필름", "레트로", "빈티지", "골목감성", "오래된거리", "로컬감성", "철도출사", "서울철도", "필름무드"]
            return !isGenericAlleyCandidate(spot)
                && (
                    containsAny(spot.mood, keywords: strongFilmSignals)
                    || containsAny(spot.hashtags, keywords: strongFilmSignals)
                )
        case .hidden:
            return normalized(spot.crowdLevelCode) == "low"
                && !isOverexposedOrCrowded(spot)
        }
    }

    private func isOverexposedOrCrowded(_ spot: PhotoSpot) -> Bool {
        if RecommendationBlacklist.isBlacklistedRecommendation(spot) {
            return true
        }

        let blacklist = [
            "남산타워", "경복궁", "롯데월드타워", "명동", "스타벅스",
            "두물머리", "일산호수공원", "고척스카이돔", "오류동역"
        ]
        let searchable = ([spot.name, spot.region, spot.summary, spot.bestTime, spot.crowdLevelCode]
            + spot.hashtags
            + spot.mood
            + spot.recommendationRegions)
            .joined(separator: " ")

        return containsAny(searchable, keywords: blacklist)
            || normalized(spot.crowdLevelCode) == "crowded"
            || containsAny(searchable, keywords: ["혼잡", "붐빔", "SNS핫플", "초대형핫플"])
    }

    private func isGenericAlleyCandidate(_ spot: PhotoSpot) -> Bool {
        if RecommendationBlacklist.isBlacklistedRecommendation(spot) {
            return true
        }

        let searchable = ([spot.name, spot.region, spot.summary]
            + spot.hashtags
            + spot.mood)
            .joined(separator: " ")

        return containsAny(searchable, keywords: ["역주변골목", "역 주변 골목", "일반주택가", "일반 주택가"])
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func containsAny(_ value: String, keywords: [String]) -> Bool {
        let normalizedValue = normalized(value)
        return keywords.contains { normalizedValue.localizedCaseInsensitiveContains($0) }
    }

    private func containsAny(_ values: [String], keywords: [String]) -> Bool {
        values.contains { containsAny($0, keywords: keywords) }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 지도 크롬 표면
//
//  [문제였던 상황]
//  지도 위 컨트롤에 .ultraThinMaterial(유리)을 썼습니다.
//  홈/상세는 검정 캔버스 위라서 유리가 잘 보였지만,
//  지도는 밝고 복잡합니다. 지하철 노선(빨강/초록/보라), POI 라벨,
//  도로가 유리 뒤에서 그대로 비쳐서 칩 글자가 배경에 묻혔습니다.
//  → 사용자 피드백: "시인성이 너무 안좋아"
//
//  [원칙]
//  지도 위에서는 유리를 쓰지 않습니다.
//  뒤에 무엇이 오든 대비가 고정되는 불투명 표면을 씁니다.
//  라이트에서는 흰 표면 + 검정 글자, 다크에서는 다크 표면 + 흰 글자로
//  지도 타일과 같은 모드에 속하게 하되 사진 핀·도로·POI 위에서도 읽힙니다.
//
//  선택 상태만 브랜드 앰버로 칠하고, 그 위 글자는 onAccent(거의 검정)입니다.
// ═══════════════════════════════════════════════════════════════════

enum MapChrome {
    // 0.94만 남겨 지도 위 컨트롤의 경계를 살리되, 뒤 타일의 라벨이
    // 글자와 섞이지 않도록 불투명에 가깝게 둡니다.
    static let surface = Color(uiColor: VFPalette.mapChrome).opacity(0.94)
    /// 검색 제안처럼 목록을 담는 면. 글을 여러 줄 읽어야 하므로
    /// 컨트롤보다 더 불투명하게 만들어 지도가 비치지 않게 합니다.
    static let panel = Color(uiColor: VFPalette.mapChrome).opacity(0.97)
    static let hairline = Color(uiColor: VFPalette.separator)
    static let ink = Color(uiColor: VFPalette.ink1)
    static let inkDim = Color(uiColor: VFPalette.ink2)
    static let controlHeight: CGFloat = 38
    static let circleSize: CGFloat = 44
}

extension View {
    /// 지도 위에 놓이는 모든 컨트롤의 공통 표면.
    func mapChromeSurface<S: Shape>(_ shape: S, isActive: Bool = false) -> some View {
        // 그림자를 없앴습니다.
        //
        // 처음에는 유리(.ultraThinMaterial) 칩이 밝은 지도에 묻히는 것을
        // 막으려고 그림자를 넣었습니다. 그 뒤 표면을 불투명 #1C1C1F 로
        // 바꾸면서 대비는 표면 자체가 확보하게 됐고, 그림자는 칩마다
        // 옅은 얼룩을 남기는 역할만 하게 됐습니다.
        //
        // 칩이 여섯 개 나란히 있으면 그림자도 여섯 개입니다.
        // 지도 위에 흐릿한 띠가 생겨 보입니다.
        self
            .background(isActive ? AppColors.accent : MapChrome.surface, in: shape)
            .overlay(
                shape.stroke(isActive ? Color.clear : MapChrome.hairline, lineWidth: 0.5)
            )
    }
}

/// 지도 상단의 canonical 테마 필터 칩.
///
/// 장소명 기반의 intrinsic width를 사용하고, MapTabView의 horizontal rail에서
/// 길이가 긴 테마명도 잘리지 않게 탐색합니다. 세로 여백으로 44pt 터치 영역을
/// 확보하되, 칩 자체는 지도 위에서 보조 탐색으로 읽히도록 낮게 유지합니다.
struct MapFilterPill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? AppColors.onAccent : MapChrome.ink)
            .padding(.horizontal, 12)
            .frame(minWidth: 44)
            .frame(height: MapChrome.controlHeight)
            .mapChromeSurface(Capsule(), isActive: isSelected)
            // 칩 자체는 38pt 지만 위아래 3pt 를 더해 44pt 터치 타겟을 만듭니다.
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

/// 지도 위 원형 아이콘 버튼. (내 위치)
struct MapCircleButton: View {
    let symbolName: String
    var isActive = false
    /// 아이콘 색을 따로 지정할 때. (내 위치 버튼은 앰버 화살표)
    /// 이 뷰가 내부에서 foregroundStyle 을 정하므로
    /// 바깥에서 .foregroundStyle 을 걸어도 덮어쓰지 못합니다.
    var tint: Color?

    private var iconColor: Color {
        if let tint { return tint }
        return isActive ? AppColors.onAccent : MapChrome.ink
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: MapChrome.circleSize, height: MapChrome.circleSize)
            .mapChromeSurface(Circle(), isActive: isActive)
            .contentShape(Circle())
            .animation(.easeInOut(duration: 0.16), value: isActive)
    }
}

/// 지도 상태 한 줄. 결과가 없거나 찾는 중일 때만 나타납니다.
struct MapStatusPill: View {
    let text: String

    var body: some View {
        // 칩 줄보다 한 단계 작게 만들어 아래 계층으로 읽히게 합니다.
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(MapChrome.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .mapChromeSurface(Capsule())
    }
}

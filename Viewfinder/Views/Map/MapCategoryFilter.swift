import Foundation
import SwiftUI

enum MapCategoryFilter: String, CaseIterable, Identifiable {
    case all
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

    /// 지도 상단 칩에 실제로 노출하는 카테고리.
    ///
    /// 7개를 모두 칩으로 깔면 화면 가로를 검은 띠가 가로지르고,
    /// 마지막 칩이 저장 버튼에 붙어 잘립니다.
    /// 5개로 줄이면 스크롤 없이 한 줄에 들어옵니다.
    ///
    /// 빼는 기준은 "칩이 약속한 결과를 지킬 수 있는가" 입니다.
    ///  - `hidden`("숨은 명소")은 crowdLevelCode == "low" 라는 시드 값에 의존합니다.
    ///    그 필드는 근거가 없어서 이미 상세/홈에서 노출을 중단하고
    ///    "현장 정보 없음"으로 바꾼 데이터입니다.
    ///    같은 값을 필터의 기준으로 쓰는 것은 앞뒤가 맞지 않습니다.
    ///  - `film`("필름감성")은 해시태그 키워드 스캔이라 결과가 들쭉날쭉합니다.
    ///
    /// 두 case 는 enum 에 남겨둡니다. SavedMapListFilter 가 판정 로직을 위임하고 있습니다.
    static let mapDisplayed: [MapCategoryFilter] = [.all, .cafe, .park, .walk, .sunset, .night]

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
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
        case .sunset:
            return containsAny(spot.bestTime, keywords: ["노을", "sunset", "해질녘", "블루아워"])
                || containsAny(spot.hashtags, keywords: ["노을", "sunset", "해질녘", "남산타워뷰", "서울시티뷰"])
        case .night:
            return containsAny(spot.bestTime, keywords: ["야경", "night", "밤", "블루아워"])
                || containsAny(spot.hashtags, keywords: ["야경", "night", "밤", "한강야경", "도심야경"])
        case .cafe:
            return CafeRecommendationPolicy.isIndependentCafeCandidate(spot)
        case .park:
            // 시드 데이터의 큐레이션된 category 필드를 그대로 씁니다.
            // 키워드 추측이 아니라 등록 시 정해진 값입니다.
            return normalized(spot.category) == "park"
        case .walk:
            // park 를 뺐습니다.
            //
            // [문제였던 상황]
            // "산책" 하나가 park + walk + trail 을 전부 삼켜서
            // 131곳 중 66곳(50%)을 반환했습니다.
            // 절반을 반환하는 필터는 좁혀주는 일을 하지 않습니다.
            // 그리고 공원 35곳이 "산책" 안에 숨어 필터로 꺼낼 수 없었습니다.
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
//  뒤에 무엇이 오든 대비가 고정되는 불투명 검정 + 흰 글자를 씁니다.
//  지도는 앱 모드와 무관하게 항상 밝으므로,
//  라이트/다크 분기 없이 한 가지 규칙만 유지합니다.
//
//  선택 상태만 브랜드 앰버로 칠하고, 그 위 글자는 onAccent(거의 검정)입니다.
// ═══════════════════════════════════════════════════════════════════

enum MapChrome {
    static let surface = Color.black.opacity(0.74)
    static let hairline = Color.white.opacity(0.16)
    static let ink = Color.white
    static let inkDim = Color.white.opacity(0.64)
    static let controlHeight: CGFloat = 38
    static let circleSize: CGFloat = 44
}

extension View {
    /// 지도 위에 놓이는 모든 컨트롤의 공통 표면.
    func mapChromeSurface<S: Shape>(_ shape: S, isActive: Bool = false) -> some View {
        self
            .background(isActive ? AppColors.accent : MapChrome.surface, in: shape)
            .overlay(
                shape.stroke(isActive ? Color.clear : MapChrome.hairline, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.24), radius: 8, y: 2)
    }
}

/// 카테고리 필터 칩.
///
/// 아이콘을 뺐습니다. 7개 카테고리에 각각 아이콘을 붙이니
/// 칩 폭이 넓어져 한 화면에 3개밖에 안 들어왔고,
/// 12pt bold 글자 옆 아이콘이 시각적 소음만 늘렸습니다.
/// 글자만 남기면 같은 폭에 5개가 들어오고 훨씬 읽기 쉽습니다.
struct MapFilterPill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isSelected ? AppColors.onAccent : MapChrome.ink)
            .padding(.horizontal, 13)
            .frame(height: MapChrome.controlHeight)
            .mapChromeSurface(Capsule(), isActive: isSelected)
            // 칩 자체는 38pt 지만 위아래 3pt 를 더해 44pt 터치 타겟을 만듭니다.
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

/// 지도 위 원형 아이콘 버튼. (저장 목록, 내 위치)
struct MapCircleButton: View {
    let symbolName: String
    var isActive = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isActive ? AppColors.onAccent : MapChrome.ink)
            .frame(width: MapChrome.circleSize, height: MapChrome.circleSize)
            .mapChromeSurface(Circle(), isActive: isActive)
            .contentShape(Circle())
            .animation(.easeInOut(duration: 0.16), value: isActive)
    }
}

/// 지도 상태 한 줄. 핀이 몇 개인지 / 왜 비었는지 알려줍니다.
struct MapStatusPill: View {
    let text: String

    var body: some View {
        // 칩 줄 바로 아래에 또 검은 캡슐이 오므로,
        // 한 단계 작게 만들어 칩보다 아래 계층으로 읽히게 합니다.
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(MapChrome.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .mapChromeSurface(Capsule())
    }
}

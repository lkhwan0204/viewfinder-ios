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
        // ═══════════════════════════════════════════════════════
        //  bestTime 을 판정에서 뺐습니다.
        //
        //  [문제였던 상황]
        //  "노을" 칩이 131곳 중 58곳(44%)을 반환했습니다.
        //  절반을 반환하는 필터는 좁혀주는 일을 하지 않습니다.
        //  "산책" 칩이 park+walk+trail 을 다 삼켜 50% 를 반환했던 것과
        //  같은 문제입니다.
        //
        //  원인은 bestTime 이었습니다. bestTime 만으로도 57곳(43%)이
        //  걸립니다. 대부분의 출사지가 "오후 늦은 빛, 해질녘" 처럼
        //  적혀 있기 때문입니다.
        //
        //  bestTime 은 "언제 가면 좋은가" 라는 방문 안내입니다.
        //  늦은 오후 빛이 대체로 좋으니 거의 모든 장소에 들어갑니다.
        //  그래서 이 필터는 "노을이 좋은 곳" 이 아니라
        //  "해질녘에 가도 되는 곳" 을 뜻하게 되어 있었습니다.
        //
        //  [지금]
        //  mood 와 tags 만 봅니다. 둘은 등록할 때 그 장소의 성격으로
        //  붙이는 값입니다. 누군가 이 장소를 노을 명소로 분류했다는
        //  뜻이므로 필터의 근거가 됩니다.
        //
        //  검증 (시드 131곳)
        //    노을  58곳(44%) -> 30곳(22%)
        //    야경  27곳(20%) -> 24곳(18%)
        //  여섯 칩이 18~32% 구간에 고르게 들어옵니다.
        // ═══════════════════════════════════════════════════════
        case .sunset:
            return containsAny(spot.mood, keywords: ["노을", "sunset", "해질녘", "블루아워"])
                || containsAny(spot.hashtags, keywords: ["노을", "sunset", "해질녘", "남산타워뷰", "서울시티뷰"])
        case .night:
            return containsAny(spot.mood, keywords: ["야경", "night", "밤", "블루아워"])
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
    // ═══════════════════════════════════════════════════════════════
    //  탭바와 같은 색으로 맞췄습니다.
    //
    //  [문제였던 상황]
    //  지도 컨트롤은 black.opacity(0.74) 였습니다. 밝은 지도 위에서는
    //  진한 회색으로 보이는데, 탭바는 iOS 26 플로팅 유리라 지도 색을
    //  따라 밝아집니다. 그래서 지도 탭에서만 상단 컨트롤은 검정,
    //  하단 탭바는 밝은 회색이 되어 두 개가 다른 시스템처럼 보였습니다.
    //  (다른 탭은 배경이 검정이라 탭바도 어두워서 문제가 없었습니다.)
    //
    //  [지금]
    //  VFPalette.mapChrome(#1C1C1F)로 고정합니다.
    //  이 값은 surface2 의 다크 값이고, 탭바 배경도 같은 값으로
    //  맞췄습니다. 두 크롬이 같은 색이 됩니다.
    //
    //  0.94 로 살짝 투명도를 남긴 이유는, 완전 불투명이면 지도 위에
    //  붙은 판처럼 보이고 떠 있는 느낌이 사라지기 때문입니다.
    // ═══════════════════════════════════════════════════════════════
    static let surface = Color(uiColor: VFPalette.mapChrome).opacity(0.94)
    /// 검색 제안처럼 목록을 담는 면. 글을 여러 줄 읽어야 하므로
    /// 컨트롤보다 더 불투명하게 만들어 지도가 비치지 않게 합니다.
    static let panel = Color(uiColor: VFPalette.mapChrome).opacity(0.97)
    static let hairline = Color.white.opacity(0.16)
    static let ink = Color.white
    static let inkDim = Color.white.opacity(0.64)
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

/// 카테고리 필터 칩.
///
/// 아이콘을 뺐습니다. 7개 카테고리에 각각 아이콘을 붙이니
/// 칩 폭이 넓어져 한 화면에 3개밖에 안 들어왔고,
/// 12pt bold 글자 옆 아이콘이 시각적 소음만 늘렸습니다.
/// 글자만 남기면 같은 폭에 5개가 들어오고 훨씬 읽기 쉽습니다.
///
/// ═══════════════════════════════════════════════════════════════
///  칩이 줄을 균등하게 나눠 씁니다.
///
///  [문제였던 상황]
///  칩은 글자 폭 + 좌우 13pt 로 자기 크기를 정했습니다.
///  6개를 더해도 325pt 라서 393pt 화면에 68pt 가 남았습니다.
///  검색바는 전체 폭을 쓰는데 그 바로 아래 칩 줄만 오른쪽에서
///  끝나 있어서, 줄이 잘렸거나 칩 하나가 빠진 것처럼 보였습니다.
///  → 사용자 피드백: "필터 맨 오른쪽이 공백이라 어색하고"
///
///  [지금]
///  각 칩이 `maxWidth: .infinity` 로 남는 폭을 똑같이 나눕니다.
///  마지막 칩의 오른쪽 끝이 검색바 오른쪽 끝과 맞습니다.
///
///  이 방식이 성립하는 이유는 노출하는 6개 라벨이
///  전체·카페·공원·산책·노을·야경 으로 전부 두 글자라는 데 있습니다.
///  글자 수가 같으므로 균등 분할이 곧 균등한 시각 무게가 됩니다.
///  (길이가 다른 "필름감성"·"숨은 명소"는 mapDisplayed 에서 빠져 있습니다.)
///
///  좌우 여백을 13 → 6 으로 줄인 것은 최소값의 의미입니다.
///  실제 여백은 균등 분할이 정하고, 이 값은 접근성 큰 글자에서
///  글자가 캡슐 테두리에 닿지 않게 하는 하한선입니다.
/// ═══════════════════════════════════════════════════════════════
struct MapFilterPill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            // 큰 글자 설정에서 두 글자가 균등 분할 폭을 넘으면
            // 잘리는 대신 살짝 줄여서 끝까지 읽히게 합니다.
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? AppColors.onAccent : MapChrome.ink)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: MapChrome.controlHeight)
            .mapChromeSurface(Capsule(), isActive: isSelected)
            // 칩 자체는 38pt 지만 위아래 3pt 를 더해 44pt 터치 타겟을 만듭니다.
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

// ═══════════════════════════════════════════════════════════════════
//  저장 필터 칩 — 저장 버튼의 다섯 번째이자 마지막 자리
//
//  [자리를 네 번 옮겼습니다]
//   1차 칩 줄 끝      스크롤되는 줄에 붙어 소속이 불분명
//   2차 검색바 옆     검색바가 전체 폭을 못 쓰고 "저장한 것 안에서
//                     검색" 으로 읽힘
//   3차 우측 하단     내 위치 버튼과 8pt 간격, 오조작
//   4차 좌측 하단     지도 위에 홀로 뜬 원. 아무것과도 관계가 없음
//  네 번 다 "어색하다" 는 반응이었습니다.
//
//  [진단]
//  자리가 문제가 아니라 층이 문제였습니다.
//  저장은 지도에 뿌릴 핀 집합을 바꾸는 필터입니다. 그런데 떠 있는
//  버튼 층에 있었습니다. 그 층에는 내 위치밖에 없고, 내 위치는
//  카메라를 움직이는 것이지 핀을 고르는 것이 아닙니다.
//  성격이 다른 것 하나를 억지로 그 층에 끼워넣었기 때문에,
//  어디에 놓아도 소속이 없어 보였습니다.
//
//  [지금]
//  필터니까 필터 줄로 갑니다. 칩 줄의 첫 칸입니다.
//  떠 있는 컨트롤이 하나 줄고, 지도를 거르는 모든 수단이 한 줄에
//  모입니다. 아래 떠 있는 것은 내 위치 하나뿐입니다.
//
//  1차와 같은 줄이지만 상황이 다릅니다. 1차의 실패 원인은 그 줄이
//  넘쳐서 스크롤됐다는 것이었고, 지금 칩 줄은 균등 분할이라 넘칠 수가
//  없습니다. 44pt 를 떼어주고도 카테고리 칩이 48pt 씩 남습니다.
//
//  [카테고리 칩과 구별되게 만든 방법]
//  저장은 카테고리와 다른 축입니다. 카페를 고르면 공원이 풀리지만,
//  저장은 카테고리와 동시에 성립하지 않고 아예 다른 모드입니다.
//  그래서 같은 줄에 있어도 같은 것으로 보이면 안 됩니다.
//   - 글자가 아니라 아이콘입니다. 여섯 개의 두 글자 칩 사이에서
//     혼자 기호라서 다른 종류로 읽힙니다.
//   - 켜지면 카테고리 칩이 사라지고 이 칩이 줄 전체로 늘어나며
//     "저장한 곳만" 이라고 말합니다. 모드가 바뀌었다는 것을 줄의
//     모양 자체가 알려주고, 빈 줄이 남지 않습니다.
// ═══════════════════════════════════════════════════════════════════
struct MapSavedFilterChip: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isActive ? "bookmark.fill" : "bookmark")
                .font(.system(size: 13, weight: .semibold))

            if isActive {
                Text("저장한 곳만")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(isActive ? AppColors.onAccent : MapChrome.ink)
        .padding(.horizontal, isActive ? 12 : 0)
        // 꺼져 있을 때는 44pt 고정입니다. 아이콘만 있으면 내용 폭이
        // 13pt 라서, 최소 폭을 주지 않으면 캡슐이 아이콘에 달라붙습니다.
        // 켜지면 줄 전체로 늘어납니다.
        .frame(minWidth: isActive ? nil : 44, maxWidth: isActive ? .infinity : 44)
        .frame(height: MapChrome.controlHeight)
        .mapChromeSurface(Capsule(), isActive: isActive)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.16), value: isActive)
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

//
//  VFDesign.swift
//  ViewFinder — Design System "Frame & Light"
//
//  이 파일이 ViewFinder의 디자인 기준입니다.
//  화면 코드에서 색상 / 간격 / 폰트 크기를 직접 쓰지 마세요.
//
//  3원칙
//  1. 사진은 화면의 경계를 넘어간다.        사진은 기본적으로 full-bleed
//  2. 배경은 어둡고, 조작 요소만 투명하다.   Glass는 허용된 8곳에만
//  3. 한 화면에는 주인공이 하나다.
//
//  ─────────────────────────────────────────────────────────────
//  VFPalette 가 앱 전체 색의 유일한 출처입니다.
//  AppColors 는 VFPalette 를 가리키는 별칭으로 유지됩니다.
//  (기존 152곳의 AppColors.primary 등 호출부를 건드리지 않기 위함)
//  ─────────────────────────────────────────────────────────────
//

import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════
// MARK: - Palette (단일 출처)
// ═══════════════════════════════════════════════════════════════════

enum VFPalette {

    // MARK: Canvas — 3단 표면
    // 다크에서 canvas 와 surface1 을 분리했기 때문에
    // 카드에 테두리를 그리지 않아도 카드가 읽힙니다.

    /// 루트 배경. 사진 대비를 최대화하는 순수 검정.
    static let canvas = dynamic(dark: 0x000000, light: 0xFFFFFF)
    /// 카드, 리스트 그룹 등 한 단계 올라온 표면.
    static let surface1 = dynamic(dark: 0x121214, light: 0xF5F5F7)
    /// surface1 위에 올라가는 요소. 칩, 아이콘 배경.
    static let surface2 = dynamic(dark: 0x1C1C1F, light: 0xEBEBF0)

    /// 지도 위 컨트롤 표면. 라이트/다크에 따라 바뀌지 않습니다.
    ///
    /// 네이버 지도는 앱 모드와 무관하게 항상 밝습니다.
    /// 그래서 지도 위 컨트롤은 다이내믹 컬러를 쓸 수 없습니다.
    /// surface2 를 쓰면 라이트 모드에서 밝은 회색 칩 + 흰 글자가 되어
    /// 아무것도 읽히지 않습니다.
    ///
    /// 값은 surface2 의 다크 값과 같습니다.
    /// 탭바(다크에서 surface2)와 지도 컨트롤이 같은 색으로 보이게
    /// 맞춘 것입니다.
    static let mapChrome = uiColor(hex: 0x1C1C1F)

    // MARK: Ink — 텍스트
    static let ink1 = dynamic(dark: 0xFFFFFF, light: 0x111111)
    static let ink2 = dynamic(dark: 0x98989D, light: 0x6E6E73)
    static let ink3 = dynamic(dark: 0x98989D, light: 0x6E6E73, darkAlpha: 0.62, lightAlpha: 0.70)

    /// 구분선. 아주 약하게. 기본 그룹핑 수단은 여백이다.
    static let separator = dynamic(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.09, lightAlpha: 0.10)

    // MARK: Brand — 오렌지
    //
    // 검정 + 강한 오렌지 조합입니다. (Blackmagic Design 계열의 인상)
    //
    // 이전에는 골든아워 앰버(#F0A03C)를 썼는데 두 가지 문제가 있었습니다.
    //  1. 노란기가 강해서 검정 위에서 강렬함이 부족했습니다.
    //  2. 혼잡도 "보통"(#D9A94B)과 색조가 거의 같아서, 브랜드 강조와
    //     의미 색을 구별할 수 없었습니다. 브랜드 색과 의미 색이 충돌하면
    //     시스템의 근본이 흔들립니다.
    //
    // 오렌지로 옮기면서 혼잡도는 무채색으로 내렸습니다.
    // 결과적으로 오렌지가 화면에서 유일한 컬러가 되어 강조력이 최대가 됩니다.
    //
    /// 앱의 시그니처. 화면당 2곳 이하로 아껴 쓴다.
    /// 허용: 선택된 탭 / 저장된 상태 / 선택된 칩 / 지도 핀 / 주 동작
    /// 금지: 본문 대량 사용 / 큰 면적 배경 / 사진 위 오버레이
    static let amber = dynamic(dark: 0xFF6D00, light: 0xD95A00)
    static let amberDim = dynamic(dark: 0xCC5700, light: 0xB04800)

    /// 오렌지 표면 위에 올라가는 텍스트/아이콘 색.
    ///
    /// #FF6D00 위 흰 글자는 대비가 2.8:1 로 기준 미달입니다.
    /// 어두운 잉크를 올리면 6.7:1 이 되어 통과합니다.
    /// 라이트의 오렌지(#D95A00)는 어두우므로 흰 글자가 맞습니다.
    static let onAmber = dynamic(dark: 0x150A00, light: 0xFFFFFF)

    // MARK: Semantic — 혼잡도
    //
    // 신호등 3색으로 갑니다. 혼잡도는 사용자가 가장 빨리 스캔하는 정보이고,
    // 초록/주황/빨강은 학습이 필요 없는 유일한 색 체계입니다.
    //
    // 단, 브랜드 오렌지(#FF6D00)와 섞이면 안 됩니다.
    // 그래서 색조를 의도적으로 벌려놨습니다.
    //   브랜드 오렌지  hue 약 26도 (붉은 주황)
    //   혼잡 주황      hue 약 40도 (노란 주황)  <- 확실히 더 노랗게
    //   매우혼잡 빨강  hue 약 4도  (순수 빨강)  <- 확실히 더 붉게
    //
    // 색 단독으로 정보를 전달하지는 않습니다.
    // VFCrowdBadge 가 점 개수(형태) + 라벨(텍스트)을 항상 함께 그립니다.
    static let crowdCalm = dynamic(dark: 0x46C08A, light: 0x2E8F63)
    static let crowdNormal = dynamic(dark: 0xF2B02E, light: 0xB07A10)
    static let crowdBusy = dynamic(dark: 0xF0453A, light: 0xC62A20)

    // MARK: Avatar
    //
    // 사용자별 아바타 배경. 이전에는 파랑/갈색/초록/보라/빨강/청록 6색이었습니다.
    // 검정·흰색·오렌지만 쓰는 체계에서 유채색 6개는 이질적입니다.
    // 밝기 6단계 무채색으로 바꿔 사용자 구분은 유지하고 색만 걷어냅니다.
    static let avatarTones: [UIColor] = [
        dynamic(dark: 0x2A2A2E, light: 0xE4E4E9),
        dynamic(dark: 0x35353A, light: 0xD8D8DE),
        dynamic(dark: 0x404046, light: 0xCCCCD3),
        dynamic(dark: 0x4B4B52, light: 0xC0C0C8),
        dynamic(dark: 0x56565E, light: 0xB4B4BD),
        dynamic(dark: 0x61616A, light: 0xA8A8B2)
    ]

    // MARK: 유틸리티

    static func dynamic(
        dark: UInt32,
        light: UInt32,
        darkAlpha: CGFloat = 1.0,
        lightAlpha: CGFloat = 1.0
    ) -> UIColor {
        UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return uiColor(
                hex: isDark ? dark : light,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        }
    }

    static func uiColor(hex: UInt32, alpha: CGFloat = 1.0) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Spacing (4pt base)
// ═══════════════════════════════════════════════════════════════════

enum VFSpace {
    static let xs: CGFloat = 4      // 아이콘 ↔ 라벨, 3열 타일 gutter
    static let sm: CGFloat = 8      // 사진 ↔ 캡션
    static let md: CGFloat = 12     // 2열 사진 gutter. 화면 마진보다 좁아야 한다
    static let lg: CGFloat = 20     // 화면 좌우 마진
    static let xl: CGFloat = 32     // 섹션 간 간격
    static let xxl: CGFloat = 48    // 챕터 분리

    /// 화면 좌우 마진. 사진은 이 값을 무시하고 full-bleed 해도 된다.
    static let screenMargin: CGFloat = 20

    /// 스크롤 콘텐츠 하단 여유. 탭바 뒤로 콘텐츠가 숨는 것을 막는다.
    static let scrollBottomInset: CGFloat = 12
}

extension View {
    /// 화면 좌우 마진. 사진 full-bleed 영역에는 쓰지 않는다.
    func vfScreenMargin() -> some View {
        padding(.horizontal, VFSpace.screenMargin)
    }

    /// 스크롤 뷰 하단에 탭바 여유를 준다.
    func vfScrollBottomInset() -> some View {
        safeAreaPadding(.bottom, VFSpace.scrollBottomInset)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Radius
// ═══════════════════════════════════════════════════════════════════

enum VFRadius {
    static let photo: CGFloat = 20      // 사진 카드
    static let inner: CGFloat = 12      // 사진 안 요소 (concentric)
    static let tile: CGFloat = 8        // 소형 타일
    static let pin: CGFloat = 12        // 지도 사진 핀
    // 유리 요소는 항상 capsule

    /// 항상 .continuous 를 쓴다.
    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Typography
//
//  한글은 라틴 기준 기본 tracking 으로 쓰면 헐렁해 보이므로 음수 tracking 이
//  필요하고, 어센더/디센더가 없어 행간이 좁게 느껴지므로 lineSpacing 을 준다.
// ═══════════════════════════════════════════════════════════════════

struct VFTextStyle {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let lineSpacing: CGFloat
    let relativeTo: Font.TextStyle
    let design: Font.Design
    let usesMonospacedDigit: Bool

    init(
        size: CGFloat,
        weight: Font.Weight,
        tracking: CGFloat,
        lineSpacing: CGFloat = 0,
        relativeTo: Font.TextStyle,
        design: Font.Design = .default,
        usesMonospacedDigit: Bool = false
    ) {
        self.size = size
        self.weight = weight
        self.tracking = tracking
        self.lineSpacing = lineSpacing
        self.relativeTo = relativeTo
        self.design = design
        self.usesMonospacedDigit = usesMonospacedDigit
    }

    /// Hero 사진 위 장소명. Hero 에만 사용.
    static let display = VFTextStyle(size: 40, weight: .bold, tracking: -0.8, relativeTo: .largeTitle)
    /// 섹션 헤더(주요). 화면당 1개. 아이콘과 부제를 붙이지 않는다.
    static let title1 = VFTextStyle(size: 28, weight: .bold, tracking: -0.5, lineSpacing: 2, relativeTo: .title)
    /// 섹션 헤더(보조), 사진 위 장소명.
    static let title2 = VFTextStyle(size: 22, weight: .semibold, tracking: -0.4, lineSpacing: 2, relativeTo: .title2)
    /// 카드 제목, 리스트 제목.
    static let headline = VFTextStyle(size: 17, weight: .semibold, tracking: -0.3, lineSpacing: 2, relativeTo: .headline)
    /// 본문, 촬영 팁.
    static let body = VFTextStyle(size: 16, weight: .regular, tracking: -0.2, lineSpacing: 6, relativeTo: .body)
    /// 버튼 라벨.
    static let callout = VFTextStyle(size: 15, weight: .medium, tracking: -0.2, relativeTo: .callout)
    /// 메타데이터.
    static let subhead = VFTextStyle(size: 14, weight: .regular, tracking: -0.1, lineSpacing: 2, relativeTo: .subheadline)
    /// 배지, 오버라인 라벨.
    static let caption = VFTextStyle(size: 12, weight: .medium, tracking: 0, relativeTo: .caption)
    /// 거리 / 시각 / 수치. 계기판 느낌이 이 앱의 목소리다.
    static let mono = VFTextStyle(
        size: 13,
        weight: .medium,
        tracking: 0.2,
        relativeTo: .footnote,
        design: .rounded,
        usesMonospacedDigit: true
    )
}

private struct VFTextModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let style: VFTextStyle

    init(style: VFTextStyle) {
        self.style = style
        _scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        var font = Font.system(size: scaledSize, weight: style.weight, design: style.design)
        if style.usesMonospacedDigit {
            font = font.monospacedDigit()
        }
        return content
            .font(font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

extension VFTextStyle {
    /// 크기는 그대로 두고 굵기만 바꾼다.
    ///
    /// 배지·타임스탬프처럼 "작지만 또렷해야 하는" 글자가 있다.
    /// 그런 곳에 크기가 맞는 토큰을 쓰면 굵기가 안 맞고, 굵기를 맞추려고
    /// 한 단계 큰 토큰을 쓰면 크기가 안 맞는다. 그래서 토큰을 벗어나
    /// raw font 로 돌아가는 일이 반복됐다.
    ///
    /// 굵기는 같은 크기 안의 변주이므로 토큰을 깨지 않는다.
    /// 크기·tracking·lineSpacing·Dynamic Type 기준은 그대로 유지된다.
    /// 크기를 바꾸는 변주는 일부러 만들지 않았다. 크기는 9개 중에서
    /// 골라야 하고, 그것이 이 시스템의 핵심이다.
    func weight(_ newWeight: Font.Weight) -> VFTextStyle {
        VFTextStyle(
            size: size,
            weight: newWeight,
            tracking: tracking,
            lineSpacing: lineSpacing,
            relativeTo: relativeTo,
            design: design,
            usesMonospacedDigit: usesMonospacedDigit
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - 아이콘의 Dynamic Type
//
//  SF Symbol 은 글자가 아니라 기호다. vfText 를 걸면 안 된다.
//  tracking / lineSpacing 이 의미가 없고, 토큰의 크기가 아이콘에 맞는
//  크기라는 보장도 없다.
//
//  그런데 아이콘도 커져야 하는 경우가 있다. 규칙은 아이콘이 무엇과
//  나란히 있는지로 갈린다.
//
//  [커져야 하는 아이콘] 글자와 한 줄에 있는 아이콘
//   글자만 커지고 아이콘이 그대로면 12pt 기호 옆에 28pt 글자가 서게
//   된다. 둘의 관계가 깨진다. 이런 곳에 vfIcon 을 쓴다.
//
//  [커지면 안 되는 아이콘] 고정 크기 프레임 안의 아이콘
//   .frame(width: 32, height: 32) 같은 터치 타겟 안에 든 아이콘이다.
//   프레임은 안 커지는데 기호만 커지면 넘쳐서 잘린다.
//   이런 곳은 고정 크기가 정답이다. 시스템 탭바·툴바 아이콘도 고정이다.
// ═══════════════════════════════════════════════════════════════════

private struct VFIconModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo: Font.TextStyle) {
        self.weight = weight
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight))
    }
}

extension View {
    /// 폰트 + 한글 tracking + lineSpacing + Dynamic Type 을 한 번에 적용한다.
    func vfText(_ style: VFTextStyle) -> some View {
        modifier(VFTextModifier(style: style))
    }

    /// SF Symbol 을 Dynamic Type 에 맞춰 키운다.
    ///
    /// 글자와 한 줄에 있는 아이콘에만 쓴다. 고정 프레임 안의 아이콘은
    /// 고정 크기로 둔다. (위 주석 참고)
    ///
    /// - Parameter relativeTo: 나란히 있는 글자의 기준 스타일.
    ///   같은 비율로 커져야 관계가 유지된다.
    func vfIcon(
        _ size: CGFloat,
        weight: Font.Weight = .semibold,
        relativeTo: Font.TextStyle = .body
    ) -> some View {
        modifier(VFIconModifier(size: size, weight: weight, relativeTo: relativeTo))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Scrim — 사진 위 텍스트의 유일한 정답
//
//  그림자나 반투명 박스를 쓰지 않는다. 어떤 사진에서도 대비가 일정해야 한다.
// ═══════════════════════════════════════════════════════════════════

struct VFScrim: View {
    enum ScrimEdge {
        case top
        case bottom
    }

    var edge: ScrimEdge = .bottom
    var strength: Double = 1.0

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.00 * strength), location: 0.00),
                .init(color: .black.opacity(0.22 * strength), location: 0.45),
                .init(color: .black.opacity(0.68 * strength), location: 1.00)
            ],
            startPoint: edge == .bottom ? .top : .bottom,
            endPoint: edge == .bottom ? .bottom : .top
        )
        .allowsHitTesting(false)
    }
}

extension View {
    /// 사진 하단에 텍스트용 scrim 을 깐다.
    func vfPhotoScrim(heightRatio: CGFloat = 0.55, strength: Double = 1.0) -> some View {
        overlay(alignment: .bottom) {
            GeometryReader { geometry in
                VFScrim(edge: .bottom, strength: strength)
                    .frame(height: geometry.size.height * heightRatio)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    /// 사진 상단에 컨트롤용 약한 scrim 을 깐다.
    func vfTopControlScrim(height: CGFloat = 88) -> some View {
        overlay(alignment: .top) {
            VFScrim(edge: .top, strength: 0.45)
                .frame(height: height)
        }
    }

    /// 스크롤 콘텐츠가 상태바 영역으로 올라올 때 부드럽게 사라지게 한다.
    ///
    /// navigationBarHidden(true) 인 화면에서는 스크롤한 본문이 상태바 시계와
    /// 그대로 겹쳐 읽히는 문제가 있었습니다. (마이 탭 스크린샷의 "저장한 장소")
    /// 배경색에서 투명으로 가는 그라디언트를 상단에 덮어 경계를 만듭니다.
    ///
    /// Phase 3 에서 iOS 26 의
    /// `.scrollEdgeEffectStyle(.soft, for: .top)` 으로 교체할 예정입니다.
    /// 스크롤 콘텐츠가 상태바 영역으로 올라올 때 시스템 재료로 경계를 만듭니다.
    /// iOS 26 미만에서는 아무 것도 하지 않습니다.
    ///
    /// ⚠️ 이 모디파이어가 빌드 에러를 내면 VFTopScrollEdgeEffect 의 본문을
    ///    `content` 만 반환하도록 바꾸면 됩니다. 기능 손실은 상단 경계뿐입니다.
    func vfTopScrollEdge() -> some View {
        modifier(VFTopScrollEdgeEffect())
    }

    func vfTopEdgeFade(height: CGFloat = 72) -> some View {
        overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(uiColor: VFPalette.canvas), location: 0.00),
                    .init(color: Color(uiColor: VFPalette.canvas), location: 0.45),
                    .init(color: Color(uiColor: VFPalette.canvas).opacity(0.0), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Glass
//
//  iOS 26 이상에서는 실제 Liquid Glass(.glassEffect) 를 사용하고,
//     그 이하에서는 material 폴백으로 동작합니다.
//     Reduce Transparency 가 켜지면 불통명 표면으로 대제합니다.
//
//  Glass 허용 위치 8곳 (이 외에는 절대 사용 금지):
//   1 탭바  2 지도 검색바  3 지도 필터칩  4 지도 위치버튼
//   5 지도 하단시트  6 사진 위 액션버튼  7 상세 하단 액션바  8 상단 상태 pill
//
//  금지: 사진 카드 / 리스트 셀 / 폼 필드 / 빈 상태 / 전체 배경 / 유리 위 유리
// ═══════════════════════════════════════════════════════════════════

struct VFGlassBackground<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    let tint: Color?
    let isInteractive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            // 접근성: 유리를 불투명 표면으로 대체한다. 심사 대응 필수.
            content
                .background(tint ?? Color(uiColor: VFPalette.surface2), in: shape)
                .overlay(shape.stroke(Color(uiColor: VFPalette.separator), lineWidth: 0.5))
        } else if #available(iOS 26.0, *) {
            liquidGlass(content)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .overlay(tintOverlay)
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func liquidGlass(_ content: Content) -> some View {
        if isInteractive, let tint {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else if isInteractive {
            content.glassEffect(.regular.interactive(), in: shape)
        } else if let tint {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }

    @ViewBuilder
    private var tintOverlay: some View {
        if let tint {
            shape.fill(tint.opacity(0.22))
        }
    }
}

extension View {
    /// 유리 배경. 기본 형태는 capsule.
    func vfGlass(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(VFGlassBackground(shape: Capsule(), tint: tint, isInteractive: interactive))
    }

    /// 사각형 유리가 필요할 때(시트 등)만 사용한다.
    func vfGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(VFGlassBackground(shape: shape, tint: tint, isInteractive: interactive))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Motion
//
//  허용 모션 4개
//  1 사진 탭 → 상세 zoom transition
//  2 필터 칩 전환
//  3 지도 시트 3단 detent
//  4 스크롤 시 탭바 축소
//
//  금지: 진입 시 stagger fade-in, scale bounce, 패럴랙스 남용, Lottie
// ═══════════════════════════════════════════════════════════════════

enum VFMotion {
    /// 기본. 화면 전환, 레이아웃 변화.
    static let standard = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// 빠른 반응. 버튼 상태, 핀 선택.
    static let quick = Animation.spring(response: 0.26, dampingFraction: 0.90)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Haptics
//
//  저장은 이 앱에서 가장 많이 쓰는 동작이다.
// ═══════════════════════════════════════════════════════════════════

enum VFHaptics {

    /// 장소 저장 / 저장 해제. 가장 중요.
    static func save() {
        impact(.soft)
    }

    /// 좋아요.
    static func like() {
        impact(.light)
    }

    /// 필터 칩, 세그먼트 전환.
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    /// 제보 완료.
    static func success() {
        notify(.success)
    }

    /// 오류.
    static func error() {
        notify(.error)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Photo Layout
//
//  사진 크기로 위계를 만든다. 모든 사진이 같은 비율이면 위계가 사라진다.
// ═══════════════════════════════════════════════════════════════════

enum VFPhoto {
    /// Hero. full-bleed.
    static let heroAspect: CGFloat = 4.0 / 5.0
    /// 가로 카로셀 카드.
    static let carouselAspect: CGFloat = 3.0 / 2.0
    /// 2열 그리드, 커뮤니티 셀.
    static let squareAspect: CGFloat = 1.0
    /// 모자이크 와이드 타일.
    static let wideAspect: CGFloat = 2.0 / 1.0

    /// Hero 가 차지할 화면 높이 비율.
    ///
    /// 0.72 로 시작했지만 HTML 목업으로 검증한 결과, 그 높이에서는 Hero 아래
    /// 첫 섹션이 "헤더만 겨우" 보이고 카드가 탭바에 잘렸습니다.
    /// "아래에 더 있다"는 신호가 없으면 스크롤을 유도하지 못합니다.
    /// 0.64 로 낮추면 첫 카드의 절반 정도가 보여서 스크롤 유도가 생깁니다.
    static let heroHeightRatio: CGFloat = 0.64
    /// 카로셀에서 다음 카드가 보이는 폭.
    static let carouselPeek: CGFloat = 28

    /// 섹션 카로셀 카드가 화면 폭에서 차지하는 비율.
    ///
    /// 처음에는 "화면 폭 - 마진 - peek" 로 계산해서 카드가 화면의 83% 를 차지했는데,
    /// Hero 가 이미 큰 사진이라 아래 카드까지 크면 화면 전체가 무거워집니다.
    /// 0.60 이면 카드 1.6장이 보여서 "옆으로 더 있다" 는 신호가 생기고
    /// 사진 크기도 Hero 와 위계가 구분됩니다.
    static let railWidthRatio: CGFloat = 0.60
    /// 3열 타일 gutter.
    static let tileGutter: CGFloat = VFSpace.xs
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Crowd Level
//
//  색상만으로 정보를 전달하지 않는다. 점 개수 + 라벨 + 색상 3중 인코딩.
// ═══════════════════════════════════════════════════════════════════

enum VFCrowdLevel: Int, CaseIterable {
    case calm = 0
    case normal
    case busy
    case veryBusy

    var label: String {
        switch self {
        case .calm:
            return "여유"
        case .normal:
            return "보통"
        case .busy:
            return "붐빔"
        case .veryBusy:
            return "매우 붐빔"
        }
    }

    var color: Color {
        switch self {
        case .calm:
            return Color(uiColor: VFPalette.crowdCalm)
        case .normal:
            return Color(uiColor: VFPalette.crowdNormal)
        case .busy, .veryBusy:
            return Color(uiColor: VFPalette.crowdBusy)
        }
    }

    /// 채워진 점의 개수. 색맹 사용자를 위한 형태 인코딩.
    ///
    /// calm 이 0 이었는데, 그러면 "여유" 일 때 점 3개가 모두 흐려져
    /// 정보가 없는 상태와 구별되지 않았습니다.
    /// 최소 1개는 채웁니다. 점 개수는 "얼마나 붐비는가" 를 뜻합니다.
    ///   1 여유 · 2 보통 · 3 붐빔
    /// busy 와 veryBusy 는 점이 같습니다. 색도 이미 같고(crowdBusy),
    /// 구분은 라벨이 합니다.
    var filledDots: Int {
        switch self {
        case .calm:
            return 1
        case .normal:
            return 2
        case .busy, .veryBusy:
            return 3
        }
    }

    var accessibilityLabel: String {
        "현재 혼잡도 \(label)"
    }

    /// 기존 문자열 데이터에서 변환한다.
    static func from(_ raw: String) -> VFCrowdLevel {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.contains("매우") {
            return .veryBusy
        }
        if text.contains("많") || text.contains("붐") || text.contains("혼잡") {
            return .busy
        }
        if text.contains("보통") {
            return .normal
        }
        return .calm
    }
}

/// 혼잡도 배지. 색 + 점 + 라벨 3중 인코딩.
struct VFCrowdBadge: View {
    let level: VFCrowdLevel
    var showsLabel: Bool = true

    var body: some View {
        HStack(spacing: VFSpace.sm - 2) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index < level.filledDots ? level.color : Color(uiColor: VFPalette.ink3))
                        .frame(width: 5, height: 5)
                }
            }

            if showsLabel {
                Text(level.label)
                    .vfText(.mono)
                    .foregroundStyle(level.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.accessibilityLabel)
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Scroll Edge Effect
//
//  navigationBar 를 숨긴 화면에서 스크롤한 본문이 상태바 시계와 겹쳐 읽히는
//  문제를 시스템 재료로 해결합니다.
//  직접 만든 그라디언트(vfTopEdgeFade)와 달리, 콘텐츠가 상단에 닿을 때만
//  나타나고 사진 위에 검정 띠를 남기지 않습니다.
//
//  ⚠️ 이 파일에서 유일하게 iOS 26 전용 API 를 쓰는 곳입니다.
//     빌드 에러가 나면 body 를 `content` 만 반환하도록 바꾸세요.
// ═══════════════════════════════════════════════════════════════════

struct VFTopScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

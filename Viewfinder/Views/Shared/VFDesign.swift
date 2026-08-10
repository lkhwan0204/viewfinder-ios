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

    // MARK: Ink — 텍스트
    static let ink1 = dynamic(dark: 0xFFFFFF, light: 0x111111)
    static let ink2 = dynamic(dark: 0x98989D, light: 0x6E6E73)
    static let ink3 = dynamic(dark: 0x98989D, light: 0x6E6E73, darkAlpha: 0.62, lightAlpha: 0.70)

    /// 구분선. 아주 약하게. 기본 그룹핑 수단은 여백이다.
    static let separator = dynamic(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.09, lightAlpha: 0.10)

    // MARK: Brand — 골든아워 앰버
    /// 앱의 시그니처. 화면당 2곳 이하로 아껴 쓴다.
    /// 허용: 선택된 탭 / 저장된 상태 / 선택된 칩 / 지도 핀 / 골든아워 / Primary 버튼
    /// 금지: 본문 대량 사용 / 큰 면적 배경 / 사진 위 오버레이
    static let amber = dynamic(dark: 0xF0A03C, light: 0xC97D1F)
    static let amberDim = dynamic(dark: 0xC4802E, light: 0xA66517)

    /// 앰버 표면 위에 올라가는 텍스트/아이콘 색.
    ///
    /// 다크의 앰버(#F0A03C)는 밝은 색이라 흰 글자를 올리면 대비가 2:1 수준으로
    /// 떨어집니다. 어두운 잉크를 올려야 4.5:1 을 넘깁니다.
    /// 라이트의 앰버(#C97D1F)는 어두우므로 흰 글자가 맞습니다.
    static let onAmber = dynamic(dark: 0x14100A, light: 0xFFFFFF)

    // MARK: Semantic — 혼잡도
    // 색상 단독으로 정보를 전달하지 않는다. 점 개수 + 라벨을 함께 쓴다.
    static let crowdCalm = dynamic(dark: 0x6BAE8E, light: 0x3F8A67)
    static let crowdNormal = dynamic(dark: 0xD9A94B, light: 0xA37B22)
    static let crowdBusy = dynamic(dark: 0xD4795E, light: 0xB0523A) // 빨강이 아니다. 테라코타.

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

extension View {
    /// 폰트 + 한글 tracking + lineSpacing + Dynamic Type 을 한 번에 적용한다.
    func vfText(_ style: VFTextStyle) -> some View {
        modifier(VFTextModifier(style: style))
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
    var filledDots: Int {
        switch self {
        case .calm:
            return 0
        case .normal:
            return 1
        case .busy:
            return 2
        case .veryBusy:
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

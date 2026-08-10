import SwiftUI

// ─────────────────────────────────────────────────────────────────
//  Phase 1 리디자인 노트
//
//  이 파일의 API 이름은 그대로 유지됩니다. (호출부 수정 0)
//  구현만 "Frame & Light" 디자인 시스템에 맞게 교체했습니다.
//
//  주요 변경
//  1. appCardSurface: 테두리와 그림자를 제거했습니다.
//     다크에서 canvas(#000) 와 surface1(#121214) 이 분리되어 있으므로
//     카드는 표면 차이만으로 읽힙니다. 테두리는 노이즈였습니다.
//  2. sectionTitle: 22pt -> 28pt 로 승격했습니다. 섹션이 약했습니다.
//  3. AppSectionHeader: 아이콘과 부제를 렌더링하지 않습니다.
//     (파라미터는 호출부 호환을 위해 남겨두었습니다)
//  4. 모든 폰트는 Dynamic Type 에 대응합니다.
//
//  색상은 VFPalette (VFDesign.swift) 가 단일 출처입니다.
// ─────────────────────────────────────────────────────────────────

enum AppLayout {
    static let pageHorizontalPadding: CGFloat = VFSpace.screenMargin
    static let pageTopPadding: CGFloat = 18
    /// 섹션 간 간격. 섹션 내부 최대 간격(12) 의 2.7배여야 그룹이 읽힌다.
    static let sectionSpacing: CGFloat = VFSpace.xl
    static let contentSpacing: CGFloat = VFSpace.md
    static let compactSpacing: CGFloat = VFSpace.sm
    static let touchTarget: CGFloat = 44

    /// 사진 카드 반경. 사진은 앱의 주인공이므로 넉넉하게.
    static let cardCornerRadius: CGFloat = VFRadius.photo
    static let mediaCornerRadius: CGFloat = VFRadius.photo
    static let controlCornerRadius: CGFloat = VFRadius.inner
    /// 테두리는 이제 거의 쓰지 않습니다. 여백으로 그룹핑하세요.
    static let borderWidth: CGFloat = 0.5
}

enum AppTypography {
    // 모두 Dynamic Type 대응 (Font.TextStyle 기반).
    // 한글 tracking / lineSpacing 이 필요한 곳에서는 .vfText(...) 를 쓰세요.

    static let navigationTitle = Font.system(.headline, weight: .semibold)
    static let screenTitle = Font.system(.largeTitle, weight: .bold)
    /// 섹션 헤더. Phase 1 에서 22pt -> 28pt 로 승격.
    static let sectionTitle = Font.system(.title, weight: .bold)
    static let prominentCardTitle = Font.system(.title2, weight: .semibold)
    static let cardTitle = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.body, weight: .regular)
    static let bodyStrong = Font.system(.body, weight: .semibold)
    static let metadata = Font.system(.subheadline, weight: .regular)
    static let caption = Font.system(.caption, weight: .medium)
}

// MARK: - Card Surface

private struct AppCardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isElevated: Bool

    func body(content: Content) -> some View {
        // 테두리와 그림자를 쓰지 않습니다.
        // 표면 색 차이만으로 카드를 표현하는 것이 콘텐츠 중심 디자인입니다.
        content
            .background(
                isElevated ? AppColors.mutedSurface : AppColors.cardBackground,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

extension View {
    func appCardSurface(
        cornerRadius: CGFloat = AppLayout.cardCornerRadius,
        elevated: Bool = false
    ) -> some View {
        modifier(AppCardSurfaceModifier(cornerRadius: cornerRadius, isElevated: elevated))
    }
}

// MARK: - State Panel

struct AppStatePanel: View {
    let symbolName: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.md) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 42, height: 42)
                .background(
                    AppColors.mutedSurface,
                    in: RoundedRectangle(cornerRadius: VFRadius.inner, style: .continuous)
                )

            VStack(alignment: .leading, spacing: VFSpace.xs + 1) {
                Text(title)
                    .vfText(.headline)
                    .foregroundStyle(AppColors.primary)

                Text(message)
                    .vfText(.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .vfText(.callout)
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, VFSpace.md + 2)
                    .frame(height: 38)
                    .background(
                        AppColors.accentSoft,
                        in: Capsule()
                    )
                    .buttonStyle(.plain)
            }
        }
        .padding(VFSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface()
    }
}

// MARK: - Section Header

struct AppSectionHeader: View {
    let title: String
    /// Phase 1 부터 렌더링하지 않습니다.
    /// 섹션 헤더 아래 설명은 정보가 아니라 소음이었습니다.
    var subtitle: String? = nil
    /// Phase 1 부터 렌더링하지 않습니다.
    /// 섹션마다 아이콘을 붙이면 모든 섹션이 같은 무게가 되어 강조가 사라집니다.
    var symbolName: String? = nil
    var count: Int? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: VFSpace.sm) {
            HStack(alignment: .firstTextBaseline, spacing: VFSpace.sm - 1) {
                Text(title)
                    .vfText(.title1)
                    .foregroundStyle(AppColors.primary)

                if let count {
                    Text("\(count)")
                        .vfText(.mono)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            Spacer(minLength: VFSpace.sm)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                            .vfText(.callout)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(minHeight: AppLayout.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) \(actionTitle)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Loading Overlay

struct AppLoadingOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()

            HStack(spacing: VFSpace.md) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(AppColors.accent)

                Text(title)
                    .vfText(.callout)
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.horizontal, VFSpace.lg)
            .frame(height: 54)
            .background(
                AppColors.mutedSurface,
                in: Capsule()
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

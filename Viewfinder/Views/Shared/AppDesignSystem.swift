import SwiftUI

enum AppLayout {
    static let pageHorizontalPadding: CGFloat = 20
    static let pageTopPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 30
    static let contentSpacing: CGFloat = 12
    static let compactSpacing: CGFloat = 8
    static let touchTarget: CGFloat = 44

    static let cardCornerRadius: CGFloat = 16
    static let mediaCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 12
    static let borderWidth: CGFloat = 0.8
}

enum AppTypography {
    static let navigationTitle = Font.headline
    static let screenTitle = Font.largeTitle.weight(.bold)
    static let sectionTitle = Font.title2.weight(.bold)
    static let prominentCardTitle = Font.title3.weight(.bold)
    static let cardTitle = Font.headline
    static let body = Font.body
    static let bodyStrong = Font.body.weight(.semibold)
    static let metadata = Font.subheadline.weight(.medium)
    static let caption = Font.caption.weight(.semibold)
}

private struct AppCardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isElevated: Bool

    func body(content: Content) -> some View {
        content
            .background(
                AppColors.cardBackground,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.divider.opacity(0.9), lineWidth: AppLayout.borderWidth)
            }
            .shadow(
                color: isElevated ? Color.black.opacity(0.07) : .clear,
                radius: isElevated ? 14 : 0,
                y: isElevated ? 5 : 0
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

struct AppStatePanel: View {
    let symbolName: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 42, height: 42)
                .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.primary)

                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface()
    }
}

struct AppSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var symbolName: String? = nil
    var count: Int? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.primary)

                    if let count {
                        Text("\(count)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(AppTypography.metadata)
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

struct AppLoadingOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(AppColors.primary)

                Text(title)
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .appCardSurface(cornerRadius: 14, elevated: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

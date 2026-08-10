import SwiftUI

struct CommunityPreviewRow: View {
    let spot: PhotoSpot
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: spot.theme.symbolName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(spot.theme.primary)
                    .frame(width: 34, height: 34)
                    .background(spot.theme.softFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(spot.communityTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)

                    Text(spot.communitySubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 62)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AppColors.accent.opacity(0.42) : AppColors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

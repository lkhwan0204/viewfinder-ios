import SwiftUI

struct SpotPreviewCard: View {
    let spot: PhotoSpot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(spot.theme.softFill)
                        .frame(width: 42, height: 42)

                    Image(systemName: spot.theme.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(spot.theme.primary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(spot.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(spot.region)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            Text(spot.summary)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(spot.hashtags.prefix(2), id: \.self) { tag in
                    Text("#\(tag.replacingOccurrences(of: "#", with: ""))")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(spot.theme.primary)
                }
            }

            Divider()

            VStack(spacing: 10) {
                InfoLine(symbolName: "calendar.badge.clock", title: spot.eventTitle, value: spot.eventPeriod)
                InfoLine(symbolName: "ticket.fill", title: "입장/비용", value: spot.feeInfo)
                InfoLine(symbolName: "bubble.left.and.bubble.right.fill", title: spot.communityTitle, value: spot.communitySubtitle)
            }

        }
        .padding(12)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct InfoLine: View {
    let symbolName: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

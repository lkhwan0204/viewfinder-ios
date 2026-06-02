import Foundation
import SwiftUI
import UIKit

enum SpotDetailSource {
    case home
    case search
    case map
    case community
    case saved

    var detents: Set<PresentationDetent> {
        switch self {
        case .map:
            return [.fraction(0.72), .large]
        case .home, .search, .community, .saved:
            return [.large]
        }
    }

    var isMapContext: Bool {
        self == .map
    }

    var isCompact: Bool {
        self == .map
    }
}

struct SpotDetailPresentation: Identifiable {
    let id = UUID()
    let spot: PhotoSpot
    let source: SpotDetailSource
}

struct SpotDetailView: View {
    let spot: PhotoSpot
    let source: SpotDetailSource
    let isSaved: Bool
    let communityPosts: [CommunityPost]
    let currentUserID: String
    let spots: [PhotoSpot]
    let onToggleSave: () -> Void
    let onOpenMap: () -> Void
    let onSubmitCommunity: (CommunityPostDraft) -> Void
    let onUpdateCommunity: (CommunityPost, CommunityPostDraft) -> Void
    let onDeleteCommunity: (CommunityPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isDirectionsDialogPresented = false
    @State private var isCommunityComposerPresented = false
    @State private var editingCommunityPost: CommunityPost?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: source.isCompact ? 14 : 20) {
                    SpotDetailHeroImage(spot: spot, height: source.isCompact ? 150 : 206)

                    header
                    detailRows
                    SpotDetailCommunitySection(
                        posts: communityPosts,
                        currentUserID: currentUserID,
                        onWrite: {
                            editingCommunityPost = nil
                            isCommunityComposerPresented = true
                        },
                        onEdit: { post in
                            editingCommunityPost = post
                            isCommunityComposerPresented = true
                        },
                        onDelete: { post in
                            onDeleteCommunity(post)
                        }
                    )
                }
                .padding(.horizontal, source.isCompact ? 14 : 18)
                .padding(.top, source.isCompact ? 12 : 18)
                .padding(.bottom, source.isCompact ? 18 : 24)
            }

            Divider()
                .overlay(AppColors.divider)

            actionBar
        }
        .background(AppColors.background.ignoresSafeArea())
        .confirmationDialog("길찾기 앱 선택", isPresented: $isDirectionsDialogPresented, titleVisibility: .visible) {
            ForEach(MapProvider.allCases) { provider in
                Button(provider.title) {
                    openDirections(with: provider)
                }
            }

            Button("취소", role: .cancel) {}
        }
        .sheet(isPresented: $isCommunityComposerPresented) {
            CommunityComposerView(
                spots: spots,
                selectedSpot: spot,
                locksSelectedSpot: true,
                editingPost: editingCommunityPost,
                onSubmit: { draft in
                    if let editingCommunityPost {
                        onUpdateCommunity(editingCommunityPost, draft)
                    } else {
                        onSubmitCommunity(draft)
                    }
                    self.editingCommunityPost = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 9) {
            if !source.isMapContext {
                Button {
                    dismiss()
                    onOpenMap()
                } label: {
                    DetailActionButton(title: "지도에서 보기", symbolName: "map.fill", isPrimary: true, height: actionButtonHeight)
                }
                .buttonStyle(.plain)
            }

            Button {
                isDirectionsDialogPresented = true
            } label: {
                DetailActionButton(title: "길찾기", symbolName: "location.fill", isPrimary: source.isMapContext, height: actionButtonHeight)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    onToggleSave()
                }
            } label: {
                DetailActionButton(
                    title: isSaved ? "저장됨" : "저장",
                    symbolName: isSaved ? "bookmark.fill" : "bookmark",
                    isPrimary: false,
                    height: actionButtonHeight,
                    tint: isSaved ? AppColors.accent : nil
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, source.isCompact ? 14 : 18)
        .padding(.top, 8)
        .padding(.bottom, source.isCompact ? 10 : 14)
        .background(AppColors.cardBackground)
    }

    private var actionButtonHeight: CGFloat {
        source.isCompact ? 38 : 42
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: source.isCompact ? 8 : 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.system(size: source.isCompact ? 21 : 24, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(HomeSpotDisplayFormatter.region(for: spot))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            Text(spot.summary)
                .font(.system(size: source.isCompact ? 13 : 14, weight: .regular))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(source.isCompact ? 2 : 2)
                .lineSpacing(1)

            HStack(spacing: 6) {
                ForEach(spot.hashtags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
    }

    private func openDirections(with provider: MapProvider) {
        let appURL = spot.directionsURL(for: provider)
        if UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
        } else {
            openURL(spot.fallbackDirectionsURL(for: provider))
        }
    }

    private var detailRows: some View {
        VStack(spacing: source.isCompact ? 13 : 15) {
            DetailInfoRow(symbolName: "clock.fill", title: "추천 시간대", value: HomeSpotDisplayFormatter.bestTime(spot.bestTime), tint: AppColors.secondaryText)
            DetailInfoRow(symbolName: "person.2.fill", title: "혼잡도", value: spot.crowdLevel, tint: AppColors.secondaryText)
            DetailInfoRow(symbolName: "camera.aperture", title: "렌즈 추천", value: spot.lensSuggestion, tint: AppColors.secondaryText)
            DetailInfoRow(symbolName: "cloud.sun.fill", title: "날씨 궁합", value: spot.weatherFit, tint: AppColors.secondaryText)
            DetailInfoRow(symbolName: "calendar.badge.clock", title: spot.eventTitle, value: spot.eventPeriod, tint: AppColors.secondaryText)
            DetailInfoRow(symbolName: "ticket.fill", title: "입장/비용", value: spot.feeInfo, tint: AppColors.secondaryText)
            DetailInfoRow(symbolName: "parkingsign.circle.fill", title: "주차", value: "\(spot.parkingInfo) · \(spot.nearbyParkingInfo)", tint: AppColors.secondaryText)
            DetailInfoRow(symbolName: "clock.badge.checkmark.fill", title: "이용 가능시간", value: spot.openingHours, tint: AppColors.secondaryText)
        }
        .padding(.top, source.isCompact ? 2 : 4)
    }
}

struct SpotDetailHeroImage: View {
    let spot: PhotoSpot
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PhotoSpotImageView(spot: spot, symbolSize: 34)

            if let attributionText {
                Text(attributionText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(.black.opacity(0.42), in: Capsule())
                    .padding(8)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.divider.opacity(0.65), lineWidth: 1)
        )
    }

    private var attributionText: String? {
        guard let credit = spot.imageCredit?.trimmingCharacters(in: .whitespacesAndNewlines),
              !credit.isEmpty else {
            return nil
        }

        if let license = spot.imageLicense?.trimmingCharacters(in: .whitespacesAndNewlines),
           !license.isEmpty {
            return "\(credit) · \(license)"
        }

        return credit
    }
}

struct SpotHeroMap: View {
    let spot: PhotoSpot

    var body: some View {
        NaverSpotPreviewMap(spot: spot)
        .allowsHitTesting(false)
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

func communityRelativeTimeText(for date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 {
        return "방금 전"
    }

    let minutes = Int(interval / 60)
    if minutes < 60 {
        return "\(minutes)분 전"
    }

    let hours = Int(interval / (60 * 60))
    if hours < 24 {
        return "\(hours)시간 전"
    }

    if Calendar.current.isDateInYesterday(date) {
        return "어제"
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "M월 d일"
    return formatter.string(from: date)
}

func communityAbsoluteTimeText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "yyyy.MM.dd a h:mm"
    return formatter.string(from: date)
}

func communityWrittenTimeText(for date: Date) -> String {
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "ko_KR")
    timeFormatter.dateFormat = "a h:mm"
    let timeText = timeFormatter.string(from: date)

    if Calendar.current.isDateInToday(date) {
        return "오늘 \(timeText) 작성"
    }

    if Calendar.current.isDateInYesterday(date) {
        return "어제 \(timeText) 작성"
    }

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ko_KR")
    dateFormatter.dateFormat = "M월 d일"
    return "\(dateFormatter.string(from: date)) \(timeText) 작성"
}

struct SpotDetailCommunitySection: View {
    let posts: [CommunityPost]
    let currentUserID: String
    let onWrite: () -> Void
    let onEdit: (CommunityPost) -> Void
    let onDelete: (CommunityPost) -> Void

    private var recentCrowdSummary: CommunityCrowdSummary? {
        let cutoff = Date().addingTimeInterval(-3 * 60 * 60)
        let recentPosts = posts.filter { $0.createdAt >= cutoff }
        guard !recentPosts.isEmpty else { return nil }

        let counts = Dictionary(grouping: recentPosts, by: \.crowd).mapValues(\.count)
        let recentCrowdsByRecency = recentPosts.sorted { $0.createdAt > $1.createdAt }.map(\.crowd)
        let selectedCrowd = CommunityPost.Crowd.allCases.max { left, right in
            let leftCount = counts[left, default: 0]
            let rightCount = counts[right, default: 0]

            if leftCount == rightCount {
                let leftRecentIndex = recentCrowdsByRecency.firstIndex(of: left) ?? Int.max
                let rightRecentIndex = recentCrowdsByRecency.firstIndex(of: right) ?? Int.max
                return leftRecentIndex > rightRecentIndex
            }

            return leftCount < rightCount
        }

        guard let selectedCrowd else { return nil }
        return CommunityCrowdSummary(crowd: selectedCrowd, reportCount: recentPosts.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("실시간 현장 정보")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.primary)

                Spacer()

                Button(action: onWrite) {
                    Label("작성", systemImage: "pencil")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 9)
                        .frame(height: 29)
                        .background(AppColors.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            CommunityCrowdSummaryCard(summary: recentCrowdSummary)

            if posts.isEmpty {
                Text("아직 이 장소의 현장 정보가 없어요. 지금 상황을 첫 번째로 알려주세요.")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.divider.opacity(0.7), lineWidth: 1)
                    )
            } else {
                VStack(spacing: 8) {
                    ForEach(posts.prefix(3)) { post in
                        CommunityInlinePostCard(
                            post: post,
                            currentUserID: currentUserID,
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
    }

}

private struct CommunityCrowdSummary {
    let crowd: CommunityPost.Crowd
    let reportCount: Int
}

private struct CommunityCrowdSummaryCard: View {
    let summary: CommunityCrowdSummary?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: summary == nil ? "person.2.slash" : "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("현재 혼잡도")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppColors.primary)

                    if let summary {
                        Text(summary.crowd.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(summary.crowd.tint)
                            .padding(.horizontal, 7)
                            .frame(height: 21)
                            .background(summary.crowd.fill, in: Capsule())
                    }
                }

                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.divider.opacity(0.7), lineWidth: 1)
        )
    }

    private var tint: Color {
        summary?.crowd.tint ?? AppColors.secondaryText
    }

    private var subtitle: String {
        guard let summary else {
            return "최근 혼잡도 정보 없음"
        }

        return "최근 제보 \(summary.reportCount)개 기준"
    }
}

struct DetailInfoRow: View {
    let symbolName: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

struct DetailActionButton: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool
    let height: CGFloat
    var tint: Color? = nil

    private var foregroundColor: Color {
        if isPrimary {
            return AppColors.primary
        }

        return tint ?? AppColors.primary
    }

    private var backgroundColor: Color {
        if isPrimary {
            return AppColors.accent
        }

        if let tint {
            return tint.opacity(0.12)
        }

        return AppColors.cardBackground
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke((tint ?? AppColors.divider).opacity(isPrimary ? 0 : 0.9), lineWidth: 1)
        )
    }
}

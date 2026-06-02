import Foundation
import SwiftUI

enum MapCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case sunset
    case night
    case cafe
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
            return "감성카페"
        case .walk:
            return "산책"
        case .film:
            return "필름감성"
        case .hidden:
            return "숨은 명소"
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
        case .walk:
            return ["park", "walk", "trail"].contains(normalized(spot.category))
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

struct MapFilterPill: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    var isLoading = false

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        } icon: {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(isSelected ? AppColors.accent : AppColors.secondaryText)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(isSelected ? AppColors.accent : AppColors.primary)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            isSelected ? AppColors.accentSoft : AppColors.cardBackground,
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? AppColors.accent.opacity(0.42) : AppColors.divider, lineWidth: 1)
        )
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

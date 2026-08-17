import Foundation

enum CafeRecommendationPolicy {
    static let excludedKeywords: [String] = [
        "런던베이글뮤지엄",
        "런던베이글",
        "스타벅스",
        "투썸",
        "투썸플레이스",
        "이디야",
        "메가커피",
        "메가mGC커피",
        "컴포즈",
        "컴포즈커피",
        "블루보틀",
        "노티드",
        "랜디스도넛",
        "아우어베이커리",
        "파리바게뜨",
        "뚜레쥬르",
        "을지로 카페골목",
        "인왕산 대충유원지",
        "학림다방"
    ]


    static func isIndependentCafeCandidate(_ spot: PhotoSpot) -> Bool {
        normalized(spot.category) == "cafe" && !isBlacklistedCafe(spot)
    }

    static func isBlacklistedCafe(_ spot: PhotoSpot) -> Bool {
        guard normalized(spot.category) == "cafe" || searchableText(for: spot).contains("카페") else {
            return false
        }

        return containsBlacklistedKeyword(in: searchableText(for: spot))
    }

    static func isBlacklistedRecommendation(_ recommendation: PhotoSpotRecommendation) -> Bool {
        if recommendation.isFranchise == true {
            return true
        }

        let text = ([recommendation.name, recommendation.description, recommendation.reason] + recommendation.tags)
            .map(normalized)
            .joined(separator: " ")
        return containsBlacklistedKeyword(in: text)
    }

    static func shouldExcludeFromKeywordSearch(_ spot: PhotoSpot, query: String) -> Bool {
        guard isBlacklistedCafe(spot) else { return false }

        let normalizedQuery = normalized(query)
        return normalizedQuery.contains("카페")
            || normalizedQuery.contains("cafe")
            || normalizedQuery.contains("감성")
            || normalizedQuery.contains("추천")
            || normalizedQuery.isEmpty
    }

    static func isDisplayableMapSpot(_ spot: PhotoSpot, recommendationModeEnabled: Bool) -> Bool {
        guard recommendationModeEnabled else { return true }
        return !isBlacklistedCafe(spot)
    }

    private static func searchableText(for spot: PhotoSpot) -> String {
        ([spot.name, spot.region, spot.summary, spot.eventPeriod, spot.mapQuery, spot.category, spot.bestTime]
            + spot.hashtags
            + spot.mood
            + spot.season
            + spot.weather
            + spot.recommendationRegions)
            .map(normalized)
            .joined(separator: " ")
    }

    private static func containsBlacklistedKeyword(in text: String) -> Bool {
        let normalizedText = normalized(text)
        return excludedKeywords.map(normalized).contains { normalizedText.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}

enum RecommendationBlacklist {
    static let excludedKeywords: [String] = [
        "오류동역 주변 골목",
        "고척 스카이돔",
        "고척스카이돔",
        "고척스카이돔 외부",
        "안양천 구로구간",
        "안양천 구로 구간",
        "일반 역 주변 골목",
        "역 주변 골목",
        "을지로 카페골목",
        "인왕산 대충유원지",
        "학림다방"
    ]


    private static let weakRecommendationSignals: [String] = [
        "단순역주변",
        "역주변골목",
        "일반골목",
        "일반주택가",
        "대형경기장"
    ]

    static func isBlacklistedRecommendation(_ spot: PhotoSpot) -> Bool {
        containsBlacklistedText(in: searchableText(for: spot))
    }

    static func isBlacklistedRecommendation(_ recommendation: PhotoSpotRecommendation) -> Bool {
        let text = ([recommendation.name, recommendation.description, recommendation.reason, recommendation.bestTime, recommendation.photoPoint ?? ""]
            + recommendation.tags)
            .map(normalized)
            .joined(separator: " ")
        return containsBlacklistedText(in: text)
    }

    static func containsBlacklistedText(_ values: [String]) -> Bool {
        containsBlacklistedText(in: values.map(normalized).joined(separator: " "))
    }

    static func isBlacklistedRecommendation(_ spot: VerifiedPhotoSpot) -> Bool {
        let text = ([spot.name, spot.description, spot.reason, spot.bestTime, spot.address]
            + spot.tags)
            .map(normalized)
            .joined(separator: " ")
        return containsBlacklistedText(in: text)
    }

    static func shouldExcludeFromSearch(_ spot: PhotoSpot, query: String) -> Bool {
        isBlacklistedRecommendation(spot) && !isDirectSearchMatch(query: query, spot: spot)
    }

    static func shouldExcludeFromSearch(_ spot: SeedPhotoSpot, query: String) -> Bool {
        let photoSpot = spot.photoSpot
        return isBlacklistedRecommendation(photoSpot) && !isDirectSearchMatch(query: query, seedSpot: spot)
    }

    private static func isDirectSearchMatch(query: String, spot: PhotoSpot) -> Bool {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return false }

        let names = [spot.name, spot.mapQuery]
            .map(normalized)

        return names.contains(normalizedQuery)
            || excludedKeywords.map(normalized).contains { keyword in
                keyword == normalizedQuery && names.contains { $0.contains(keyword) }
            }
    }

    private static func isDirectSearchMatch(query: String, seedSpot: SeedPhotoSpot) -> Bool {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return false }

        let names = [seedSpot.name, "\(seedSpot.name) \(seedSpot.address)"]
            .map(normalized)

        return names.contains(normalizedQuery)
            || excludedKeywords.map(normalized).contains { keyword in
                keyword == normalizedQuery && names.contains { $0.contains(keyword) }
            }
    }

    private static func searchableText(for spot: PhotoSpot) -> String {
        ([spot.name, spot.region, spot.summary, spot.eventPeriod, spot.mapQuery, spot.category, spot.bestTime, spot.crowdLevelCode]
            + spot.hashtags
            + spot.mood
            + spot.season
            + spot.weather
            + spot.recommendationRegions)
            .map(normalized)
            .joined(separator: " ")
    }

    private static func containsBlacklistedText(in text: String) -> Bool {
        let normalizedText = normalized(text)
        return (excludedKeywords + weakRecommendationSignals)
            .map(normalized)
            .contains { normalizedText.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}

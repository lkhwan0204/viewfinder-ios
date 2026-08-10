import CoreLocation
import Foundation

struct KeywordSearchResults: Equatable {
    let spots: [PhotoSpot]
    let communityPosts: [CommunityPost]

    static let empty = KeywordSearchResults(spots: [], communityPosts: [])
}

protocol SearchProvider {
    func search(
        query: String,
        spots: [PhotoSpot],
        communityPosts: [CommunityPost]
    ) -> KeywordSearchResults
}

struct LocalKeywordSearchProvider: SearchProvider {
    func search(
        query: String,
        spots: [PhotoSpot],
        communityPosts: [CommunityPost]
    ) -> KeywordSearchResults {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return .empty }
        let variants = SearchRegionPolicy.contentQueryVariants(for: query)
        let regionScope = SearchRegionPolicy.scope(for: query)
        let spotsByID = Dictionary(spots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return KeywordSearchResults(
            spots: rankedSpots(
                spots.filter {
                    SearchRegionPolicy.matches($0, query: query)
                        && !SearchRegionPolicy.shouldSuppressFromGeneralSearch($0, query: query)
                        && !CafeRecommendationPolicy.isBlacklistedCafe($0)
                        && !RecommendationBlacklist.shouldExcludeFromSearch($0, query: query)
                        && !CafeRecommendationPolicy.shouldExcludeFromKeywordSearch($0, query: query)
                },
                query: query
            ),
            communityPosts: communityPosts.filter { post in
                if let regionScope {
                    guard let spot = spotsByID[post.spotID],
                          SearchRegionPolicy.matches(spot, scope: regionScope) else {
                        return false
                    }
                }

                if variants.isEmpty {
                    return regionScope != nil
                }

                return variants.contains { query in
                    searchableCommunityFields(for: post).contains {
                        normalized($0).contains(query)
                    }
                }
            }
        )
    }

    private func rankedSpots(_ spots: [PhotoSpot], query: String) -> [PhotoSpot] {
        let variants = SearchRegionPolicy.contentQueryVariants(for: query)
        let regionScope = SearchRegionPolicy.scope(for: query)

        return uniqueSpots(
            spots
                .compactMap { spot -> (PhotoSpot, Int)? in
                    let score = matchScore(for: spot, queryVariants: variants, regionScope: regionScope)
                    return score == nil ? nil : (spot, score ?? 99)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                    return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
                }
                .map { $0.0 }
        )
    }

    private func matchScore(
        for spot: PhotoSpot,
        queryVariants: [String],
        regionScope: SearchRegionPolicy.RegionScope?
    ) -> Int? {
        if let regionScope {
            guard SearchRegionPolicy.matches(spot, scope: regionScope) else { return nil }
            if queryVariants.isEmpty {
                return 0
            }
        }

        let regionFields = [spot.region, spot.mapQuery].map(normalized)
        if let regionScope,
           SearchRegionPolicy.matches(fields: regionFields, scope: regionScope),
           containsQuery(in: [spot.name], queryVariants: queryVariants) {
            return 0
        }

        if containsQuery(in: [spot.name], queryVariants: queryVariants) {
            return 1
        }

        if containsQuery(in: spot.hashtags + [spot.category] + spot.mood, queryVariants: queryVariants) {
            return 2
        }

        if containsQuery(in: [spot.summary], queryVariants: queryVariants) {
            return 3
        }

        return nil
    }

    private func containsQuery(in fields: [String], queryVariants: [String]) -> Bool {
        let normalizedFields = fields.map(normalized)
        return queryVariants.contains { query in
            normalizedFields.contains { field in
                field.contains(query)
            }
        }
    }

    private func searchableCommunityFields(for post: CommunityPost) -> [String] {
        [post.message] + post.hashtags + post.statusTags
    }

    private func uniqueSpots(_ spots: [PhotoSpot]) -> [PhotoSpot] {
        spots.reduce(into: [PhotoSpot]()) { result, spot in
            guard !result.contains(where: { $0.id == spot.id || $0.mapQuery == spot.mapQuery }) else {
                return
            }

            result.append(spot)
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private func queryVariants(for query: String) -> [String] {
        SearchRegionPolicy.contentQueryVariants(for: query)
    }
}

enum SearchRegionPolicy {
    struct RegionScope: Equatable {
        let displayName: String
        let aliases: [String]
        let surroundingTitle: String
    }

    private static let scopes: [RegionScope] = [
        RegionScope(displayName: "구로구", aliases: ["구로구", "구로"], surroundingTitle: "구로구 주변 추천"),
        RegionScope(displayName: "강서구", aliases: ["강서구", "강서"], surroundingTitle: "강서구 주변 추천"),
        RegionScope(displayName: "서울", aliases: ["서울특별시", "서울시", "서울"], surroundingTitle: "서울 주변 추천"),
        RegionScope(displayName: "부산", aliases: ["부산광역시", "부산시", "부산"], surroundingTitle: "부산 주변 추천"),
        RegionScope(displayName: "인천", aliases: ["인천광역시", "인천시", "인천"], surroundingTitle: "인천 주변 추천"),
        RegionScope(displayName: "경기", aliases: ["경기도", "경기"], surroundingTitle: "경기 주변 추천"),
        RegionScope(displayName: "양평", aliases: ["양평군", "양평"], surroundingTitle: "양평 주변 추천"),
        RegionScope(displayName: "부천", aliases: ["부천시", "부천"], surroundingTitle: "부천 주변 추천"),
        RegionScope(displayName: "김포", aliases: ["김포시", "김포"], surroundingTitle: "김포 주변 추천"),
        RegionScope(displayName: "수원", aliases: ["수원시", "수원"], surroundingTitle: "수원 주변 추천"),
        RegionScope(displayName: "파주", aliases: ["파주시", "파주"], surroundingTitle: "파주 주변 추천")
    ]

    private static let genericSearchWords = [
        "출사지", "출사", "사진", "스팟", "추천", "장소", "명소", "오늘", "찾기"
    ]

    private static let weakGeneralSearchNames = [
        "학림다방"
    ]

    static func scope(for query: String) -> RegionScope? {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return nil }

        return scopes.first { scope in
            scope.aliases
                .map(normalized)
                .contains { alias in normalizedQuery.contains(alias) }
        }
    }

    static func contentQueryVariants(for query: String) -> [String] {
        var cleanedQuery = normalized(query)

        if let scope = scope(for: query) {
            scope.aliases
                .map(normalized)
                .sorted { $0.count > $1.count }
                .forEach { alias in
                    cleanedQuery = cleanedQuery.replacingOccurrences(of: alias, with: "")
                }
        }

        genericSearchWords
            .map(normalized)
            .sorted { $0.count > $1.count }
            .forEach { keyword in
                cleanedQuery = cleanedQuery.replacingOccurrences(of: keyword, with: "")
            }

        var variants = [cleanedQuery]
        if cleanedQuery.hasSuffix("구"), cleanedQuery.count > 1 {
            variants.append(String(cleanedQuery.dropLast()))
        }

        return variants.reduce(into: [String]()) { result, variant in
            guard !variant.isEmpty, !result.contains(variant) else { return }
            result.append(variant)
        }
    }

    static func matches(_ spot: PhotoSpot, query: String) -> Bool {
        guard let scope = scope(for: query) else { return true }
        return matches(spot, scope: scope)
    }

    static func matches(_ spot: PhotoSpot, scope: RegionScope) -> Bool {
        matches(fields: [spot.region, spot.mapQuery], scope: scope)
    }

    static func matches(_ spot: SeedPhotoSpot, query: String) -> Bool {
        guard let scope = scope(for: query) else { return true }
        return matches(fields: [spot.region ?? "", spot.address], scope: scope)
    }

    static func matches(_ spot: VerifiedPhotoSpot, query: String) -> Bool {
        guard let scope = scope(for: query) else { return true }
        return matches(fields: [spot.address], scope: scope)
    }

    static func allowsRecommendationCandidate(_ recommendation: PhotoSpotRecommendation, query: String) -> Bool {
        guard let scope = scope(for: query) else { return true }

        let fields = [recommendation.name, recommendation.description, recommendation.reason, recommendation.bestTime, recommendation.photoPoint ?? ""]
            + recommendation.tags
        if matches(fields: fields, scope: scope) {
            return true
        }

        let text = fields.map(normalized).joined(separator: " ")
        let outsideAliases = scopes
            .filter { $0 != scope }
            .flatMap(\.aliases)
            .map(normalized)

        return !outsideAliases.contains { alias in
            !alias.isEmpty && text.contains(alias)
        }
    }

    static func shouldSuppressFromGeneralSearch(_ spot: PhotoSpot, query: String) -> Bool {
        guard !isCafeFocusedQuery(query) else { return false }

        let text = ([spot.name, spot.region, spot.mapQuery, spot.summary, spot.category]
            + spot.hashtags
            + spot.mood)
            .map(normalized)
            .joined(separator: " ")

        return weakGeneralSearchNames
            .map(normalized)
            .contains { text.contains($0) }
    }

    static func matches(fields: [String], scope: RegionScope) -> Bool {
        let normalizedFields = fields.map(normalized)
        let aliases = scope.aliases.map(normalized)

        return aliases.contains { alias in
            normalizedFields.contains { field in
                field == alias || field.contains(alias)
            }
        }
    }

    private static func isCafeFocusedQuery(_ query: String) -> Bool {
        let normalizedQuery = normalized(query)
        return normalizedQuery.contains("카페")
            || normalizedQuery.contains("cafe")
            || normalizedQuery.contains("다방")
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}

struct ExternalPlaceSearchCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let tags: [String]
}

protocol ExternalPlaceSearchService {
    func searchPlaces(matching query: String) async throws -> [ExternalPlaceSearchCandidate]
}

struct ExternalPlaceSearchVerificationPipeline {
    let externalSearchService: any ExternalPlaceSearchService
    let verificationService: PlaceVerificationService

    func verifiedSpots(
        matching query: String,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> [VerifiedPhotoSpot] {
        let candidates = try await externalSearchService.searchPlaces(matching: query)
        let recommendations = candidates.map {
            PhotoSpotRecommendation(
                id: $0.id,
                name: $0.name,
                description: $0.summary,
                bestTime: "",
                reason: $0.summary,
                tags: $0.tags
            )
        }
        .filter { !CafeRecommendationPolicy.isBlacklistedRecommendation($0) }
        .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
        .filter { SearchRegionPolicy.allowsRecommendationCandidate($0, query: query) }

        return try await verificationService.verify(
            recommendations: recommendations,
            region: query,
            userLocation: userLocation
        )
    }
}

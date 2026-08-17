import CoreLocation
import Foundation
import SwiftUI
import UIKit

struct SeedPhotoSpot: Decodable, Identifiable {
    let id: String
    let name: String
    let region: String?
    let regions: [String]
    let address: String
    let description: String
    let bestTime: String
    let reason: String
    let tags: [String]
    let latitude: Double
    let longitude: Double
    let source: String
    let theme: String
    let imageURL: URL?
    let category: String?
    let season: [String]?
    let weather: [String]?
    let mood: [String]?
    let crowdLevel: String?
    let imageName: String?
    let imageCredit: String?
    let imageLicense: String?
    let imageSourceURL: URL?
    let openingHours: String?
    let feeInfo: String?
    let parkingInfo: String?
    let nearbyParkingInfo: String?
    let isHiddenSpot: Bool?

    var verifiedSpot: VerifiedPhotoSpot {
        VerifiedPhotoSpot(
            id: id,
            name: name,
            description: description,
            bestTime: bestTime,
            reason: reason,
            tags: tags,
            address: address,
            latitude: latitude,
            longitude: longitude,
            source: source,
            imageURL: imageURL
        )
    }

    var photoSpot: PhotoSpot {
        let resolvedTheme = SpotTheme(rawValue: theme) ?? verifiedSpot.photoSpot.theme

        return PhotoSpot(
            id: id,
            name: name,
            region: address,
            summary: description,
            hashtags: normalizedTags,
            eventTitle: "추천 이유",
            eventPeriod: reason,
            feeInfo: feeInfo?.nilIfBlank ?? "방문 전 공식 정보 확인 필요",
            openingHours: openingHours?.nilIfBlank ?? "이용 가능시간 확인 필요",
            bestTime: bestTime,
            crowdLevel: "주말 오후와 해질녘은 혼잡할 수 있어요",
            lensSuggestion: lensSuggestion(for: resolvedTheme),
            weatherFit: weatherFit(for: resolvedTheme),
            parkingInfo: parkingInfo?.nilIfBlank ?? "주차 정보 확인 필요",
            nearbyParkingInfo: nearbyParkingInfo?.nilIfBlank ?? "네이버 지도 또는 카카오맵에서 주변 주차장 확인",
            communityTitle: "\(name) 실시간",
            communitySubtitle: "날씨, 혼잡도, 촬영 포인트 공유 예정",
            mapQuery: "\(name) \(address)",
            latitude: latitude,
            longitude: longitude,
            theme: resolvedTheme,
            imageURL: imageURL,
            category: category?.nilIfBlank ?? inferredCategory,
            season: cleanedList(season),
            weather: cleanedList(weather),
            mood: cleanedList(mood),
            crowdLevelCode: crowdLevel?.nilIfBlank ?? "normal",
            imageName: imageName?.nilIfBlank,
            imageCredit: imageCredit?.nilIfBlank,
            imageLicense: imageLicense?.nilIfBlank,
            imageSourceURL: imageSourceURL,
            recommendationRegions: recommendationRegions,
            isHiddenSpot: resolvedIsHiddenSpot
        )
    }

    private var recommendationRegions: [String] {
        cleanedUnique(
            [region, addressRegionHint]
                + regions.map(Optional.some)
                + tags.filter(isRegionLikeTag).map(Optional.some)
        )
    }

    private var resolvedIsHiddenSpot: Bool {
        if let isHiddenSpot {
            return isHiddenSpot
        }

        let searchable = ([crowdLevel ?? "", description, reason] + tags + cleanedList(mood))
            .joined(separator: " ")
        return crowdLevel == "low"
            || searchable.contains("숨은")
            || searchable.contains("한적")
            || searchable.lowercased().contains("hidden")
    }

    private var normalizedTags: [String] {
        let cleaned = tags
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleaned.isEmpty ? ["출사지"] : Array(cleaned.prefix(4))
    }

    private var inferredCategory: String {
        let normalizedTags = tags.map { $0.lowercased() }

        if normalizedTags.contains(where: { $0.contains("공원") || $0.contains("숲") }) {
            return "park"
        }

        if normalizedTags.contains(where: { $0.contains("산책") || $0.contains("길") }) {
            return "walk"
        }

        if theme == "indoor" {
            return "indoor"
        }

        return "spot"
    }

    private func cleanedList(_ values: [String]?) -> [String] {
        values?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func cleanedUnique(_ values: [String?]) -> [String] {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(value) else { return }
                result.append(value)
            }
    }

    private var addressRegionHint: String? {
        let knownRegions = [
            "문래", "성수", "을지로", "연남", "익선동", "서촌", "해방촌",
            "한강", "서울숲", "선유도", "북촌", "망원", "보라매", "경의선숲길",
            "항동", "안양천", "서래섬", "반포", "이촌", "뚝섬", "양화",
            "잠원", "도농", "삼패", "하늘공원", "백빈", "압구정", "영천"
        ]
        return knownRegions.first { address.contains($0) || name.contains($0) }
    }

    private func isRegionLikeTag(_ tag: String) -> Bool {
        [
            "문래", "성수", "을지로", "연남", "익선동", "서촌", "해방촌",
            "한강", "서울숲", "선유도", "북촌", "망원", "잠실", "대학로",
            "보라매", "경의선숲길", "항동", "안양천", "서래섬", "반포",
            "이촌", "뚝섬", "양화", "잠원", "도농", "삼패", "하늘공원",
            "백빈", "압구정", "영천"
        ].contains(tag)
    }

    private func lensSuggestion(for theme: SpotTheme) -> String {
        switch theme {
        case .night, .city, .water:
            return "24-70mm 줌, 야경은 밝은 단렌즈"
        case .flower:
            return "50mm 단렌즈 또는 접사 가능한 표준 줌"
        case .indoor:
            return "35mm 밝은 단렌즈"
        case .healing:
            return "35mm 또는 50mm 단렌즈"
        }
    }

    private func weatherFit(for theme: SpotTheme) -> String {
        switch theme {
        case .night:
            return "맑은 밤과 비 온 뒤 반사 컷에 좋아요"
        case .flower, .healing:
            return "맑거나 얇게 흐린 날 색감이 부드러워요"
        case .indoor:
            return "비 오는 날에도 촬영하기 좋아요"
        case .water:
            return "바람 적은 날 반영이 깔끔해요"
        case .city:
            return "맑은 날 선명하고 흐린 날은 차분한 색감이 좋아요"
        }
    }
}

struct LocalSeedDataService {
    private static var cachedSpots: [SeedPhotoSpot]?
    private static var cachedPhotoSpots: [PhotoSpot]?

    func allPhotoSpots() -> [PhotoSpot] {
        if let cachedPhotoSpots = Self.cachedPhotoSpots {
            return cachedPhotoSpots
        }

        let photoSpots = loadSpots().map(\.photoSpot)
        Self.cachedPhotoSpots = photoSpots
        return photoSpots
    }

    func allSeedSpots() -> [SeedPhotoSpot] {
        loadSpots()
    }

    func verifiedSpots(matching query: String, limit: Int = 12) -> [VerifiedPhotoSpot] {
        seedSpots(matching: query, limit: limit).map(\.verifiedSpot)
    }

    func photoSpots(matching query: String, limit: Int = 12) -> [PhotoSpot] {
        seedSpots(matching: query, limit: limit).map(\.photoSpot)
    }

    func homePhotoSpots(near coordinate: CLLocationCoordinate2D?, limit: Int = 8) -> [PhotoSpot] {
        sortedByDistanceIfPossible(
            loadSpots().filter {
                $0.photoSpot.hasReliableDisplayImage
                    && !RecommendationBlacklist.isBlacklistedRecommendation($0.photoSpot)
            },
            near: coordinate
        )
            .prefix(limit)
            .map(\.photoSpot)
    }

    func photoSpots(
        near coordinate: CLLocationCoordinate2D,
        within radiusMeters: CLLocationDistance = 10_000,
        limit: Int = 20
    ) -> [PhotoSpot] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return loadSpots()
            .filter {
                $0.imageURL != nil
                    && !RecommendationBlacklist.isBlacklistedRecommendation($0.photoSpot)
            }
            .map { spot in
                (
                    spot,
                    CLLocation(latitude: spot.latitude, longitude: spot.longitude).distance(from: origin)
                )
            }
            .filter { $0.1 <= radiusMeters }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0.photoSpot }
    }

    func photoSpots(matchingAnyTag tags: [String], near coordinate: CLLocationCoordinate2D?, limit: Int = 8) -> [PhotoSpot] {
        let normalizedTags = tags.map(normalized)
        let rawQuery = tags.joined(separator: " ")
        let spots = loadSpots().filter { spot in
            guard spot.imageURL != nil else { return false }
            guard !RecommendationBlacklist.isBlacklistedRecommendation(spot.photoSpot) else {
                return false
            }
            guard !CafeRecommendationPolicy.shouldExcludeFromKeywordSearch(spot.photoSpot, query: rawQuery) else {
                return false
            }

            let spotTags = spot.tags.map(normalized)
            let searchable = ([spot.name, spot.description, spot.reason, spot.address] + spot.tags).map(normalized)
            return normalizedTags.contains { requestedTag in
                spotTags.contains { $0.contains(requestedTag) || requestedTag.contains($0) }
                    || searchable.contains { $0.contains(requestedTag) }
            }
        }

        return sortedByDistanceIfPossible(spots, near: coordinate)
            .prefix(limit)
            .map(\.photoSpot)
    }

    private func seedSpots(matching query: String, limit: Int) -> [SeedPhotoSpot] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let queryVariants = SearchRegionPolicy.contentQueryVariants(for: query)
        let regionScope = SearchRegionPolicy.scope(for: query)

        let availableSpots = loadSpots().filter { seedSpot in
            let allowsImageMissingForDirectSearch = normalized(seedSpot.name).contains(normalizedQuery)
                || normalizedQuery.contains(normalized(seedSpot.name))
            guard seedSpot.imageURL != nil || seedSpot.imageName != nil || allowsImageMissingForDirectSearch else {
                return false
            }
            guard SearchRegionPolicy.matches(seedSpot, query: query) else {
                return false
            }
            guard !SearchRegionPolicy.shouldSuppressFromGeneralSearch(seedSpot.photoSpot, query: query) else {
                return false
            }
            guard !CafeRecommendationPolicy.isBlacklistedCafe(seedSpot.photoSpot) else {
                return false
            }
            guard !RecommendationBlacklist.shouldExcludeFromSearch(seedSpot, query: query) else {
                return false
            }
            return !CafeRecommendationPolicy.shouldExcludeFromKeywordSearch(seedSpot.photoSpot, query: query)
        }

        return availableSpots
            .compactMap { spot -> (SeedPhotoSpot, Int)? in
                guard let score = matchScore(for: spot, queryVariants: queryVariants, regionScope: regionScope) else {
                    return nil
                }
                return (spot, score)
            }
            .sorted { left, right in
                if left.1 != right.1 { return left.1 < right.1 }
                return left.0.name.localizedStandardCompare(right.0.name) == .orderedAscending
            }
            .map { $0.0 }
            .reduce(into: [SeedPhotoSpot]()) { result, spot in
                guard !result.contains(where: { $0.id == spot.id }) else { return }
                result.append(spot)
            }
            .prefix(limit)
            .map { $0 }
    }

    private func matchScore(
        for spot: SeedPhotoSpot,
        queryVariants: [String],
        regionScope: SearchRegionPolicy.RegionScope?
    ) -> Int? {
        if let regionScope {
            guard SearchRegionPolicy.matches(fields: [spot.region ?? "", spot.address], scope: regionScope) else {
                return nil
            }

            if queryVariants.isEmpty {
                return 0
            }
        }

        let regionFields = [spot.region ?? "", spot.address].map(normalized)
        if let regionScope,
           SearchRegionPolicy.matches(fields: regionFields, scope: regionScope),
           containsQuery(in: [spot.name], queryVariants: queryVariants) {
            return 0
        }

        if containsQuery(in: [spot.name], queryVariants: queryVariants) {
            return 1
        }

        if containsQuery(in: spot.tags + [spot.category ?? ""], queryVariants: queryVariants) {
            return 2
        }

        if containsQuery(in: [spot.description, spot.reason], queryVariants: queryVariants) {
            return 3
        }

        return nil
    }

    private func containsQuery(in fields: [String], queryVariants: [String], allowExact: Bool = false) -> Bool {
        let normalizedFields = fields.map(normalized)
        return queryVariants.contains { query in
            normalizedFields.contains { field in
                field.contains(query) || (allowExact && field == query)
            }
        }
    }

    private func loadSpots() -> [SeedPhotoSpot] {
        if let cachedSpots = Self.cachedSpots {
            return cachedSpots
        }

        guard let url = Bundle.main.url(forResource: "photo_spots_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let spots = try? JSONDecoder().decode([SeedPhotoSpot].self, from: data) else {
            return []
        }

        Self.cachedSpots = spots
        return spots
    }

    private func sortedByDistanceIfPossible(_ spots: [SeedPhotoSpot], near coordinate: CLLocationCoordinate2D?) -> [SeedPhotoSpot] {
        guard let coordinate else { return spots }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return spots.sorted { left, right in
            let leftLocation = CLLocation(latitude: left.latitude, longitude: left.longitude)
            let rightLocation = CLLocation(latitude: right.latitude, longitude: right.longitude)
            return leftLocation.distance(from: origin) < rightLocation.distance(from: origin)
        }
    }

    private func uniqueSpots(_ spots: [SeedPhotoSpot]) -> [SeedPhotoSpot] {
        spots.reduce(into: [SeedPhotoSpot]()) { result, spot in
            guard !result.contains(where: { $0.id == spot.id }) else { return }
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
        let normalizedQuery = normalized(query)
        let withoutSeoul = normalizedQuery
            .replacingOccurrences(of: "서울특별시", with: "")
            .replacingOccurrences(of: "서울시", with: "")
            .replacingOccurrences(of: "서울", with: "")

        var variants = [normalizedQuery, withoutSeoul]
        if withoutSeoul.hasSuffix("구"), withoutSeoul.count > 1 {
            variants.append(String(withoutSeoul.dropLast()))
        }

        return variants.reduce(into: [String]()) { result, variant in
            guard !variant.isEmpty, !result.contains(variant) else { return }
            result.append(variant)
        }
    }
}

enum HomeRecommendationKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sunset
    case night
    case cafe
    case seasonal
    case rainy
    case walk
    case film
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunset:
            return "노을 명소"
        case .night:
            return "야경 명소"
        case .cafe:
            return "감성 카페"
        case .seasonal:
            return "계절 명소"
        case .rainy:
            return "비 오는 날 감성"
        case .walk:
            return "산책 출사"
        case .film:
            return "필름 감성 스팟"
        case .hidden:
            return "사람 적은 숨은 명소"
        }
    }

    var symbolName: String {
        switch self {
        case .sunset:
            return "sunset.fill"
        case .night:
            return "moon.stars.fill"
        case .cafe:
            return "cup.and.saucer.fill"
        case .seasonal:
            return "camera.macro"
        case .rainy:
            return "cloud.rain.fill"
        case .walk:
            return "figure.walk"
        case .film:
            return "camera.fill"
        case .hidden:
            return "sparkle.magnifyingglass"
        }
    }

    var accentColor: Color {
        switch self {
        case .sunset:
            return AppColors.primary.opacity(0.82)
        case .night:
            return AppColors.primary
        case .cafe:
            return AppColors.secondaryText
        case .seasonal:
            return AppColors.secondaryText
        case .rainy:
            return AppColors.secondaryText
        case .walk:
            return AppColors.secondaryText
        case .film:
            return AppColors.primary.opacity(0.86)
        case .hidden:
            return AppColors.primary.opacity(0.86)
        }
    }
}

struct RecommendationWeatherContext: Equatable, Sendable {
    let condition: String
    let temperature: Int
    let apparentTemperature: Int
    let precipitation: Double
    let cloudCover: Int
    let windSpeed: Double
    let pm10: Double?
    let pm25: Double?

    var isRainy: Bool {
        condition.contains("비") || condition.contains("천둥") || precipitation > 0.1
    }

    var isSnowy: Bool {
        condition.contains("눈")
    }

    var isFoggy: Bool {
        condition.contains("안개")
    }

    var isClear: Bool {
        condition == "맑음" || (condition == "구름 조금" && cloudCover < 65 && !isRainy)
    }

    var isCloudy: Bool {
        cloudCover >= 70 && !isRainy && !isSnowy && !isFoggy
    }

    var hasBadAirQuality: Bool {
        (pm10 ?? 0) >= 81 || (pm25 ?? 0) >= 36
    }

    var isTooHot: Bool {
        apparentTemperature >= 30
    }

    var isTooCold: Bool {
        apparentTemperature <= 0
    }

    var isWindy: Bool {
        windSpeed >= 8
    }
}

struct RecommendationTimeContext: Equatable, Sendable {
    enum Phase: Sendable {
        case dawn
        case morning
        case day
        case goldenHour
        case evening
        case night
    }

    let phase: Phase

    init(referenceDate: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let hour = calendar.component(.hour, from: referenceDate)

        switch hour {
        case 5..<8:
            phase = .dawn
        case 8..<12:
            phase = .morning
        case 12..<16:
            phase = .day
        case 16..<19:
            phase = .goldenHour
        case 19..<22:
            phase = .evening
        default:
            phase = .night
        }
    }
}

struct HomeRecommendationSnapshot: Sendable {
    let todayRecommendations: [RecommendedSpot]
    let sections: [HomeRecommendationKind: [RecommendedSpot]]
    let expandedSections: [HomeRecommendationKind: [RecommendedSpot]]

    var visibleSpots: [PhotoSpot] {
        let sectionSpots = sections.values.flatMap { $0.map(\.spot) }
        return (todayRecommendations.map(\.spot) + sectionSpots).reduce(into: [PhotoSpot]()) { result, spot in
            guard !result.contains(where: { $0.id == spot.id }) else { return }
            result.append(spot)
        }
    }
}

struct HomeRecommendationService: Sendable {
    private let baseSpots: [PhotoSpot]
    private let maxItemsPerSection = 5
    private let maxExpandedItemsPerSection = 16
    private let priorityTags = [
        "필름감성", "필름", "빈티지", "레트로", "로컬카페", "골목감성",
        "야경", "노을", "산책", "한적함", "데이트", "실내", "벚꽃",
        "철길", "한강", "초록", "로컬", "오래된거리", "강변", "사진구도",
        "꽃시즌", "꽃밭", "봄꽃", "유채꽃", "장미정원", "수레국화",
        "샤스타데이지", "꽃무릇", "남산타워뷰", "서울시티뷰", "철도출사",
        "숲길", "감성산책", "인물사진", "커플스냅", "촬영후기", "한강감성"
    ]
    private let overexposedSpotNeedles = [
        "남산타워", "경복궁", "롯데월드타워", "명동", "스타벅스",
        "두물머리", "일산호수공원"
    ]
    private let weakPhotoSpotNeedles = [
        "고척스카이돔", "고척스카이돔외부", "오류동역주변골목"
    ]

    init(seedService: LocalSeedDataService = LocalSeedDataService()) {
        baseSpots = seedService.allPhotoSpots()
    }

    func makeSnapshot(
        communityPosts: [CommunityPost] = [],
        userLocation: CLLocationCoordinate2D? = nil,
        weatherContext: RecommendationWeatherContext? = nil,
        referenceDate: Date = Date(),
        variationSeed: Int = 0
    ) -> HomeRecommendationSnapshot {
        let communitySignal = HomeCommunitySignal(posts: communityPosts)
        let timeContext = RecommendationTimeContext(referenceDate: referenceDate)
        let baseCandidates = baseSpots
            .filter { !CafeRecommendationPolicy.isBlacklistedCafe($0) }
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
            .shuffled()
        let scopedCandidates = locationScopedCandidates(from: baseCandidates, userLocation: userLocation)
        let candidates = scopedCandidates.spots

        var usedSpotIDs = Set<String>()
        var sections: [HomeRecommendationKind: [RecommendedSpot]] = [:]
        let assignmentOrder: [HomeRecommendationKind] = [.cafe, .night, .sunset, .film, .walk, .hidden, .rainy, .seasonal]

        let todayCandidatePool = imagePreferredTodayCandidates(
            todayCandidateSpots(from: candidates, userLocation: userLocation)
        )
        var todaySpots = variedTopSpots(
            ranked(
                todayCandidatePool,
                kind: nil,
                communitySignal: communitySignal,
                userLocation: userLocation,
                weatherContext: weatherContext,
                timeContext: timeContext
            ),
            count: maxItemsPerSection,
            variationSeed: variationSeed,
            salt: 0
        )

        if userLocation == nil, todaySpots.count < maxItemsPerSection {
            let existingTodayIDs = Set(todaySpots.map(\.id))
            let fallbackCandidatePool = imagePreferredTodayCandidates(
                todayFallbackSpots(from: candidates, userLocation: userLocation)
            )
            let fallbackSpots = ranked(
                fallbackCandidatePool,
                kind: nil,
                communitySignal: communitySignal,
                userLocation: userLocation,
                weatherContext: weatherContext,
                timeContext: timeContext
            )
                .filter { !existingTodayIDs.contains($0.id) }
                .prefix(maxItemsPerSection - todaySpots.count)
            todaySpots.append(contentsOf: fallbackSpots)
        }

        let todayRecommendations = todaySpots.map { spot in
            usedSpotIDs.insert(spot.id)
            return recommendation(
                for: spot,
                label: "오늘 추천",
                communitySignal: communitySignal,
                weatherContext: weatherContext,
                timeContext: timeContext
            )
        }

        for kind in assignmentOrder {
            let strictCandidates = candidates
                .filter { !usedSpotIDs.contains($0.id) }
                .filter { matches($0, kind: kind) }
            let expandedStrictCandidates = expandedSectionCandidates(
                for: kind,
                strictCandidates: strictCandidates,
                allCandidates: baseCandidates,
                usedSpotIDs: usedSpotIDs
            )
            let candidatePool = expandedStrictCandidates.isEmpty
                ? candidates
                    .filter { !usedSpotIDs.contains($0.id) }
                    .filter { relaxedMatches($0, kind: kind) }
                : expandedStrictCandidates
            let displayCandidatePool = imagePreferredCandidates(candidatePool, kind: kind)
            let spots = variedTopSpots(
                ranked(
                    displayCandidatePool,
                    kind: kind,
                    communitySignal: communitySignal,
                    userLocation: userLocation,
                    weatherContext: weatherContext,
                    timeContext: timeContext
                ),
                count: maxItemsPerSection,
                variationSeed: variationSeed,
                salt: assignmentOrder.firstIndex(of: kind) ?? 0
            )

            guard !spots.isEmpty else {
                logEmptyHomeSection(kind: kind, strictCandidateCount: expandedStrictCandidates.count)
                continue
            }

            let recommendations = spots.map { spot in
                usedSpotIDs.insert(spot.id)
                return recommendation(
                    for: spot,
                    label: kind.title,
                    communitySignal: communitySignal,
                    weatherContext: weatherContext,
                    timeContext: timeContext
                )
            }

            sections[kind] = recommendations
        }

        var expandedSections: [HomeRecommendationKind: [RecommendedSpot]] = [:]

        for kind in assignmentOrder {
            let featuredRecommendations = sections[kind] ?? []
            let featuredIDs = Set(featuredRecommendations.map(\.spot.id))
            let strictCandidates = baseCandidates
                .filter { !featuredIDs.contains($0.id) }
                .filter { matches($0, kind: kind) }
            let relaxedCandidates = baseCandidates
                .filter { !featuredIDs.contains($0.id) }
                .filter { relaxedMatches($0, kind: kind) }
            let strictExtraSpots = Array(ranked(
                imagePreferredCandidates(uniqueHomeSpots(strictCandidates), kind: kind),
                kind: kind,
                communitySignal: communitySignal,
                userLocation: userLocation,
                weatherContext: weatherContext,
                timeContext: timeContext
            )
                .filter { !featuredIDs.contains($0.id) }
                .prefix(max(0, maxExpandedItemsPerSection - featuredRecommendations.count)))
            let strictExtraIDs = Set(strictExtraSpots.map(\.id))
            let remainingCount = max(
                0,
                maxExpandedItemsPerSection - featuredRecommendations.count - strictExtraSpots.count
            )
            let relaxedExtraSpots = ranked(
                imagePreferredCandidates(uniqueHomeSpots(relaxedCandidates), kind: kind),
                kind: kind,
                communitySignal: communitySignal,
                userLocation: userLocation,
                weatherContext: weatherContext,
                timeContext: timeContext
            )
                .filter { !featuredIDs.contains($0.id) && !strictExtraIDs.contains($0.id) }
                .prefix(remainingCount)
            let extraSpots = strictExtraSpots + relaxedExtraSpots
            let extraRecommendations = extraSpots.map { spot in
                recommendation(
                    for: spot,
                    label: kind.title,
                    communitySignal: communitySignal,
                    weatherContext: weatherContext,
                    timeContext: timeContext
                )
            }

            expandedSections[kind] = featuredRecommendations + extraRecommendations
        }

        logRecommendationSnapshot(
            userLocation: userLocation,
            radius: scopedCandidates.radius,
            candidateCount: candidates.count,
            finalSpots: todayRecommendations.map(\.spot),
            fallbackUsed: scopedCandidates.fallbackUsed
        )

        return HomeRecommendationSnapshot(
            todayRecommendations: todayRecommendations,
            sections: sections,
            expandedSections: expandedSections
        )
    }

    private func expandedSectionCandidates(
        for kind: HomeRecommendationKind,
        strictCandidates: [PhotoSpot],
        allCandidates: [PhotoSpot],
        usedSpotIDs: Set<String>
    ) -> [PhotoSpot] {
        let globallyExpandedKinds: [HomeRecommendationKind] = [.cafe, .night, .film, .hidden]
        let minimumImageCount = min(maxItemsPerSection, 3)
        let shouldExpandGlobally = globallyExpandedKinds.contains(kind)
            && (
                strictCandidates.count < maxItemsPerSection
                || strictCandidates.filter(\.hasReliableDisplayImage).count < minimumImageCount
            )

        guard shouldExpandGlobally else {
            return imagePreferredCandidates(strictCandidates, kind: kind)
        }

        let existingIDs = Set(strictCandidates.map(\.id))
        let extraCandidates = allCandidates
            .filter { !usedSpotIDs.contains($0.id) }
            .filter { !existingIDs.contains($0.id) }
            .filter { matches($0, kind: kind) }

        return imagePreferredCandidates(
            uniqueHomeSpots(strictCandidates + extraCandidates),
            kind: kind
        )
    }

    private func uniqueHomeSpots(_ spots: [PhotoSpot]) -> [PhotoSpot] {
        spots.reduce(into: [PhotoSpot]()) { result, spot in
            guard !result.contains(where: { $0.id == spot.id }) else { return }
            result.append(spot)
        }
    }

    private func imagePreferredCandidates(_ candidates: [PhotoSpot], kind: HomeRecommendationKind) -> [PhotoSpot] {
        imagePrioritizedCandidates(candidates)
    }

    private func imagePreferredTodayCandidates(_ candidates: [PhotoSpot]) -> [PhotoSpot] {
        imagePrioritizedCandidates(candidates)
    }

    private func imagePrioritizedCandidates(_ candidates: [PhotoSpot]) -> [PhotoSpot] {
        candidates
            .filter(\.hasReliableDisplayImage)
            .enumerated()
            .sorted { left, right in
                return left.offset < right.offset
            }
            .map(\.element)
    }

    private func locationScopedCandidates(
        from candidates: [PhotoSpot],
        userLocation: CLLocationCoordinate2D?
    ) -> (spots: [PhotoSpot], radius: CLLocationDistance?, fallbackUsed: Bool) {
        guard let userLocation else {
            let defaultSeoulCandidates = candidates.filter {
                containsAny(searchableValues(for: $0), ["서울", "한강", "성수", "문래", "을지로", "연남", "선유도", "망원", "서촌", "해방촌", "북촌"])
            }
            return (defaultSeoulCandidates.isEmpty ? candidates : defaultSeoulCandidates, nil, true)
        }

        var nearestNonEmpty: (spots: [PhotoSpot], radius: CLLocationDistance)?

        for radius in [10_000.0, 20_000.0, 30_000.0] {
            let nearby = candidates.filter {
                distance(from: userLocation, to: $0) <= radius
            }
            let nearestSpots = nearby.sorted {
                distance(from: userLocation, to: $0) < distance(from: userLocation, to: $1)
            }

            if !nearestSpots.isEmpty, nearestNonEmpty == nil {
                nearestNonEmpty = (nearestSpots, radius)
            }

            if nearestSpots.count >= 18 {
                return (
                    Array(nearestSpots.prefix(42)),
                    radius,
                    false
                )
            }
        }

        if let nearestNonEmpty {
            return (
                Array(nearestNonEmpty.spots.prefix(42)),
                nearestNonEmpty.radius,
                false
            )
        }

        return ([], 30_000, false)
    }

    private func ranked(
        _ spots: [PhotoSpot],
        kind: HomeRecommendationKind?,
        communitySignal: HomeCommunitySignal,
        userLocation: CLLocationCoordinate2D?,
        weatherContext: RecommendationWeatherContext?,
        timeContext: RecommendationTimeContext
    ) -> [PhotoSpot] {
        spots
            .enumerated()
            .map { index, spot in
                RankedHomeSpot(
                    spot: spot,
                    score: score(
                        for: spot,
                        kind: kind,
                        communitySignal: communitySignal,
                        userLocation: userLocation,
                        weatherContext: weatherContext,
                        timeContext: timeContext
                    ),
                    originalIndex: index
                )
            }
            .sorted { left, right in
                if left.score == right.score {
                    return left.originalIndex < right.originalIndex
                }

                return left.score > right.score
            }
            .map(\.spot)
    }

    private func variedTopSpots(
        _ rankedSpots: [PhotoSpot],
        count: Int,
        variationSeed: Int,
        salt: Int
    ) -> [PhotoSpot] {
        guard count > 0, !rankedSpots.isEmpty else { return [] }

        let pool = Array(rankedSpots.prefix(count * 3))
        guard variationSeed > 0, pool.count > count else {
            return Array(pool.prefix(count))
        }

        let startIndex = ((variationSeed * count) + (salt * 2)) % pool.count
        return (0..<min(count, pool.count)).map { offset in
            pool[(startIndex + offset) % pool.count]
        }
    }

    private func score(
        for spot: PhotoSpot,
        kind: HomeRecommendationKind?,
        communitySignal: HomeCommunitySignal,
        userLocation: CLLocationCoordinate2D?,
        weatherContext: RecommendationWeatherContext?,
        timeContext: RecommendationTimeContext
    ) -> Int {
        var score = communitySignal.score(for: spot)
        score += aestheticScore(for: spot)
        score += proximityScore(for: spot, userLocation: userLocation)
        score += weatherScore(for: spot, weatherContext: weatherContext)
        score += timeScore(for: spot, timeContext: timeContext)

        if let kind, matches(spot, kind: kind) {
            score += 3
        }

        if spot.hasReliableDisplayImage {
            score += 2
        }

        if descriptionMatchesPhotoPurpose(spot, kind: kind) {
            score += 1
        }

        if RecommendationBlacklist.isBlacklistedRecommendation(spot) {
            score -= 1_000
        }

        if isOverexposedCandidate(spot) {
            score -= 80
        }

        if isWeakPhotoSpotCandidate(spot) {
            score -= 34
        }

        for tag in priorityTags where searchableValues(for: spot).contains(where: { containsAny($0, [tag]) }) {
            score += 4
        }

        switch kind {
        case .cafe:
            score += regionScore(for: spot, preferredRegions: ["문래", "성수", "을지로", "연남", "익선동", "서촌", "해방촌"]) * 9
            score += moodClusterScore(
                for: spot,
                regions: ["성수", "문래", "을지로", "연남"],
                moods: ["카페", "로컬카페", "골목", "저녁빛", "빈티지"]
            )
            if containsAny(searchableValues(for: spot), ["로컬카페", "독립카페", "공간", "뷰좋은카페"]) {
                score += 12
            }
        case .walk:
            score += regionScore(for: spot, preferredRegions: ["한강", "서울숲", "선유도", "북촌", "서촌", "해방촌", "보라매", "경의선숲길", "안양천", "항동", "서래섬", "반포", "이촌", "뚝섬", "양화", "망원", "잠원", "삼패", "하늘공원", "압구정"]) * 8
            score += moodClusterScore(
                for: spot,
                regions: ["한강", "서울숲", "선유도", "북촌", "경의선숲길", "안양천", "서래섬", "양화", "삼패", "하늘공원"],
                moods: ["산책", "초록", "강변", "골목", "조용함", "감성산책", "피크닉", "숲길"]
            )
        case .hidden:
            if isLikelyCrowded(spot) || isOverexposedCandidate(spot) || isWeakPhotoSpotCandidate(spot) {
                score -= 120
            }
            if spot.isHiddenSpot {
                score += 35
            }
            if normalized(spot.crowdLevelCode) == "low" {
                score += 18
            }
            if containsAny(searchableValues(for: spot), ["한적함", "숨은", "사람적음"]) {
                score += 10
            }
        case .film:
            score += regionScore(for: spot, preferredRegions: ["문래", "을지로", "익선동", "서촌", "해방촌", "북촌", "성수", "항동", "백빈", "하늘공원", "망원", "선유도"]) * 7
            score += moodClusterScore(
                for: spot,
                regions: ["문래", "을지로", "항동", "해방촌", "북촌", "백빈", "하늘공원", "망원", "선유도"],
                moods: ["필름감성", "빈티지", "레트로", "골목감성", "로컬감성", "철길", "오래된거리", "철도출사", "필름무드", "서울철도"]
            )
        case .sunset:
            score += regionScore(for: spot, preferredRegions: ["한강", "선유도", "노들섬", "반포", "망원", "서래섬", "안양천", "이촌", "뚝섬", "양화", "잠원", "삼패"]) * 7
            score += moodClusterScore(
                for: spot,
                regions: ["한강", "선유도", "망원", "서래섬", "안양천", "이촌", "뚝섬", "양화", "잠원", "삼패"],
                moods: ["노을", "강변", "산책", "실루엣", "남산타워뷰", "서울시티뷰", "블루아워", "인물사진"]
            )
        case .night:
            score += regionScore(for: spot, preferredRegions: ["성수", "을지로", "문래", "한강", "반포", "뚝섬", "한강로", "용산", "백빈"]) * 7
            score += moodClusterScore(
                for: spot,
                regions: ["문래", "을지로", "성수", "한강", "반포", "뚝섬", "용산"],
                moods: ["야경", "조명", "골목", "철골목", "도시", "한강야경", "도심야경", "남산타워뷰"]
            )
        case .rainy:
            if containsAny(spot.weather, ["rain", "비", "rainy"]) {
                score += 14
            }
            if containsAny(searchableValues(for: spot), ["실내", "카페", "미술관", "다방"]) {
                score += 8
            }
        case .seasonal:
            score += spot.season.count * 5
            if containsAny(searchableValues(for: spot), ["벚꽃", "단풍", "꽃", "계절", "꽃시즌", "유채꽃", "수레국화", "샤스타데이지", "꽃무릇", "장미정원", "봄꽃"]) {
                score += 18
            }
        case .none:
            score += regionScore(for: spot, preferredRegions: ["문래", "성수", "을지로", "연남", "익선동", "서촌", "해방촌", "한강", "서울숲", "선유도", "북촌", "망원", "보라매", "경의선숲길", "안양천", "항동", "서래섬", "반포", "이촌", "뚝섬", "양화", "잠원", "도농", "삼패", "하늘공원", "백빈"]) * 4
            score += moodClusterScore(
                for: spot,
                regions: ["성수", "문래", "연남", "한강", "안양천", "항동", "서래섬", "삼패", "백빈", "하늘공원"],
                moods: ["필름감성", "골목", "산책", "노을", "로컬카페", "조용함", "꽃시즌", "남산타워뷰", "철도출사", "인물사진"]
            )
            if spot.isHiddenSpot {
                score += 5
            }
        }

        return score
    }

    private func matches(_ spot: PhotoSpot, kind: HomeRecommendationKind) -> Bool {
        guard !RecommendationBlacklist.isBlacklistedRecommendation(spot) else {
            return false
        }

        let tags = spot.hashtags.map(normalized)
        let bestTime = normalized(spot.bestTime)
        let category = normalized(spot.category)
        let season = spot.season.map(normalized)
        let weather = spot.weather.map(normalized)
        let mood = spot.mood.map(normalized)
        let crowdLevel = normalized(spot.crowdLevelCode)

        switch kind {
        case .sunset:
            return containsAny(bestTime, ["노을", "sunset", "해질녘"]) || containsAny(tags, ["노을", "sunset", "해질녘"])
        case .night:
            return containsAny(bestTime, ["야경", "night", "밤"]) || containsAny(tags, ["야경", "night", "밤"])
        case .cafe:
            return category == "cafe" && CafeRecommendationPolicy.isIndependentCafeCandidate(spot)
        case .seasonal:
            return !season.isEmpty
        case .rainy:
            return containsAny(weather, ["rain", "비", "rainy"])
        case .walk:
            return ["park", "walk", "trail"].contains(category)
        case .film:
            let strongFilmSignals = ["필름", "레트로", "빈티지", "골목감성", "오래된거리", "로컬감성"]
            return !isGenericAlleyCandidate(spot)
                && (
                    containsAny(mood, strongFilmSignals)
                    || containsAny(tags, strongFilmSignals)
                )
        case .hidden:
            let hiddenCandidate = crowdLevel == "low"
                || spot.isHiddenSpot
            return hiddenCandidate
                && !isLikelyCrowded(spot)
                && !isOverexposedCandidate(spot)
                && !isWeakPhotoSpotCandidate(spot)
        }
    }

    private func relaxedMatches(_ spot: PhotoSpot, kind: HomeRecommendationKind) -> Bool {
        guard !RecommendationBlacklist.isBlacklistedRecommendation(spot) else {
            return false
        }

        switch kind {
        case .sunset:
            return matches(spot, kind: kind)
                || containsAny(searchableValues(for: spot), ["노을", "해질녘", "sunset", "블루아워", "한강", "강변", "남산타워뷰", "서울시티뷰"])
        case .night:
            return matches(spot, kind: kind)
                || containsAny(searchableValues(for: spot), ["야경", "night", "밤", "조명", "블루아워", "도시", "반영", "한강야경", "도심야경"])
        case .cafe:
            return matches(spot, kind: kind)
        case .seasonal:
            return matches(spot, kind: kind)
                || containsAny(searchableValues(for: spot), ["벚꽃", "단풍", "꽃", "계절", "봄", "가을", "유채꽃", "수레국화", "샤스타데이지", "꽃무릇", "장미정원", "꽃시즌"])
        case .rainy:
            return matches(spot, kind: kind)
                || (["indoor", "cafe"].contains(normalized(spot.category))
                    && containsAny(searchableValues(for: spot), ["실내", "카페", "비", "rain"]))
        case .walk:
            return matches(spot, kind: kind)
                || containsAny(searchableValues(for: spot), ["산책", "공원", "숲길", "한강", "강변", "감성산책", "피크닉"])
        case .film:
            return matches(spot, kind: kind)
                || (!isGenericAlleyCandidate(spot)
                    && containsAny(searchableValues(for: spot), ["필름감성", "레트로", "빈티지", "골목감성", "오래된거리", "로컬감성", "철도출사", "서울철도", "필름무드"]))
        case .hidden:
            return matches(spot, kind: kind)
        }
    }

    private func recommendation(
        for spot: PhotoSpot,
        label: String,
        communitySignal: HomeCommunitySignal,
        weatherContext: RecommendationWeatherContext?,
        timeContext: RecommendationTimeContext
    ) -> RecommendedSpot {
        let contextualReason = contextualReason(
            for: spot,
            label: label,
            weatherContext: weatherContext,
            timeContext: timeContext
        )
        let contextualLabel = contextualLabel(
            for: spot,
            label: label,
            weatherContext: weatherContext,
            timeContext: timeContext
        )

        return RecommendedSpot(
            spot: spot,
            reason: communitySignal.highlightReason(for: spot) ?? contextualReason ?? spot.eventPeriod
        )
    }

    private func contextualLabel(
        for spot: PhotoSpot,
        label: String,
        weatherContext: RecommendationWeatherContext?,
        timeContext: RecommendationTimeContext
    ) -> String {
        guard label == "오늘 추천" else { return label }

        if weatherContext?.hasBadAirQuality == true, isIndoorFriendly(spot) {
            return "미세먼지 실내 추천"
        }

        if weatherContext?.isRainy == true, isIndoorFriendly(spot) {
            return "비 오는 날 추천"
        }

        switch timeContext.phase {
        case .goldenHour where isSunsetFriendly(spot):
            return "노을 시간 추천"
        case .evening, .night:
            return isNightFriendly(spot) ? "야경 시간 추천" : label
        case .dawn, .morning:
            return isWalkFriendly(spot) ? "오전 산책 추천" : label
        default:
            return label
        }
    }

    private func contextualReason(
        for spot: PhotoSpot,
        label: String,
        weatherContext: RecommendationWeatherContext?,
        timeContext: RecommendationTimeContext
    ) -> String? {
        guard label == "오늘 추천" else { return nil }

        if weatherContext?.hasBadAirQuality == true, isIndoorFriendly(spot) {
            return "공기가 탁한 날에도 실내 동선으로 촬영하기 좋아요"
        }

        if weatherContext?.isRainy == true {
            if isIndoorFriendly(spot) {
                return "비 오는 날에도 실내와 지붕 있는 공간 위주로 담기 좋아요"
            }
            if containsAny(searchableValues(for: spot), ["반영", "네온", "우산"]) {
                return "비 오는 날 반영과 네온 분위기를 살리기 좋은 출사지예요"
            }
        }

        if weatherContext?.isClear == true, isSunsetFriendly(spot), timeContext.phase == .goldenHour {
            return "맑은 해질녘 빛과 실루엣을 담기 좋은 시간대예요"
        }

        switch timeContext.phase {
        case .goldenHour where isSunsetFriendly(spot):
            return "지금 시간대에는 노을빛과 역광 구도가 잘 살아나요"
        case .evening, .night:
            return isNightFriendly(spot) ? "저녁 조명과 야경 컷을 담기 좋은 시간대예요" : nil
        case .dawn, .morning:
            return isWalkFriendly(spot) ? "오전 자연광과 한적한 산책 컷을 기대하기 좋아요" : nil
        default:
            return nil
        }
    }

    private func regionScore(for spot: PhotoSpot, preferredRegions: [String]) -> Int {
        preferredRegions.reduce(0) { result, region in
            result + (containsAny(searchableValues(for: spot), [region]) ? 1 : 0)
        }
    }

    private func todayCandidateSpots(
        from candidates: [PhotoSpot],
        userLocation: CLLocationCoordinate2D?
    ) -> [PhotoSpot] {
        let eligible = candidates.filter { !isTodayRecommendationExcluded($0, userLocation: userLocation) }

        guard let userLocation else {
            return eligible
        }

        for radius in [10_000.0, 20_000.0, 30_000.0] {
            let nearby = eligible.filter { distance(from: userLocation, to: $0) <= radius }
            if !nearby.isEmpty {
                return nearby
            }
        }

        return []
    }

    private func todayFallbackSpots(
        from candidates: [PhotoSpot],
        userLocation: CLLocationCoordinate2D?
    ) -> [PhotoSpot] {
        candidates.filter {
            !isTodayRecommendationExcluded($0, userLocation: userLocation)
        }
    }

    private func isTodayRecommendationExcluded(
        _ spot: PhotoSpot,
        userLocation: CLLocationCoordinate2D?
    ) -> Bool {
        if RecommendationBlacklist.isBlacklistedRecommendation(spot)
            || isOverexposedCandidate(spot)
            || isWeakPhotoSpotCandidate(spot) {
            return true
        }

        if let userLocation {
            return distance(from: userLocation, to: spot) > 30_000
        }

        return containsAny(searchableValues(for: spot), ["부산", "강원", "강원도", "제주", "제주도"])
    }

    private func proximityScore(for spot: PhotoSpot, userLocation: CLLocationCoordinate2D?) -> Int {
        guard let userLocation else { return 0 }

        let distance = distance(from: userLocation, to: spot)
        switch distance {
        case ...3_000:
            return 80
        case ...10_000:
            return 45
        case ...20_000:
            return 18
        case ...30_000:
            return 8
        default:
            return -80
        }
    }

    private func weatherScore(for spot: PhotoSpot, weatherContext: RecommendationWeatherContext?) -> Int {
        guard let weatherContext else { return 0 }

        var score = 0
        let values = searchableValues(for: spot)

        if weatherContext.isRainy {
            if isIndoorFriendly(spot) || containsAny(values, ["비", "rain", "반영", "우산", "네온"]) {
                score += 34
            } else if isOutdoorOpenSpace(spot) {
                score -= 28
            }
        }

        if weatherContext.isSnowy {
            if containsAny(values, ["눈", "겨울", "실내", "카페", "한적함", "공원"]) {
                score += 20
            }
            if isOutdoorOpenSpace(spot) {
                score -= 8
            }
        }

        if weatherContext.isFoggy {
            if containsAny(values, ["안개", "몽환", "숲길", "강변", "한적함", "필름감성"]) {
                score += 22
            }
            if containsAny(values, ["전망", "스카이라인", "야경"]) {
                score -= 14
            }
        }

        if weatherContext.isClear {
            if isSunsetFriendly(spot) || isWalkFriendly(spot) || containsAny(values, ["빛", "자연광", "역광", "초록"]) {
                score += 18
            }
            if isNightFriendly(spot) {
                score += 6
            }
        }

        if weatherContext.isCloudy {
            if containsAny(values, ["필름감성", "골목", "빈티지", "레트로", "카페", "실내"]) {
                score += 16
            }
            if isSunsetFriendly(spot) {
                score -= 12
            }
        }

        if weatherContext.hasBadAirQuality {
            if isIndoorFriendly(spot) {
                score += 30
            }
            if isOutdoorOpenSpace(spot) || isSunsetFriendly(spot) || isNightFriendly(spot) {
                score -= 24
            }
        }

        if weatherContext.isTooHot || weatherContext.isTooCold || weatherContext.isWindy {
            if isIndoorFriendly(spot) {
                score += 18
            }
            if isWalkFriendly(spot) || isOutdoorOpenSpace(spot) {
                score -= 12
            }
        }

        return score
    }

    private func timeScore(for spot: PhotoSpot, timeContext: RecommendationTimeContext) -> Int {
        let values = searchableValues(for: spot)
        var score = 0

        switch timeContext.phase {
        case .dawn:
            if containsAny(values, ["오전", "새벽", "조용함", "한적함", "자연광", "숲길", "강변"]) {
                score += 18
            }
            if isLikelyCrowded(spot) {
                score -= 10
            }
        case .morning:
            if containsAny(values, ["오전", "자연광", "산책", "공원", "카페", "초록", "스냅"]) {
                score += 16
            }
        case .day:
            if isIndoorFriendly(spot) || containsAny(values, ["건축", "미술관", "박물관", "공간", "실내"]) {
                score += 12
            }
            if containsAny(values, ["한적함", "골목", "로컬카페"]) {
                score += 8
            }
        case .goldenHour:
            if isSunsetFriendly(spot) || containsAny(values, ["해질녘", "노을", "역광", "실루엣", "강변", "한강"]) {
                score += 36
            }
            if containsAny(values, ["오전"]) {
                score -= 8
            }
        case .evening:
            if isNightFriendly(spot) || containsAny(values, ["저녁", "블루아워", "조명", "네온", "도시", "카페"]) {
                score += 26
            }
            if isSunsetFriendly(spot) {
                score += 10
            }
        case .night:
            if isNightFriendly(spot) || containsAny(values, ["야경", "조명", "네온", "도시", "반영", "실내"]) {
                score += 28
            }
            if isWalkFriendly(spot) && !isNightFriendly(spot) {
                score -= 14
            }
        }

        return score
    }

    private func distance(from coordinate: CLLocationCoordinate2D, to spot: PhotoSpot) -> CLLocationDistance {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let destination = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        return destination.distance(from: origin)
    }

    private func aestheticScore(for spot: PhotoSpot) -> Int {
        let values = searchableValues(for: spot)
        var score = 0

        let moodSignals = [
            "필름감성", "골목감성", "골목", "산책", "노을", "야경", "철길",
            "빈티지", "레트로", "조용함", "한적함", "한강", "강변", "초록",
            "로컬카페", "오래된거리", "반영", "빛", "구도", "꽃시즌",
            "꽃밭", "봄꽃", "유채꽃", "장미정원", "수레국화", "샤스타데이지",
            "꽃무릇", "남산타워뷰", "서울시티뷰", "철도출사", "숲길",
            "감성산책", "인물사진", "커플스냅", "촬영후기", "한강감성"
        ]
        for signal in moodSignals where containsAny(values, [signal]) {
            score += 6
        }

        if spot.imageURL != nil || spot.imageName != nil {
            score += 10
        }

        if containsAny(values, ["관광지", "랜드마크", "대형", "몰", "쇼핑몰", "상권", "프랜차이즈", "체인", "핫플", "유명지점"]) {
            score -= 18
        }

        if isLikelyCrowded(spot) {
            score -= 10
        }

        return score
    }

    private func descriptionMatchesPhotoPurpose(_ spot: PhotoSpot, kind: HomeRecommendationKind?) -> Bool {
        let values = searchableValues(for: spot)
        let baseSignals = ["출사", "스냅", "촬영", "구도", "빛", "노을", "야경", "필름", "산책", "골목"]

        if containsAny(values, baseSignals) {
            return true
        }

        guard let kind else { return false }

        switch kind {
        case .sunset:
            return containsAny(values, ["노을", "해질녘", "실루엣"])
        case .night:
            return containsAny(values, ["야경", "조명", "반영"])
        case .cafe:
            return containsAny(values, ["카페", "로컬카페", "공간"])
        case .seasonal:
            return containsAny(values, ["꽃", "벚꽃", "단풍", "계절"])
        case .rainy:
            return containsAny(values, ["비", "실내", "반사"])
        case .walk:
            return containsAny(values, ["산책", "공원", "숲길", "강변"])
        case .film:
            return containsAny(values, ["필름", "레트로", "빈티지", "오래된거리", "로컬감성"])
        case .hidden:
            return containsAny(values, ["한적함", "조용함", "숨은"])
        }
    }

    private func moodClusterScore(for spot: PhotoSpot, regions: [String], moods: [String]) -> Int {
        let values = searchableValues(for: spot)
        let hasRegion = containsAny(values, regions)
        let moodMatches = moods.filter { containsAny(values, [$0]) }.count

        guard hasRegion, moodMatches > 0 else { return 0 }
        return 8 + min(moodMatches * 4, 16)
    }

    private func isOverexposedCandidate(_ spot: PhotoSpot) -> Bool {
        containsAny(searchableValues(for: spot), overexposedSpotNeedles)
    }

    private func isWeakPhotoSpotCandidate(_ spot: PhotoSpot) -> Bool {
        RecommendationBlacklist.isBlacklistedRecommendation(spot)
            || containsAny(searchableValues(for: spot), weakPhotoSpotNeedles)
    }

    private func isGenericAlleyCandidate(_ spot: PhotoSpot) -> Bool {
        containsAny(searchableValues(for: spot), ["역주변골목", "역 주변 골목", "일반주택가", "일반 주택가"])
    }

    private func isLikelyCrowded(_ spot: PhotoSpot) -> Bool {
        let crowdLevel = normalized(spot.crowdLevelCode)
        return crowdLevel == "crowded"
            || containsAny(searchableValues(for: spot), ["혼잡", "붐빔", "주말대기", "SNS핫플", "초대형핫플", "대표명소"])
    }

    private func isIndoorFriendly(_ spot: PhotoSpot) -> Bool {
        let category = normalized(spot.category)
        return ["indoor", "cafe"].contains(category)
            || containsAny(searchableValues(for: spot), ["실내", "카페", "미술관", "박물관", "공간", "다방", "전시"])
    }

    private func isOutdoorOpenSpace(_ spot: PhotoSpot) -> Bool {
        let category = normalized(spot.category)
        return ["park", "walk", "trail"].contains(category)
            || containsAny(searchableValues(for: spot), ["공원", "숲길", "한강", "강변", "산책", "야외", "노을"])
    }

    private func isSunsetFriendly(_ spot: PhotoSpot) -> Bool {
        containsAny(searchableValues(for: spot), ["노을", "해질녘", "sunset", "역광", "실루엣", "한강", "강변", "블루아워", "남산타워뷰", "서울시티뷰"])
    }

    private func isNightFriendly(_ spot: PhotoSpot) -> Bool {
        containsAny(searchableValues(for: spot), ["야경", "night", "밤", "조명", "네온", "도시", "반영", "블루아워", "한강야경", "도심야경"])
    }

    private func isWalkFriendly(_ spot: PhotoSpot) -> Bool {
        let category = normalized(spot.category)
        return ["park", "walk", "trail"].contains(category)
            || containsAny(searchableValues(for: spot), ["산책", "공원", "숲길", "강변", "한강", "초록", "골목", "감성산책", "피크닉"])
    }

    private func searchableValues(for spot: PhotoSpot) -> [String] {
        [spot.name, spot.region, spot.summary, spot.bestTime, spot.category, spot.crowdLevelCode]
            + spot.hashtags
            + spot.mood
            + spot.weather
            + spot.season
            + spot.recommendationRegions
    }

    private func containsAny(_ values: [String], _ needles: [String]) -> Bool {
        values.contains { value in
            containsAny(value, needles)
        }
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        let normalizedValue = normalized(value)
        return needles.map(normalized).contains { normalizedValue.contains($0) }
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private func logEmptyHomeSection(kind: HomeRecommendationKind, strictCandidateCount: Int) {
        let reason: String
        switch kind {
        case .sunset:
            reason = "bestTime/tags에 노을, sunset, 해질녘 후보 부족"
        case .night:
            reason = "bestTime/tags에 야경, night, 밤 후보 부족"
        case .cafe:
            reason = "category == cafe 이면서 프랜차이즈가 아닌 후보 부족"
        case .seasonal:
            reason = "season 값이 있는 후보 부족"
        case .rainy:
            reason = "weather에 rain/비/rainy 후보 부족"
        case .walk:
            reason = "category park/walk/trail 후보 부족"
        case .film:
            reason = "mood/tags에 필름/레트로/빈티지/골목감성 후보 부족"
        case .hidden:
            reason = "crowdLevel == low 또는 isHiddenSpot 후보 부족"
        }

        AppLog.recommendations.debug(
            "\(kind.title, privacy: .public) has no candidates: \(reason, privacy: .public), strictCandidates=\(strictCandidateCount)"
        )
    }

    private func logRecommendationSnapshot(
        userLocation: CLLocationCoordinate2D?,
        radius: CLLocationDistance?,
        candidateCount: Int,
        finalSpots: [PhotoSpot],
        fallbackUsed: Bool
    ) {
        let coordinateText = userLocation.map {
            String(format: "%.5f, %.5f", $0.latitude, $0.longitude)
        } ?? "없음"
        let radiusText = radius.map { "\(Int($0 / 1_000))km" } ?? "기본"
        let names = finalSpots.map(\.name).joined(separator: ", ")
        AppLog.recommendations.debug(
            "Home coordinate=\(coordinateText, privacy: .public) radius=\(radiusText, privacy: .public) candidates=\(candidateCount) final=[\(names, privacy: .public)] fallback=\(fallbackUsed)"
        )
    }
}

private struct RankedHomeSpot {
    let spot: PhotoSpot
    let score: Int
    let originalIndex: Int
}

private struct HomeCommunitySignal {
    private let tagCounts: [String: Int]

    init(posts: [CommunityPost]) {
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        tagCounts = posts
            .filter { $0.createdAt >= recentCutoff }
            .flatMap { $0.tags + $0.hashtags + $0.statusTags + $0.message.components(separatedBy: .whitespacesAndNewlines) }
            .map(Self.normalized)
            .filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { result, tag in
                result[tag, default: 0] += 1
            }
    }

    func score(for spot: PhotoSpot) -> Int {
        let searchable = searchableValues(for: spot)
        return tagCounts.reduce(0) { result, item in
            let (tag, count) = item
            guard searchable.contains(where: { $0.contains(tag) || tag.contains($0) }) else {
                return result
            }

            return result + min(count * 8, 32)
        }
    }

    func highlightLabel(for spot: PhotoSpot) -> String? {
        guard let tag = bestMatchingTag(for: spot) else { return nil }
        return "요즘 인기 #\(tag)"
    }

    func highlightReason(for spot: PhotoSpot) -> String? {
        guard let tag = bestMatchingTag(for: spot) else { return nil }
        return "커뮤니티에서 #\(tag) 이야기가 자주 올라오는 출사지예요"
    }

    private func bestMatchingTag(for spot: PhotoSpot) -> String? {
        let searchable = searchableValues(for: spot)
        return tagCounts
            .filter { item in
                searchable.contains { value in
                    value.contains(item.key) || item.key.contains(value)
                }
            }
            .sorted { left, right in
                if left.value == right.value {
                    return left.key < right.key
                }

                return left.value > right.value
            }
            .first?
            .key
    }

    private func searchableValues(for spot: PhotoSpot) -> [String] {
        ([spot.name, spot.region, spot.summary, spot.bestTime, spot.category, spot.crowdLevelCode]
            + spot.hashtags
            + spot.mood
            + spot.weather
            + spot.season
            + spot.recommendationRegions)
            .map(Self.normalized)
    }

    private static func normalized(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        let particles = ["에서는", "에서", "으로", "에게", "한테", "부터", "까지", "처럼", "보다", "로", "은", "는", "이", "가", "을", "를", "도", "만", "에", "와", "과", "랑"]
        if let particle = particles.first(where: { trimmed.count > $0.count + 1 && trimmed.hasSuffix($0) }) {
            return String(trimmed.dropLast(particle.count))
        }

        return trimmed
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

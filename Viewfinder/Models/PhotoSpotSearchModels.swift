import Foundation

struct PhotoSpotRecommendation: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let bestTime: String
    let reason: String
    let photoPoint: String?
    let tags: [String]
    let isFranchise: Bool?

    init(
        id: String,
        name: String,
        description: String,
        bestTime: String,
        reason: String,
        photoPoint: String? = nil,
        tags: [String],
        isFranchise: Bool? = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.bestTime = bestTime
        self.reason = reason
        self.photoPoint = photoPoint
        self.tags = tags
        self.isFranchise = isFranchise
    }
}

struct VerifiedPhotoSpot: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let bestTime: String
    let reason: String
    let tags: [String]
    let address: String
    let latitude: Double
    let longitude: Double
    let source: String
    let imageURL: URL?

    var photoSpot: PhotoSpot {
        PhotoSpot(
            id: source == "local" ? id : "verified-\(source)-\(id)",
            name: name,
            region: address,
            summary: description,
            hashtags: normalizedTags,
            eventTitle: "추천 이유",
            eventPeriod: reason,
            feeInfo: "방문 전 공식 정보 확인 필요",
            openingHours: "이용 가능시간 확인 필요",
            bestTime: bestTime,
            crowdLevel: "방문 전 혼잡도 확인 추천",
            lensSuggestion: lensSuggestion,
            weatherFit: "오늘 날씨와 현장 상황을 보고 촬영 동선을 잡아보세요",
            parkingInfo: "주차 정보 확인 필요",
            nearbyParkingInfo: "네이버 지도 또는 카카오맵에서 주변 주차장 확인",
            communityTitle: "\(name) 실시간",
            communitySubtitle: "날씨, 혼잡도, 촬영 포인트 공유 예정",
            mapQuery: "\(name) \(address)",
            latitude: latitude,
            longitude: longitude,
            theme: inferredTheme,
            imageURL: imageURL,
            category: inferredCategory,
            weather: inferredWeather,
            mood: normalizedTags,
            crowdLevelCode: "normal"
        )
    }

    private var normalizedTags: [String] {
        let cleaned = tags
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleaned.isEmpty ? ["출사지", "AI추천"] : Array(cleaned.prefix(4))
    }

    private var lensSuggestion: String {
        if normalizedTags.contains(where: { $0.contains("야경") || $0.contains("노을") || $0.contains("전망") }) {
            return "24-70mm 줌, 야경은 밝은 단렌즈"
        }

        if normalizedTags.contains(where: { $0.contains("카페") || $0.contains("실내") }) {
            return "35mm 또는 50mm 밝은 단렌즈"
        }

        return "35mm 스냅 또는 24-70mm 표준 줌"
    }

    private var inferredTheme: SpotTheme {
        let text = ([name, description, reason, address] + normalizedTags).joined(separator: " ")

        if text.contains("야경") || text.contains("밤") || text.contains("조명") {
            return .night
        }

        if text.contains("카페") || text.contains("실내") || text.contains("미술관") {
            return .indoor
        }

        if text.contains("꽃") || text.contains("정원") || text.contains("식물") {
            return .flower
        }

        if text.contains("한강") || text.contains("호수") || text.contains("바다") || text.contains("물") {
            return .water
        }

        if text.contains("공원") || text.contains("숲") || text.contains("산책") {
            return .healing
        }

        return .city
    }

    private var inferredCategory: String {
        let text = ([name, description, reason, address] + normalizedTags).joined(separator: " ")

        if text.contains("카페") || text.lowercased().contains("cafe") {
            return "cafe"
        }

        if text.contains("공원") || text.contains("숲") {
            return "park"
        }

        if text.contains("산책") || text.contains("길") {
            return "walk"
        }

        return "spot"
    }

    private var inferredWeather: [String] {
        let text = ([name, description, reason, address] + normalizedTags).joined(separator: " ")
        guard text.contains("비") || text.lowercased().contains("rain") else { return [] }
        return ["rain"]
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - 추천 장소
//
//  원래 이름은 GPTRecommendedSpot 이었고 GPTRecommendationService.swift
//  안에 있었습니다. 그 서비스가 지워지면서 이곳으로 옮겼습니다.
//  GPT 가 만드는 것이 아니므로 이름에서 GPT 를 뺐습니다.
//  지금 추천을 만드는 것은 HomeRecommendationService 입니다.
//  131곳 시드와 커뮤니티 제보를 거리·시간대·날씨·혼잡도로 고르는
//  로컬 규칙 코드입니다.
//
//  필드가 둘 줄었습니다.
//   scoreLabel        "카카오 검증", "기본 데이터" 같은 내부 사정 문자열
//   isGeneratedByGPT  AI 생성 여부
//  둘 다 값만 넣고 읽는 곳이 없었습니다. 화면에 그려지지 않았습니다.
//  특히 scoreLabel 은 남겨두면 언젠가 화면에 나올 위험이 있었습니다.
//  사용자는 카카오가 검증했는지 네이버가 검증했는지 알 필요가 없습니다.
// ═══════════════════════════════════════════════════════════════════

struct RecommendedSpot: Identifiable, Equatable, Sendable {
    let spot: PhotoSpot
    /// 왜 이 장소를 지금 추천하는지 한 줄.
    let reason: String

    var id: String {
        spot.id
    }
}

import CoreLocation
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
    /// 네이버 지역 검색이 돌려준 원본 분류입니다.
    /// 기존 검증 응답과 시드 데이터에는 없을 수 있으므로 optional 로 둡니다.
    let category: String?
    let address: String
    let latitude: Double
    let longitude: Double
    let source: String
    let imageURL: URL?
    /// 외부 검색 공급자와 안정적인 장소 ID입니다. 이전 응답에는 없을 수 있습니다.
    let provider: String?
    let providerPlaceID: String?

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
            crowdLevelCode: "normal",
            provider: provider ?? source,
            providerPlaceID: providerPlaceID,
            galleryPhotos: imageURL.map { url in
                [
                    PlacePhoto(
                        id: "verified-\(source)-\(id)-cover",
                        placeID: source == "local" ? id : "verified-\(source)-\(id)",
                        imageURL: url,
                        source: .seed
                    )
                ]
            } ?? []
        )
    }

    private var normalizedTags: [String] {
        let cleaned = tags
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleaned.isEmpty ? ["출사지", "AI추천"] : Array(cleaned.prefix(4))
    }

    /// 결과 목록에서 보여 줄 한 줄 분류입니다.
    /// 네이버의 `카페,디저트>커피전문점` 같은 경로는 읽기 쉬운 구분자로
    /// 바꾸고, 이전 응답처럼 원본 분류가 없을 때만 태그를 보조값으로 씁니다.
    var displayCategory: String {
        let trimmedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCategory.isEmpty {
            return trimmedCategory
                .components(separatedBy: CharacterSet(charactersIn: ">,/"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }

        return normalizedTags.prefix(2).joined(separator: " · ")
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
        SpotTheme.resolve(
            name: name,
            description: description,
            tags: normalizedTags,
            category: category
        )
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

enum PlaceSubmissionAvailability: String, Equatable, Sendable {
    case registered
    case new

    var badgeTitle: String? {
        switch self {
        case .registered:
            return "등록됨"
        case .new:
            return nil
        }
    }
}

/// 장소 중복 검사의 공통 비교 단위입니다.
/// 기존 장소에는 provider ID가 없을 수 있으므로 모든 보조 식별자를 함께 보관합니다.
struct PlaceIdentity: Equatable, Sendable {
    let id: String?
    let provider: String?
    let providerPlaceID: String?
    let name: String
    let address: String
    let mapQuery: String
    let latitude: Double?
    let longitude: Double?

    init(
        id: String? = nil,
        provider: String? = nil,
        providerPlaceID: String? = nil,
        name: String,
        address: String,
        mapQuery: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.provider = provider
        self.providerPlaceID = providerPlaceID
        self.name = name
        self.address = address
        self.mapQuery = mapQuery
        self.latitude = latitude
        self.longitude = longitude
    }

    init(spot: PhotoSpot) {
        self.init(
            id: spot.id,
            provider: spot.provider,
            providerPlaceID: spot.providerPlaceID,
            name: spot.name,
            address: spot.region,
            mapQuery: spot.mapQuery,
            latitude: spot.latitude,
            longitude: spot.longitude
        )
    }
}

enum PlaceIdentityMatcher {
    /// 같은 건물 안의 다른 POI를 합치지 않도록 수십 미터 수준으로 제한합니다.
    static let coordinateThresholdMeters: CLLocationDistance = 60

    static func matches(_ lhs: PlaceIdentity, _ rhs: PlaceIdentity) -> Bool {
        let lhsProviderID = normalized(lhs.providerPlaceID)
        let rhsProviderID = normalized(rhs.providerPlaceID)
        let lhsProvider = normalized(lhs.provider)
        let rhsProvider = normalized(rhs.provider)

        if !lhsProviderID.isEmpty, !rhsProviderID.isEmpty,
           !lhsProvider.isEmpty, lhsProvider == rhsProvider {
            if lhsProviderID == rhsProviderID {
                return true
            }
        }

        let lhsID = normalized(lhs.id)
        let rhsID = normalized(rhs.id)
        if !lhsID.isEmpty, lhsID == rhsID {
            return true
        }

        let nameMatches = textMatches(lhs.name, rhs.name)
        let addressMatches = textMatches(lhs.address, rhs.address)
        let mapQueryMatches = textMatches(lhs.mapQuery, rhs.mapQuery)

        // 이름과 주소(또는 검색 query)가 함께 맞으면 provider ID가 없는
        // 기존 121개 장소도 안정적으로 등록됨으로 분류합니다.
        if nameMatches && (addressMatches || mapQueryMatches) {
            return true
        }

        guard let lhsCoordinate = coordinate(for: lhs),
              let rhsCoordinate = coordinate(for: rhs),
              lhsCoordinate.distance(from: rhsCoordinate) <= coordinateThresholdMeters else {
            return false
        }

        // 좌표만으로는 같은 건물 안의 서로 다른 장소를 합치지 않습니다.
        return nameMatches || addressMatches
    }

    static func normalized(_ value: String?) -> String {
        guard let value else { return "" }
        let normalized = value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        return String(normalized.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })
    }

    private static func textMatches(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.contains(right) || right.contains(left)
    }

    private static func coordinate(for identity: PlaceIdentity) -> CLLocation? {
        guard let latitude = identity.latitude,
              let longitude = identity.longitude,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              abs(latitude) > 0.000001 || abs(longitude) > 0.000001 else {
            return nil
        }

        return CLLocation(latitude: latitude, longitude: longitude)
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


// ═══════════════════════════════════════════════════════════════════
// MARK: - 장소 검색·검증·제보 실패
//
//  [이 타입이 이 파일로 온 이유]
//  GeminiRecommendationService.swift 안에 있었습니다. AI 코드를 정리하며
//  그 파일을 지웠는데 이 타입은 살아 있었고, 두 서비스가 계속 쓰고
//  있어서 빌드가 깨졌습니다. 공용 타입이므로 모델 파일로 옮깁니다.
//
//  [모양을 바꿨습니다]
//  전에는 이랬습니다.
//    case configuration(String)
//    case server(String)
//  그리고 errorDescription 이 그 String 을 그대로 돌려줬습니다.
//
//  그래서 이런 것이 사용자 화면에 닿았습니다.
//    "장소 검증 서버 주소가 설정되지 않았어요"
//    "카카오 또는 네이버 장소검색 API 키를 확인해야 해요"
//    "장소 검증 서버 오류가 발생했어요 (500)"
//  마지막은 더 나빴습니다. PlaceVerificationService 가 서버 응답의
//  error 필드를 그대로 반환하고 있어서, 서버가 보낸
//    KAKAO_REST_API_KEY or NAVER_CLIENT_ID/NAVER_CLIENT_SECRET is required
//  같은 영문 환경변수 이름이 사용자에게 그대로 표시될 수 있었습니다.
//
//  문구만 고쳐도 됐지만 그러면 같은 일이 반복됩니다. 케이스가 String 을
//  들고 있고 그 String 이 화면에 쓰이는 구조라면, 누군가는 언젠가
//  서버 문자열을 거기에 넣습니다.
//
//  그래서 타입에서 "화면에 쓸 문자열"을 없앴습니다.
//  케이스는 무슨 일이 일어났는지만 말하고, 사용자 문구는 이 타입이
//  혼자 정합니다. 서버가 준 설명은 diagnostic 에 들어가고 로그로만
//  나갑니다. 실수를 기억으로 막지 않고 구조로 막습니다.
// ═══════════════════════════════════════════════════════════════════

enum PhotoSpotSearchError: LocalizedError, Equatable {
    /// 서버 주소가 없습니다.
    ///
    /// 릴리스 빌드는 HTTPS 가 아닌 주소를 의도적으로 무시하므로
    /// (AppInfrastructure 의 AppBackendConfiguration) 로컬 주소만 설정된
    /// 상태도 여기에 해당합니다. 다시 시도해도 결과가 같습니다.
    case notConfigured

    /// 서버에 닿았지만 실패했습니다.
    ///
    /// diagnostic 은 원인을 찾기 위한 것이고 화면에 쓰지 않습니다.
    /// errorDescription 이 이 값을 절대 읽지 않는 것이 이 타입의 핵심입니다.
    case server(statusCode: Int, diagnostic: String)

    /// 응답을 해석할 수 없습니다.
    case malformedResponse

    /// 결과가 없습니다.
    case empty

    /// 화면에 그대로 쓸 수 있는 문구.
    ///
    /// 이 타입은 자기가 검색에서 났는지 제보에서 났는지 모릅니다.
    /// 그래서 문구도 어느 기능인지 말하지 않습니다. 기능 이름이 필요한
    /// 자리에서는 호출하는 쪽이 앞에 붙입니다.
    /// (PlaceFinder.failureMessage, ContentView.submissionFailureMessage)
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "지금은 이 기능을 쓸 수 없어요"
        case .server, .malformedResponse:
            return "잠시 후 다시 시도해주세요"
        case .empty:
            return "결과가 없어요"
        }
    }

    /// 로그로만 나가는 설명. 화면에 쓰지 않습니다.
    var diagnosticDescription: String {
        switch self {
        case .notConfigured:
            return "backend endpoint is not configured (empty or non-HTTPS in release)"
        case .server(let statusCode, let diagnostic):
            return "server responded \(statusCode): \(diagnostic)"
        case .malformedResponse:
            return "response could not be decoded"
        case .empty:
            return "no results"
        }
    }

    /// 다시 시도해서 달라질 수 있는 실패인지.
    ///
    /// 사용자에게 "잠시 후 다시 시도해주세요" 라고 말해도 되는지를
    /// 판단하는 데 씁니다. 주소가 설정되지 않은 상태는 몇 번을 다시
    /// 해도 같으므로, 그 경우에 재시도를 권하면 거짓말이 됩니다.
    var isWorthRetrying: Bool {
        switch self {
        case .notConfigured:
            return false
        case .server, .malformedResponse, .empty:
            return true
        }
    }
}

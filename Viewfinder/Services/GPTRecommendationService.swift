import CoreLocation
import Foundation

struct GPTRecommendation: Identifiable, Equatable {
    let id: String
    let spotID: String
    let reason: String
    let scoreLabel: String

    init(spotID: String, reason: String, scoreLabel: String) {
        id = spotID
        self.spotID = spotID
        self.reason = reason
        self.scoreLabel = scoreLabel
    }
}

struct GPTRecommendedSpot: Identifiable, Equatable {
    let spot: PhotoSpot
    let reason: String
    let scoreLabel: String
    let isGeneratedByGPT: Bool

    var id: String {
        spot.id
    }
}

struct GPTRecommendationResult {
    let recommendations: [GPTRecommendedSpot]
    let statusMessage: String?
}

struct GPTDiscoveredSpot: Identifiable, Decodable, Equatable {
    let name: String
    let region: String
    let mapQuery: String
    let summary: String
    let hashtags: [String]
    let reason: String
    let scoreLabel: String
    let theme: String
    let parkingInfo: String
    let nearbyParkingInfo: String
    let openingHours: String?
    let bestTime: String?
    let crowdLevel: String?
    let lensSuggestion: String?
    let weatherFit: String?

    var id: String {
        "\(name)-\(region)-\(mapQuery)"
    }
}

struct GPTDiscoveryRegion {
    let query: String
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct GPTDiscoveryResult {
    let spots: [GPTDiscoveredSpot]
    let statusMessage: String?
}

struct GPTRecommendationService {
    private struct RequestBody: Encodable {
        struct SpotPayload: Encodable {
            let id: String
            let name: String
            let region: String
            let summary: String
            let hashtags: [String]
            let category: String
            let recommendationRegions: [String]
            let mood: [String]
            let isHiddenSpot: Bool
            let parkingInfo: String
            let nearbyParkingInfo: String
            let latitude: Double
            let longitude: Double
        }

        struct UserLocationPayload: Encodable {
            let latitude: Double
            let longitude: Double
        }

        struct SearchRegionPayload: Encodable {
            let query: String
            let name: String
            let latitude: Double
            let longitude: Double
        }

        let date: String
        let currentTime: String
        let hour: Int
        let timeZone: String
        let locale: String
        let moodCategory: String?
        let userLocation: UserLocationPayload?
        let searchRegion: SearchRegionPayload?
        let localDataPolicy: String
        let spots: [SpotPayload]
    }

    private struct ResponseBody: Decodable {
        struct RecommendationPayload: Decodable {
            let spotID: String
            let reason: String
            let scoreLabel: String?
        }

        let recommendations: [RecommendationPayload]
    }

    private struct DiscoveryResponseBody: Decodable {
        let spots: [GPTDiscoveredSpot]
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    var endpointURL: URL? {
        guard
            let rawValue = Bundle.main.object(forInfoDictionaryKey: "ViewfinderRecommendationEndpoint") as? String,
            !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return URL(string: rawValue)
    }

    func recommendations(
        from spots: [PhotoSpot],
        userLocation: CLLocationCoordinate2D? = nil
    ) async -> GPTRecommendationResult {
        guard let endpointURL else {
            return fallbackResult(from: spots, message: "추천 서버 주소가 설정되지 않았어요")
        }

        do {
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(requestBody(from: spots, userLocation: userLocation))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return fallbackResult(from: spots, message: "추천 서버 응답을 읽지 못했어요")
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                return fallbackResult(
                    from: spots,
                    message: statusMessage(from: data, statusCode: httpResponse.statusCode)
                )
            }

            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            let recommended = decoded.recommendations.compactMap { item -> GPTRecommendedSpot? in
                guard let spot = spots.first(where: { $0.id == item.spotID }) else { return nil }
                guard !RecommendationBlacklist.isBlacklistedRecommendation(spot) else { return nil }
                return GPTRecommendedSpot(
                    spot: spot,
                    reason: item.reason,
                    scoreLabel: item.scoreLabel ?? "AI 추천",
                    isGeneratedByGPT: true
                )
            }

            if recommended.isEmpty {
                return fallbackResult(from: spots, message: "AI 추천 결과가 비어 있어요")
            }

            return GPTRecommendationResult(recommendations: recommended, statusMessage: nil)
        } catch {
            return fallbackResult(from: spots, message: "추천 서버에 연결하지 못했어요")
        }
    }

    func discoverSpots(
        from spots: [PhotoSpot],
        userLocation: CLLocationCoordinate2D? = nil,
        searchRegion: GPTDiscoveryRegion? = nil,
        moodCategory: String? = nil
    ) async -> GPTDiscoveryResult {
        guard let endpointURL = discoveryEndpointURL else {
            return GPTDiscoveryResult(spots: [], statusMessage: "추천 서버 주소가 설정되지 않았어요")
        }

        do {
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 18
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                requestBody(
                    from: spots,
                    userLocation: userLocation,
                    searchRegion: searchRegion,
                    moodCategory: moodCategory
                )
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return GPTDiscoveryResult(spots: [], statusMessage: "추천 서버 응답을 읽지 못했어요")
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                return GPTDiscoveryResult(
                    spots: [],
                    statusMessage: statusMessage(from: data, statusCode: httpResponse.statusCode)
                )
            }

            let decoded = try JSONDecoder().decode(DiscoveryResponseBody.self, from: data)
            let allowedSpots = decoded.spots.filter {
                !RecommendationBlacklist.containsBlacklistedText([
                    $0.name,
                    $0.region,
                    $0.mapQuery,
                    $0.summary,
                    $0.reason,
                    $0.scoreLabel
                ] + $0.hashtags)
            }
            guard !allowedSpots.isEmpty else {
                return GPTDiscoveryResult(spots: [], statusMessage: "AI 추천 결과가 비어 있어요")
            }

            return GPTDiscoveryResult(spots: allowedSpots, statusMessage: nil)
        } catch {
            return GPTDiscoveryResult(spots: [], statusMessage: "추천 서버에 연결하지 못했어요")
        }
    }

    private func requestBody(
        from spots: [PhotoSpot],
        userLocation: CLLocationCoordinate2D?,
        searchRegion: GPTDiscoveryRegion? = nil,
        moodCategory: String? = nil
    ) -> RequestBody {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd EEEE"

        let now = Date()
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ko_KR")
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return RequestBody(
            date: formatter.string(from: now),
            currentTime: timeFormatter.string(from: now),
            hour: calendar.component(.hour, from: now),
            timeZone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            moodCategory: moodCategory,
            userLocation: userLocation.map {
                RequestBody.UserLocationPayload(latitude: $0.latitude, longitude: $0.longitude)
            },
            searchRegion: searchRegion.map {
                RequestBody.SearchRegionPayload(
                    query: $0.query,
                    name: $0.name,
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                )
            },
            localDataPolicy: "AI 추천은 로컬 출사지 후보의 지역, 태그, 카테고리, 커뮤니티 신호를 보강하는 용도로만 사용한다. 행정구역이나 유명 관광지보다 사진 결과물이 예쁘게 나오는 실제 출사 포인트를 우선한다. 성수=카페+골목+저녁빛, 문래=빈티지+철골목+야간출사, 연남=산책+감성카페+골목, 한강=노을+야경+산책처럼 지역 감성 조합을 반영한다. 사람 적은 명소는 유명 관광지, SNS 초대형 핫플, 주말 혼잡 장소를 제외하고 조용한 공원/산책길/골목을 우선한다.\n\(RecommendationBlacklist.geminiInstruction)",
            spots: spots.filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }.map {
                RequestBody.SpotPayload(
                    id: $0.id,
                    name: $0.name,
                    region: $0.region,
                    summary: $0.summary,
                    hashtags: $0.hashtags,
                    category: $0.category,
                    recommendationRegions: $0.recommendationRegions,
                    mood: $0.mood,
                    isHiddenSpot: $0.isHiddenSpot,
                    parkingInfo: $0.parkingInfo,
                    nearbyParkingInfo: $0.nearbyParkingInfo,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
        )
    }

    private var discoveryEndpointURL: URL? {
        guard let endpointURL else { return nil }

        if endpointURL.lastPathComponent == "discover-spots" {
            return endpointURL
        }

        return endpointURL.deletingLastPathComponent().appendingPathComponent("discover-spots")
    }

    private func fallbackResult(from spots: [PhotoSpot], message: String) -> GPTRecommendationResult {
        let recommendations = spots
            .filter { !RecommendationBlacklist.isBlacklistedRecommendation($0) }
            .prefix(6)
            .map { spot in
            GPTRecommendedSpot(
                spot: spot,
                reason: message,
                scoreLabel: "기본 추천",
                isGeneratedByGPT: false
            )
        }

        return GPTRecommendationResult(recommendations: recommendations, statusMessage: message)
    }

    private func statusMessage(from data: Data, statusCode: Int) -> String {
        if let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            let lowercasedError = errorBody.error.lowercased()

            if lowercasedError.contains("quota")
                || lowercasedError.contains("billing")
                || lowercasedError.contains("resource_exhausted") {
                return "AI 사용량 한도 또는 결제 설정을 확인해야 해요"
            }

            if lowercasedError.contains("gemini_api_key") || lowercasedError.contains("gemini api key") {
                return "Gemini API 키를 확인해야 해요"
            }

            if lowercasedError.contains("openai_api_key") || lowercasedError.contains("openai api key") {
                return "OpenAI API 키를 확인해야 해요"
            }

            if lowercasedError.contains("api_key") || lowercasedError.contains("api key") {
                return "AI API 키를 확인해야 해요"
            }
        }

        return "추천 서버 오류가 발생했어요 (\(statusCode))"
    }
}

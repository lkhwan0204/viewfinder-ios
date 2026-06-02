import CoreLocation
import Foundation

struct GeminiRecommendationService {
    private struct RequestBody: Encodable {
        struct UserLocationPayload: Encodable {
            let latitude: Double
            let longitude: Double
        }

        let query: String
        let date: String
        let currentTime: String
        let hour: Int
        let timeZone: String
        let locale: String
        let userLocation: UserLocationPayload?
        let cafeRecommendationPolicy: String
        let expectedCandidateFields: [String]
    }

    private struct ResponseBody: Decodable {
        let recommendations: [PhotoSpotRecommendation]
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    func recommendations(
        for query: String,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> [PhotoSpotRecommendation] {
        guard let endpointURL else {
            throw PhotoSpotSearchError.configuration("추천 서버 주소가 설정되지 않았어요")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody(query: query, userLocation: userLocation))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoSpotSearchError.server("추천 서버 응답을 읽지 못했어요")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw PhotoSpotSearchError.server(statusMessage(from: data, statusCode: httpResponse.statusCode))
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.recommendations.filter {
            SearchRegionPolicy.allowsRecommendationCandidate($0, query: query)
                && !CafeRecommendationPolicy.isBlacklistedRecommendation($0)
                && !RecommendationBlacklist.isBlacklistedRecommendation($0)
        }
    }

    private var endpointURL: URL? {
        guard
            let rawValue = Bundle.main.object(forInfoDictionaryKey: "ViewfinderRecommendationEndpoint") as? String,
            let baseURL = URL(string: rawValue)
        else {
            return nil
        }

        return baseURL.deletingLastPathComponent().appendingPathComponent("spot-recommendations")
    }

    private func requestBody(query: String, userLocation: CLLocationCoordinate2D?) -> RequestBody {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd EEEE"

        let now = Date()
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ko_KR")
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return RequestBody(
            query: query,
            date: formatter.string(from: now),
            currentTime: timeFormatter.string(from: now),
            hour: calendar.component(.hour, from: now),
            timeZone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            userLocation: userLocation.map {
                RequestBody.UserLocationPayload(latitude: $0.latitude, longitude: $0.longitude)
            },
            cafeRecommendationPolicy: "\(CafeRecommendationPolicy.geminiInstruction)\n\(RecommendationBlacklist.geminiInstruction)",
            expectedCandidateFields: [
                "id",
                "name",
                "description",
                "bestTime",
                "reason",
                "photoPoint",
                "tags",
                "isFranchise"
            ]
        )
    }

    private func statusMessage(from data: Data, statusCode: Int) -> String {
        if let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            let lowercasedError = errorBody.error.lowercased()

            if lowercasedError.contains("gemini_api_key") || lowercasedError.contains("api key") {
                return "Gemini API 키를 확인해야 해요"
            }

            if lowercasedError.contains("quota")
                || lowercasedError.contains("rate-limit")
                || lowercasedError.contains("rate_limits")
                || lowercasedError.contains("free_tier") {
                return "Gemini 무료 사용량 한도에 잠시 걸렸어요. 조금 뒤 다시 시도해보세요."
            }

            return errorBody.error
        }

        return "추천 서버 오류가 발생했어요 (\(statusCode))"
    }
}

enum PhotoSpotSearchError: LocalizedError, Equatable {
    case configuration(String)
    case server(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .configuration(let message), .server(let message):
            return message
        case .empty:
            return "검색 결과가 없어요"
        }
    }
}

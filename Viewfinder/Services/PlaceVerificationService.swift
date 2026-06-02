import CoreLocation
import Foundation

struct PlaceVerificationService {
    private struct RequestBody: Encodable {
        struct UserLocationPayload: Encodable {
            let latitude: Double
            let longitude: Double
        }

        let region: String
        let userLocation: UserLocationPayload?
        let recommendations: [PhotoSpotRecommendation]
    }

    private struct ResponseBody: Decodable {
        let spots: [VerifiedPhotoSpot]
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    func verify(
        recommendations: [PhotoSpotRecommendation],
        region: String,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> [VerifiedPhotoSpot] {
        guard let endpointURL else {
            throw PhotoSpotSearchError.configuration("장소 검증 서버 주소가 설정되지 않았어요")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let allowedRecommendations = recommendations.filter {
            SearchRegionPolicy.allowsRecommendationCandidate($0, query: region)
                && !CafeRecommendationPolicy.isBlacklistedRecommendation($0)
                && !RecommendationBlacklist.isBlacklistedRecommendation($0)
        }

        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                region: region,
                userLocation: userLocation.map {
                    RequestBody.UserLocationPayload(latitude: $0.latitude, longitude: $0.longitude)
                },
                recommendations: allowedRecommendations
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoSpotSearchError.server("장소 검증 서버 응답을 읽지 못했어요")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw PhotoSpotSearchError.server(statusMessage(from: data, statusCode: httpResponse.statusCode))
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.spots.filter {
            SearchRegionPolicy.matches($0, query: region)
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

        return baseURL.deletingLastPathComponent().appendingPathComponent("verify-spots")
    }

    private func statusMessage(from data: Data, statusCode: Int) -> String {
        if let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            let lowercasedError = errorBody.error.lowercased()

            if lowercasedError.contains("kakao") || lowercasedError.contains("naver") {
                return "카카오 또는 네이버 장소검색 API 키를 확인해야 해요"
            }

            return errorBody.error
        }

        return "장소 검증 서버 오류가 발생했어요 (\(statusCode))"
    }
}

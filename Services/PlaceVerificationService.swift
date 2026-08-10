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

        let (data, response) = try await BackendClient.shared.data(for: request)
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
        AppBackendConfiguration.current.endpoint(named: "verify-spots")
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

struct PlaceSearchService {
    private struct RequestBody: Encodable {
        struct UserLocationPayload: Encodable {
            let latitude: Double
            let longitude: Double
        }

        let query: String
        let userLocation: UserLocationPayload?
    }

    private struct ResponseBody: Decodable {
        let spots: [VerifiedPhotoSpot]
    }

    private struct ErrorBody: Decodable {
        let error: String
        let code: String?
    }

    func search(
        query: String,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> [VerifiedPhotoSpot] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        return try await searchServer(
            query: trimmedQuery,
            userLocation: userLocation
        )
    }

    private func searchServer(
        query: String,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> [VerifiedPhotoSpot] {
        guard let endpointURL else {
            throw PhotoSpotSearchError.configuration("장소 검색 서버 주소가 설정되지 않았어요")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                query: query,
                userLocation: userLocation.map {
                    RequestBody.UserLocationPayload(latitude: $0.latitude, longitude: $0.longitude)
                }
            )
        )

        let (data, response) = try await BackendClient.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoSpotSearchError.server("장소 검색 서버 응답을 읽지 못했어요")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data)

            if errorBody?.code == "naver_place_search_unconfigured" {
                throw PhotoSpotSearchError.configuration(
                    "네이버 실제 장소검색 설정이 아직 완료되지 않았어요"
                )
            }

            let message = errorBody?.error ?? "장소 검색 중 오류가 발생했어요"
            throw PhotoSpotSearchError.server(message)
        }

        return try JSONDecoder().decode(ResponseBody.self, from: data).spots
    }

    private var endpointURL: URL? {
        AppBackendConfiguration.current.endpoint(named: "search-places")
    }
}

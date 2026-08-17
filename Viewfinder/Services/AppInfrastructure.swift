import Foundation
import OSLog

enum AsyncLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)

    var isLoading: Bool {
        self == .loading
    }

    var errorMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}

enum AppLog {
    static let network = Logger(subsystem: "com.lkh.photoshoot", category: "Network")
    static let location = Logger(subsystem: "com.lkh.photoshoot", category: "Location")
    static let persistence = Logger(subsystem: "com.lkh.photoshoot", category: "Persistence")
    static let authentication = Logger(subsystem: "com.lkh.photoshoot", category: "Authentication")
    static let recommendations = Logger(subsystem: "com.lkh.photoshoot", category: "Recommendations")
}

struct AppBackendConfiguration {
    static let current = AppBackendConfiguration()

    let recommendationURL: URL?

    init(bundle: Bundle = .main) {
        guard let rawValue = bundle.object(
            forInfoDictionaryKey: "ViewfinderRecommendationEndpoint"
        ) as? String else {
            recommendationURL = nil
            return
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              !trimmedValue.contains("$("),
              let url = URL(string: trimmedValue) else {
            recommendationURL = nil
            return
        }

#if DEBUG
        recommendationURL = url
#else
        recommendationURL = url.scheme?.lowercased() == "https" ? url : nil
#endif
    }

    /// 서버를 부를 수 있는 상태인지.
    ///
    /// 이 값이 false 면 장소 검색과 장소 제보가 동작하지 않습니다.
    /// 릴리스 빌드에서 VIEWFINDER_RECOMMENDATION_ENDPOINT 가 비어 있으면
    /// (지금 상태입니다) 여기가 false 입니다.
    ///
    /// 화면에서 이 값을 보고 "할 수 없는 일을 제안하지 않는" 판단을
    /// 합니다. 사용자가 제보 양식을 다 채운 뒤에 실패하는 것보다,
    /// 처음부터 아직 준비되지 않았다고 말하는 편이 낫습니다.
    var isConfigured: Bool {
        recommendationURL != nil
    }

    func endpoint(named path: String) -> URL? {
        recommendationURL?
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}

final class BackendClient: @unchecked Sendable {
    static let shared = BackendClient()

    private let session: URLSession
    private let availabilityGate: BackendAvailabilityGate

    init(
        session: URLSession? = nil,
        availabilityGate: BackendAvailabilityGate = .shared
    ) {
        self.availabilityGate = availabilityGate

        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        configuration.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        guard await availabilityGate.canAttempt(url) else {
            AppLog.network.debug(
                "Skipping temporarily unavailable backend: \(url.host ?? "unknown", privacy: .public)"
            )
            throw URLError(.cannotConnectToHost)
        }

        do {
            let response = try await session.data(for: request)
            await availabilityGate.markAvailable(url)
            return response
        } catch {
            if let urlError = error as? URLError, urlError.isTransientConnectionFailure {
                await availabilityGate.markUnavailable(url)
            }
            AppLog.network.error(
                "Request failed: \(request.url?.absoluteString ?? "unknown", privacy: .public), \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        return try await data(for: request)
    }
}

actor BackendAvailabilityGate {
    static let shared = BackendAvailabilityGate()

    private var retryDatesByHost: [String: Date] = [:]
    private let retryInterval: TimeInterval

    init(retryInterval: TimeInterval = 30) {
        self.retryInterval = retryInterval
    }

    func canAttempt(_ url: URL, now: Date = Date()) -> Bool {
        guard let host = url.host,
              let retryDate = retryDatesByHost[host] else {
            return true
        }

        if now >= retryDate {
            retryDatesByHost[host] = nil
            return true
        }

        return false
    }

    func markAvailable(_ url: URL) {
        guard let host = url.host else { return }
        retryDatesByHost[host] = nil
    }

    func markUnavailable(_ url: URL, now: Date = Date()) {
        guard let host = url.host else { return }
        retryDatesByHost[host] = now.addingTimeInterval(retryInterval)
    }
}

private extension URLError {
    var isTransientConnectionFailure: Bool {
        switch code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

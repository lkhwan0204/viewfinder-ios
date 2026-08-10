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

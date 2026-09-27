import CoreLocation
import Foundation
import OSLog

struct WeatherService {
    private let client: BackendClient

    init(client: BackendClient = .shared) {
        self.client = client
    }

    func snapshot(
        for coordinate: CLLocationCoordinate2D,
        diagnosticStartedAt: TimeInterval? = nil
    ) async throws -> WeatherSnapshot {
        guard let url = weatherURL(for: coordinate) else {
            throw URLError(.badURL)
        }

        let forecastRequestStartedAt = ProcessInfo.processInfo.systemUptime
        logHomeWeather("forecast API request started", since: diagnosticStartedAt)
        let (data, response) = try await client.data(from: url)
        logHomeWeather(
            "forecast API response received",
            since: diagnosticStartedAt,
            detail: "request=\(elapsed(since: forecastRequestStartedAt))s"
        )
        try validate(response)
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let timeZone = TimeZone(identifier: decoded.timezone ?? "")
            ?? decoded.utc_offset_seconds.flatMap { TimeZone(secondsFromGMT: $0) }
            ?? .current
        let fineDustRequestStartedAt = ProcessInfo.processInfo.systemUptime
        logHomeWeather("fine dust API request started", since: diagnosticStartedAt)
        let fineDust = try? await fineDust(for: coordinate)
        logHomeWeather(
            "fine dust API finished",
            since: diagnosticStartedAt,
            detail: "request=\(elapsed(since: fineDustRequestStartedAt))s result=\(fineDust == nil ? "unavailable" : "available")"
        )

        let snapshot = WeatherSnapshot(
            condition: weatherDescription(for: decoded.current.weatherCode),
            temperature: Int(decoded.current.temperature2M.rounded()),
            highTemperature: Int(
                (decoded.daily.temperature2MMax.first ?? decoded.current.temperature2M).rounded()
            ),
            lowTemperature: Int(
                (decoded.daily.temperature2MMin.first ?? decoded.current.temperature2M).rounded()
            ),
            apparentTemperature: Int(decoded.current.apparentTemperature.rounded()),
            humidity: decoded.current.relativeHumidity2M,
            precipitation: decoded.current.precipitation,
            cloudCover: decoded.current.cloudCover,
            windSpeed: decoded.current.windSpeed10M,
            fineDust: fineDust,
            hourlyForecasts: hourlyForecasts(from: decoded, timeZone: timeZone),
            timeZoneIdentifier: timeZone.identifier,
            fetchedAt: Date(),
            sunrise: solarDate(decoded.daily.sunrise, at: 0, timeZone: timeZone),
            sunset: solarDate(decoded.daily.sunset, at: 0, timeZone: timeZone),
            tomorrowSunrise: solarDate(decoded.daily.sunrise, at: 1, timeZone: timeZone)
        )
        logHomeWeather("weather payload ready", since: diagnosticStartedAt)
        return snapshot
    }

    private func logHomeWeather(
        _ event: String,
        since startedAt: TimeInterval?,
        detail: String? = nil
    ) {
#if DEBUG
        guard let startedAt else { return }
        let totalElapsed = elapsed(since: startedAt)
        let suffix = detail.map { " \($0)" } ?? ""
        AppLog.network.debug(
            "[HomeWeather] \(event) +\(totalElapsed)s\(suffix, privacy: .public)"
        )
#endif
    }

    private func elapsed(since startedAt: TimeInterval) -> String {
        String(format: "%.2f", max(0, ProcessInfo.processInfo.systemUptime - startedAt))
    }

    /// Open-Meteo 의 "yyyy-MM-dd'T'HH:mm" 문자열을 Date 로 변환합니다.
    /// hourlyForecasts 와 동일한 포맷/타임존 규칙을 씁니다.
    private func solarDate(
        _ values: [String]?,
        at index: Int,
        timeZone: TimeZone
    ) -> Date? {
        guard let values, values.indices.contains(index) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: values[index])
    }

    private func fineDust(for coordinate: CLLocationCoordinate2D) async throws -> FineDustSnapshot {
        guard let url = fineDustURL(for: coordinate) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await client.data(from: url)
        try validate(response)
        let decoded = try JSONDecoder().decode(OpenMeteoAirQualityResponse.self, from: data)
        return FineDustSnapshot(
            pm10: decoded.hourly.pm10.compactMap { $0 }.first,
            pm25: decoded.hourly.pm25.compactMap { $0 }.first
        )
    }

    private func weatherURL(for coordinate: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,cloud_cover,weather_code,wind_speed_10m"
            ),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,weather_code,precipitation_probability,cloud_cover"
            ),
            URLQueryItem(
                name: "daily",
                value: "temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset"
            ),
            // 2일치를 받습니다. 일몰 이후에는 "내일 일출까지" 를 보여줘야 하는데
            // 1일치만 받으면 그 시점에 표시할 다음 이벤트가 없습니다.
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return components?.url
    }

    private func fineDustURL(for coordinate: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents(
            string: "https://air-quality-api.open-meteo.com/v1/air-quality"
        )
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "hourly", value: "pm10,pm2_5"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return components?.url
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
    }

    private func hourlyForecasts(
        from decoded: OpenMeteoResponse,
        timeZone: TimeZone
    ) -> [WeatherHourlyForecast] {
        let hourly = decoded.hourly
        let count = min(
            hourly.time.count,
            hourly.temperature2M.count,
            hourly.weatherCode.count,
            hourly.cloudCover.count
        )
        guard count > 0 else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        return (0..<count)
            .compactMap { index -> WeatherHourlyForecast? in
                guard let date = formatter.date(from: hourly.time[index]),
                      date >= now.addingTimeInterval(-60 * 60) else {
                    return nil
                }

                let hour = calendar.component(.hour, from: date)
                return WeatherHourlyForecast(
                    timeLabel: "\(hour)시",
                    condition: weatherDescription(for: hourly.weatherCode[index]),
                    temperature: Int(hourly.temperature2M[index].rounded()),
                    precipitationProbability: hourly.precipitationProbability?[safe: index],
                    cloudCover: hourly.cloudCover[index]
                )
            }
            .prefix(12)
            .map { $0 }
    }

    private func weatherDescription(for code: Int) -> String {
        switch code {
        case 0:
            return "맑음"
        case 1...3:
            return "구름 조금"
        case 45, 48:
            return "안개"
        case 51...67, 80...82:
            return "비"
        case 71...77, 85...86:
            return "눈"
        case 95...99:
            return "천둥"
        default:
            return "날씨 확인"
        }
    }
}

/// The rounded location key used by both the request coalescer and the cache.
struct WeatherContextKey: Hashable {
    let latitude: Int
    let longitude: Int

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = Int((coordinate.latitude * 100).rounded())
        longitude = Int((coordinate.longitude * 100).rounded())
    }

    var logDescription: String {
        "\(latitude)/100,\(longitude)/100"
    }
}

@MainActor
final class WeatherStore: ObservableObject {
    private static let defaultLocationTitle = "현재 위치 기반"

    private struct CachedWeather {
        let snapshot: WeatherSnapshot
        let locationTitle: String
    }

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var locationTitle = WeatherStore.defaultLocationTitle
    @Published private(set) var state: AsyncLoadState = .idle

    private let service: WeatherService
    private let geocoder = CLGeocoder()
    private let locationChangeThresholdMeters: CLLocationDistance = 1_500
    private var contextCoordinate: CLLocationCoordinate2D?
    private var lastFetchDate: Date?
    private var loadRevision = 0
    private var locationContextRevision = 0
    private(set) var inFlightRequestID: Int?
    private(set) var inFlightRequestContextKey: WeatherContextKey?
    private var cachedSnapshots: [WeatherContextKey: CachedWeather] = [:]

    init(service: WeatherService = WeatherService()) {
        self.service = service
    }

    var hasFailed: Bool {
        state.errorMessage != nil
    }

    /// A recent snapshot is safe to keep visible while Core Location is
    /// temporarily unavailable. It is deliberately time-bounded so the Home
    /// pill never turns into an indefinitely stale weather value.
    var hasFreshSnapshot: Bool {
        guard let snapshot else { return false }
        return Date().timeIntervalSince(snapshot.fetchedAt) < 30 * 60
    }

    func hasInFlightRequest(for coordinate: CLLocationCoordinate2D) -> Bool {
        state.isLoading && inFlightRequestContextKey == WeatherContextKey(coordinate)
    }

    func load(
        for coordinate: CLLocationCoordinate2D,
        fallbackTitle: String? = nil,
        force: Bool = false,
        diagnosticStartedAt: TimeInterval? = nil
    ) async {
        let requestedContextKey = WeatherContextKey(coordinate)
        let isSameContext = isCurrentLocationContext(coordinate)

        guard !Task.isCancelled else {
            logHomeWeather("cancelled before request start", since: diagnosticStartedAt)
            return
        }

        // GPS가 같은 생활권 안에서 연속 값을 내보낼 때 동일한 네트워크 요청을
        // 겹쳐 시작하지 않습니다. force도 이미 진행 중인 요청을 복제하지 않습니다.
        if state.isLoading, inFlightRequestContextKey == requestedContextKey {
            logHomeWeather("cache lookup finished", since: diagnosticStartedAt, detail: "result=in-flight request")
            debugLog("request coalesced context=\(requestedContextKey.logDescription)")
            return
        }

        if !force,
           isSameContext,
           snapshot != nil,
           state == .loaded,
           let lastFetchDate,
           Date().timeIntervalSince(lastFetchDate) < 30 * 60 {
            logHomeWeather("cache lookup finished", since: diagnosticStartedAt, detail: "result=fresh current snapshot")
            return
        }

        let contextChanged = contextCoordinate != nil && !isSameContext
        if contextCoordinate == nil || contextChanged {
            contextCoordinate = coordinate
            locationContextRevision &+= 1
        }

        var cacheLookupResult = snapshot == nil ? "miss" : "current snapshot stale"
        if contextChanged || snapshot == nil {
            if let cached = freshCachedWeather(for: requestedContextKey) {
                snapshot = cached.snapshot
                lastFetchDate = cached.snapshot.fetchedAt
                locationTitle = cached.locationTitle
                cacheLookupResult = "context cache hit"
                debugLog("using cached weather context=\(requestedContextKey.logDescription)")
            } else if contextChanged {
                // 다른 생활권의 이전 날씨를 현재 위치처럼 보여주지 않습니다.
                // 다만 동일 context의 캐시가 있으면 위에서 먼저 복원합니다.
                clearSnapshot(reason: "context changed without matching cache")
                locationTitle = fallbackTitle ?? Self.defaultLocationTitle
            }
        } else if let fallbackTitle,
                  locationTitle == Self.defaultLocationTitle {
            locationTitle = fallbackTitle
        }
        logHomeWeather("cache lookup finished", since: diagnosticStartedAt, detail: "result=\(cacheLookupResult)")

        loadRevision &+= 1
        let revision = loadRevision
        state = .loading
        inFlightRequestID = revision
        inFlightRequestContextKey = requestedContextKey
        logHomeWeather("weather request started", since: diagnosticStartedAt, detail: "id=\(revision)")
        debugLog("request started id=\(revision) context=\(requestedContextKey.logDescription)")

        do {
            let newSnapshot = try await service.snapshot(
                for: coordinate,
                diagnosticStartedAt: diagnosticStartedAt
            )
            logHomeWeather("weather response received", since: diagnosticStartedAt, detail: "id=\(revision) snapshot assembled")
            guard !Task.isCancelled,
                  revision == loadRevision,
                  isCurrentLocationContext(coordinate) else {
                if revision == loadRevision {
                    finishRequest(revision: revision, state: snapshot == nil ? .idle : .loaded)
                    logHomeWeather("request cancelled", since: diagnosticStartedAt, detail: "id=\(revision) reason=task or context")
                    debugLog("request cancelled id=\(revision)")
                } else {
                    logHomeWeather("stale response ignored", since: diagnosticStartedAt, detail: "id=\(revision) current=\(loadRevision)")
                    debugLog("ignored stale response id=\(revision)")
                }
                return
            }
            snapshot = newSnapshot
            lastFetchDate = Date()
            cachedSnapshots[requestedContextKey] = CachedWeather(
                snapshot: newSnapshot,
                locationTitle: locationTitle
            )
            state = .loaded
            clearInFlightRequest(revision: revision)
            logHomeWeather("weather state updated", since: diagnosticStartedAt, detail: "id=\(revision)")
            debugLog("request success id=\(revision) context=\(requestedContextKey.logDescription)")
        } catch {
            if Task.isCancelled {
                guard revision == loadRevision else {
                    logHomeWeather("cancelled request ignored", since: diagnosticStartedAt, detail: "id=\(revision) current=\(loadRevision)")
                    debugLog("request cancelled as stale id=\(revision)")
                    return
                }
                finishRequest(revision: revision, state: snapshot == nil ? .idle : .loaded)
                logHomeWeather("request cancelled", since: diagnosticStartedAt, detail: "id=\(revision)")
                debugLog("request cancelled id=\(revision)")
                return
            }

            guard revision == loadRevision,
                  isCurrentLocationContext(coordinate) else {
                logHomeWeather("stale failure ignored", since: diagnosticStartedAt, detail: "id=\(revision) current=\(loadRevision)")
                debugLog("ignored stale failure id=\(revision)")
                return
            }
            AppLog.network.error(
                "Weather fetch failed: \(error.localizedDescription, privacy: .public)"
            )
            logHomeWeather("weather request failed", since: diagnosticStartedAt, detail: "id=\(revision)")
            state = .failed(message: "날씨 정보를 불러오지 못했어요")
            clearInFlightRequest(revision: revision)
            debugLog("request failed id=\(revision)")
        }
    }

    func updateLocationTitle(for coordinate: CLLocationCoordinate2D) async {
        let contextRevision = locationContextRevision
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        do {
            guard let placemark = try await geocoder.reverseGeocodeLocation(location).first else {
                return
            }
            guard contextRevision == locationContextRevision,
                  isCurrentLocationContext(coordinate) else {
                return
            }
            let title = Self.displayLocationTitle(from: placemark)
            if !title.isEmpty {
                locationTitle = title
            }
        } catch {
            AppLog.location.error(
                "Reverse geocoding failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// 위치 권한이 사라져 좌표가 nil이 된 경우 Main이 호출합니다.
    /// 진행 중 응답은 revision guard에서 폐기하고, 호출자가 요청하면
    /// 아직 신선한 snapshot만 화면에 남겨 fallback으로 사용할 수 있습니다.
    func invalidateLocationContext(preservingFreshSnapshot: Bool = false) {
        let preservedSnapshot = preservingFreshSnapshot && hasFreshSnapshot ? snapshot : nil
        let preservedLocationTitle = locationTitle

        loadRevision &+= 1
        locationContextRevision &+= 1
        inFlightRequestID = nil
        inFlightRequestContextKey = nil
        geocoder.cancelGeocode()
        contextCoordinate = nil

        if let preservedSnapshot {
            snapshot = preservedSnapshot
            locationTitle = preservedLocationTitle
            lastFetchDate = preservedSnapshot.fetchedAt
            state = .loaded
            debugLog("using cached weather after location invalidation")
        } else {
            clearSnapshot(reason: "location context invalidated")
            locationTitle = Self.defaultLocationTitle
            lastFetchDate = nil
            state = .idle
        }
    }

    private func freshCachedWeather(for key: WeatherContextKey) -> CachedWeather? {
        guard let cached = cachedSnapshots[key],
              Date().timeIntervalSince(cached.snapshot.fetchedAt) < 30 * 60 else {
            return nil
        }
        return cached
    }

    private func clearSnapshot(reason: String) {
        snapshot = nil
        lastFetchDate = nil
        debugLog("state cleared reason=\(reason)")
    }

    private func finishRequest(revision: Int, state nextState: AsyncLoadState) {
        guard revision == loadRevision else { return }
        state = nextState
        clearInFlightRequest(revision: revision)
    }

    private func clearInFlightRequest(revision: Int) {
        guard revision == loadRevision else { return }
        inFlightRequestID = nil
        inFlightRequestContextKey = nil
    }

    private func debugLog(_ message: String) {
#if DEBUG
        AppLog.network.debug("[HomeWeather] \(message, privacy: .public)")
#endif
    }

    private func logHomeWeather(
        _ event: String,
        since startedAt: TimeInterval?,
        detail: String? = nil
    ) {
#if DEBUG
        guard let startedAt else { return }
        let elapsed = String(
            format: "%.2f",
            max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        )
        let suffix = detail.map { " \($0)" } ?? ""
        AppLog.network.debug(
            "[HomeWeather] \(event) +\(elapsed)s\(suffix, privacy: .public)"
        )
#endif
    }

    private func isCurrentLocationContext(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let contextCoordinate else { return false }
        let currentLocation = CLLocation(
            latitude: contextCoordinate.latitude,
            longitude: contextCoordinate.longitude
        )
        let candidateLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        return currentLocation.distance(from: candidateLocation) < locationChangeThresholdMeters
    }

    private static func displayLocationTitle(from placemark: CLPlacemark) -> String {
        let tokens = locationTokens(from: placemark)
        let city = firstLocationToken(
            in: tokens,
            suffixes: ["특별시", "광역시", "특별자치시", "특별자치도", "도"]
        )
        let district = firstLocationToken(
            in: tokens,
            suffixes: ["구", "군", "시"],
            excluding: [city]
        )
        let neighborhood = firstLocationToken(
            in: tokens,
            suffixes: ["동", "읍", "면", "리"],
            excluding: [city, district]
        )

        let preferred = [city, district, neighborhood]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) {
                    result.append(item)
                }
            }
        if !preferred.isEmpty {
            return preferred.joined(separator: " ")
        }

        return [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.subLocality
        ]
            .compactMap { normalizedLocationToken($0) }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) {
                    result.append(item)
                }
            }
            .joined(separator: " ")
    }

    private static func locationTokens(from placemark: CLPlacemark) -> [String] {
        [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.name
        ]
            .compactMap { $0 }
            .flatMap { value in
                value
                    .replacingOccurrences(of: ",", with: " ")
                    .split(separator: " ")
                    .map(String.init)
            }
            .compactMap { normalizedLocationToken($0) }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) {
                    result.append(item)
                }
            }
    }

    private static func firstLocationToken(
        in tokens: [String],
        suffixes: [String],
        excluding excluded: [String?] = []
    ) -> String? {
        let excludedValues = Set(excluded.compactMap { $0 })
        return tokens.first { token in
            !excludedValues.contains(token)
                && !token.hasSuffix("로")
                && !token.hasSuffix("길")
                && suffixes.contains(where: { token.hasSuffix($0) })
        }
    }

    private static func normalizedLocationToken(_ value: String?) -> String? {
        guard var token = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        token = token
            .replacingOccurrences(of: "대한민국", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

extension WeatherSnapshot {
    var recommendationContext: RecommendationWeatherContext {
        RecommendationWeatherContext(
            condition: condition,
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            precipitation: precipitation,
            cloudCover: cloudCover,
            windSpeed: windSpeed,
            pm10: fineDust?.pm10,
            pm25: fineDust?.pm25,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

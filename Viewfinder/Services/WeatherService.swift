import CoreLocation
import Foundation
import OSLog

struct WeatherService {
    private let client: BackendClient

    init(client: BackendClient = .shared) {
        self.client = client
    }

    func snapshot(for coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        guard let url = weatherURL(for: coordinate) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await client.data(from: url)
        try validate(response)
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let fineDust = try? await fineDust(for: coordinate)

        return WeatherSnapshot(
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
            hourlyForecasts: hourlyForecasts(from: decoded),
            sunrise: solarDate(decoded.daily.sunrise, at: 0),
            sunset: solarDate(decoded.daily.sunset, at: 0),
            tomorrowSunrise: solarDate(decoded.daily.sunrise, at: 1)
        )
    }

    /// Open-Meteo 의 "yyyy-MM-dd'T'HH:mm" 문자열을 Date 로 변환합니다.
    /// hourlyForecasts 와 동일한 포맷/타임존 규칙을 씁니다.
    private func solarDate(_ values: [String]?, at index: Int) -> Date? {
        guard let values, values.indices.contains(index) else { return nil }
        return Self.solarFormatter.date(from: values[index])
    }

    private static let solarFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

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
            URLQueryItem(name: "timezone", value: "Asia/Seoul")
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
            URLQueryItem(name: "timezone", value: "Asia/Seoul")
        ]
        return components?.url
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
    }

    private func hourlyForecasts(from decoded: OpenMeteoResponse) -> [WeatherHourlyForecast] {
        let hourly = decoded.hourly
        let count = min(
            hourly.time.count,
            hourly.temperature2M.count,
            hourly.weatherCode.count,
            hourly.cloudCover.count
        )
        guard count > 0 else { return [] }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
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

@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var locationTitle = "현재 위치 기반"
    @Published private(set) var state: AsyncLoadState = .idle

    private let service: WeatherService
    private let geocoder = CLGeocoder()
    private var coordinateKey: String?
    private var lastFetchDate: Date?
    private var loadRevision = 0

    init(service: WeatherService = WeatherService()) {
        self.service = service
    }

    var hasFailed: Bool {
        state.errorMessage != nil
    }

    func load(
        for coordinate: CLLocationCoordinate2D,
        fallbackTitle: String? = nil,
        force: Bool = false
    ) async {
        let key = coordinateCacheKey(for: coordinate)
        if !force,
           coordinateKey == key,
           snapshot != nil,
           state == .loaded,
           let lastFetchDate,
           Date().timeIntervalSince(lastFetchDate) < 30 * 60 {
            return
        }

        coordinateKey = key
        loadRevision &+= 1
        let revision = loadRevision
        if let fallbackTitle, locationTitle == "현재 위치 기반" {
            locationTitle = fallbackTitle
        }
        state = .loading

        do {
            let newSnapshot = try await service.snapshot(for: coordinate)
            guard revision == loadRevision else { return }
            snapshot = newSnapshot
            lastFetchDate = Date()
            state = .loaded
        } catch {
            guard revision == loadRevision else { return }
            AppLog.network.error(
                "Weather fetch failed: \(error.localizedDescription, privacy: .public)"
            )
            state = .failed(message: "날씨 정보를 불러오지 못했어요")
        }
    }

    func updateLocationTitle(for coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        do {
            guard let placemark = try await geocoder.reverseGeocodeLocation(location).first else {
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

    private func coordinateCacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        "\(Int((coordinate.latitude * 100).rounded()))-\(Int((coordinate.longitude * 100).rounded()))"
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
            pm25: fineDust?.pm25
        )
    }
}

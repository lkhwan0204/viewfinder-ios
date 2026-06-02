import Foundation
import SwiftUI

struct WeatherSnapshot: Equatable {
    let condition: String
    let temperature: Int
    let highTemperature: Int
    let lowTemperature: Int
    let apparentTemperature: Int
    let humidity: Int
    let precipitation: Double
    let cloudCover: Int
    let windSpeed: Double
    let fineDust: FineDustSnapshot?
    let hourlyForecasts: [WeatherHourlyForecast]

    var displayText: String {
        "\(temperature)°"
    }

    var accentColor: Color {
        switch condition {
        case "맑음":
            return AppColors.primary.opacity(0.72)
        case "비", "천둥":
            return AppColors.primary.opacity(0.72)
        case "눈":
            return AppColors.secondaryText
        case "안개":
            return AppColors.secondaryText
        default:
            return AppColors.secondaryText
        }
    }

    var symbolName: String {
        switch condition {
        case "맑음":
            return "sun.max.fill"
        case "구름 조금":
            return "cloud.sun.fill"
        case "비":
            return "cloud.rain.fill"
        case "눈":
            return "cloud.snow.fill"
        case "안개":
            return "cloud.fog.fill"
        case "천둥":
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.sun.fill"
        }
    }
}

struct FineDustSnapshot: Equatable {
    let pm10: Double?
    let pm25: Double?

    var summary: String {
        guard let pm10 else {
            return "정보 없음"
        }

        if let pm25 {
            return "\(grade(forPM10: pm10)) · PM10 \(Int(pm10.rounded())) · PM2.5 \(Int(pm25.rounded()))"
        }

        return "\(grade(forPM10: pm10)) · PM10 \(Int(pm10.rounded()))"
    }

    private func grade(forPM10 value: Double) -> String {
        switch value {
        case ..<31:
            return "좋음"
        case ..<81:
            return "보통"
        case ..<151:
            return "나쁨"
        default:
            return "매우 나쁨"
        }
    }
}

struct WeatherHourlyForecast: Identifiable, Equatable {
    var id: String {
        timeLabel
    }

    let timeLabel: String
    let condition: String
    let temperature: Int
    let precipitationProbability: Int?
    let cloudCover: Int

    var symbolName: String {
        switch condition {
        case "맑음":
            return "sun.max.fill"
        case "구름 조금":
            return "cloud.sun.fill"
        case "비":
            return "cloud.rain.fill"
        case "눈":
            return "cloud.snow.fill"
        case "안개":
            return "cloud.fog.fill"
        case "천둥":
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}

struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather
    let hourly: HourlyWeather
    let daily: DailyWeather

    struct CurrentWeather: Decodable {
        let temperature2M: Double
        let apparentTemperature: Double
        let relativeHumidity2M: Int
        let precipitation: Double
        let cloudCover: Int
        let weatherCode: Int
        let windSpeed10M: Double

        enum CodingKeys: String, CodingKey {
            case temperature2M = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2M = "relative_humidity_2m"
            case precipitation
            case cloudCover = "cloud_cover"
            case weatherCode = "weather_code"
            case windSpeed10M = "wind_speed_10m"
        }
    }

    struct HourlyWeather: Decodable {
        let time: [String]
        let temperature2M: [Double]
        let weatherCode: [Int]
        let precipitationProbability: [Int]?
        let cloudCover: [Int]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2M = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationProbability = "precipitation_probability"
            case cloudCover = "cloud_cover"
        }
    }

    struct DailyWeather: Decodable {
        let temperature2MMax: [Double]
        let temperature2MMin: [Double]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case temperature2MMax = "temperature_2m_max"
            case temperature2MMin = "temperature_2m_min"
            case weatherCode = "weather_code"
        }
    }
}

struct OpenMeteoAirQualityResponse: Decodable {
    let hourly: HourlyAirQuality

    struct HourlyAirQuality: Decodable {
        let pm10: [Double?]
        let pm25: [Double?]

        enum CodingKeys: String, CodingKey {
            case pm10
            case pm25 = "pm2_5"
        }
    }
}

struct WeatherDetailView: View {
    let snapshot: WeatherSnapshot?
    let locationTitle: String

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if let snapshot {
                    WeatherCurrentHeroCard(
                        snapshot: snapshot,
                        locationTitle: locationTitle
                    )

                    if !snapshot.hourlyForecasts.isEmpty {
                        WeatherHourlySection(forecasts: snapshot.hourlyForecasts, tint: snapshot.accentColor)
                    }

                    WeatherMetricsGrid(snapshot: snapshot)
                } else {
                    WeatherLoadingCard()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(AppColors.background.ignoresSafeArea())
    }
}

struct WeatherCurrentHeroCard: View {
    let snapshot: WeatherSnapshot
    let locationTitle: String

    private var fineDustShortText: String {
        snapshot.fineDust?.summary.components(separatedBy: " · ").first ?? "정보 없음"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(locationTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)

                    HStack(alignment: .center, spacing: 14) {
                        Text("\(snapshot.temperature)°")
                            .font(.system(size: 68, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                            .minimumScaleFactor(0.7)

                        Image(systemName: snapshot.symbolName)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(snapshot.accentColor)
                            .frame(width: 54, height: 54)
                    }

                    Text(snapshot.condition)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.primary)

                    Text("최고 \(snapshot.highTemperature)° · 최저 \(snapshot.lowTemperature)° · 체감 \(snapshot.apparentTemperature)°")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                WeatherHeroMiniMetric(title: "강수", value: "\(Int(snapshot.precipitation.rounded())) mm", symbolName: "drop.fill", tint: AppColors.primary.opacity(0.72))
                WeatherHeroMiniMetric(title: "미세먼지", value: fineDustShortText, symbolName: "aqi.medium", tint: AppColors.accent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 222, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

struct WeatherHeroMiniMetric: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)

                Text(value)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .background(AppColors.mutedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct WeatherLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ProgressView()
                .controlSize(.regular)
                .tint(AppColors.accent)
            }

            Text("오늘 날씨를 불러오는 중이에요")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Text("현재 위치 기준으로 시간대별 날씨와 촬영에 필요한 정보를 정리하고 있어요.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

struct WeatherHourlySection: View {
    let forecasts: [WeatherHourlyForecast]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)

                Text("시간대별 날씨")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .textCase(.uppercase)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(forecasts) { forecast in
                        WeatherHourlyCard(forecast: forecast, tint: tint)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
        )
    }
}

struct WeatherHourlyCard: View {
    let forecast: WeatherHourlyForecast
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(forecast.timeLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Image(systemName: forecast.symbolName)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 26)

            Text("\(forecast.temperature)°")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.primary)

            precipitationLabel
        }
        .frame(width: 54)
    }

    @ViewBuilder
    private var precipitationLabel: some View {
        if let probability = forecast.precipitationProbability, probability > 0 {
            HStack(spacing: 3) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 7, weight: .bold))

                Text("\(probability)%")
                    .font(.system(size: 9.5, weight: .bold))
            }
            .foregroundStyle(tint.opacity(0.82))
            .lineLimit(1)
        } else {
            Text(" ")
                .font(.system(size: 9.5, weight: .bold))
                .lineLimit(1)
        }
    }
}

struct WeatherMetricsGrid: View {
    let snapshot: WeatherSnapshot

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var fineDustValue: String {
        snapshot.fineDust?.summary.components(separatedBy: " · ").first ?? "정보 없음"
    }

    private var fineDustDetail: String? {
        guard let summary = snapshot.fineDust?.summary else { return nil }
        let parts = summary.components(separatedBy: " · ")
        guard parts.count > 1 else { return nil }
        return parts.dropFirst().joined(separator: " · ")
    }

    private var precipitationProbability: Int {
        snapshot.hourlyForecasts.first?.precipitationProbability ?? Int(snapshot.precipitation.rounded())
    }

    private var metrics: [WeatherMetric] {
        [
            WeatherMetric(symbolName: "thermometer.medium", title: "현재 기온", value: "\(snapshot.temperature)°", subtitle: "최고 \(snapshot.highTemperature)° · 최저 \(snapshot.lowTemperature)°"),
            WeatherMetric(symbolName: snapshot.symbolName, title: "기상상태", value: snapshot.condition, subtitle: "체감 \(snapshot.apparentTemperature)°"),
            WeatherMetric(symbolName: "drop.fill", title: "강수확률", value: "\(precipitationProbability)%", subtitle: "현재 강수 \(Int(snapshot.precipitation.rounded())) mm"),
            WeatherMetric(symbolName: "aqi.medium", title: "미세먼지", value: fineDustValue, subtitle: fineDustDetail),
            WeatherMetric(symbolName: "wind", title: "바람", value: String(format: "%.1f km/h", snapshot.windSpeed), subtitle: "현재 풍속"),
            WeatherMetric(symbolName: "humidity.fill", title: "습도", value: "\(snapshot.humidity)%", subtitle: "상대 습도")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("오늘 정보")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppColors.primary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(metrics) { metric in
                    WeatherMetricCard(metric: metric, tint: snapshot.accentColor)
                }
            }
        }
    }
}

struct WeatherMetric: Identifiable {
    var id: String {
        title
    }

    let symbolName: String
    let title: String
    let value: String
    var subtitle: String?
}

struct WeatherMetricCard: View {
    let metric: WeatherMetric
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: metric.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)

                Text(metric.value)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let subtitle = metric.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.divider.opacity(0.7), lineWidth: 1)
        )
    }
}

struct WeatherDetailRow: View {
    let symbolName: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColors.primary)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}

struct WeatherHourlyRow: View {
    let forecast: WeatherHourlyForecast
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(forecast.timeLabel)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 42, alignment: .leading)

            Image(systemName: forecast.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(forecast.condition)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.primary)

                Text("구름 \(forecast.cloudCover)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(forecast.temperature)°")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.primary)

                Text("강수 \(forecast.precipitationProbability ?? 0)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    ContentView()
}

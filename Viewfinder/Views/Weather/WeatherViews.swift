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
        detailTheme.accent
    }

    var detailTheme: WeatherVisualTheme {
        WeatherVisualTheme.theme(for: condition)
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

struct WeatherVisualTheme {
    let gradientColors: [Color]
    let accent: Color
    let warmAccent: Color
    let coolAccent: Color
    let rainAccent: Color
    let glow: Color
    let cardFill: Color
    let cardStroke: Color
    let separator: Color
    let primaryText: Color
    let secondaryText: Color

    static let fallback = WeatherVisualTheme(
        gradientColors: [
            Color(red: 0.10, green: 0.15, blue: 0.23),
            Color(red: 0.18, green: 0.25, blue: 0.36),
            Color(red: 0.07, green: 0.10, blue: 0.16)
        ],
        accent: Color(red: 0.92, green: 0.94, blue: 0.98),
        warmAccent: Color(red: 1.00, green: 0.82, blue: 0.24),
        coolAccent: Color(red: 0.65, green: 0.86, blue: 1.00),
        rainAccent: Color(red: 0.43, green: 0.74, blue: 1.00),
        glow: Color(red: 0.55, green: 0.65, blue: 0.78),
        cardFill: Color.white.opacity(0.13),
        cardStroke: Color.white.opacity(0.18),
        separator: Color.white.opacity(0.15),
        primaryText: .white,
        secondaryText: .white.opacity(0.72)
    )

    static func theme(for condition: String) -> WeatherVisualTheme {
        switch condition {
        case "맑음":
            return WeatherVisualTheme(
                gradientColors: [
                    Color(red: 0.15, green: 0.47, blue: 0.84),
                    Color(red: 0.29, green: 0.65, blue: 0.92),
                    Color(red: 0.89, green: 0.58, blue: 0.20)
                ],
                accent: Color(red: 1.00, green: 0.84, blue: 0.16),
                warmAccent: Color(red: 1.00, green: 0.76, blue: 0.10),
                coolAccent: Color(red: 0.56, green: 0.86, blue: 1.00),
                rainAccent: Color(red: 0.36, green: 0.72, blue: 1.00),
                glow: Color(red: 1.00, green: 0.74, blue: 0.20),
                cardFill: Color.white.opacity(0.16),
                cardStroke: Color.white.opacity(0.24),
                separator: Color.white.opacity(0.18),
                primaryText: .white,
                secondaryText: .white.opacity(0.78)
            )
        case "비", "천둥":
            return WeatherVisualTheme(
                gradientColors: [
                    Color(red: 0.05, green: 0.10, blue: 0.18),
                    Color(red: 0.12, green: 0.20, blue: 0.31),
                    Color(red: 0.03, green: 0.06, blue: 0.11)
                ],
                accent: Color(red: 0.45, green: 0.76, blue: 1.00),
                warmAccent: Color(red: 1.00, green: 0.68, blue: 0.22),
                coolAccent: Color(red: 0.55, green: 0.82, blue: 1.00),
                rainAccent: Color(red: 0.39, green: 0.72, blue: 1.00),
                glow: Color(red: 0.30, green: 0.55, blue: 0.82),
                cardFill: Color.white.opacity(0.12),
                cardStroke: Color.white.opacity(0.17),
                separator: Color.white.opacity(0.14),
                primaryText: .white,
                secondaryText: .white.opacity(0.70)
            )
        case "눈":
            return WeatherVisualTheme(
                gradientColors: [
                    Color(red: 0.28, green: 0.46, blue: 0.66),
                    Color(red: 0.49, green: 0.63, blue: 0.77),
                    Color(red: 0.18, green: 0.28, blue: 0.42)
                ],
                accent: Color(red: 0.88, green: 0.96, blue: 1.00),
                warmAccent: Color(red: 1.00, green: 0.78, blue: 0.30),
                coolAccent: Color(red: 0.78, green: 0.94, blue: 1.00),
                rainAccent: Color(red: 0.60, green: 0.84, blue: 1.00),
                glow: Color(red: 0.78, green: 0.90, blue: 1.00),
                cardFill: Color.white.opacity(0.15),
                cardStroke: Color.white.opacity(0.22),
                separator: Color.white.opacity(0.17),
                primaryText: .white,
                secondaryText: .white.opacity(0.76)
            )
        case "안개":
            return WeatherVisualTheme(
                gradientColors: [
                    Color(red: 0.22, green: 0.28, blue: 0.36),
                    Color(red: 0.35, green: 0.42, blue: 0.50),
                    Color(red: 0.14, green: 0.18, blue: 0.25)
                ],
                accent: Color(red: 0.88, green: 0.90, blue: 0.92),
                warmAccent: Color(red: 1.00, green: 0.74, blue: 0.28),
                coolAccent: Color(red: 0.76, green: 0.86, blue: 0.94),
                rainAccent: Color(red: 0.56, green: 0.74, blue: 0.92),
                glow: Color(red: 0.72, green: 0.76, blue: 0.80),
                cardFill: Color.white.opacity(0.13),
                cardStroke: Color.white.opacity(0.18),
                separator: Color.white.opacity(0.15),
                primaryText: .white,
                secondaryText: .white.opacity(0.72)
            )
        default:
            return fallback
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

    var accentColor: Color {
        WeatherVisualTheme.theme(for: condition).accent
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

    private var theme: WeatherVisualTheme {
        snapshot?.detailTheme ?? .fallback
    }

    var body: some View {
        ZStack {
            WeatherAtmosphericBackground(theme: theme, symbolName: snapshot?.symbolName ?? "cloud.fill")
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if let snapshot {
                        WeatherCurrentHeroCard(
                            snapshot: snapshot,
                            locationTitle: locationTitle,
                            theme: theme
                        )

                        if !snapshot.hourlyForecasts.isEmpty {
                            WeatherHourlySection(
                                forecasts: snapshot.hourlyForecasts,
                                theme: theme
                            )
                        }

                        WeatherMetricsGrid(snapshot: snapshot, theme: theme)
                    } else {
                        WeatherLoadingCard(theme: theme)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 26)
                .padding(.bottom, 40)
            }
        }
    }
}

struct WeatherAtmosphericBackground: View {
    let theme: WeatherVisualTheme
    let symbolName: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: theme.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 8)
            .scaleEffect(1.06)

            Image(systemName: symbolName)
                .font(.system(size: 260, weight: .black))
                .foregroundStyle(theme.accent.opacity(0.18))
                .blur(radius: 24)
                .offset(x: 118, y: -160)

            Image(systemName: symbolName)
                .font(.system(size: 170, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.08))
                .blur(radius: 18)
                .offset(x: -128, y: 68)

            VStack(spacing: -34) {
                WeatherCloudBand(opacity: 0.18)
                    .offset(x: -64)

                WeatherCloudBand(opacity: 0.10)
                    .scaleEffect(1.25)
                    .offset(x: 72, y: -18)

                Spacer()
            }
            .padding(.top, 44)

            RadialGradient(
                colors: [
                    theme.glow.opacity(0.34),
                    theme.glow.opacity(0.10),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 18,
                endRadius: 360
            )
        }
    }
}

struct WeatherCloudBand: View {
    let opacity: Double

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(opacity))
                .frame(width: 360, height: 78)
                .blur(radius: 30)

            Capsule()
                .fill(Color.white.opacity(opacity * 0.72))
                .frame(width: 260, height: 52)
                .offset(x: 84, y: 18)
                .blur(radius: 24)
        }
    }
}

struct WeatherCurrentHeroCard: View {
    let snapshot: WeatherSnapshot
    let locationTitle: String
    let theme: WeatherVisualTheme

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 12, weight: .bold))

                Text("현재 위치")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(theme.primaryText.opacity(0.92))

            Text(locationTitle)
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Text("\(snapshot.temperature)")
                .font(.system(size: 96, weight: .thin))
                .foregroundStyle(theme.primaryText)
                .minimumScaleFactor(0.68)
                .lineLimit(1)
                .overlay(alignment: .topTrailing) {
                    Text("°")
                        .font(.system(size: 58, weight: .thin))
                        .foregroundStyle(theme.primaryText)
                        .offset(x: 30, y: 10)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

            HStack(spacing: 8) {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(snapshot.accentColor)

                Text(snapshot.condition)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text("최고:\(snapshot.highTemperature)°  최저:\(snapshot.lowTemperature)°  체감:\(snapshot.apparentTemperature)°")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primaryText.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 286)
        .padding(.horizontal, 18)
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
    let theme: WeatherVisualTheme

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            HStack {
                ProgressView()
                .controlSize(.regular)
                .tint(theme.primaryText)
            }

            Text("오늘 날씨를 불러오는 중이에요")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.primaryText)

            Text("현재 위치 기준으로 시간대별 날씨와 촬영에 필요한 정보를 정리하고 있어요.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        .weatherGlassCard(theme: theme, cornerRadius: 24)
    }
}

struct WeatherHourlySection: View {
    let forecasts: [WeatherHourlyForecast]
    let theme: WeatherVisualTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("기상 상태")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.primaryText)

                Text("온도 (°C)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(forecasts) { forecast in
                        WeatherHourlyCard(forecast: forecast, theme: theme)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .weatherGlassCard(theme: theme, cornerRadius: 24)
    }
}

struct WeatherHourlyCard: View {
    let forecast: WeatherHourlyForecast
    let theme: WeatherVisualTheme

    var body: some View {
        VStack(spacing: 8) {
            Text(forecast.timeLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.primaryText.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Image(systemName: forecast.symbolName)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(forecast.accentColor)
                .frame(width: 30, height: 26)

            Text("\(forecast.temperature)°")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.primaryText)

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
                    .foregroundStyle(theme.rainAccent)

                Text("\(probability)%")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(theme.primaryText)
            }
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
    let theme: WeatherVisualTheme

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
                .foregroundStyle(theme.primaryText)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(metrics) { metric in
                    WeatherMetricCard(metric: metric, tint: snapshot.accentColor, theme: theme)
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
    let theme: WeatherVisualTheme

    private var iconTint: Color {
        switch metric.title {
        case "현재 기온":
            return theme.warmAccent
        case "기상상태":
            return tint
        case "강수확률", "습도":
            return theme.rainAccent
        case "미세먼지":
            return Color(red: 0.68, green: 0.93, blue: 0.66)
        case "바람":
            return theme.coolAccent
        default:
            return tint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: metric.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Text(metric.value)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let subtitle = metric.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .weatherGlassCard(theme: theme, cornerRadius: 18)
    }
}

private extension View {
    func weatherGlassCard(theme: WeatherVisualTheme, cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
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

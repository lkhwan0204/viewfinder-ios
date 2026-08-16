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

    // 골든아워 표시용. 기본값을 둬서 기존 생성 호출부가 그대로 컴파일됩니다.
    var sunrise: Date? = nil
    var sunset: Date? = nil
    /// forecast_days=2 로 받은 내일 일출. 일몰 이후에도 다음 이벤트를 보여주기 위함입니다.
    var tomorrowSunrise: Date? = nil

    var displayText: String {
        "\(temperature)°"
    }

    /// 다음에 올 해 이벤트. 지금이 일몰 전이면 일몰, 일몰 후면 내일 일출입니다.
    ///
    /// 이 앱에서 시간은 장소만큼 중요합니다. 같은 장소가 시각에 따라 완전히
    /// 다른 사진이 되기 때문에, "지금 나가면 빛이 좋은가" 가 핵심 정보입니다.
    var nextSunEvent: SunEvent? {
        let now = Date()
        var candidates: [SunEvent] = []

        if let sunrise {
            candidates.append(SunEvent(kind: .sunrise, date: sunrise))
        }
        if let sunset {
            candidates.append(SunEvent(kind: .sunset, date: sunset))
        }
        if let tomorrowSunrise {
            candidates.append(SunEvent(kind: .sunrise, date: tomorrowSunrise))
        }

        return candidates
            .filter { $0.date > now }
            .min { $0.date < $1.date }
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

/// 일출 / 일몰 이벤트와 그 표시 문자열.
struct SunEvent: Equatable {
    enum Kind {
        case sunrise
        case sunset
    }

    let kind: Kind
    let date: Date

    var symbolName: String {
        kind == .sunset ? "sunset.fill" : "sunrise.fill"
    }

    private var name: String {
        kind == .sunset ? "일몰" : "일출"
    }

    /// 남은 시간이 짧을수록 구체적으로 보여줍니다.
    ///
    /// 90분 이내는 분 단위로 (지금 움직여야 하는 구간),
    /// 3시간 이내는 시간+분,
    /// 그보다 멀면 카운트다운이 의미 없으므로 절대 시각으로 표시합니다.
    var label: String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else {
            return "\(name) \(Self.timeFormatter.string(from: date))"
        }

        let minutes = Int(remaining / 60)

        if minutes <= 90 {
            return "\(name)까지 \(minutes)분"
        }

        if minutes <= 180 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0
                ? "\(name)까지 \(hours)시간"
                : "\(name)까지 \(hours)시간 \(rest)분"
        }

        return "\(name) \(Self.timeFormatter.string(from: date))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
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

    // ═══════════════════════════════════════════════════════════════
    //  조건별 컬러 테마를 걷어냈습니다.
    //
    //  [문제였던 상황]
    //  이 파일이 앱 41개 파일 중 유일하게 토큰을 쓰지 않았습니다.
    //  하드코딩된 색이 41개, 날씨 조건 5종마다 전체 화면 그라디언트가
    //  바뀌고, 카드는 white.opacity(0.13), 글자는 순백이었습니다.
    //  앱은 검정 캔버스 + surface1/surface2 + 앰버인데, 날씨 시트만
    //  파란 하늘색 세계였습니다. 탭을 옮기면 다른 앱처럼 보였습니다.
    //
    //  [남긴 색]
    //  색을 다 없애지는 않았습니다. 날씨에서 색은 정보입니다.
    //  다만 새 색을 만들지 않고 이미 있는 토큰만 씁니다.
    //
    //    앰버        골든아워와 기온.
    //                골든아워는 브랜드 색과 의미가 정확히 겹치는
    //                유일한 지점입니다. 이 앱의 존재 이유가
    //                "언제 가면 빛이 좋은가" 이고 그 색이 앰버입니다.
    //                전에는 이걸 노란색(#FFD129)으로 칠하고 있었습니다.
    //    혼잡도 3색  미세먼지 등급. 좋음/보통/나쁨은 여유/보통/붐빔과
    //                같은 의미 구조라 같은 색을 재사용합니다.
    //                전에는 미세먼지에만 하드코딩 초록이 있었습니다.
    //    무채색      그 외 전부.
    //
    //  구조체 모양은 그대로 둡니다. 18곳의 사용부를 건드리지 않고
    //  색 정의만 바꾸기 위해서입니다.
    // ═══════════════════════════════════════════════════════════════
    static let fallback = WeatherVisualTheme(
        gradientColors: [AppColors.background, AppColors.background],
        accent: AppColors.primary,
        warmAccent: AppColors.accent,
        coolAccent: AppColors.secondaryText,
        rainAccent: AppColors.secondaryText,
        glow: .clear,
        cardFill: AppColors.cardBackground,
        cardStroke: .clear,
        separator: AppColors.divider,
        primaryText: AppColors.primary,
        secondaryText: AppColors.secondaryText
    )

    /// 조건에 따라 색을 바꾸지 않습니다.
    /// 날씨 조건은 심볼(sun.max.fill / cloud.rain.fill …)이 말합니다.
    /// 배경색까지 바꾸면 같은 화면이 조건마다 다른 화면처럼 보입니다.
    static func theme(for condition: String) -> WeatherVisualTheme {
        fallback
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
        /// 골든아워 계산용. 기존 응답에는 없던 필드라 optional 로 둡니다.
        let sunrise: [String]?
        let sunset: [String]?

        enum CodingKeys: String, CodingKey {
            case temperature2MMax = "temperature_2m_max"
            case temperature2MMin = "temperature_2m_min"
            case weatherCode = "weather_code"
            case sunrise
            case sunset
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

                        // 사진가가 날씨를 여는 이유는 "지금 가면 빛이 어떤가"
                        // 입니다. 그 답을 기온 다음 자리에 둡니다.
                        WeatherSunSection(snapshot: snapshot, theme: theme)

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

// ═══════════════════════════════════════════════════════════════════
//  배경
//
//  [전에 있던 것]
//  조건별 3색 그라디언트 + 260pt 블러 심볼 2개 + 흰 구름 밴드 2개
//  + 방사형 글로우. 파란 하늘을 그려내는 구성이었습니다.
//
//  [지금]
//  앱과 같은 검정 캔버스 + 조건 심볼 하나만 아주 흐리게 남깁니다.
//  심볼이 조건(맑음/비/눈)을 이미 말하고 있으므로 배경색까지
//  바꿀 필요가 없습니다.
//  구름 밴드와 글로우는 하늘을 흉내내는 장식이었고, 검정 캔버스
//  위에서는 흰 얼룩으로만 보입니다.
// ═══════════════════════════════════════════════════════════════════

struct WeatherAtmosphericBackground: View {
    let theme: WeatherVisualTheme
    let symbolName: String

    var body: some View {
        ZStack {
            AppColors.background

            // 조건을 알려주는 유일한 배경 요소.
            // 사진 위가 아니라 독립 시트이므로 이 정도 질감은 허용합니다.
            Image(systemName: symbolName)
                .font(.system(size: 240, weight: .black))
                .foregroundStyle(AppColors.primary.opacity(0.04))
                .blur(radius: 18)
                .offset(x: 112, y: -180)
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

    /// 미세먼지 등급을 혼잡도 색 체계로 옮깁니다.
    static func airQualityTint(for value: String) -> Color {
        if value.contains("좋음") {
            return AppColors.crowdRelaxed
        }
        if value.contains("나쁨") {
            return AppColors.crowdCrowded
        }
        if value.contains("보통") {
            return AppColors.crowdNormal
        }
        return AppColors.secondaryText
    }

    private var iconTint: Color {
        switch metric.title {
        case "현재 기온":
            return theme.warmAccent
        case "기상상태":
            return tint
        case "강수확률", "습도":
            return theme.rainAccent
        case "미세먼지":
            // 좋음/보통/나쁨은 여유/보통/붐빔과 같은 의미 구조입니다.
            // 새 색을 만들지 않고 혼잡도 토큰을 재사용합니다.
            // 전에는 여기만 하드코딩 초록이었습니다.
            return WeatherMetricCard.airQualityTint(for: metric.value)
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


// ═══════════════════════════════════════════════════════════════════
// MARK: - 해 시간
//
//  [문제였던 상황]
//  날씨 상세 시트에 일출·일몰이 없었습니다.
//
//  시트 구성이 이랬습니다.
//    현재 기온 -> 시간별 예보 -> 오늘 정보(기온·기상상태·강수확률·미세먼지)
//
//  미세먼지는 카드를 하나 받는데 일몰 시각은 어디에도 없었습니다.
//  사진가가 날씨를 여는 이유는 기온이 아니라 빛입니다.
//  같은 장소가 시각에 따라 완전히 다른 사진이 되기 때문에
//  "지금 나가면 빛이 좋은가" 가 이 화면의 존재 이유입니다.
//
//  데이터는 이미 있었습니다.
//  Phase 2B 에서 Open-Meteo 의 sunrise/sunset 을 받아
//  WeatherSnapshot.nextSunEvent 까지 만들어 뒀는데,
//  홈 화면에서만 쓰고 상세 시트에서는 표시하지 않았습니다.
//
//  [표시 원칙]
//  아는 값만 보여줍니다.
//  "골든아워 18:47부터" 같은 문구는 넣지 않았습니다.
//  골든아워 시작 시각을 서버에서 받지 않기 때문입니다.
//  일몰에서 60분을 빼서 만들어낼 수도 있지만, 그것은 근거 없는 값을
//  정확한 시각처럼 보여주는 일입니다. "추천 렌즈" 를 걷어낸 것과
//  같은 이유로 하지 않습니다.
//  대신 남은 시간 카운트다운으로 행동 가능한 정보를 줍니다.
// ═══════════════════════════════════════════════════════════════════

struct WeatherSunSection: View {
    let snapshot: WeatherSnapshot
    let theme: WeatherVisualTheme

    private var hasAnyEvent: Bool {
        snapshot.sunrise != nil || snapshot.sunset != nil || snapshot.nextSunEvent != nil
    }

    var body: some View {
        if hasAnyEvent {
            VStack(alignment: .leading, spacing: VFSpace.md) {
                if let event = snapshot.nextSunEvent {
                    countdown(event)
                }

                if snapshot.sunrise != nil || snapshot.sunset != nil {
                    HStack(spacing: 0) {
                        if let sunrise = snapshot.sunrise {
                            timeColumn(symbol: "sunrise.fill", title: "일출", date: sunrise)
                        }

                        if snapshot.sunrise != nil, snapshot.sunset != nil {
                            Rectangle()
                                .fill(theme.separator)
                                .frame(width: 0.5, height: 34)
                        }

                        if let sunset = snapshot.sunset {
                            timeColumn(symbol: "sunset.fill", title: "일몰", date: sunset)
                        }
                    }
                }
            }
            .padding(VFSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.cardFill,
                in: RoundedRectangle(cornerRadius: VFRadius.photo, style: .continuous)
            )
        }
    }

    /// 다음 해 이벤트까지 남은 시간.
    ///
    /// 이 앱에서 앰버가 의미와 정확히 겹치는 유일한 자리입니다.
    /// 골든아워는 브랜드 색이 곧 정보인 지점입니다.
    private func countdown(_ event: SunEvent) -> some View {
        HStack(spacing: VFSpace.sm) {
            Image(systemName: event.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.accent)

            Text(event.label)
                .vfText(.headline)
                .foregroundStyle(AppColors.accent)

            Spacer(minLength: 0)
        }
    }

    private func timeColumn(symbol: String, title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .vfText(.caption)
            }
            .foregroundStyle(theme.secondaryText)

            Text(Self.timeFormatter.string(from: date))
                .vfText(.title2)
                .foregroundStyle(theme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, VFSpace.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(Self.timeFormatter.string(from: date))")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

import CoreLocation
import SwiftUI
import UIKit

enum AppColors {
    static let uiPrimary = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .white
            : UIColor(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0, alpha: 1)
    }
    static let uiSecondaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 152.0 / 255.0, green: 152.0 / 255.0, blue: 157.0 / 255.0, alpha: 1)
            : UIColor(red: 110.0 / 255.0, green: 110.0 / 255.0, blue: 115.0 / 255.0, alpha: 1)
    }
    static let uiAccent = uiPrimary
    static let uiCardBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    }
    static let uiBackground = uiCardBackground
    static let uiDivider = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.18, alpha: 1)
            : UIColor(red: 234.0 / 255.0, green: 234.0 / 255.0, blue: 234.0 / 255.0, alpha: 1)
    }

    static let text = Color(uiColor: uiPrimary)
    static let neutralGray = Color(uiColor: uiSecondaryText)
    static let silverGray = Color(uiColor: uiAccent)
    static let borderGray = Color(uiColor: uiDivider)
    static let primary = text
    static let accent = silverGray
    static let background = Color(uiColor: uiBackground)
    static let cardBackground = Color(uiColor: uiCardBackground)
    static let secondaryText = neutralGray
    static let divider = borderGray
    static let mutedSurface = text.opacity(0.035)
    static let accentSoft = silverGray.opacity(0.12)
    static let primarySoft = text.opacity(0.045)

    static let crowdRelaxed = neutralGray
    static let crowdNormal = neutralGray
    static let crowdCrowded = text.opacity(0.78)

}

struct PhotoSpot: Identifiable, Equatable {
    let id: String
    let name: String
    let region: String
    let summary: String
    let hashtags: [String]
    let eventTitle: String
    let eventPeriod: String
    let feeInfo: String
    let openingHours: String
    let bestTime: String
    let crowdLevel: String
    let lensSuggestion: String
    let weatherFit: String
    let parkingInfo: String
    let nearbyParkingInfo: String
    let communityTitle: String
    let communitySubtitle: String
    let mapQuery: String
    let latitude: Double
    let longitude: Double
    let theme: SpotTheme
    let imageURL: URL?
    let category: String
    let season: [String]
    let weather: [String]
    let mood: [String]
    let crowdLevelCode: String
    let imageName: String?
    let imageCredit: String?
    let imageLicense: String?
    let imageSourceURL: URL?
    let recommendationRegions: [String]
    let isHiddenSpot: Bool

    init(
        id: String,
        name: String,
        region: String,
        summary: String,
        hashtags: [String],
        eventTitle: String,
        eventPeriod: String,
        feeInfo: String,
        openingHours: String,
        bestTime: String,
        crowdLevel: String,
        lensSuggestion: String,
        weatherFit: String,
        parkingInfo: String,
        nearbyParkingInfo: String,
        communityTitle: String,
        communitySubtitle: String,
        mapQuery: String,
        latitude: Double,
        longitude: Double,
        theme: SpotTheme,
        imageURL: URL? = nil,
        category: String = "spot",
        season: [String] = [],
        weather: [String] = [],
        mood: [String] = [],
        crowdLevelCode: String = "normal",
        imageName: String? = nil,
        imageCredit: String? = nil,
        imageLicense: String? = nil,
        imageSourceURL: URL? = nil,
        recommendationRegions: [String] = [],
        isHiddenSpot: Bool = false
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.summary = summary
        self.hashtags = hashtags
        self.eventTitle = eventTitle
        self.eventPeriod = eventPeriod
        self.feeInfo = feeInfo
        self.openingHours = openingHours
        self.bestTime = bestTime
        self.crowdLevel = crowdLevel
        self.lensSuggestion = lensSuggestion
        self.weatherFit = weatherFit
        self.parkingInfo = parkingInfo
        self.nearbyParkingInfo = nearbyParkingInfo
        self.communityTitle = communityTitle
        self.communitySubtitle = communitySubtitle
        self.mapQuery = mapQuery
        self.latitude = latitude
        self.longitude = longitude
        self.theme = theme
        self.imageURL = imageURL
        self.category = category
        self.season = season
        self.weather = weather
        self.mood = mood
        self.crowdLevelCode = crowdLevelCode
        self.imageName = imageName
        self.imageCredit = imageCredit
        self.imageLicense = imageLicense
        self.imageSourceURL = imageSourceURL
        self.recommendationRegions = recommendationRegions
        self.isHiddenSpot = isHiddenSpot
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasReliableDisplayImage: Bool {
        if let imageName = imageName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !imageName.isEmpty,
           UIImage(named: imageName) != nil {
            return true
        }

        return imageURL?.isLikelyRenderablePhotoSpotImageURL == true
    }

    func matches(_ rawQuery: String) -> Bool {
        let query = normalizedSearchText(rawQuery)
        guard !query.isEmpty else { return true }

        let withoutSeoul = query
            .replacingOccurrences(of: "서울특별시", with: "")
            .replacingOccurrences(of: "서울시", with: "")
            .replacingOccurrences(of: "서울", with: "")
        var variants = [query, withoutSeoul]
        if withoutSeoul.hasSuffix("구"), withoutSeoul.count > 1 {
            variants.append(String(withoutSeoul.dropLast()))
        }

        let fields = [name, region, summary, category] + hashtags + mood + recommendationRegions
        return variants
            .filter { !$0.isEmpty }
            .contains { query in
                fields.map(normalizedSearchText).contains { $0.contains(query) }
            }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    func hasTag(_ tag: String) -> Bool {
        hashtags.contains(tag)
    }

    func mapURL(for provider: MapProvider) -> URL {
        MapDestination(spot: self).mapURL(for: provider)
    }

    func directionsURL(for provider: MapProvider) -> URL {
        MapDestination(spot: self).directionsURL(for: provider)
    }

    func fallbackDirectionsURL(for provider: MapProvider) -> URL {
        MapDestination(spot: self).fallbackDirectionsURL(for: provider)
    }
}

private extension URL {
    var isLikelyRenderablePhotoSpotImageURL: Bool {
        let normalizedHost = host?.lowercased() ?? ""
        let normalizedPath = path.lowercased()

        if normalizedHost == "upload.wikimedia.org" {
            return true
        }

        if normalizedHost == "commons.wikimedia.org",
           normalizedPath.contains("/wiki/special:redirect/file/") {
            return true
        }

        return ["jpg", "jpeg", "png", "webp"].contains(pathExtension.lowercased())
    }
}

struct MapDestination: Identifiable, Equatable {
    enum Kind: Equatable {
        case curated(SpotTheme)
        case searchResult
    }

    let id: String
    let name: String
    let subtitle: String
    let query: String
    let latitude: Double
    let longitude: Double
    let kind: Kind

    init(spot: PhotoSpot) {
        id = spot.id
        name = spot.name
        subtitle = spot.region
        query = spot.mapQuery
        latitude = spot.latitude
        longitude = spot.longitude
        kind = .curated(spot.theme)
    }

    init(
        id: String,
        name: String,
        subtitle: String,
        query: String,
        latitude: Double,
        longitude: Double
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.query = query
        self.latitude = latitude
        self.longitude = longitude
        kind = .searchResult
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var tint: Color {
        switch kind {
        case .curated(let theme):
            return theme.primary
        case .searchResult:
            return AppColors.accent
        }
    }

    var isSearchResult: Bool {
        kind == .searchResult
    }

    func mapURL(for provider: MapProvider) -> URL {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let encodedPlaceName = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query

        switch provider {
        case .naver:
            return URL(string: "https://map.naver.com/p/search/\(encodedQuery)")!
        case .kakao:
            return URL(string: "https://map.kakao.com/link/map/\(encodedPlaceName),\(latitude),\(longitude)")!
        case .apple:
            return URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(encodedQuery)")!
        }
    }

    func directionsURL(for provider: MapProvider) -> URL {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        switch provider {
        case .naver:
            return URL(string: "nmap://route/walk?dlat=\(latitude)&dlng=\(longitude)&dname=\(encodedName)&appname=com.lkh.photoshoot")!
        case .kakao:
            return URL(string: "kakaomap://route?ep=\(latitude),\(longitude)&by=FOOT")!
        case .apple:
            return URL(string: "maps://?daddr=\(latitude),\(longitude)&q=\(encodedQuery)")!
        }
    }

    func fallbackDirectionsURL(for provider: MapProvider) -> URL {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name

        switch provider {
        case .naver:
            return URL(string: "https://map.naver.com/p/search/\(encodedQuery)")!
        case .kakao:
            return URL(string: "https://map.kakao.com/link/to/\(encodedName),\(latitude),\(longitude)")!
        case .apple:
            return URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)&q=\(encodedQuery)")!
        }
    }
}

enum MapProvider: CaseIterable, Identifiable {
    case naver
    case kakao
    case apple

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .naver:
            return "네이버지도"
        case .kakao:
            return "카카오맵"
        case .apple:
            return "Apple 지도"
        }
    }
}

enum SpotTheme: String, Equatable {
    case city
    case healing
    case night
    case flower
    case indoor
    case water

    var primary: Color {
        switch self {
        case .city:
            return AppColors.text
        case .healing:
            return AppColors.secondaryText
        case .night:
            return AppColors.text.opacity(0.86)
        case .flower:
            return AppColors.secondaryText
        case .indoor:
            return AppColors.text.opacity(0.72)
        case .water:
            return AppColors.secondaryText
        }
    }

    var softFill: Color {
        primary.opacity(0.06)
    }

    var symbolName: String {
        switch self {
        case .city:
            return "building.2.fill"
        case .healing:
            return "camera.viewfinder"
        case .night:
            return "moon.stars.fill"
        case .flower:
            return "camera.macro"
        case .indoor:
            return "house.fill"
        case .water:
            return "sparkles"
        }
    }
}

struct SpotInterest: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let matchingTag: String?

    static let all = SpotInterest(
        id: "all",
        title: "#전체",
        symbolName: "camera.aperture",
        matchingTag: nil
    )
}

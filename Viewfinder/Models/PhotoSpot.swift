import CoreLocation
import SwiftUI
import UIKit

enum AppColors {

    // -------------------------------------------------------------
    // VFPalette 가 색의 단일 출처입니다. (Views/Shared/VFDesign.swift)
    // 이 enum 은 기존 호출부 호환을 위한 별칭 레이어입니다.
    // 새 코드에서는 VFPalette 를 직접 쓰세요.
    // -------------------------------------------------------------

    // MARK: UIKit

    static let uiPrimary = VFPalette.ink1
    static let uiSecondaryText = VFPalette.ink2
    /// 브랜드 앰버. 저장됨 / 선택됨 상태에만 쓰인다.
    static let uiAccent = VFPalette.amber
    /// 카드 표면. 다크에서 canvas 와 분리되어 테두리 없이도 읽힌다.
    static let uiCardBackground = VFPalette.surface1
    /// 루트 배경. 다크에서 순수 검정.
    static let uiBackground = VFPalette.canvas
    static let uiDivider = VFPalette.separator

    // MARK: SwiftUI

    static let text = Color(uiColor: uiPrimary)
    static let neutralGray = Color(uiColor: uiSecondaryText)
    static let silverGray = Color(uiColor: uiAccent)
    static let borderGray = Color(uiColor: uiDivider)
    static let primary = text
    static let accent = silverGray
    static let background = Color(uiColor: uiBackground)
    static let feedBackground = Color(uiColor: VFPalette.feedCanvas)
    static let feedSurface = Color(uiColor: VFPalette.feedSurface)
    static let cardBackground = Color(uiColor: uiCardBackground)
    static let secondaryText = neutralGray
    static let divider = borderGray
    static let mutedSurface = Color(uiColor: VFPalette.surface2)
    static let accentSoft = silverGray.opacity(0.14)
    /// 앰버 표면 위에 올라가는 텍스트/아이콘 색. 대비 확보용.
    static let onAccent = Color(uiColor: VFPalette.onAmber)
    static let primarySoft = text.opacity(0.055)

    // MARK: 혼잡도
    // 색상 단독 사용 금지. VFCrowdBadge 를 쓰면 점 개수 + 라벨이 함께 표시된다.

    static let crowdRelaxed = Color(uiColor: VFPalette.crowdCalm)
    static let crowdNormal = Color(uiColor: VFPalette.crowdNormal)
    static let crowdCrowded = Color(uiColor: VFPalette.crowdBusy)
}

/// 장소 상세에서 보여줄 수 있는 사진 풀의 한 항목입니다.
///
/// 번들 대표 사진, 장소 제보 사진, 기존 장소 사진 기여, Community에서
/// 갤러리 공유를 선택한 사진을 같은 모델로 다룹니다. `imageData`는 아직 서버에
/// 동기화되지 않은 현재 기기의 사진을 즉시 보여주기 위한 값이며,
/// Firestore의 공개 문서에는 저장하지 않습니다.
enum PlacePhotoSource: String, Codable, Sendable {
    case seed
    case placeSubmission
    case communityContribution
    case placeContribution
}

struct PlacePhoto: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let placeID: String
    let imageURL: URL?
    let imageName: String?
    let imageData: Data?
    let uploaderID: String?
    let uploaderName: String?
    let createdAt: Date?
    let source: PlacePhotoSource
    let communityPostID: String?

    init(
        id: String,
        placeID: String,
        imageURL: URL? = nil,
        imageName: String? = nil,
        imageData: Data? = nil,
        uploaderID: String? = nil,
        uploaderName: String? = nil,
        createdAt: Date? = nil,
        source: PlacePhotoSource,
        communityPostID: String? = nil
    ) {
        self.id = id
        self.placeID = placeID
        self.imageURL = imageURL
        self.imageName = imageName
        self.imageData = imageData
        self.uploaderID = uploaderID
        self.uploaderName = uploaderName
        self.createdAt = createdAt
        self.source = source
        self.communityPostID = communityPostID
    }

    var hasDisplayImage: Bool {
        if imageData != nil {
            return true
        }

        if let imageName,
           !imageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           UIImage(named: imageName) != nil {
            return true
        }

        guard let imageURL,
              let scheme = imageURL.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

/// 상세 화면 한 세션에서 사용할 사진을 고르는 규칙입니다.
/// 첫 사진은 장소의 대표 사진으로 고정하고, 이후 사진은 가능한 한
/// 업로더가 섞이도록 고른 뒤 남은 슬롯을 무작위로 채웁니다.
enum PlacePhotoPool {
    static let defaultLimit = 10
    static let preferredUploaderLimit = 2

    static func candidates(for spot: PhotoSpot) -> [PlacePhoto] {
        let fallback = PlacePhoto(
            id: "cover-\(spot.id)",
            placeID: spot.id,
            imageURL: spot.imageURL,
            imageName: spot.imageName,
            source: .seed
        )

        return deduplicated(spot.galleryPhotos + [fallback])
            .filter(\.hasDisplayImage)
    }

    static func select(for spot: PhotoSpot, limit: Int = defaultLimit) -> [PlacePhoto] {
        select(from: candidates(for: spot), limit: limit)
    }

    static func select(from photos: [PlacePhoto], limit: Int = defaultLimit) -> [PlacePhoto] {
        guard limit > 0 else { return [] }

        let candidates = deduplicated(photos)
            .filter(\.hasDisplayImage)
        guard !candidates.isEmpty else { return [] }
        guard candidates.count > limit else { return candidates }

        var selected = [candidates[0]]
        var remaining = Array(candidates.dropFirst())
        var uploaderCounts: [String: Int] = [:]

        if let uploaderID = candidates[0].uploaderID, !uploaderID.isEmpty {
            uploaderCounts[uploaderID] = 1
        }

        while selected.count < limit, !remaining.isEmpty {
            let unseenUploaderCandidates = remaining.filter { photo in
                guard let uploaderID = normalizedUploaderID(photo.uploaderID) else { return true }
                return uploaderCounts[uploaderID, default: 0] == 0
            }

            let underPreferredLimit = remaining.filter { photo in
                guard let uploaderID = normalizedUploaderID(photo.uploaderID) else { return true }
                return uploaderCounts[uploaderID, default: 0] < preferredUploaderLimit
            }

            let pool = unseenUploaderCandidates.isEmpty
                ? (underPreferredLimit.isEmpty ? remaining : underPreferredLimit)
                : unseenUploaderCandidates
            guard let next = pool.randomElement(),
                  let index = remaining.firstIndex(where: { $0.id == next.id }) else {
                break
            }

            selected.append(next)
            remaining.remove(at: index)
            if let uploaderID = normalizedUploaderID(next.uploaderID) {
                uploaderCounts[uploaderID, default: 0] += 1
            }
        }

        return selected
    }

    private static func deduplicated(_ photos: [PlacePhoto]) -> [PlacePhoto] {
        photos.reduce(into: [PlacePhoto]()) { result, photo in
            guard !result.contains(where: { existing in
                existing.id == photo.id
                    || (existing.placeID == photo.placeID && existing.imageURL == photo.imageURL && photo.imageURL != nil)
                    || (existing.placeID == photo.placeID && existing.imageName == photo.imageName && photo.imageName != nil)
            }) else {
                return
            }
            result.append(photo)
        }
    }

    private static func normalizedUploaderID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PhotoSpot: Identifiable, Equatable, Sendable {
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
    /// 외부 장소 검색 공급자. 기존 번들 데이터는 nil일 수 있습니다.
    let provider: String?
    /// 공급자가 제공한 안정적인 장소 ID. 없으면 이름·주소·좌표로 대체합니다.
    let providerPlaceID: String?
    /// 장소 상세에서 사용할 추가 사진 풀입니다. 기존 장소는 대표 사진 하나를
    /// 로컬 seed 변환 과정에서 자동으로 채웁니다.
    let galleryPhotos: [PlacePhoto]

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
        isHiddenSpot: Bool = false,
        provider: String? = nil,
        providerPlaceID: String? = nil,
        galleryPhotos: [PlacePhoto] = []
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
        self.provider = provider
        self.providerPlaceID = providerPlaceID
        self.galleryPhotos = galleryPhotos
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

    func replacingDisplayImage(from source: PhotoSpot) -> PhotoSpot {
        guard !hasReliableDisplayImage, source.hasReliableDisplayImage else {
            return self
        }

        return PhotoSpot(
            id: id,
            name: name,
            region: region,
            summary: summary,
            hashtags: hashtags,
            eventTitle: eventTitle,
            eventPeriod: eventPeriod,
            feeInfo: feeInfo,
            openingHours: openingHours,
            bestTime: bestTime,
            crowdLevel: crowdLevel,
            lensSuggestion: lensSuggestion,
            weatherFit: weatherFit,
            parkingInfo: parkingInfo,
            nearbyParkingInfo: nearbyParkingInfo,
            communityTitle: communityTitle,
            communitySubtitle: communitySubtitle,
            mapQuery: mapQuery,
            latitude: latitude,
            longitude: longitude,
            theme: theme,
            imageURL: source.imageURL,
            category: category,
            season: season,
            weather: weather,
            mood: mood,
            crowdLevelCode: crowdLevelCode,
            imageName: source.imageName,
            imageCredit: source.imageCredit,
            imageLicense: source.imageLicense,
            imageSourceURL: source.imageSourceURL,
            recommendationRegions: recommendationRegions,
            isHiddenSpot: isHiddenSpot,
            provider: provider,
            providerPlaceID: providerPlaceID,
            galleryPhotos: galleryPhotos.isEmpty ? source.galleryPhotos : galleryPhotos
        )
    }

    /// 기존 장소에 첫 사용자 사진이 등록된 뒤, 현재 세션의 카드/검색에서도
    /// 그 사진을 대표 이미지로 사용할 수 있도록 메모리상의 장소만 갱신합니다.
    /// Firestore의 Place document를 수정하는 동작은 아닙니다.
    func replacingDisplayImage(with photo: PlacePhoto) -> PhotoSpot {
        guard !hasReliableDisplayImage, photo.hasDisplayImage else {
            return self
        }

        return PhotoSpot(
            id: id,
            name: name,
            region: region,
            summary: summary,
            hashtags: hashtags,
            eventTitle: eventTitle,
            eventPeriod: eventPeriod,
            feeInfo: feeInfo,
            openingHours: openingHours,
            bestTime: bestTime,
            crowdLevel: crowdLevel,
            lensSuggestion: lensSuggestion,
            weatherFit: weatherFit,
            parkingInfo: parkingInfo,
            nearbyParkingInfo: nearbyParkingInfo,
            communityTitle: communityTitle,
            communitySubtitle: communitySubtitle,
            mapQuery: mapQuery,
            latitude: latitude,
            longitude: longitude,
            theme: theme,
            imageURL: photo.imageURL,
            category: category,
            season: season,
            weather: weather,
            mood: mood,
            crowdLevelCode: crowdLevelCode,
            imageName: photo.imageName,
            imageCredit: "ViewFinder 사용자 제보",
            imageLicense: "업로더 제공",
            imageSourceURL: nil,
            recommendationRegions: recommendationRegions,
            isHiddenSpot: isHiddenSpot,
            provider: provider,
            providerPlaceID: providerPlaceID,
            galleryPhotos: [photo] + galleryPhotos
        )
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

        // 장소 사진 기여는 Firebase Storage 공개 URL을 사용합니다.
        // 다운로드 URL은 경로가 이미지 확장자로 끝나지 않을 수 있지만
        // 실제 응답은 이미지이므로 카드·지도에서도 유효한 사진으로 취급합니다.
        if normalizedHost == "firebasestorage.googleapis.com"
            || normalizedHost == "firebasestorage.app"
            || normalizedHost.hasSuffix(".firebasestorage.app")
            || normalizedHost.hasSuffix(".appspot.com") {
            return true
        }

        // 장소 제보 서버의 사진 endpoint는 응답 본문으로 이미지를 반환하므로
        // URL에 jpg/png 확장자가 없습니다. 등록 직후 지도·홈·검색에서도
        // 사용할 수 있는 공개 이미지 경로임을 명시적으로 허용합니다.
        if normalizedPath.contains("/submitted-spots/"),
           normalizedPath.contains("/photo") {
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

enum SpotTheme: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    /// 장소의 주 피사체를 나타내는 단일 분류입니다.
    /// 노을·야경·필름감성·계절 같은 값은 hashtags/mood/season에 남깁니다.
    case cityArchitecture = "cityArchitecture"
    case landscape = "landscape"
    case retroAlley = "retroAlley"
    case historyTradition = "historyTradition"
    case viewpoint = "viewpoint"
    case cafeIndoor = "cafeIndoor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cityArchitecture:
            return "도심/건축"
        case .landscape:
            return "자연/풍경"
        case .retroAlley:
            return "골목/레트로"
        case .historyTradition:
            return "역사/전통"
        case .viewpoint:
            return "전망/뷰"
        case .cafeIndoor:
            return "실내/카페"
        }
    }

    /// 기존 seed의 legacy theme/category와 태그를 한 번만 정규화합니다.
    /// 기존 JSON을 즉시 깨뜨리지 않으면서 PhotoSpot에는 항상 새 주 테마가 들어갑니다.
    static func resolve(
        legacyValue: String? = nil,
        name: String = "",
        description: String = "",
        tags: [String] = [],
        category: String? = nil
    ) -> SpotTheme {
        let normalizedName = normalized(name)
        let normalizedCategory = normalized(category ?? "")
        let normalizedTags = tags.map(normalized)
        let searchable = ([name, description, category ?? ""] + tags)
            .map(normalized)
            .joined(separator: " ")
        let legacy = normalized(legacyValue ?? "")

        // 이후 seed가 canonical 값을 직접 저장하게 되어도 같은 모델을 그대로 읽습니다.
        // normalized()가 camelCase를 소문자로 만들기 때문에 rawValue를
        // 직접 대조하지 않고 정규화한 값으로 비교합니다.
        if let canonicalTheme = SpotTheme.allCases.first(where: {
            normalized($0.rawValue) == legacy
        }) {
            return canonicalTheme
        }

        // 레거시 city/indoor 값으로 저장된 기록도 역사·전통 장소를
        // 골목이나 실내로 잘못 되돌리지 않도록 이름 기반 호환 규칙을 둡니다.
        let historicalPlaceNames = [
            "북촌한옥마을", "익선동한옥거리", "수원화성화홍문", "집옥재",
            "대구불로동고분군", "청운문학도서관"
        ]
        if historicalPlaceNames.contains(where: { normalizedName.contains($0) }) {
            return .historyTradition
        }

        // 카페 거리/창작촌처럼 장소 전체가 거리인 경우에는
        // category가 cafe로 들어와도 골목/레트로를 우선합니다.
        let namedStreetPlace = [
            "창작촌", "카페거리", "카페골목", "문화의거리", "한옥마을",
            "한옥거리", "철길", "건널목", "골목", "신흥시장", "캠프마켓"
        ]
        if namedStreetPlace.contains(where: { normalizedName.contains($0) }) {
            return .retroAlley
        }

        let isCafeOrIndoor = ["cafe", "카페", "실내", "indoor"].contains {
            normalizedCategory == $0
        } || normalizedTags.contains(where: {
            ["카페", "실내", "미술관", "박물관", "도서관", "전시", "라이브러리", "베이커리", "다방"]
                .contains($0)
        })

        // 실제 카페/전시/도서관은 전망 태그가 있어도 카페/실내입니다.
        if isCafeOrIndoor {
            return .cafeIndoor
        }

        let viewpointSignals = [
            "전망", "전망대", "스카이워크", "뷰포인트", "스카이라인", "능선",
            "조망", "내려다", "팔각정", "남산타워뷰", "서울시티뷰", "한강뷰",
            "호수뷰", "산뷰", "바다뷰"
        ]
        if normalizedCategory == "viewpoint"
            || viewpointSignals.contains(where: { searchable.contains($0) }) {
            return .viewpoint
        }

        let naturalSignals = [
            "공원", "숲", "수목원", "식물원", "정원", "꽃밭", "호수", "한강",
            "강변", "바다", "해수욕장", "목장", "들판", "초원", "생태", "습지",
            "산책로"
        ]
        let isNaturalPlace = ["park", "trail", "water"].contains(normalizedCategory)
            || naturalSignals.contains(where: { searchable.contains($0) })

        // 다리·대교·성곽처럼 구조물 자체가 주 피사체인 장소는
        // 자연 배경 태그가 함께 있어도 도심/건축으로 분류합니다.
        let architectureSignals = [
            "ddp", "건축물", "건축", "다리", "대교", "육교", "교량", "스카이돔",
            "성곽", "고궁", "정자", "철골", "콘크리트구조물", "구조물", "마천루",
            "빌딩"
        ]
        let isStrongArchitecturePlace = architectureSignals.contains(where: {
            normalizedName.contains($0)
        }) || (
            architectureSignals.contains(where: { searchable.contains($0) })
                && !isNaturalPlace
        )

        if isStrongArchitecturePlace {
            return .cityArchitecture
        }

        if isNaturalPlace {
            return .landscape
        }

        let retroSignals = [
            "골목", "레트로", "빈티지", "오래된거리", "철도", "한옥", "시장",
            "서촌", "북촌", "을지로", "문래", "익선동", "해방촌", "행궁동"
        ]
        if retroSignals.contains(where: { searchable.contains($0) }) {
            return .retroAlley
        }

        switch legacy {
        case "indoor", "cafe":
            return .cafeIndoor
        case "flower", "healing", "water", "sunset":
            return .landscape
        case "night", "city":
            return .cityArchitecture
        case "history", "tradition", "heritage":
            return .historyTradition
        default:
            return .cityArchitecture
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var primary: Color {
        switch self {
        case .cityArchitecture:
            return AppColors.text
        case .landscape:
            return AppColors.secondaryText
        case .retroAlley:
            return AppColors.text.opacity(0.86)
        case .historyTradition:
            return AppColors.text.opacity(0.82)
        case .viewpoint:
            return AppColors.secondaryText
        case .cafeIndoor:
            return AppColors.text.opacity(0.72)
        }
    }

    var softFill: Color {
        primary.opacity(0.06)
    }

    var symbolName: String {
        switch self {
        case .cityArchitecture:
            return "building.2.fill"
        case .landscape:
            return "leaf.fill"
        case .retroAlley:
            return "signpost.right.fill"
        case .historyTradition:
            return "building.columns.fill"
        case .viewpoint:
            return "binoculars.fill"
        case .cafeIndoor:
            return "house.fill"
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

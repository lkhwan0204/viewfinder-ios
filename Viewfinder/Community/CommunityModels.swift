import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CommunityExifVisibility: String, CaseIterable, Codable, Hashable, Sendable {
    case privateOnly = "private"
    case publicInfo = "public"
}

enum CommunityLocationVisibility: String, CaseIterable, Codable, Hashable, Sendable {
    case privateOnly = "private"
    case approximate = "approximate"
    case exact = "exact"

    var title: String {
        switch self {
        case .privateOnly:
            return "공개하지 않기"
        case .approximate:
            return "대략적인 지역만 공개"
        case .exact:
            return "정확한 위치 공개"
        }
    }
}

struct CommunityPhotoExif: Codable, Equatable, Sendable {
    let cameraMake: String?
    let cameraModel: String?
    let lensMake: String?
    let lensModel: String?
    let focalLengthMillimeters: Double?
    let focalLength35mm: Int?
    let aperture: Double?
    let exposureTime: Double?
    let iso: Int?
    let capturedAt: Date?

    static let empty = CommunityPhotoExif(
        cameraMake: nil,
        cameraModel: nil,
        lensMake: nil,
        lensModel: nil,
        focalLengthMillimeters: nil,
        focalLength35mm: nil,
        aperture: nil,
        exposureTime: nil,
        iso: nil,
        capturedAt: nil
    )

    var isEmpty: Bool {
        cameraDisplay == nil
            && lensDisplay == nil
            && focalLengthDisplay == nil
            && apertureDisplay == nil
            && exposureDisplay == nil
            && isoDisplay == nil
            && capturedAtDisplay == nil
    }

    var cameraDisplay: String? {
        Self.join(make: cameraMake, model: cameraModel)
    }

    var lensDisplay: String? {
        Self.join(make: lensMake, model: lensModel)
    }

    var focalLengthDisplay: String? {
        guard let focalLengthMillimeters else { return nil }
        let focal = Self.number(focalLengthMillimeters)
        guard let focalLength35mm else { return focal + "mm" }
        return "\(focal)mm · \(focalLength35mm)mm 환산"
    }

    var apertureDisplay: String? {
        guard let aperture else { return nil }
        return "f/\(Self.number(aperture))"
    }

    var exposureDisplay: String? {
        guard let exposureTime, exposureTime > 0 else { return nil }
        if exposureTime >= 1 {
            return "\(Self.number(exposureTime))s"
        }
        return "1/\(Int((1 / exposureTime).rounded()))s"
    }

    var isoDisplay: String? {
        guard let iso else { return nil }
        return "ISO \(iso)"
    }

    var capturedAtDisplay: String? {
        guard let capturedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: capturedAt)
    }

    var compactSummary: String? {
        let camera = cameraDisplay
        let lens = lensDisplay
        let firstLine = [camera, lens].compactMap { $0 }.joined(separator: " · ")
        let secondLine = [
            focalLengthDisplay?.replacingOccurrences(of: " · ", with: " / "),
            apertureDisplay,
            exposureDisplay,
            isoDisplay
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        let result = [firstLine, secondLine].filter { !$0.isEmpty }.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    /// 게시글 상세에서 현재 사진 아래 한 줄로 보여줄 요약입니다.
    /// 35mm 환산값과 촬영일시는 편집 화면에서 유지하지만,
    /// 상세의 한 줄에서는 사진 감상을 방해하지 않도록 생략합니다.
    var detailSummary: String? {
        let focalLength = focalLengthMillimeters.map { Self.number($0) + "mm" }
        let values = [
            detailCameraDisplay,
            detailLensDisplay,
            focalLength,
            apertureDisplay,
            exposureDisplay,
            isoDisplay
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    /// 상세 화면에서는 제조사와 모델을 기계적으로 이어 붙이지 않고,
    /// 사용자가 알아보기 쉬운 모델명을 우선합니다. 예를 들어
    /// `Apple` + `iPhone 17`은 `iPhone 17`로 표시합니다.
    private var detailCameraDisplay: String? {
        Self.cleaned(cameraModel) ?? Self.cleaned(cameraMake)
    }

    /// 모바일 기기에서 렌즈 필드가 `back dual wide camera ...`처럼
    /// 촬영 장치 설명 전체로 들어오는 경우에는 이미 초점거리/조리개가
    /// 뒤에서 표시되므로 렌즈명을 생략해 중복을 줄입니다.
    private var detailLensDisplay: String? {
        guard let value = Self.cleaned(lensModel) ?? Self.cleaned(lensMake) else {
            return nil
        }

        let lowercased = value.localizedLowercase
        let cameraDescriptionMarkers = [
            "back dual",
            "wide camera",
            "ultra wide camera",
            "telephoto camera",
            "front camera"
        ]
        if cameraDescriptionMarkers.contains(where: { lowercased.contains($0) }) {
            return nil
        }

        if value.count > 32 {
            return String(value.prefix(31)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return value
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [:]
        if let cameraMake { data["cameraMake"] = cameraMake }
        if let cameraModel { data["cameraModel"] = cameraModel }
        if let lensMake { data["lensMake"] = lensMake }
        if let lensModel { data["lensModel"] = lensModel }
        if let focalLengthMillimeters { data["focalLengthMillimeters"] = focalLengthMillimeters }
        if let focalLength35mm { data["focalLength35mm"] = focalLength35mm }
        if let aperture { data["aperture"] = aperture }
        if let exposureTime { data["exposureTime"] = exposureTime }
        if let iso { data["iso"] = iso }
        if let capturedAt { data["capturedAt"] = capturedAt }
        return data
    }

    private static func join(make: String?, model: String?) -> String? {
        let values = [make, model].compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !values.isEmpty else { return nil }
        if values.count == 2,
           values[1].localizedCaseInsensitiveContains(values[0]) {
            return values[1]
        }
        return values.joined(separator: " ")
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

struct CommunityPhotoLocation: Codable, Equatable, Sendable {
    let visibility: CommunityLocationVisibility
    let regionName: String?
    let latitude: Double?
    let longitude: Double?

    var displayText: String? {
        switch visibility {
        case .privateOnly:
            return nil
        case .approximate:
            return regionName ?? "촬영 지역"
        case .exact:
            return regionName ?? "정확한 촬영 위치"
        }
    }

    var firestoreData: [String: Any]? {
        guard visibility != .privateOnly else { return nil }

        var data: [String: Any] = ["visibility": visibility.rawValue]
        if let regionName { data["regionName"] = regionName }
        if visibility == .exact,
           let latitude,
           let longitude {
            data["latitude"] = latitude
            data["longitude"] = longitude
        }
        return data
    }
}

/// Community 글에 사용자가 직접 추가한 촬영 위치입니다.
///
/// 등록된 ViewFinder 출사지는 placeID로 연결하고, 검색으로 찾은
/// 미등록 장소는 이름·지역·주소만 저장합니다. 이 값은 장소 제보를
/// 생성하지 않으며, 사진 EXIF GPS와도 연결되지 않습니다.
struct CommunityCaptureLocation: Codable, Equatable, Sendable, Identifiable {
    let placeID: String?
    let name: String
    let region: String?
    let address: String?

    var id: String {
        [placeID, name, region, address]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = ["name": name]
        if let placeID { data["placeID"] = placeID }
        if let region { data["region"] = region }
        if let address { data["address"] = address }
        return data
    }
}

struct CommunityPhotoAttachment: Identifiable, Equatable, Sendable {
    let id: String
    let imageData: Data?
    let remoteURL: URL?
    let metadata: CommunityPhotoExif?
    let location: CommunityPhotoLocation?
    /// 관련 출사지가 선택된 Community 글에서만 사용합니다.
    /// 기본값은 false이며, true인 사진만 장소 사진 풀에 복사됩니다.
    let sharesToPlaceGallery: Bool

    init(
        id: String,
        imageData: Data?,
        remoteURL: URL?,
        metadata: CommunityPhotoExif?,
        location: CommunityPhotoLocation?,
        sharesToPlaceGallery: Bool = false
    ) {
        self.id = id
        self.imageData = imageData
        self.remoteURL = remoteURL
        self.metadata = metadata
        self.location = location
        self.sharesToPlaceGallery = sharesToPlaceGallery
    }
}

struct CommunityPhotoDraft: Identifiable, Equatable, Sendable {
    let id: String
    let data: Data
    var exif: CommunityPhotoExif?
    var sharesToPlaceGallery: Bool

    init(
        id: String,
        data: Data,
        exif: CommunityPhotoExif? = nil,
        sharesToPlaceGallery: Bool = false
    ) {
        self.id = id
        self.data = data
        self.exif = exif
        self.sharesToPlaceGallery = sharesToPlaceGallery
    }

    func publicAttachment(
        exifVisibility: CommunityExifVisibility,
        sharesToPlaceGallery: Bool = false
    ) -> CommunityPhotoAttachment {
        let publicMetadata = exifVisibility == .publicInfo ? exif : nil

        return CommunityPhotoAttachment(
            id: id,
            imageData: CommunityPhotoPrivacyProcessor.sanitizedData(
                from: data,
                exifVisibility: exifVisibility
            ),
            remoteURL: nil,
            metadata: publicMetadata,
            location: nil,
            sharesToPlaceGallery: sharesToPlaceGallery
        )
    }
}

enum CommunityPhotoEXIFReader {
    struct Inspection: Equatable, Sendable {
        let exif: CommunityPhotoExif?
    }

    static func inspect(data: Data) -> Inspection? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let photoExif = CommunityPhotoExif(
            cameraMake: string(kCGImagePropertyTIFFMake, from: tiff),
            cameraModel: string(kCGImagePropertyTIFFModel, from: tiff),
            lensMake: string(kCGImagePropertyExifLensMake, from: exif),
            lensModel: string(kCGImagePropertyExifLensModel, from: exif),
            focalLengthMillimeters: number(kCGImagePropertyExifFocalLength, from: exif),
            focalLength35mm: int(kCGImagePropertyExifFocalLenIn35mmFilm, from: exif),
            aperture: number(kCGImagePropertyExifFNumber, from: exif),
            exposureTime: number(kCGImagePropertyExifExposureTime, from: exif),
            iso: iso(from: exif),
            capturedAt: date(from: exif)
        )

        return Inspection(exif: photoExif.isEmpty ? nil : photoExif)
    }

    private static func string(_ key: CFString, from dictionary: [CFString: Any]?) -> String? {
        guard let value = dictionary?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ key: CFString, from dictionary: [CFString: Any]?) -> Double? {
        (dictionary?[key] as? NSNumber)?.doubleValue
    }

    private static func int(_ key: CFString, from dictionary: [CFString: Any]?) -> Int? {
        (dictionary?[key] as? NSNumber)?.intValue
    }

    private static func iso(from dictionary: [CFString: Any]?) -> Int? {
        if let values = dictionary?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber] {
            return values.first?.intValue
        }
        if let values = dictionary?[kCGImagePropertyExifISOSpeedRatings] as? [Any] {
            return (values.first as? NSNumber)?.intValue
        }
        return nil
    }

    private static func date(from dictionary: [CFString: Any]?) -> Date? {
        guard let value = string(kCGImagePropertyExifDateTimeOriginal, from: dictionary)
                ?? string(kCGImagePropertyExifDateTimeDigitized, from: dictionary) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // EXIF DateTimeOriginal은 보통 시간대 정보를 포함하지 않는
        // 카메라의 현지 촬영 시각이므로, 현재 지역 기준으로 표시합니다.
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }

}

enum CommunityPhotoPrivacyProcessor {
    static func sanitizedData(
        from data: Data,
        exifVisibility: CommunityExifVisibility
    ) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  destinationData,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              ) else {
            return UIImage(data: data)?.jpegData(compressionQuality: 0.92) ?? data
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var metadata: [CFString: Any] = [:]

        if let orientation = properties?[kCGImagePropertyOrientation] {
            metadata[kCGImagePropertyOrientation] = orientation
        }

        if exifVisibility == .publicInfo {
            if let tiff = properties?[kCGImagePropertyTIFFDictionary] {
                metadata[kCGImagePropertyTIFFDictionary] = tiff
            }
            if var exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                // MakerNote는 제조사별 비공개 blob이라 GPS가 포함될 수 있어
                // 촬영 위치를 별도로 추가했더라도 항상 제거합니다.
                exif[kCGImagePropertyExifMakerNote] = nil
                metadata[kCGImagePropertyExifDictionary] = exif
            }
        }

        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return UIImage(data: data)?.jpegData(compressionQuality: 0.92) ?? data
        }
        return destinationData as Data
    }
}

struct CommunityPost: Identifiable, Equatable, Sendable {
    enum Crowd: String, CaseIterable, Identifiable, Hashable, Sendable {
        case relaxed = "여유"
        case normal = "보통"
        case crowded = "많음"

        var id: String { rawValue }

        /// Firestore에 이미 저장된 rawValue는 호환성을 위해 유지하고,
        /// 화면에는 앱 전체에서 사용하는 세 단계 이름만 노출합니다.
        var displayName: String {
            switch self {
            case .relaxed:
                return "여유"
            case .normal:
                return "보통"
            case .crowded:
                return "혼잡"
            }
        }

        var displayText: String {
            "혼잡도 · \(displayName)"
        }

        /// 과거에 저장된 한적/붐빔/혼잡 값도 읽을 수 있도록 합니다.
        /// 새 저장값은 현재 rawValue를 사용해 기존 Firestore 문서와의
        /// 호환성을 유지합니다.
        static func fromStoredValue(_ rawValue: String?) -> Crowd? {
            guard let rawValue else { return nil }
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let crowd = Crowd(rawValue: normalized) {
                return crowd
            }

            switch normalized {
            case "한적", "여유로움", "여유함":
                return .relaxed
            case "혼잡", "붐빔", "매우 붐빔", "많음":
                return .crowded
            default:
                return nil
            }
        }

        var tint: Color {
            switch self {
            case .relaxed:
                return AppColors.crowdRelaxed
            case .normal:
                return AppColors.crowdNormal
            case .crowded:
                return AppColors.crowdCrowded
            }
        }

        /// 선택 버튼처럼 흰색 라벨을 올리는 불투명 배경 색상입니다.
        /// 일반 `tint`는 배지와 텍스트에 맞춘 밝기이므로 버튼에는 별도 토큰을 사용합니다.
        var buttonFill: Color {
            switch self {
            case .relaxed:
                return Color(uiColor: VFPalette.crowdCalmButton)
            case .normal:
                return Color(uiColor: VFPalette.crowdNormalButton)
            case .crowded:
                return Color(uiColor: VFPalette.crowdBusyButton)
            }
        }

        var fill: Color {
            tint.opacity(0.12)
        }

        var selectedFill: Color {
            tint.opacity(0.24)
        }
    }

    let id: String
    let spotID: String
    let spotName: String
    let title: String?
    let captureLocation: CommunityCaptureLocation?
    let message: String
    let crowd: Crowd
    let tags: [String]
    let photoData: Data?
    let photoAttachments: [CommunityPhotoAttachment]
    let hasStatusInfo: Bool
    let likeCount: Int
    let authorID: String
    let authorName: String
    let createdAt: Date
    let updatedAt: Date?

    var statusTags: [String] {
        tags
    }

    var hashtags: [String] {
        tags.map { tag in
            tag.hasPrefix("#") ? tag : "#\(tag)"
        }
    }

    var relatedSpotID: String? {
        spotID.isEmpty ? nil : spotID
    }

    var relatedSpotName: String? {
        spotName.isEmpty ? nil : spotName
    }

    var hasPhotos: Bool {
        !publicPhotoAttachments.isEmpty
    }

    /// 새 첨부 구조가 없는 기존 게시물은 legacy photoData 를 한 장의
    /// 첨부사진처럼 읽어 기존 피드/상세 화면과 호환합니다.
    var publicPhotoAttachments: [CommunityPhotoAttachment] {
        if !photoAttachments.isEmpty {
            return photoAttachments
        }

        guard let photoData else { return [] }
        return [
            CommunityPhotoAttachment(
                id: "legacy-\(id)",
                imageData: photoData,
                remoteURL: nil,
                metadata: nil,
                location: nil
            )
        ]
    }

    init(
        id: String,
        spotID: String,
        spotName: String,
        message: String,
        crowd: Crowd,
        tags: [String],
        photoData: Data?,
        likeCount: Int,
        authorID: String,
        authorName: String,
        createdAt: Date,
        updatedAt: Date?
    ) {
        self.id = id
        self.spotID = spotID
        self.spotName = spotName
        self.title = nil
        self.captureLocation = nil
        self.message = message
        self.crowd = crowd
        self.tags = tags
        self.photoData = photoData
        self.photoAttachments = []
        self.hasStatusInfo = true
        self.likeCount = likeCount
        self.authorID = authorID
        self.authorName = authorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(
        id: String,
        spot: PhotoSpot?,
        title: String?,
        captureLocation: CommunityCaptureLocation? = nil,
        crowd: Crowd? = nil,
        message: String,
        tags: [String],
        photoAttachments: [CommunityPhotoAttachment],
        likeCount: Int,
        authorID: String,
        authorName: String,
        createdAt: Date,
        updatedAt: Date?,
        hasStatusInfo: Bool = false
    ) {
        self.id = id
        self.spotID = spot?.id ?? ""
        self.spotName = spot?.name ?? ""
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.captureLocation = captureLocation
        self.message = message
        self.crowd = crowd ?? .normal
        self.tags = tags
        self.photoData = photoAttachments.first?.imageData
        self.photoAttachments = photoAttachments
        self.hasStatusInfo = hasStatusInfo || crowd != nil
        self.likeCount = likeCount
        self.authorID = authorID
        self.authorName = authorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum CrowdReportSource: String, Codable, Sendable {
    case placeDetail
    case community
}

/// 장소에 대한 혼잡도 제보입니다. Community 글과 분리된 장소 상태이며,
/// Community 글에서 선택적으로 생성된 경우에만 `communityPostID`를 가집니다.
struct CrowdReport: Identifiable, Equatable, Sendable {
    let id: String
    let placeID: String
    let crowd: CommunityPost.Crowd
    let authorID: String
    let createdAt: Date
    /// 같은 사용자의 재제보는 기존 문서를 갱신하므로 생성 시각과
    /// 최신 상태 시각을 분리합니다. 구문서에는 이 값이 없어 createdAt으로
    /// 복원합니다.
    let updatedAt: Date
    let source: CrowdReportSource
    let communityPostID: String?

    init(
        id: String = UUID().uuidString,
        placeID: String,
        crowd: CommunityPost.Crowd,
        authorID: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        source: CrowdReportSource,
        communityPostID: String? = nil
    ) {
        self.id = id
        self.placeID = placeID
        self.crowd = crowd
        self.authorID = authorID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.source = source
        self.communityPostID = communityPostID
    }
}

struct CrowdReportSummary: Equatable, Sendable {
    let crowd: CommunityPost.Crowd
    let reportCount: Int
    let latestDate: Date
}

struct CommunityPostDraft {
    let spot: PhotoSpot?
    let title: String?
    let captureLocation: CommunityCaptureLocation?
    let message: String
    let crowd: CommunityPost.Crowd?
    let tags: [String]
    let photoData: Data?
    let photoAttachments: [CommunityPhotoAttachment]

    init(
        spot: PhotoSpot,
        message: String,
        crowd: CommunityPost.Crowd,
        tags: [String],
        photoData: Data?,
        photoAttachments: [CommunityPhotoAttachment] = []
    ) {
        self.spot = spot
        self.title = nil
        self.captureLocation = nil
        self.message = message
        self.crowd = crowd
        self.tags = tags
        self.photoData = photoData ?? photoAttachments.first?.imageData
        self.photoAttachments = photoAttachments
    }

    init(
        spot: PhotoSpot?,
        title: String?,
        captureLocation: CommunityCaptureLocation? = nil,
        message: String,
        tags: [String] = [],
        photoAttachments: [CommunityPhotoAttachment] = [],
        crowd: CommunityPost.Crowd? = nil
    ) {
        self.spot = spot
        self.title = title
        self.captureLocation = captureLocation
        self.message = message
        self.crowd = crowd
        self.tags = tags
        self.photoData = photoAttachments.first?.imageData
        self.photoAttachments = photoAttachments
    }
}

struct CommunityComment: Identifiable, Equatable {
    let id: String
    let authorName: String
    let message: String
    let createdAt: Date
}

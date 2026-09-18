import ImageIO
import SwiftUI
import UIKit

/// 큰 원본을 실제 표시 크기에 맞게 디코딩합니다.
///
/// 네트워크 응답이나 PhotosPicker의 `Data`를 `UIImage(data:)`로 바로 열면
/// 작은 썸네일도 원본 픽셀 전체가 메모리에 올라옵니다. ImageIO가 썸네일을
/// 만들면서 orientation까지 적용하게 해 목록/지도/상세가 같은 규칙을 씁니다.
enum VFImageDownsampler {
    static func image(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    static func memoryCost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        return Int(pixelWidth * pixelHeight * 4)
    }
}

struct PhotoSpotImageView: View {
    let spot: PhotoSpot
    var symbolSize: CGFloat
    /// 원격 이미지를 받아올 목표 폭(px).
    ///
    /// 이전에는 1200 이 하드코딩되어 있었습니다. 그래서 화면 폭 236pt 짜리
    /// 작은 카드도, 3열 썸네일도 모두 1200px 이미지를 내려받아 디코딩했습니다.
    /// 디코딩 비용은 픽셀 수에 비례하므로 이게 스크롤 성능의 주 병목입니다.
    /// 쓰이는 크기에 맞게 요청하도록 파라미터로 뺐습니다.
    var targetPixelWidth: Int = VFPhotoDetail.card.pixelWidth
    @State private var revealedRemoteImageKey: String?

    var body: some View {
        if let assetImage {
            fitted(Image(uiImage: assetImage))
        } else if let imageURL = spot.imageURL {
            remoteImage(
                for: imageURL.wikimediaPreviewURL(width: targetPixelWidth) ?? imageURL
            )
        } else {
            placeholder
        }
    }

    /// 데이터가 도착한 순간 회색 표면을 사진으로 교체하지 않고,
    /// 같은 표면 위에서 짧게 opacity 를 올려 사진이 조용히 들어오게 합니다.
    private func remoteImage(for url: URL) -> some View {
        AsyncImage(url: url) { phase in
            ZStack {
                loadingPlaceholder

                switch phase {
                case .empty:
                    EmptyView()
                case .success(let image):
                    fitted(image)
                        .opacity(revealedRemoteImageKey == url.absoluteString ? 1 : 0)
                        .onAppear {
                            guard revealedRemoteImageKey != url.absoluteString else { return }
                            withAnimation(.easeOut(duration: 0.18)) {
                                revealedRemoteImageKey = url.absoluteString
                            }
                        }
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        }
        .onChange(of: url) { _, newURL in
            guard revealedRemoteImageKey != newURL.absoluteString else { return }
            revealedRemoteImageKey = nil
        }
    }

    private var assetImage: UIImage? {
        guard let imageName = spot.imageName, !imageName.isEmpty else { return nil }
        return UIImage(named: imageName)
    }

    private func fitted(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    /// 로딩 중에는 아무 것도 그리지 않고 표면만 둡니다.
    ///
    /// 사진 앱에서 스피너는 실패 신호처럼 보입니다.
    /// 사진이 준비되면 조용히 나타나는 편이 품질 있게 느껴집니다.
    private var loadingPlaceholder: some View {
        placeholderSurface
    }

    private var placeholder: some View {
        placeholderSurface
        .overlay {
            Image(systemName: "camera.aperture")
                .font(.system(size: symbolSize, weight: .regular))
                .foregroundStyle(AppColors.secondaryText.opacity(0.58))
        }
    }

    private var placeholderSurface: some View {
        AppColors.mutedSurface
            .overlay {
                Rectangle()
                    .stroke(AppColors.divider.opacity(0.72), lineWidth: 1)
            }
    }
}

struct MissingSpotPhotoPrompt: View {
    enum Layout {
        case hero
        case compact
    }

    let layout: Layout

    var body: some View {
        VStack(spacing: layout == .hero ? 10 : 6) {
            Image(systemName: "camera.badge.plus")
                .font(.system(size: layout == .hero ? 28 : 20, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)

            Text("이 장소의 첫 사진을 남겨주세요")
                .font(.system(size: layout == .hero ? 16 : 12, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .multilineTextAlignment(.center)

            if layout == .hero {
                Text("직접 촬영한 사진만 등록할 수 있어요")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(layout == .hero ? 20 : 10)
        .background(AppColors.mutedSurface)
    }
}

// private 에서 internal 로 올렸습니다.
// 지도 사진 핀에서도 같은 축소 규칙을 써야 하는데, 로직을 복사하면
// 두 곳이 어긋날 수 있습니다.
extension URL {
    func wikimediaPreviewURL(width: Int) -> URL? {
        guard host == "upload.wikimedia.org",
              path.contains("/wikipedia/commons/") else {
            return nil
        }

        let fileName = lastPathComponent.removingPercentEncoding ?? lastPathComponent
        var components = URLComponents()
        components.scheme = "https"
        components.host = "commons.wikimedia.org"
        components.path = "/wiki/Special:Redirect/file/\(fileName)"
        components.queryItems = [
            URLQueryItem(name: "width", value: "\(width)")
        ]
        return components.url
    }
}

struct RemotePhotoSpotImageView: View {
    let spot: PhotoSpot
    let imageURL: URL
    let symbolSize: CGFloat

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            default:
                PhotoSpotImageView(spot: spot, symbolSize: symbolSize)
            }
        }
    }
}

struct SkeletonRail: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.primary.opacity(0.06))
                            .frame(height: 78)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppColors.primary.opacity(0.07))
                            .frame(width: 118, height: 14)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppColors.primary.opacity(0.05))
                            .frame(width: 146, height: 12)
                    }
                    .padding(8)
                    .frame(width: 160, height: 160)
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.divider, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }
}

import SwiftUI
import UIKit

struct PhotoSpotImageView: View {
    let spot: PhotoSpot
    var symbolSize: CGFloat

    var body: some View {
        if let assetImage {
            fitted(Image(uiImage: assetImage))
        } else if let imageURL = spot.imageURL {
            AsyncImage(url: imageURL.wikimediaPreviewURL(width: 1200) ?? imageURL) { phase in
                switch phase {
                case .empty:
                    loadingPlaceholder
                case .success(let image):
                    fitted(image)
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
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

    private var loadingPlaceholder: some View {
        placeholderSurface
            .overlay {
                ProgressView()
                    .tint(AppColors.secondaryText)
                    .controlSize(.small)
            }
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

private extension URL {
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

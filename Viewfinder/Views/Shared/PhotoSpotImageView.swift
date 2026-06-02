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
        placeholder
            .overlay {
                ProgressView()
                    .tint(spot.theme.primary)
                    .scaleEffect(0.76)
            }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: placeholderColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(spot.theme.primary.opacity(0.55))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var placeholderColors: [Color] {
        let palettes: [[Color]] = [
            [AppColors.background, AppColors.mutedSurface],
            [AppColors.cardBackground, AppColors.background],
            [AppColors.background, AppColors.divider.opacity(0.48)],
            [AppColors.mutedSurface, AppColors.divider.opacity(0.62)],
            [AppColors.cardBackground, AppColors.mutedSurface]
        ]
        let index = abs(spot.id.hashValue) % palettes.count
        return palettes[index]
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

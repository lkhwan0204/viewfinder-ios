import Foundation

struct PhotoSpotCacheService {
    private struct CachePayload: Codable {
        let region: String
        let cachedAt: Date
        let spots: [VerifiedPhotoSpot]
    }

    private let fileManager = FileManager.default

    func cachedSpots(for region: String) -> [VerifiedPhotoSpot] {
        guard let url = cacheURL(for: region),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else {
            return []
        }

        return payload.spots
    }

    func store(_ spots: [VerifiedPhotoSpot], for region: String) {
        guard !spots.isEmpty, let url = cacheURL(for: region) else { return }

        let payload = CachePayload(region: region, cachedAt: Date(), spots: spots)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    private func cacheURL(for region: String) -> URL? {
        guard let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        return directory
            .appendingPathComponent("ViewfinderRecommendationCache", isDirectory: true)
            .appendingPathComponent("\(cacheKey(for: region)).json")
    }

    private func cacheKey(for region: String) -> String {
        let normalized = region
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        return normalized.isEmpty ? "default" : String(normalized)
    }
}

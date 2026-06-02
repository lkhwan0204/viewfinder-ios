import Foundation
import SwiftUI

struct CommunityPost: Identifiable, Equatable {
    enum Crowd: String, CaseIterable, Identifiable {
        case relaxed = "여유"
        case normal = "보통"
        case crowded = "많음"

        var id: String { rawValue }

        var displayText: String {
            switch self {
            case .relaxed:
                return "혼잡도 · 여유"
            case .normal:
                return "혼잡도 · 보통"
            case .crowded:
                return "혼잡도 · 많음"
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

        var fill: Color {
            tint.opacity(0.12)
        }
    }

    let id: String
    let spotID: String
    let spotName: String
    let message: String
    let crowd: Crowd
    let tags: [String]
    let photoData: Data?
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
}

struct CommunityPostDraft {
    let spot: PhotoSpot
    let message: String
    let crowd: CommunityPost.Crowd
    let tags: [String]
    let photoData: Data?
}

struct CommunityComment: Identifiable, Equatable {
    let id: String
    let authorName: String
    let message: String
    let createdAt: Date
}

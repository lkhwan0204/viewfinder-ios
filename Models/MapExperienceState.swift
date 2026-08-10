import Foundation

enum MapFilterMode {
    case recommendations
    case saved
    case explicitSpot
}

@MainActor
final class MapExperienceState: ObservableObject {
    @Published var mode: MapFilterMode = .recommendations
    @Published private(set) var recommendationState: AsyncLoadState = .idle
    @Published var explicitSpot: PhotoSpot?
    @Published var shouldFocusUserOnSelection = true
    @Published var isSavedListPresented = false
    @Published var savedListFilter: SavedMapListFilter = .all
    @Published var categoryFilter: MapCategoryFilter = .all
    @Published var userLocationFocusRevision = 0

    var isRecommendationLoading: Bool {
        recommendationState.isLoading
    }

    func activateRecommendations(resetCategory: Bool = true) {
        mode = .recommendations
        recommendationState = .loaded
        explicitSpot = nil
        isSavedListPresented = false
        savedListFilter = .all
        shouldFocusUserOnSelection = true
        if resetCategory {
            categoryFilter = .all
        }
    }

    func beginRecommendations() {
        mode = .recommendations
        recommendationState = .loading
        explicitSpot = nil
        isSavedListPresented = false
        savedListFilter = .all
    }

    func finishRecommendations(errorMessage: String? = nil) {
        guard mode == .recommendations else { return }
        if let errorMessage {
            recommendationState = .failed(message: errorMessage)
        } else {
            recommendationState = .loaded
        }
    }

    func showSavedSpots() {
        mode = .saved
        recommendationState = .idle
        explicitSpot = nil
        isSavedListPresented = false
    }

    func showExplicitSpot(_ spot: PhotoSpot) {
        mode = .explicitSpot
        recommendationState = .idle
        explicitSpot = spot
        isSavedListPresented = false
        savedListFilter = .all
        shouldFocusUserOnSelection = false
    }
}

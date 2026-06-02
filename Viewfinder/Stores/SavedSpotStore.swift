import Combine
import Foundation

@MainActor
final class SavedSpotStore: ObservableObject {
    @Published private(set) var savedSpotIDs: Set<String>

    private let storageKey = "photo-shoot-saved-spot-ids"

    init() {
        let ids = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        savedSpotIDs = Set(ids)
    }

    func contains(_ spot: PhotoSpot) -> Bool {
        savedSpotIDs.contains(spot.id)
    }

    func toggle(_ spot: PhotoSpot) {
        if savedSpotIDs.contains(spot.id) {
            savedSpotIDs.remove(spot.id)
        } else {
            savedSpotIDs.insert(spot.id)
        }

        UserDefaults.standard.set(Array(savedSpotIDs), forKey: storageKey)
    }
}

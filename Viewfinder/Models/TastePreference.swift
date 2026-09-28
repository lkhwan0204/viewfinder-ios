import Foundation

/// The nine offline-first photos used to seed the first Home recommendations.
struct TasteOnboardingPhoto: Identifiable, Sendable {
    let id: String
    let assetName: String
    let accessibilityDescription: String
    let primaryTheme: SpotTheme
    let moods: [String]
    let subjects: [String]
    let timeOfDay: [String]
}

enum TasteOnboardingCatalog {
    static let photos: [TasteOnboardingPhoto] = [
        .init(id: "city-bridge", assetName: "spot_seongsu_cloud_bridge",
              accessibilityDescription: "도심 다리 야경 사진", primaryTheme: .cityArchitecture,
              moods: ["야경", "필름감성"], subjects: ["다리", "도시"], timeOfDay: ["야경"]),
        .init(id: "forest", assetName: "spot_seoul_forest",
              accessibilityDescription: "초록 숲길 사진", primaryTheme: .landscape,
              moods: ["초록", "산책"], subjects: ["숲", "꽃"], timeOfDay: ["오전"]),
        .init(id: "retro-alley", assetName: "spot_mullae_creative_village",
              accessibilityDescription: "레트로 골목 사진", primaryTheme: .retroAlley,
              moods: ["필름감성", "빈티지"], subjects: ["골목", "철"], timeOfDay: ["오후"]),
        .init(id: "sunset-park", assetName: "spot_nanji_hangang_park",
              accessibilityDescription: "한강 노을 공원 사진", primaryTheme: .landscape,
              moods: ["노을", "피크닉"], subjects: ["한강", "공원"], timeOfDay: ["노을"]),
        .init(id: "ancient-tombs", assetName: "spot_daegu_bullodong_tombs",
              accessibilityDescription: "초록 고분군과 소나무 사진", primaryTheme: .historyTradition,
              moods: ["고요함", "초록"], subjects: ["고분군", "소나무"], timeOfDay: ["오전"]),
        .init(id: "city-view", assetName: "spot_yongmasan_skywalk",
              accessibilityDescription: "도시 전망 야경 사진", primaryTheme: .viewpoint,
              moods: ["야경", "블루아워"], subjects: ["전망", "도시"], timeOfDay: ["야경"]),
        .init(id: "cafe", assetName: "spot_house_of_vinyl_yeonhui",
              accessibilityDescription: "빈티지 카페 외관 사진", primaryTheme: .cafeIndoor,
              moods: ["필름감성", "빈티지"], subjects: ["카페", "간판"], timeOfDay: ["오후"]),
        .init(id: "river-view", assetName: "spot_yeongdong_bridge_lower",
              accessibilityDescription: "도시와 한강 노을 전망 사진", primaryTheme: .viewpoint,
              moods: ["노을", "야경"], subjects: ["한강", "도시"], timeOfDay: ["노을"]),
        .init(id: "sea", assetName: "spot_busan_gwangalli_beach",
              accessibilityDescription: "바다와 해변 야경 사진", primaryTheme: .landscape,
              moods: ["야경", "산책"], subjects: ["바다", "해변"], timeOfDay: ["야경"])
    ]
}

struct TastePreference: Codable, Equatable, Sendable {
    let selectedPhotoIDs: [String]
    let themeWeights: [String: Int]
    let moodWeights: [String: Int]
    let subjectWeights: [String: Int]
    let timeOfDayWeights: [String: Int]
    let completedAt: Date

    /// First selection has the strongest influence. Keep this in one place
    /// so changing the ranking policy does not require changing the UI.
    static let selectionWeights = [3, 2, 1]
    static let maximumBonus = 24

    init?(selectedPhotoIDs: [String], completedAt: Date = Date()) {
        guard selectedPhotoIDs.count == Self.selectionWeights.count,
              Set(selectedPhotoIDs).count == selectedPhotoIDs.count else { return nil }
        let photosByID = Dictionary(uniqueKeysWithValues: TasteOnboardingCatalog.photos.map { ($0.id, $0) })
        guard selectedPhotoIDs.allSatisfy({ photosByID[$0] != nil }) else { return nil }

        self.selectedPhotoIDs = selectedPhotoIDs
        self.completedAt = completedAt
        var themeWeights: [String: Int] = [:]
        var moodWeights: [String: Int] = [:]
        var subjectWeights: [String: Int] = [:]
        var timeOfDayWeights: [String: Int] = [:]

        for (index, id) in selectedPhotoIDs.enumerated() {
            guard let photo = photosByID[id] else { continue }
            let weight = Self.selectionWeights[index]
            themeWeights[photo.primaryTheme.rawValue, default: 0] += weight
            for mood in Set(photo.moods) { moodWeights[mood, default: 0] += weight }
            for subject in Set(photo.subjects) { subjectWeights[subject, default: 0] += weight }
            for time in Set(photo.timeOfDay) { timeOfDayWeights[time, default: 0] += weight }
        }

        self.themeWeights = themeWeights
        self.moodWeights = moodWeights
        self.subjectWeights = subjectWeights
        self.timeOfDayWeights = timeOfDayWeights
    }

    /// A small additive score only: it never excludes a place or replaces the
    /// existing location, weather, time and editorial ranking signals.
    func affinityBonus(for spot: PhotoSpot) -> Int {
        let searchable = ([spot.name, spot.summary, spot.category, spot.bestTime]
            + spot.hashtags + spot.mood).map(Self.normalized)
        func matchedWeight(_ weights: [String: Int]) -> Int {
            weights.reduce(0) { total, entry in
                let token = Self.normalized(entry.key)
                return total + (searchable.contains(where: { $0.contains(token) }) ? entry.value : 0)
            }
        }

        let theme = themeWeights[spot.theme.rawValue, default: 0] * 2
        let mood = min(matchedWeight(moodWeights), 8)
        let subject = min(matchedWeight(subjectWeights), 6)
        let time = min(matchedWeight(timeOfDayWeights), 3)
        return min(Self.maximumBonus, theme + mood + subject + time)
    }

    var cacheKey: String { "taste-v1-" + selectedPhotoIDs.joined(separator: "-") }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))
            .filter { !$0.isWhitespace }
    }
}

enum TastePreferenceStore {
    static let completionKey = "hasCompletedTasteOnboarding"
    private static let preferenceKey = "viewfinder.tastePreference.v1"

    static func load(defaults: UserDefaults = .standard) -> TastePreference? {
        guard let data = defaults.data(forKey: preferenceKey) else { return nil }
        return try? JSONDecoder().decode(TastePreference.self, from: data)
    }

    @discardableResult
    static func save(_ preference: TastePreference, defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(preference) else { return false }
        defaults.set(data, forKey: preferenceKey)
        defaults.set(true, forKey: completionKey)
        return true
    }

    static func skip(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferenceKey)
        defaults.set(true, forKey: completionKey)
    }
}

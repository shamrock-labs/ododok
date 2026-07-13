import Foundation

struct PersonalizedChewDetectionSettings: Codable, Equatable {
    let minPeakAmplitude: Double
    let calibrationPeakCount: Int
    let validationDetectedCount: Int
    let calibratedAt: Date

    var configuration: ChewDetectionConfiguration {
        ChewDetectionConfiguration(minPeakAmplitude: minPeakAmplitude)
    }
}

protocol ChewDetectionPersonalizationStoring {
    func load() -> PersonalizedChewDetectionSettings?
    func save(_ settings: PersonalizedChewDetectionSettings)
    func clear()
}

struct UserDefaultsChewProfileStore: ChewDetectionPersonalizationStoring {
    static let storageKey = "ododok.chewDetectionPersonalization.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersonalizedChewDetectionSettings? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(PersonalizedChewDetectionSettings.self, from: data)
    }

    func save(_ settings: PersonalizedChewDetectionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

import Foundation

struct PersonalizedChewDetectionSettings: Codable, Equatable {
    let minPeakAmplitude: Double
    let calibrationPeakCount: Int
    let validationDetectedCount: Int
    let calibratedAt: Date
    var naturalChewInterval: TimeInterval?
    var calibrationAmplitudes: [Double]?
    var gateThresholds: ChewingGateThresholds?

    init(
        minPeakAmplitude: Double,
        calibrationPeakCount: Int,
        validationDetectedCount: Int,
        calibratedAt: Date,
        naturalChewInterval: TimeInterval? = nil,
        calibrationAmplitudes: [Double]? = nil,
        gateThresholds: ChewingGateThresholds? = nil
    ) {
        self.minPeakAmplitude = minPeakAmplitude
        self.calibrationPeakCount = calibrationPeakCount
        self.validationDetectedCount = validationDetectedCount
        self.calibratedAt = calibratedAt
        self.naturalChewInterval = naturalChewInterval
        self.calibrationAmplitudes = calibrationAmplitudes
        self.gateThresholds = gateThresholds
    }

    var configuration: ChewDetectionConfiguration {
        ChewDetectionConfiguration(
            minPeakAmplitude: minPeakAmplitude,
            gateThresholds: gateThresholds ?? .standard
        )
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

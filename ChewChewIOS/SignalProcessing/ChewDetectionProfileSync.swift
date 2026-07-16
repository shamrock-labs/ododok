import Foundation
import Observation

struct ChewDetectionGateThresholdsDTO: Codable, Equatable {
    let minimumRotationYStd: Double
    let minimumRotationYDominance: Double
    let minimumRotationYJitterBandDominance: Double
    let requiresOpenActivityGate: Bool

    static let standard = ChewDetectionGateThresholdsDTO(
        minimumRotationYStd: ChewingGateThresholds.standard.minimumRotationYStd,
        minimumRotationYDominance: ChewingGateThresholds.standard.minimumRotationYDominance,
        minimumRotationYJitterBandDominance: ChewingGateThresholds.standard.minimumRotationYJitterBandDominance,
        requiresOpenActivityGate: true
    )

    var configurationValue: ChewingGateThresholds {
        ChewingGateThresholds(
            minimumRotationYStd: minimumRotationYStd,
            minimumRotationYDominance: minimumRotationYDominance,
            minimumRotationYJitterBandDominance: minimumRotationYJitterBandDominance
        )
    }
}

struct ChewDetectionProfileDTO: Codable, Equatable {
    let id: UUID
    let modelVersion: String
    let revision: Int
    let minPeakAmplitude: Double
    let calibrationPeakCount: Int
    let validationDetectedCount: Int
    let calibratedAt: Date
    let naturalChewInterval: TimeInterval?
    let calibrationAmplitudes: [Double]?
    let gateThresholds: ChewDetectionGateThresholdsDTO?
    let source: String
    let createdAt: Date

    var settings: PersonalizedChewDetectionSettings {
        PersonalizedChewDetectionSettings(
            minPeakAmplitude: minPeakAmplitude,
            calibrationPeakCount: calibrationPeakCount,
            validationDetectedCount: validationDetectedCount,
            calibratedAt: calibratedAt,
            naturalChewInterval: naturalChewInterval,
            calibrationAmplitudes: calibrationAmplitudes,
            gateThresholds: gateThresholds?.configurationValue
        )
    }

    var configuration: ChewDetectionConfiguration {
        ChewDetectionConfiguration(
            minPeakAmplitude: minPeakAmplitude,
            gateThresholds: gateThresholds?.configurationValue ?? .standard,
            requiresOpenActivityGate: gateThresholds?.requiresOpenActivityGate ?? true
        )
    }
}

struct ChewDetectionProfileRequestDTO: Codable, Equatable {
    let modelVersion: String
    let minPeakAmplitude: Double
    let calibrationPeakCount: Int
    let validationDetectedCount: Int
    let calibratedAt: Date
    let naturalChewInterval: TimeInterval?
    let calibrationAmplitudes: [Double]?
    let gateThresholds: ChewDetectionGateThresholdsDTO?
    let source: String

    init(settings: PersonalizedChewDetectionSettings, modelVersion: String, source: String) {
        self.modelVersion = modelVersion
        minPeakAmplitude = settings.minPeakAmplitude
        calibrationPeakCount = settings.calibrationPeakCount
        validationDetectedCount = settings.validationDetectedCount
        calibratedAt = settings.calibratedAt
        naturalChewInterval = settings.naturalChewInterval
        calibrationAmplitudes = settings.calibrationAmplitudes
        if let thresholds = settings.gateThresholds {
            gateThresholds = ChewDetectionGateThresholdsDTO(
                minimumRotationYStd: thresholds.minimumRotationYStd,
                minimumRotationYDominance: thresholds.minimumRotationYDominance,
                minimumRotationYJitterBandDominance: thresholds.minimumRotationYJitterBandDominance,
                requiresOpenActivityGate: settings.configuration.requiresOpenActivityGate
            )
        } else {
            gateThresholds = nil
        }
        self.source = source
    }
}

struct MealChewDetectionContext: Equatable {
    let configuration: ChewDetectionConfiguration
    let profileId: UUID?

    static let standard = MealChewDetectionContext(configuration: .standard, profileId: nil)
}

final class UserDefaultsChewDetectionProfileCache {
    static let storageKey = "ododok.chewDetectionProfileCache.v1"
    static let legacyOwnerKey = "ododok.chewDetectionProfileCache.legacyOwner.v1"
    static let freshnessInterval: TimeInterval = 24 * 60 * 60

    private struct Entry: Codable {
        let resolvedAt: Date
        let profile: ChewDetectionProfileDTO?
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func storeResolved(
        _ profile: ChewDetectionProfileDTO?,
        userId: String,
        modelVersion: String,
        at date: Date
    ) {
        var entries = loadEntries()
        entries[key(userId: userId, modelVersion: modelVersion)] = Entry(resolvedAt: date, profile: profile)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func needsRefresh(userId: String, modelVersion: String, now: Date = Date()) -> Bool {
        guard let entry = loadEntries()[key(userId: userId, modelVersion: modelVersion)] else { return true }
        return now.timeIntervalSince(entry.resolvedAt) >= Self.freshnessInterval
    }

    func cachedProfile(userId: String, modelVersion: String) -> ChewDetectionProfileDTO? {
        loadEntries()[key(userId: userId, modelVersion: modelVersion)]?.profile
    }

    func mealContext(userId: String?, modelVersion: String) -> MealChewDetectionContext {
        guard let userId,
              let profile = cachedProfile(userId: userId, modelVersion: modelVersion) else {
            return .standard
        }
        return MealChewDetectionContext(configuration: profile.configuration, profileId: profile.id)
    }

    func clear(userId: String) {
        var entries = loadEntries()
        entries = entries.filter { !$0.key.hasPrefix("\(userId)\u{1F}") }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func claimLegacyOwnershipIfNeeded(userId: String) {
        guard defaults.string(forKey: Self.legacyOwnerKey) == nil else { return }
        defaults.set(userId, forKey: Self.legacyOwnerKey)
    }

    func legacyBelongs(to userId: String) -> Bool {
        defaults.string(forKey: Self.legacyOwnerKey) == userId
    }

    func clearLegacyOwnership() {
        defaults.removeObject(forKey: Self.legacyOwnerKey)
    }

    private func loadEntries() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func key(userId: String, modelVersion: String) -> String {
        "\(userId)\u{1F}\(modelVersion)"
    }
}

@Observable
@MainActor
final class ChewDetectionProfileManager {
    private(set) var currentProfile: ChewDetectionProfileDTO?
    private(set) var activeUserId: String?

    private let remoteStore: any RemoteStore
    private let cache: UserDefaultsChewDetectionProfileCache
    private let legacyStore: any ChewDetectionPersonalizationStoring
    private let now: () -> Date

    init(
        remoteStore: any RemoteStore,
        cache: UserDefaultsChewDetectionProfileCache = UserDefaultsChewDetectionProfileCache(),
        legacyStore: any ChewDetectionPersonalizationStoring = UserDefaultsChewProfileStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.remoteStore = remoteStore
        self.cache = cache
        self.legacyStore = legacyStore
        self.now = now
    }

    var currentSettings: PersonalizedChewDetectionSettings? { currentProfile?.settings }

    func activate(userId: String, forceRefresh: Bool = false) async {
        activeUserId = userId
        if legacyStore.load() != nil {
            cache.claimLegacyOwnershipIfNeeded(userId: userId)
        }
        currentProfile = cache.cachedProfile(userId: userId, modelVersion: ChewDetectionEngine.modelVersion)
        guard forceRefresh || cache.needsRefresh(
            userId: userId,
            modelVersion: ChewDetectionEngine.modelVersion,
            now: now()
        ) else { return }

        do {
            if let serverProfile = try await remoteStore.fetchCurrentChewDetectionProfile(
                modelVersion: ChewDetectionEngine.modelVersion
            ) {
                apply(serverProfile, userId: userId)
                clearLegacyIfOwned(by: userId)
                return
            }
            if cache.legacyBelongs(to: userId), let legacySettings = legacyStore.load() {
                let imported = try await remoteStore.createChewDetectionProfile(
                    ChewDetectionProfileRequestDTO(
                        settings: legacySettings,
                        modelVersion: ChewDetectionEngine.modelVersion,
                        source: "LEGACY_LOCAL"
                    ),
                    idempotencyKey: "legacy-local-v1-\(ChewDetectionEngine.modelVersion)"
                )
                apply(imported, userId: userId)
                clearLegacyIfOwned(by: userId)
                return
            }
            cache.storeResolved(nil, userId: userId, modelVersion: ChewDetectionEngine.modelVersion, at: now())
            currentProfile = nil
        } catch {
            // 동기화 실패 시 식사 시작을 막지 않고 마지막 캐시(없으면 기본 DSP)를 유지한다.
        }
    }

    func refreshIfStale(userId: String) async {
        guard cache.needsRefresh(
            userId: userId,
            modelVersion: ChewDetectionEngine.modelVersion,
            now: now()
        ) else { return }
        await activate(userId: userId, forceRefresh: true)
    }

    func save(_ settings: PersonalizedChewDetectionSettings, userId: String) async throws {
        let saved = try await remoteStore.createChewDetectionProfile(
            ChewDetectionProfileRequestDTO(
                settings: settings,
                modelVersion: ChewDetectionEngine.modelVersion,
                source: "PERSONALIZATION"
            ),
            idempotencyKey: UUID().uuidString
        )
        apply(saved, userId: userId)
        clearLegacyIfOwned(by: userId)
    }

    func reset(userId: String) async throws {
        try await remoteStore.resetCurrentChewDetectionProfile(modelVersion: ChewDetectionEngine.modelVersion)
        cache.storeResolved(nil, userId: userId, modelVersion: ChewDetectionEngine.modelVersion, at: now())
        clearLegacyIfOwned(by: userId)
        if activeUserId == userId { currentProfile = nil }
    }

    func mealContext(userId: String?) -> MealChewDetectionContext {
        let cached = cache.mealContext(userId: userId, modelVersion: ChewDetectionEngine.modelVersion)
        if cached.profileId != nil { return cached }
        if let userId,
           cache.legacyBelongs(to: userId),
           let legacySettings = legacyStore.load() {
            return MealChewDetectionContext(configuration: legacySettings.configuration, profileId: nil)
        }
        return cached
    }

    func deactivate() {
        activeUserId = nil
        currentProfile = nil
    }

    func clearLocalAccountData(userId: String) {
        cache.clear(userId: userId)
        clearLegacyIfOwned(by: userId)
        deactivate()
    }

    private func apply(_ profile: ChewDetectionProfileDTO, userId: String) {
        cache.storeResolved(profile, userId: userId, modelVersion: profile.modelVersion, at: now())
        if activeUserId == userId { currentProfile = profile }
    }

    private func clearLegacyIfOwned(by userId: String) {
        guard cache.legacyBelongs(to: userId) else { return }
        legacyStore.clear()
        cache.clearLegacyOwnership()
    }
}

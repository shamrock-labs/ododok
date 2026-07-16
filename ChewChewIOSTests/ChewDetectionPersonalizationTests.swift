import XCTest
@testable import ChewChewIOS

final class ChewDetectionPersonalizationTests: XCTestCase {
    func testAccountAndModelScopedCacheDoesNotLeakProfiles() throws {
        let suiteName = "ChewDetectionProfileCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = UserDefaultsChewDetectionProfileCache(defaults: defaults)
        let profile = makeRemoteProfile(id: UUID(), amplitude: 0.0042)

        cache.storeResolved(profile, userId: "user-a", modelVersion: "dsp-chewcounter-3", at: Date())

        XCTAssertEqual(
            cache.mealContext(userId: "user-a", modelVersion: "dsp-chewcounter-3").profileId,
            profile.id
        )
        XCTAssertNil(cache.mealContext(userId: "user-b", modelVersion: "dsp-chewcounter-3").profileId)
        XCTAssertNil(cache.mealContext(userId: "user-a", modelVersion: "dsp-chewcounter-2").profileId)
    }

    func testResolvedNoProfileIsFreshForTwentyFourHoursButUnresolvedIsNot() throws {
        let suiteName = "ChewDetectionProfileCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = UserDefaultsChewDetectionProfileCache(defaults: defaults)
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(cache.needsRefresh(
            userId: "user-a", modelVersion: "dsp-chewcounter-3", now: now))

        cache.storeResolved(nil, userId: "user-a", modelVersion: "dsp-chewcounter-3", at: now)

        XCTAssertFalse(cache.needsRefresh(
            userId: "user-a",
            modelVersion: "dsp-chewcounter-3",
            now: now.addingTimeInterval(86_399)))
        XCTAssertTrue(cache.needsRefresh(
            userId: "user-a",
            modelVersion: "dsp-chewcounter-3",
            now: now.addingTimeInterval(86_401)))
    }

    func testMealContextUsesTheCachedConfigurationSnapshot() throws {
        let suiteName = "ChewDetectionProfileCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = UserDefaultsChewDetectionProfileCache(defaults: defaults)
        let profile = makeRemoteProfile(id: UUID(), amplitude: 0.0091)
        cache.storeResolved(profile, userId: "user-a", modelVersion: "dsp-chewcounter-3", at: Date())

        let context = cache.mealContext(userId: "user-a", modelVersion: "dsp-chewcounter-3")

        XCTAssertEqual(context.profileId, profile.id)
        XCTAssertEqual(context.configuration.minPeakAmplitude, 0.0091)
    }

    @MainActor
    func testServerProfileWinsOverLegacyLocalSettings() async throws {
        let suiteName = "ChewDetectionProfileManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = UserDefaultsChewProfileStore(defaults: defaults)
        legacy.save(makeSettings(amplitude: 0.003))
        let serverProfile = makeRemoteProfile(id: UUID(), amplitude: 0.009)
        let remote = ChewProfileRemoteStoreStub(serverProfile: serverProfile)
        let manager = ChewDetectionProfileManager(
            remoteStore: remote,
            cache: UserDefaultsChewDetectionProfileCache(defaults: defaults),
            legacyStore: legacy
        )

        await manager.activate(userId: "user-a", forceRefresh: true)

        XCTAssertEqual(manager.currentProfile?.id, serverProfile.id)
        XCTAssertNil(remote.createdRequest)
        XCTAssertNil(legacy.load(), "server-wins sync must remove the obsolete global legacy value")
    }

    @MainActor
    func testFailedInitialSyncKeepsUsingLegacyDSPWithoutAProfileId() async throws {
        let suiteName = "ChewDetectionProfileManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = UserDefaultsChewProfileStore(defaults: defaults)
        legacy.save(makeSettings(amplitude: 0.0055))
        let remote = ChewProfileRemoteStoreStub(serverProfile: nil)
        remote.shouldFailFetch = true
        let manager = ChewDetectionProfileManager(
            remoteStore: remote,
            cache: UserDefaultsChewDetectionProfileCache(defaults: defaults),
            legacyStore: legacy
        )

        await manager.activate(userId: "user-a", forceRefresh: true)
        let context = manager.mealContext(userId: "user-a")

        XCTAssertNil(context.profileId)
        XCTAssertEqual(context.configuration.minPeakAmplitude, 0.0055)
        XCTAssertNotNil(legacy.load())

        manager.deactivate()
        await manager.activate(userId: "user-b", forceRefresh: true)
        let otherAccountContext = manager.mealContext(userId: "user-b")
        XCTAssertNil(otherAccountContext.profileId)
        XCTAssertEqual(otherAccountContext.configuration, .standard)
    }

    @MainActor
    func testAccountSwitchDoesNotImportAnotherAccountsOwnedLegacySettings() async throws {
        let suiteName = "ChewDetectionProfileManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = UserDefaultsChewProfileStore(defaults: defaults)
        legacy.save(makeSettings(amplitude: 0.0055))
        let remote = ChewProfileRemoteStoreStub(serverProfile: nil)
        remote.shouldFailFetch = true
        let manager = ChewDetectionProfileManager(
            remoteStore: remote,
            cache: UserDefaultsChewDetectionProfileCache(defaults: defaults),
            legacyStore: legacy
        )

        await manager.activate(userId: "user-a", forceRefresh: true)
        remote.shouldFailFetch = false
        manager.deactivate()

        await manager.activate(userId: "user-b", forceRefresh: true)

        XCTAssertNil(remote.createdRequest)
        XCTAssertNotNil(legacy.load())
        XCTAssertEqual(manager.mealContext(userId: "user-b").configuration, .standard)
    }

    @MainActor
    func testLateNoProfileResponseDoesNotClearTheActiveAccountsProfile() async throws {
        let suiteName = "ChewDetectionProfileManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userBProfile = makeRemoteProfile(id: UUID(), amplitude: 0.009)
        let remote = ControlledAccountSwitchRemoteStore(secondProfile: userBProfile)
        let manager = ChewDetectionProfileManager(
            remoteStore: remote,
            cache: UserDefaultsChewDetectionProfileCache(defaults: defaults),
            legacyStore: UserDefaultsChewProfileStore(defaults: defaults)
        )

        let userAActivation = Task {
            await manager.activate(userId: "user-a", forceRefresh: true)
        }
        await remote.waitUntilFirstFetchStarts()

        await manager.activate(userId: "user-b", forceRefresh: true)
        XCTAssertEqual(manager.currentProfile?.id, userBProfile.id)

        await remote.completeFirstFetch(with: nil)
        await userAActivation.value

        XCTAssertEqual(manager.activeUserId, "user-b")
        XCTAssertEqual(manager.currentProfile?.id, userBProfile.id)
    }

    @MainActor
    func testClearingLocalAccountDataRemovesProfileCacheAndOwnedLegacySettings() throws {
        let suiteName = "ChewDetectionProfileManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = UserDefaultsChewDetectionProfileCache(defaults: defaults)
        let legacy = UserDefaultsChewProfileStore(defaults: defaults)
        legacy.save(makeSettings(amplitude: 0.0055))
        cache.claimLegacyOwnershipIfNeeded(userId: "user-a")
        cache.storeResolved(
            makeRemoteProfile(id: UUID(), amplitude: 0.009),
            userId: "user-a",
            modelVersion: "dsp-chewcounter-3",
            at: Date()
        )
        let manager = ChewDetectionProfileManager(
            remoteStore: ChewProfileRemoteStoreStub(serverProfile: nil),
            cache: cache,
            legacyStore: legacy
        )

        manager.clearLocalAccountData(userId: "user-a")

        XCTAssertTrue(cache.needsRefresh(userId: "user-a", modelVersion: "dsp-chewcounter-3"))
        XCTAssertNil(cache.cachedProfile(userId: "user-a", modelVersion: "dsp-chewcounter-3"))
        XCTAssertNil(legacy.load())
        XCTAssertFalse(cache.legacyBelongs(to: "user-a"))
    }

    @MainActor
    func testSaveFailureKeepsThePreviouslyActiveProfile() async throws {
        let suiteName = "ChewDetectionProfileManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldProfile = makeRemoteProfile(id: UUID(), amplitude: 0.004)
        let remote = ChewProfileRemoteStoreStub(serverProfile: oldProfile)
        let manager = ChewDetectionProfileManager(
            remoteStore: remote,
            cache: UserDefaultsChewDetectionProfileCache(defaults: defaults),
            legacyStore: UserDefaultsChewProfileStore(defaults: defaults)
        )
        await manager.activate(userId: "user-a", forceRefresh: true)
        remote.shouldFailCreate = true

        do {
            try await manager.save(makeSettings(amplitude: 0.02), userId: "user-a")
            XCTFail("Expected save to fail")
        } catch {
            XCTAssertEqual(manager.currentProfile?.id, oldProfile.id)
            XCTAssertEqual(manager.currentProfile?.minPeakAmplitude, 0.004)
        }
    }

    func testSettingsRoundTripThroughUserDefaults() throws {
        let suiteName = "ChewDetectionPersonalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsChewProfileStore(defaults: defaults)
        let expected = PersonalizedChewDetectionSettings(
            minPeakAmplitude: 0.0042,
            calibrationPeakCount: 10,
            validationDetectedCount: 9,
            calibratedAt: Date(timeIntervalSince1970: 1_000),
            naturalChewInterval: 0.74,
            calibrationAmplitudes: [0.021, 0.024, 0.026],
            gateThresholds: ChewingGateThresholds(
                minimumRotationYStd: 0.025,
                minimumRotationYDominance: 0.2,
                minimumRotationYJitterBandDominance: 0.18
            )
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
        XCTAssertEqual(store.load()?.configuration.minPeakAmplitude, 0.0042)
        XCTAssertEqual(store.load()?.naturalChewInterval, 0.74)
        XCTAssertEqual(store.load()?.calibrationAmplitudes, [0.021, 0.024, 0.026])
        XCTAssertEqual(store.load()?.configuration.gateThresholds, expected.gateThresholds)
    }

    func testClearRestoresStandardFallback() throws {
        let suiteName = "ChewDetectionPersonalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsChewProfileStore(defaults: defaults)
        store.save(PersonalizedChewDetectionSettings(
            minPeakAmplitude: 0.0042,
            calibrationPeakCount: 10,
            validationDetectedCount: 10,
            calibratedAt: Date()
        ))

        store.clear()

        XCTAssertNil(store.load())
    }

    func testLegacyProfileWithoutGateThresholdsUsesStandardGate() throws {
        let suiteName = "ChewDetectionPersonalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyJSON = """
        {
          "minPeakAmplitude": 0.0042,
          "calibrationPeakCount": 10,
          "validationDetectedCount": 9,
          "calibratedAt": 0
        }
        """
        defaults.set(Data(legacyJSON.utf8), forKey: UserDefaultsChewProfileStore.storageKey)

        let settings = UserDefaultsChewProfileStore(defaults: defaults).load()

        XCTAssertNotNil(settings)
        XCTAssertNil(settings?.gateThresholds)
        XCTAssertEqual(settings?.configuration.gateThresholds, .standard)
    }

    private func makeRemoteProfile(id: UUID, amplitude: Double) -> ChewDetectionProfileDTO {
        ChewDetectionProfileDTO(
            id: id,
            modelVersion: "dsp-chewcounter-3",
            revision: 1,
            minPeakAmplitude: amplitude,
            calibrationPeakCount: 10,
            validationDetectedCount: 9,
            calibratedAt: Date(timeIntervalSince1970: 1_000),
            naturalChewInterval: 0.74,
            calibrationAmplitudes: [0.021, 0.024],
            gateThresholds: .standard,
            source: "PERSONALIZATION",
            createdAt: Date(timeIntervalSince1970: 1_001)
        )
    }

    private func makeSettings(amplitude: Double) -> PersonalizedChewDetectionSettings {
        PersonalizedChewDetectionSettings(
            minPeakAmplitude: amplitude,
            calibrationPeakCount: 10,
            validationDetectedCount: 9,
            calibratedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

private final class ChewProfileRemoteStoreStub: RemoteStore {
    enum StubError: Error { case failed, unused }

    var serverProfile: ChewDetectionProfileDTO?
    var createdRequest: ChewDetectionProfileRequestDTO?
    var shouldFailCreate = false
    var shouldFailFetch = false

    init(serverProfile: ChewDetectionProfileDTO?) {
        self.serverProfile = serverProfile
    }

    func fetchCurrentChewDetectionProfile(modelVersion: String) async throws -> ChewDetectionProfileDTO? {
        if shouldFailFetch { throw StubError.failed }
        return serverProfile
    }

    func createChewDetectionProfile(
        _ profile: ChewDetectionProfileRequestDTO,
        idempotencyKey: String
    ) async throws -> ChewDetectionProfileDTO {
        if shouldFailCreate { throw StubError.failed }
        createdRequest = profile
        return ChewDetectionProfileDTO(
            id: UUID(),
            modelVersion: profile.modelVersion,
            revision: 1,
            minPeakAmplitude: profile.minPeakAmplitude,
            calibrationPeakCount: profile.calibrationPeakCount,
            validationDetectedCount: profile.validationDetectedCount,
            calibratedAt: profile.calibratedAt,
            naturalChewInterval: profile.naturalChewInterval,
            calibrationAmplitudes: profile.calibrationAmplitudes,
            gateThresholds: profile.gateThresholds,
            source: profile.source,
            createdAt: Date()
        )
    }

    func resetCurrentChewDetectionProfile(modelVersion: String) async throws { serverProfile = nil }
    func upsertProfile(_ profile: ProfileDTO) async throws {}
    func fetchProfile() async throws -> ProfileDTO? { nil }
    func fetchUserStats() async throws -> UserStatsDTO? { nil }
    func deleteUserData() async throws {}
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        throw StubError.unused
    }
    func fetchHome(deviceId: String) async throws -> HomeStateDTO { .empty(deviceId: deviceId) }
    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        throw StubError.unused
    }
    func fetchChewingSessions(
        deviceId: String,
        since: Date,
        until: Date?
    ) async throws -> [ChewingSessionDTO] { [] }
    func deleteChewingSession(id: UUID, deviceId: String) async throws {}
    func deleteAllChewingSessions(deviceId: String) async throws {}
    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String { "" }
}

private actor ControlledAccountSwitchRemoteStore: RemoteStore {
    enum StubError: Error { case unused }

    private let secondProfile: ChewDetectionProfileDTO
    private var fetchCount = 0
    private var firstFetchStarted = false
    private var firstFetchWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstFetchContinuation: CheckedContinuation<ChewDetectionProfileDTO?, Never>?

    init(secondProfile: ChewDetectionProfileDTO) {
        self.secondProfile = secondProfile
    }

    func waitUntilFirstFetchStarts() async {
        if firstFetchStarted { return }
        await withCheckedContinuation { firstFetchWaiters.append($0) }
    }

    func completeFirstFetch(with profile: ChewDetectionProfileDTO?) {
        firstFetchContinuation?.resume(returning: profile)
        firstFetchContinuation = nil
    }

    func fetchCurrentChewDetectionProfile(modelVersion: String) async throws -> ChewDetectionProfileDTO? {
        fetchCount += 1
        if fetchCount == 1 {
            firstFetchStarted = true
            firstFetchWaiters.forEach { $0.resume() }
            firstFetchWaiters.removeAll()
            return await withCheckedContinuation { firstFetchContinuation = $0 }
        }
        return secondProfile
    }

    func createChewDetectionProfile(
        _ profile: ChewDetectionProfileRequestDTO,
        idempotencyKey: String
    ) async throws -> ChewDetectionProfileDTO { throw StubError.unused }
    func resetCurrentChewDetectionProfile(modelVersion: String) async throws { throw StubError.unused }
    func upsertProfile(_ profile: ProfileDTO) async throws {}
    func fetchProfile() async throws -> ProfileDTO? { nil }
    func fetchUserStats() async throws -> UserStatsDTO? { nil }
    func deleteUserData() async throws {}
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO {
        throw StubError.unused
    }
    func fetchHome(deviceId: String) async throws -> HomeStateDTO { .empty(deviceId: deviceId) }
    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        throw StubError.unused
    }
    func fetchChewingSessions(
        deviceId: String,
        since: Date,
        until: Date?
    ) async throws -> [ChewingSessionDTO] { [] }
    func deleteChewingSession(id: UUID, deviceId: String) async throws {}
    func deleteAllChewingSessions(deviceId: String) async throws {}
    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String { "" }
}

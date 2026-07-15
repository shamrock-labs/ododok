import XCTest
@testable import ChewChewIOS

final class ChewDetectionPersonalizationTests: XCTestCase {
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
}

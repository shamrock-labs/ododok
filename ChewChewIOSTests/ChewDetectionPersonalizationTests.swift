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
            calibratedAt: Date(timeIntervalSince1970: 1_000)
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
        XCTAssertEqual(store.load()?.configuration.minPeakAmplitude, 0.0042)
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
}

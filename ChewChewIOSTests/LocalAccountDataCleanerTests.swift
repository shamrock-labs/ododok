import XCTest
@testable import ChewChewIOS

@MainActor
final class LocalAccountDataCleanerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var rootDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "LocalAccountDataCleanerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalAccountDataCleanerTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootDirectory)
        defaults = nil
        suiteName = nil
        rootDirectory = nil
        super.tearDown()
    }

    func testClearRemovesPersonalizationReminderCacheAndPendingIMUArtifacts() async {
        let bundle = makeArtifactBundle()
        let failedUploader = SpyRemoteStore()
        failedUploader.uploadCalibrationArtifactsError = RemoteStoreError.offline
        let queue = CalibrationArtifactUploadQueue(
            remoteStore: failedUploader,
            rootDirectory: rootDirectory
        )
        await queue.enqueue(bundle)
        saveAccountScopedDefaults()
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootDirectory.path))
        XCTAssertNotNil(UserDefaultsChewProfileStore(defaults: defaults).load())
        XCTAssertNotEqual(MealReminderSettings.load(from: defaults), .default)

        LocalAccountDataCleaner(
            defaults: defaults,
            calibrationUploadsDirectory: rootDirectory
        ).clear()

        XCTAssertNil(UserDefaultsChewProfileStore(defaults: defaults).load())
        XCTAssertEqual(MealReminderSettings.load(from: defaults), .default)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootDirectory.path))
    }

    func testDeletedAccountPendingArtifactsAreNotUploadedForNextAccount() async {
        let failedUploader = SpyRemoteStore()
        failedUploader.uploadCalibrationArtifactsError = RemoteStoreError.offline
        let oldAccountQueue = CalibrationArtifactUploadQueue(
            remoteStore: failedUploader,
            rootDirectory: rootDirectory
        )
        await oldAccountQueue.enqueue(makeArtifactBundle())
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootDirectory.path))

        LocalAccountDataCleaner(
            defaults: defaults,
            calibrationUploadsDirectory: rootDirectory
        ).clear()

        let nextAccountRemote = SpyRemoteStore()
        let nextAccountQueue = CalibrationArtifactUploadQueue(
            remoteStore: nextAccountRemote,
            rootDirectory: rootDirectory
        )
        await nextAccountQueue.retryPending()

        XCTAssertTrue(nextAccountRemote.uploadedCalibrationBundles.isEmpty)
    }

    private func saveAccountScopedDefaults() {
        UserDefaultsChewProfileStore(defaults: defaults).save(.init(
            minPeakAmplitude: 0.02,
            calibrationPeakCount: 10,
            validationDetectedCount: 9,
            calibratedAt: .now
        ))
        var reminders = MealReminderSettings.default
        reminders.breakfast.enabled = true
        reminders.save(to: defaults)
    }

    private func makeArtifactBundle() -> CalibrationArtifactBundle {
        CalibrationArtifactBundle(
            calibrationId: UUID(),
            artifacts: CalibrationArtifactKind.allCases.map { kind in
                CalibrationArtifactUpload(kind: kind, data: Data(kind.rawValue.utf8))
            }
        )
    }
}

import XCTest
@testable import ChewChewIOS

@MainActor
final class MeasurementOnboardingStoreTests: XCTestCase {
    func testConnectedUserCanMoveFromIntroToCalibration() {
        let store = makeStore(isAirPodsConnected: true)

        store.moveForward()
        XCTAssertEqual(store.stage, .connection)

        store.moveForward()
        XCTAssertEqual(store.stage, .calibration)
    }

    func testDisconnectedUserCannotLeaveConnectionStep() {
        let store = makeStore(isAirPodsConnected: false)

        store.moveForward()
        store.moveForward()

        XCTAssertEqual(store.stage, .connection)
    }

    func testCalibrationNeedsAtLeastSevenRepresentativePeaks() {
        XCTAssertNil(PeakAmplitudeCalibration.personalizedThreshold(
            from: [0.02, 0.021, 0.022, 0.023, 0.024, 0.025]
        ))
    }

    func testCalibrationUsesConservativeLowerPeakAndClamp() throws {
        let threshold = try XCTUnwrap(PeakAmplitudeCalibration.personalizedThreshold(
            from: [0.028, 0.031, 0.034, 0.041, 0.029, 0.036, 0.033, 0.039, 0.030, 0.037]
        ))

        XCTAssertEqual(threshold, 0.0174, accuracy: 0.000_001)
    }

    func testValidationAcceptsSmallCountingTolerance() {
        XCTAssertFalse(PeakAmplitudeCalibration.validationPassed(detectedCount: 7))
        XCTAssertTrue(PeakAmplitudeCalibration.validationPassed(detectedCount: 8))
        XCTAssertTrue(PeakAmplitudeCalibration.validationPassed(detectedCount: 12))
        XCTAssertFalse(PeakAmplitudeCalibration.validationPassed(detectedCount: 13))
    }

    func testTenCalibrationChewsThenTenValidationChewsBuildLocalProfile() async {
        let sampler = ManualCalibrationSampler()
        let cuePlayer = RecordingMeasurementCuePlayer()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            timing: .init(cueCount: 10, cueInterval: .milliseconds(20)),
            sampler: sampler,
            cuePlayer: cuePlayer
        )

        store.startMeasurement()
        await emitOnePeakPerCue(store: store, sampler: sampler)
        await waitUntil { store.measurementCompleted }

        XCTAssertEqual(store.calibrationAmplitudes.count, 10)
        XCTAssertNotNil(store.candidateMinPeakAmplitude)
        XCTAssertEqual(cuePlayer.playCount, 10)

        store.moveForward()
        XCTAssertEqual(store.stage, .validation)

        store.startMeasurement()
        await emitOnePeakPerCue(store: store, sampler: sampler)
        await waitUntil { store.stage == .ready }

        XCTAssertEqual(store.profile?.validationDetectedCount, 10)
        XCTAssertEqual(store.profile?.calibrationAmplitudes.count, 10)
    }

    func testCalibrationIgnoresMotionBeforeNoteReachesTarget() async throws {
        let sampler = ManualCalibrationSampler()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            timing: .init(
                cueCount: 2,
                cueInterval: .milliseconds(40),
                cueApproachDuration: .milliseconds(20),
                cueResponseDuration: .milliseconds(20)
            ),
            sampler: sampler,
            cuePlayer: RecordingMeasurementCuePlayer()
        )

        store.startMeasurement()
        await waitUntil { store.cueIndex == 1 }
        sampler.emit(amplitude: 0.09)
        await waitUntil { store.cueHitID == 1 }
        sampler.emit(amplitude: 0.03)
        await waitUntil { store.calibrationAmplitudes.count == 1 }
        store.cancelMeasurement()

        XCTAssertEqual(try XCTUnwrap(store.calibrationAmplitudes.first), 0.03, accuracy: 0.000_001)
    }

    private func makeStore(isAirPodsConnected: Bool) -> MeasurementOnboardingStore {
        MeasurementOnboardingStore(
            isAirPodsConnected: isAirPodsConnected,
            sampler: ManualCalibrationSampler()
        )
    }

    private func emitOnePeakPerCue(
        store: MeasurementOnboardingStore,
        sampler: ManualCalibrationSampler
    ) async {
        for cue in 1...10 {
            if store.stage == .calibration {
                await waitUntil { store.cueHitID == cue }
            } else {
                await waitUntil { store.cueIndex == cue }
            }
            sampler.emit(amplitude: 0.03 + Double(cue) * 0.001)
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class RecordingMeasurementCuePlayer: MeasurementCuePlaying {
    private(set) var playCount = 0

    func playCalibrationCue() {
        playCount += 1
    }
}

@MainActor
private final class ManualCalibrationSampler: MeasurementCalibrationSampling {
    var isDeviceMotionAvailable = true
    private var onEvent: (@MainActor (ChewDetectionEvent) -> Void)?
    private var eventCount = 0

    func start(
        minPeakAmplitude _: Double,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError _: @escaping @MainActor (String) -> Void
    ) {
        self.onEvent = onEvent
        eventCount = 0
    }

    func emit(amplitude: Double) {
        eventCount += 1
        onEvent?(ChewDetectionEvent(
            count: eventCount,
            timestamp: Double(eventCount),
            amplitude: amplitude
        ))
    }

    func stop() async {
        onEvent = nil
    }
}

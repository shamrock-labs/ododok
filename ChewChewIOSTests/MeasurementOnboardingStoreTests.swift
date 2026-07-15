import XCTest
@testable import ChewChewIOS

@MainActor
final class MeasurementOnboardingStoreTests: XCTestCase {
    func testConnectedUserMovesFromIntroToStationaryBaseline() {
        let store = makeStore(isAirPodsConnected: true)

        store.moveForward()
        XCTAssertEqual(store.stage, .connection)

        store.moveForward()
        XCTAssertEqual(store.stage, .baseline)
    }

    func testDisconnectedUserCannotLeaveConnectionStep() {
        let store = makeStore(isAirPodsConnected: false)

        store.moveForward()
        store.moveForward()

        XCTAssertEqual(store.stage, .connection)
    }

    func testStationaryBaselineAutomaticallyMovesToNaturalMeasurement() async {
        let sampler = ManualCalibrationSampler()
        let store = MeasurementOnboardingStore(
            stage: .baseline,
            isAirPodsConnected: true,
            timing: .init(cueCount: 10, baselineDuration: .milliseconds(2)),
            sampler: sampler
        )

        store.startMeasurement()
        await waitUntil { store.stage == .calibration }

        XCTAssertFalse(store.isMeasuring)
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

    func testNaturalMeasurementKeepsStrongestPeakWithinOneChewWindow() throws {
        let events = [
            event(count: 1, timestamp: 0.00, amplitude: 0.010),
            event(count: 2, timestamp: 0.12, amplitude: 0.030),
            event(count: 3, timestamp: 0.24, amplitude: 0.020),
            event(count: 4, timestamp: 0.75, amplitude: 0.028),
            event(count: 5, timestamp: 1.50, amplitude: 0.032),
            event(count: 6, timestamp: 2.25, amplitude: 0.034),
            event(count: 7, timestamp: 3.00, amplitude: 0.036),
            event(count: 8, timestamp: 3.75, amplitude: 0.038),
            event(count: 9, timestamp: 4.50, amplitude: 0.040),
        ]

        let measurement = try XCTUnwrap(PeakAmplitudeCalibration.naturalMeasurement(from: events))

        XCTAssertEqual(measurement.representativePeaks.count, 7)
        XCTAssertEqual(measurement.representativePeaks.first?.timestamp, 0.12)
        XCTAssertEqual(measurement.representativePeaks.first?.amplitude, 0.030)
        XCTAssertEqual(measurement.naturalChewInterval, 0.75, accuracy: 0.000_001)
    }

    func testNaturalMeasurementKeepsTenStrongestPeaksInTimestampOrder() {
        let events = (0..<12).map { index in
            event(
                count: index + 1,
                timestamp: Double(index) * 0.7,
                amplitude: 0.01 + Double(index) * 0.001
            )
        }

        let peaks = PeakAmplitudeCalibration.representativePeaks(from: events)

        XCTAssertEqual(peaks.count, 10)
        XCTAssertEqual(peaks.map(\.timestamp), (2..<12).map { Double($0) * 0.7 })
    }

    func testAdjustmentTargetsEightToTenDetectedChews() {
        XCTAssertFalse(PeakAmplitudeCalibration.adjustmentSucceeded(detectedCount: 7))
        XCTAssertTrue(PeakAmplitudeCalibration.adjustmentSucceeded(detectedCount: 8))
        XCTAssertTrue(PeakAmplitudeCalibration.adjustmentSucceeded(detectedCount: 10))
        XCTAssertFalse(PeakAmplitudeCalibration.adjustmentSucceeded(detectedCount: 11))
    }

    func testFailedCalibrationExportsFourDiagnosticFiles() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = CalibrationArtifactBundle(
            calibrationId: UUID(),
            artifacts: CalibrationArtifactKind.allCases.map { kind in
                CalibrationArtifactUpload(kind: kind, data: Data(kind.rawValue.utf8))
            }
        )

        let urls = MeasurementCalibrationArtifactExporter.export(
            bundle,
            rootDirectory: root
        )

        XCTAssertEqual(
            Set(urls.map(\.lastPathComponent)),
            Set(CalibrationArtifactKind.allCases.map(\.filename))
        )
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testNaturalMeasurementThenPersonalRhythmValidationBuildsProfile() async throws {
        let sampler = ManualCalibrationSampler()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            timing: .init(
                cueCount: 10,
                cueInterval: .milliseconds(5)
            ),
            sampler: sampler,
            gateCalibrator: StubGateCalibrator()
        )

        store.startMeasurement()
        emitNaturalChews(sampler: sampler)
        await store.finishNaturalMeasurement()

        XCTAssertEqual(store.calibrationAmplitudes.count, 10)
        let naturalChewInterval = try XCTUnwrap(store.naturalChewInterval)
        XCTAssertEqual(naturalChewInterval, 0.75, accuracy: 0.000_001)
        XCTAssertNotNil(store.candidateMinPeakAmplitude)
        XCTAssertEqual(store.candidateGateThresholds, .standard)
        XCTAssertTrue(store.measurementCompleted)

        store.moveForward()
        XCTAssertEqual(store.stage, .adjustment)

        store.startMeasurement()
        await waitUntil { store.cuePulseID >= 1 }
        for index in 0..<10 {
            sampler.emit(timestamp: 10 + Double(index) * 0.75, amplitude: 0.03)
        }
        await waitUntil { store.stage == .ready }

        XCTAssertEqual(store.profile?.validationDetectedCount, 10)
        let profileNaturalChewInterval = try XCTUnwrap(store.profile?.naturalChewInterval)
        XCTAssertEqual(profileNaturalChewInterval, 0.75, accuracy: 0.000_001)
    }

    func testValidationPresentsExactlyTenGuides() async {
        let sampler = ManualCalibrationSampler()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            timing: .init(
                cueCount: 10,
                cueInterval: .milliseconds(2)
            ),
            sampler: sampler,
            gateCalibrator: StubGateCalibrator()
        )
        store.startMeasurement()
        emitNaturalChews(sampler: sampler)
        await store.finishNaturalMeasurement()
        store.moveForward()

        store.startMeasurement()
        await waitUntil { !store.isMeasuring }

        XCTAssertEqual(store.cuePulseID, 10)
        XCTAssertEqual(store.cueHitID, 10)
    }

    func testValidationRetryKeepsPersonalThresholdAndOnlyRepeatsValidation() async throws {
        let sampler = ManualCalibrationSampler()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            timing: .init(cueCount: 10, cueInterval: .milliseconds(2)),
            sampler: sampler,
            gateCalibrator: StubGateCalibrator()
        )
        store.startMeasurement()
        emitNaturalChews(sampler: sampler)
        await store.finishNaturalMeasurement()
        let threshold = try XCTUnwrap(store.candidateMinPeakAmplitude)
        store.moveForward()

        store.startMeasurement()
        await waitUntil { store.stage == .signalIssue }

        XCTAssertEqual(store.issue, .adjustmentNeeded)
        XCTAssertEqual(store.candidateMinPeakAmplitude, threshold)
        XCTAssertEqual(store.calibrationAmplitudes.count, 10)

        await store.retryAdjustment()
        XCTAssertEqual(store.stage, .adjustment)
        await waitUntil { store.cuePulseID >= 1 }
        for index in 0..<10 {
            sampler.emit(timestamp: 10 + Double(index) * 0.75, amplitude: 0.03)
        }
        await waitUntil { store.stage == .ready }

        XCTAssertEqual(store.profile?.validationDetectedCount, 10)
        XCTAssertEqual(store.profile?.minPeakAmplitude, threshold)
        XCTAssertEqual(store.profile?.gateThresholds, .standard)
    }

    func testUnderDetectedValidationAppliesOneAutomaticGateAdjustment() async throws {
        let sampler = ManualCalibrationSampler()
        let adjustedThresholds = ChewingGateThresholds(
            minimumRotationYStd: 0.030,
            minimumRotationYDominance: 0.032,
            minimumRotationYJitterBandDominance: 0.040
        )
        let adjustmentSearcher = StubGateAdjustmentSearcher(
            result: GateAdjustmentResult(
                initialThresholds: .standard,
                adjustedThresholds: adjustedThresholds,
                adjustedEvents: (0..<10).map { index in
                    event(count: index + 1, timestamp: Double(index) * 0.75, amplitude: 0.02)
                },
                replayCount: 3
            )
        )
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            timing: .init(cueCount: 10, cueInterval: .milliseconds(2)),
            sampler: sampler,
            gateCalibrator: StubGateCalibrator(),
            gateAdjustmentSearcher: adjustmentSearcher
        )
        store.startMeasurement()
        emitNaturalChews(sampler: sampler)
        await store.finishNaturalMeasurement()
        store.moveForward()

        store.startMeasurement()
        await waitUntil { store.stage == .ready }

        XCTAssertEqual(adjustmentSearcher.callCount, 1)
        XCTAssertTrue(store.gateAdjustmentApplied)
        XCTAssertEqual(store.detectedCountBeforeAdjustment, 0)
        XCTAssertEqual(store.adjustmentDetectedCount, 10)
        XCTAssertEqual(store.profile?.gateThresholds, adjustedThresholds)
    }

    func testGateCalibrationSeparatesStationaryNoiseFromChewing() throws {
        let baseline = Array(repeating: ChewingGateFeatures(
            rotationYStd: 0.012,
            rotationYDominance: 0.10,
            rotationYJitterBandDominance: 0.11,
            accelToRotation: 0.01
        ), count: 30)
        let chewing = Array(repeating: ChewingGateFeatures(
            rotationYStd: 0.044,
            rotationYDominance: 0.38,
            rotationYJitterBandDominance: 0.34,
            accelToRotation: 0.01
        ), count: 30)

        let thresholds = try XCTUnwrap(PersonalizedChewingGateCalibration.thresholds(
            baseline: baseline,
            chewing: chewing
        ))

        XCTAssertEqual(thresholds.minimumRotationYStd, 0.030, accuracy: 0.000_001)
        XCTAssertEqual(thresholds.minimumRotationYDominance, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(thresholds.minimumRotationYJitterBandDominance, 0.15, accuracy: 0.000_001)
    }

    func testGateCalibrationPersonalizesWeakRotationYDominance() throws {
        let baseline = Array(repeating: ChewingGateFeatures(
            rotationYStd: 0.010,
            rotationYDominance: 0.01,
            rotationYJitterBandDominance: 0.01,
            accelToRotation: 0.01
        ), count: 30)
        let chewing = Array(repeating: ChewingGateFeatures(
            rotationYStd: 0.040,
            rotationYDominance: 0.04,
            rotationYJitterBandDominance: 0.05,
            accelToRotation: 0.01
        ), count: 30)

        let thresholds = try XCTUnwrap(PersonalizedChewingGateCalibration.thresholds(
            baseline: baseline,
            chewing: chewing
        ))

        XCTAssertEqual(thresholds.minimumRotationYDominance, 0.032, accuracy: 0.000_001)
        XCTAssertEqual(thresholds.minimumRotationYJitterBandDominance, 0.040, accuracy: 0.000_001)
    }

    func testGateCalibrationKeepsStandardGateForOverlappingSignals() {
        let feature = ChewingGateFeatures(
            rotationYStd: 0.02,
            rotationYDominance: 0.2,
            rotationYJitterBandDominance: 0.2,
            accelToRotation: 0.01
        )

        XCTAssertEqual(PersonalizedChewingGateCalibration.thresholds(
            baseline: Array(repeating: feature, count: 30),
            chewing: Array(repeating: feature, count: 30)
        ), .standard)
    }

    func testGateCalibrationKeepsStandardRotationYStd() throws {
        let baseline = Array(repeating: ChewingGateFeatures(
            rotationYStd: 0.040,
            rotationYDominance: 0.30,
            rotationYJitterBandDominance: 0.30,
            accelToRotation: 0.01
        ), count: 30)
        let chewing = Array(repeating: ChewingGateFeatures(
            rotationYStd: 0.080,
            rotationYDominance: 0.30,
            rotationYJitterBandDominance: 0.30,
            accelToRotation: 0.01
        ), count: 30)

        let thresholds = try XCTUnwrap(PersonalizedChewingGateCalibration.thresholds(
            baseline: baseline,
            chewing: chewing
        ))

        XCTAssertEqual(thresholds.minimumRotationYStd, 0.030, accuracy: 0.000_001)
        XCTAssertEqual(thresholds.minimumRotationYDominance, 0.15)
        XCTAssertEqual(thresholds.minimumRotationYJitterBandDominance, 0.15)
    }

    func testRetryWaitsForPreviousSamplerToStop() async {
        let sampler = SuspendingStopCalibrationSampler()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            sampler: sampler
        )
        store.startMeasurement()

        let retryTask = Task { await store.retryMeasurement() }
        await waitUntil { sampler.isStopPending }

        XCTAssertEqual(sampler.startCount, 1)
        sampler.finishStop()
        await retryTask.value

        XCTAssertEqual(sampler.startCount, 2)
        XCTAssertTrue(store.isMeasuring)
    }

    func testRestartAfterLeavingWaitsForPreviousSamplerToStop() async {
        let sampler = SuspendingStopCalibrationSampler()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            sampler: sampler
        )
        store.startMeasurement()

        store.cancelMeasurement()
        await waitUntil { sampler.isStopPending }
        store.startMeasurement()

        XCTAssertEqual(sampler.startCount, 1)
        XCTAssertFalse(store.isMeasuring)

        sampler.finishStop()
        await waitUntil { sampler.startCount == 2 }

        XCTAssertTrue(store.isMeasuring)
        XCTAssertEqual(store.stage, .calibration)
    }

    func testLeavingAdjustmentDoesNotReportFailureAfterGuidesFinish() async {
        let sampler = ManualCalibrationSampler()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            timing: .init(cueCount: 10, cueInterval: .milliseconds(2)),
            sampler: sampler,
            gateCalibrator: StubGateCalibrator()
        )
        store.startMeasurement()
        emitNaturalChews(sampler: sampler)
        await store.finishNaturalMeasurement()
        store.moveForward()
        store.startMeasurement()
        await waitUntil { store.cuePulseID > 0 }

        store.cancelMeasurement()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.stage, .adjustment)
        XCTAssertNil(store.issue)
        XCTAssertFalse(store.isMeasuring)
    }

    private func makeStore(isAirPodsConnected: Bool) -> MeasurementOnboardingStore {
        MeasurementOnboardingStore(
            isAirPodsConnected: isAirPodsConnected,
            sampler: ManualCalibrationSampler()
        )
    }

    private func emitNaturalChews(sampler: ManualCalibrationSampler) {
        for index in 0..<10 {
            sampler.emit(
                timestamp: Double(index) * 0.75,
                amplitude: 0.028 + Double(index) * 0.001
            )
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

    private func event(count: Int, timestamp: Double, amplitude: Double) -> ChewDetectionEvent {
        ChewDetectionEvent(count: count, timestamp: timestamp, amplitude: amplitude)
    }
}

@MainActor
private final class ManualCalibrationSampler: MeasurementCalibrationSampling {
    var isDeviceMotionAvailable = true
    private var onEvent: (@MainActor (ChewDetectionEvent) -> Void)?
    private var eventCount = 0
    private var activeMode: MeasurementCalibrationSamplingMode?

    func start(
        mode: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError _: @escaping @MainActor (String) -> Void
    ) {
        self.onEvent = onEvent
        activeMode = mode
        eventCount = 0
    }

    func emit(timestamp: Double, amplitude: Double) {
        eventCount += 1
        onEvent?(ChewDetectionEvent(
            count: eventCount,
            timestamp: timestamp,
            amplitude: amplitude
        ))
    }

    func stop() async -> MeasurementCalibrationCapture? {
        onEvent = nil
        defer { activeMode = nil }
        guard activeMode == .captureBaseline || isValidationMode(activeMode) else { return nil }
        let date = Date()
        return MeasurementCalibrationCapture(
            startedAt: date,
            endedAt: date,
            samples: [testMotionSample()]
        )
    }

    private func isValidationMode(_ mode: MeasurementCalibrationSamplingMode?) -> Bool {
        if case .some(.adjust) = mode { return true }
        return false
    }
}

private func testMotionSample() -> HeadphoneMotionSample {
    HeadphoneMotionSample(
        timestamp: 0,
        rotationRateMagnitude: 0,
        userAccelerationMagnitude: 0,
        attitudeRoll: 0,
        attitudePitch: 0,
        attitudeYaw: 0,
        rotationX: 0,
        rotationY: 0,
        rotationZ: 0,
        gravityX: 0,
        gravityY: 0,
        gravityZ: -1,
        userAccelX: 0,
        userAccelY: 0,
        userAccelZ: 0,
        magneticFieldX: 0,
        magneticFieldY: 0,
        magneticFieldZ: 0,
        sensorLocation: "headphone_right"
    )
}

private struct StubGateCalibrator: ChewingGateCalibrating {
    func thresholds(
        baseline _: MeasurementCalibrationCapture?,
        measurement _: MeasurementCalibrationCapture?,
        representativePeaks _: [ChewPeak]
    ) -> ChewingGateThresholds? {
        .standard
    }
}

@MainActor
private final class StubGateAdjustmentSearcher: GateAdjustmentSearching {
    private let result: GateAdjustmentResult?
    private(set) var callCount = 0

    init(result: GateAdjustmentResult?) {
        self.result = result
    }

    func adjustment(
        for _: MeasurementCalibrationCapture,
        minPeakAmplitude _: Double,
        initialThresholds _: ChewingGateThresholds,
        initialCount _: Int
    ) async -> GateAdjustmentResult? {
        callCount += 1
        return result
    }
}

@MainActor
private final class SuspendingStopCalibrationSampler: MeasurementCalibrationSampling {
    var isDeviceMotionAvailable = true
    private(set) var startCount = 0
    private(set) var isStopPending = false
    private var stopContinuation: CheckedContinuation<Void, Never>?
    func start(
        mode _: MeasurementCalibrationSamplingMode,
        onEvent _: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError _: @escaping @MainActor (String) -> Void
    ) {
        startCount += 1
    }

    func stop() async -> MeasurementCalibrationCapture? {
        isStopPending = true
        await withCheckedContinuation { continuation in
            stopContinuation = continuation
        }
        isStopPending = false
        return nil
    }

    func finishStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

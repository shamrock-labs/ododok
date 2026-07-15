import XCTest
@testable import ChewChewIOS

@MainActor
final class MeasurementOnboardingStateLifecycleTests: XCTestCase {
    func testRapidDoubleRetryStartsOnlyOneNewMeasurement() async {
        let sampler = LifecycleSuspendingStopSampler()
        let store = makeStore(sampler: sampler)
        store.startMeasurement()

        let firstRetry = Task { await store.retryMeasurement() }
        await waitUntil { sampler.isStopPending }
        let secondRetry = Task { await store.retryMeasurement() }
        sampler.finishStop()
        await firstRetry.value
        await secondRetry.value

        XCTAssertEqual(sampler.startCount, 2)
        XCTAssertTrue(store.isMeasuring)
        XCTAssertFalse(store.isRestartingMeasurement)
    }

    func testClosingWhileRetryWaitsDoesNotStartAnotherMeasurement() async {
        let sampler = LifecycleSuspendingStopSampler()
        let store = makeStore(sampler: sampler)
        store.startMeasurement()

        let retryTask = Task { await store.retryMeasurement() }
        await waitUntil { sampler.isStopPending }
        store.cancelMeasurement()
        sampler.finishStop()
        await retryTask.value

        XCTAssertEqual(sampler.startCount, 1)
        XCTAssertFalse(store.isMeasuring)
        XCTAssertFalse(store.isRestartingMeasurement)
    }

    func testCancellingWhileNaturalMeasurementStopsIgnoresLateCompletion() async {
        let sampler = LifecycleSuspendingStopSampler(capture: makeCapture())
        let store = makeStore(sampler: sampler, gateCalibrator: LifecycleGateCalibrator())
        store.startMeasurement()
        emitNaturalChews(to: sampler)

        let finishTask = Task { await store.finishNaturalMeasurement() }
        await waitUntil { sampler.isStopPending }
        store.cancelMeasurement()
        sampler.finishStop()
        await finishTask.value

        XCTAssertEqual(store.stage, .calibration)
        XCTAssertFalse(store.isMeasuring)
        XCTAssertFalse(store.isFinishingMeasurement)
        XCTAssertFalse(store.measurementCompleted)
        XCTAssertNil(store.profile)
        XCTAssertNil(store.issue)
    }

    func testPreviousRunSensorErrorCannotFailRestartedMeasurement() async {
        let sampler = LifecycleRetainingCallbacksSampler()
        let store = makeStore(sampler: sampler)
        store.startMeasurement()
        store.cancelMeasurement()
        await waitUntil { sampler.stopCount == 1 }

        store.startMeasurement()
        await waitUntil { sampler.startCount == 2 }
        sampler.fail(run: 0, message: "old run error")

        XCTAssertEqual(store.stage, .calibration)
        XCTAssertTrue(store.isMeasuring)
        XCTAssertNil(store.issue)
    }

    func testPreviousRunEventCannotCompleteRestartedMeasurement() async {
        let sampler = LifecycleRetainingCallbacksSampler()
        let store = makeStore(sampler: sampler, gateCalibrator: LifecycleGateCalibrator())
        store.startMeasurement()
        store.cancelMeasurement()
        await waitUntil { sampler.stopCount == 1 }
        store.startMeasurement()
        await waitUntil { sampler.startCount == 2 }

        for index in 0..<6 {
            sampler.emit(run: 1, timestamp: Double(index) * 0.75, amplitude: 0.03)
        }
        sampler.emit(run: 0, timestamp: 4.5, amplitude: 0.03)
        await store.finishNaturalMeasurement()

        XCTAssertEqual(store.stage, .signalIssue)
        XCTAssertEqual(store.issue, .insufficientCalibration)
        XCTAssertFalse(store.measurementCompleted)
    }

    func testCancellingDuringGateAdjustmentSearchCannotFinishOnboarding() async {
        let sampler = LifecycleImmediateSampler()
        let searcher = LifecycleGateAdjustmentSearcher()
        let store = MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            timing: .init(cueCount: 1, cueInterval: .milliseconds(1)),
            sampler: sampler,
            gateCalibrator: LifecycleGateCalibrator(),
            gateAdjustmentSearcher: searcher
        )
        store.startMeasurement()
        emitNaturalChews(to: sampler)
        await store.finishNaturalMeasurement()
        store.moveForward()
        store.startMeasurement()
        await waitUntil { searcher.isPending }

        store.cancelMeasurement()
        searcher.finish(with: GateAdjustmentResult(
            initialThresholds: .standard,
            adjustedThresholds: .standard,
            adjustedEvents: makeEvents(count: 9),
            replayCount: 1
        ))
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(store.stage, .adjustment)
        XCTAssertFalse(store.isMeasuring)
        XCTAssertNil(store.profile)
        XCTAssertNil(store.issue)
    }

    private func makeStore(
        sampler: any MeasurementCalibrationSampling,
        gateCalibrator: any ChewingGateCalibrating = LifecycleGateCalibrator()
    ) -> MeasurementOnboardingStore {
        MeasurementOnboardingStore(
            stage: .calibration,
            isAirPodsConnected: true,
            sampler: sampler,
            gateCalibrator: gateCalibrator
        )
    }

    private func emitNaturalChews(to sampler: some LifecycleEventEmitting) {
        for index in 0..<10 {
            sampler.emit(timestamp: Double(index) * 0.75, amplitude: 0.028 + Double(index) * 0.001)
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

    private func makeEvents(count: Int) -> [ChewDetectionEvent] {
        (0..<count).map { index in
            ChewDetectionEvent(count: index + 1, timestamp: Double(index), amplitude: 0.03)
        }
    }
}

@MainActor
private protocol LifecycleEventEmitting {
    func emit(timestamp: Double, amplitude: Double)
}

@MainActor
private final class LifecycleImmediateSampler: MeasurementCalibrationSampling, LifecycleEventEmitting {
    var isDeviceMotionAvailable = true
    private var onEvent: (@MainActor (ChewDetectionEvent) -> Void)?

    func start(
        mode _: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError _: @escaping @MainActor (String) -> Void
    ) {
        self.onEvent = onEvent
    }

    func emit(timestamp: Double, amplitude: Double) {
        onEvent?(ChewDetectionEvent(count: 1, timestamp: timestamp, amplitude: amplitude))
    }

    func stop() async -> MeasurementCalibrationCapture? { makeCapture() }
}

@MainActor
private final class LifecycleSuspendingStopSampler: MeasurementCalibrationSampling, LifecycleEventEmitting {
    var isDeviceMotionAvailable = true
    private(set) var startCount = 0
    private(set) var isStopPending = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var onEvent: (@MainActor (ChewDetectionEvent) -> Void)?
    private let capture: MeasurementCalibrationCapture?

    init(capture: MeasurementCalibrationCapture? = nil) {
        self.capture = capture
    }

    func start(
        mode _: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError _: @escaping @MainActor (String) -> Void
    ) {
        startCount += 1
        self.onEvent = onEvent
    }

    func emit(timestamp: Double, amplitude: Double) {
        onEvent?(ChewDetectionEvent(count: 1, timestamp: timestamp, amplitude: amplitude))
    }

    func stop() async -> MeasurementCalibrationCapture? {
        isStopPending = true
        await withCheckedContinuation { continuation = $0 }
        isStopPending = false
        return capture
    }

    func finishStop() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class LifecycleRetainingCallbacksSampler: MeasurementCalibrationSampling {
    var isDeviceMotionAvailable = true
    private(set) var stopCount = 0
    private var eventHandlers: [(@MainActor (ChewDetectionEvent) -> Void)] = []
    private var errorHandlers: [(@MainActor (String) -> Void)] = []

    var startCount: Int { eventHandlers.count }

    func start(
        mode _: MeasurementCalibrationSamplingMode,
        onEvent: @escaping @MainActor (ChewDetectionEvent) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        eventHandlers.append(onEvent)
        errorHandlers.append(onError)
    }

    func stop() async -> MeasurementCalibrationCapture? {
        stopCount += 1
        return makeCapture()
    }

    func emit(run: Int, timestamp: Double, amplitude: Double) {
        eventHandlers[run](ChewDetectionEvent(count: 1, timestamp: timestamp, amplitude: amplitude))
    }

    func fail(run: Int, message: String) {
        errorHandlers[run](message)
    }
}

private struct LifecycleGateCalibrator: ChewingGateCalibrating {
    func thresholds(
        baseline _: MeasurementCalibrationCapture?,
        measurement _: MeasurementCalibrationCapture?,
        representativePeaks _: [ChewPeak]
    ) -> ChewingGateThresholds? { .standard }
}

@MainActor
private final class LifecycleGateAdjustmentSearcher: GateAdjustmentSearching {
    private(set) var isPending = false
    private var continuation: CheckedContinuation<GateAdjustmentResult?, Never>?

    func adjustment(
        for _: MeasurementCalibrationCapture,
        minPeakAmplitude _: Double,
        initialThresholds _: ChewingGateThresholds,
        initialCount _: Int
    ) async -> GateAdjustmentResult? {
        isPending = true
        let result = await withCheckedContinuation { continuation = $0 }
        isPending = false
        return result
    }

    func finish(with result: GateAdjustmentResult?) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private func makeCapture() -> MeasurementCalibrationCapture {
    let date = Date()
    return MeasurementCalibrationCapture(
        startedAt: date,
        endedAt: date,
        samples: [makeMotionSample()]
    )
}

private func makeMotionSample() -> HeadphoneMotionSample {
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

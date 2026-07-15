import XCTest
@testable import ChewChewIOS

final class ChewDetectionEngineTests: XCTestCase {
    func testCalibrationProbeFindsWeakPeakWithoutActivityGate() async {
        let probe = ChewPeakAmplitudeProbe()
        var events: [ChewDetectionEvent] = []

        for index in 0..<100 {
            let timestamp = Double(index) / 50
            let rotationY = 0.005 * sin(2 * Double.pi * timestamp)
            let event = await probe.feed(ChewDetectionSample(
                timestamp: timestamp,
                rotX: 0,
                rotY: rotationY,
                rotZ: 0,
                accelX: 0,
                accelY: 0,
                accelZ: 0
            ))
            if let event {
                events.append(event)
            }
        }

        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { $0.amplitude < 0.006 })
    }

    func testFeedReturnsDetectionEventWhenPeakIsCounted() async {
        let engine = ChewDetectionEngine()
        var events: [ChewDetectionEvent] = []

        for index in 0..<500 {
            let sample = makeSample(index: index, rotationY: chewingRotationY(index: index))
            if let event = await engine.feed(sample) {
                events.append(event)
            }
        }

        let snapshot = await engine.snapshot()

        XCTAssertFalse(events.isEmpty)
        XCTAssertLessThanOrEqual(events.count, snapshot.chewCount)
        XCTAssertEqual(events.map(\.count), Array(1...events.count))
        XCTAssertEqual(events.map(\.timestamp), Array(snapshot.chewTimestamps.prefix(events.count)))
        XCTAssertEqual(events.map(\.amplitude), Array(snapshot.chewAmplitudes.prefix(events.count)))
    }

    func testFeedDoesNotReturnDetectionEventForFlatMotion() async {
        let engine = ChewDetectionEngine()
        var events: [ChewDetectionEvent] = []

        for index in 0..<500 {
            if let event = await engine.feed(makeSample(index: index, rotationY: 0)) {
                events.append(event)
            }
        }

        let snapshot = await engine.snapshot()

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(snapshot.chewCount, 0)
        XCTAssertTrue(snapshot.chewTimestamps.isEmpty)
        XCTAssertTrue(snapshot.chewAmplitudes.isEmpty)
    }

    func testConfiguredPeakAmplitudeSuppressesPeaksBelowPersonalThreshold() async {
        let engine = ChewDetectionEngine(
            configuration: ChewDetectionConfiguration(minPeakAmplitude: 1)
        )

        await feedChewingSamples(to: engine)
        _ = await engine.finishSession()

        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot.chewCount, 0)
    }

    func testValidationConfigurationCountsPeaksWithoutOpeningActivityGate() async {
        let standardEngine = ChewDetectionEngine(
            configuration: ChewDetectionConfiguration(minPeakAmplitude: 0.001)
        )
        let validationEngine = ChewDetectionEngine(
            configuration: ChewDetectionConfiguration(
                minPeakAmplitude: 0.001,
                requiresOpenActivityGate: false
            )
        )

        for index in 0..<500 {
            let elapsed = Double(index) / 50.0
            let weakChewSignal = 0.01 * sin(2 * Double.pi * 1.4 * elapsed)
            let sample = makeSample(index: index, rotationY: weakChewSignal)
            await standardEngine.feed(sample)
            await validationEngine.feed(sample)
        }
        await standardEngine.finishSession()
        await validationEngine.finishSession()

        let standardSnapshot = await standardEngine.snapshot()
        let validationSnapshot = await validationEngine.snapshot()
        let validationGateOpen = await validationEngine.isChewingGateOpen

        XCTAssertEqual(standardSnapshot.chewCount, 0)
        XCTAssertFalse(validationGateOpen)
        XCTAssertGreaterThan(validationSnapshot.chewCount, 0)
    }

    func testStrongChewRotationIsNotDiscardedAsHeadingMotion() async {
        let engine = ChewDetectionEngine()

        for index in 0..<500 {
            let elapsed = Double(index) / 50.0
            let strongChewSignal = 0.16 * sin(2 * Double.pi * 1.4 * elapsed)
            await engine.feed(makeSample(index: index, rotationY: strongChewSignal))
        }
        await engine.finishSession()

        let snapshot = await engine.snapshot()
        XCTAssertGreaterThan(snapshot.chewCount, 0)
    }

    func testRepresentativePeakWindowKeepsStrongestPeak() {
        var selector = RepresentativePeakWindow(windowDuration: 0.30)

        XCTAssertNil(selector.collect(ChewPeak(timestamp: 1.00, amplitude: 0.010)))
        XCTAssertNil(selector.collect(ChewPeak(timestamp: 1.10, amplitude: 0.025)))
        XCTAssertNil(selector.collect(ChewPeak(timestamp: 1.20, amplitude: 0.015)))

        XCTAssertEqual(
            selector.flushIfExpired(at: 1.30),
            ChewPeak(timestamp: 1.10, amplitude: 0.025)
        )
    }

    func testRepresentativePeakWindowStartsNextWindow() {
        var selector = RepresentativePeakWindow(windowDuration: 0.30)

        XCTAssertNil(selector.collect(ChewPeak(timestamp: 1.00, amplitude: 0.010)))
        XCTAssertEqual(
            selector.collect(ChewPeak(timestamp: 1.31, amplitude: 0.020)),
            ChewPeak(timestamp: 1.00, amplitude: 0.010)
        )
        XCTAssertEqual(
            selector.flush(),
            ChewPeak(timestamp: 1.31, amplitude: 0.020)
        )
    }

    func testSnapshotDoesNotFinalizePendingPeak() async {
        let engine = ChewDetectionEngine()
        await feedChewingSamples(to: engine)

        let firstSnapshot = await engine.snapshot()
        let secondSnapshot = await engine.snapshot()

        XCTAssertEqual(firstSnapshot, secondSnapshot)
    }

    func testFinishSessionFinalizesPendingPeakOnlyOnce() async {
        let engine = ChewDetectionEngine()
        await feedChewingSamples(to: engine, sampleCount: 480)
        let beforeFinish = await engine.snapshot()

        let finalEvent = await engine.finishSession()
        let afterFirstFinish = await engine.snapshot()
        let duplicateEvent = await engine.finishSession()
        let afterSecondFinish = await engine.snapshot()

        XCTAssertNotNil(finalEvent)
        XCTAssertEqual(afterFirstFinish.chewCount, beforeFinish.chewCount + 1)
        XCTAssertNil(duplicateEvent)
        XCTAssertEqual(afterSecondFinish, afterFirstFinish)
    }

    func testFinishedSessionRejectsAdditionalSamples() async {
        let engine = ChewDetectionEngine()
        await feedChewingSamples(to: engine)
        await engine.finishSession()
        let finishedSnapshot = await engine.snapshot()

        let event = await engine.feed(makeSample(index: 500, rotationY: 0.08))

        let snapshotAfterRejectedSample = await engine.snapshot()

        XCTAssertNil(event)
        XCTAssertEqual(snapshotAfterRejectedSample, finishedSnapshot)
    }

    private func feedChewingSamples(
        to engine: ChewDetectionEngine,
        sampleCount: Int = 500
    ) async {
        for index in 0..<sampleCount {
            let sample = makeSample(index: index, rotationY: chewingRotationY(index: index))
            await engine.feed(sample)
        }
    }

    private func makeSample(index: Int, rotationY: Double) -> ChewDetectionSample {
        ChewDetectionSample(
            timestamp: Double(index) / 50.0,
            rotX: 0,
            rotY: rotationY,
            rotZ: 0,
            accelX: 0,
            accelY: 0,
            accelZ: 0
        )
    }

    private func chewingRotationY(index: Int) -> Double {
        let elapsed = Double(index) / 50.0
        return 0.08 * sin(2 * Double.pi * 1.4 * elapsed)
    }
}

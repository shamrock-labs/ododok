import XCTest
@testable import ChewChewIOS

@MainActor
final class CalibrationSignalAnalysisTests: XCTestCase {
    func testWeakRotationYDominanceIsLoweredAndReplayedOnce() async throws {
        let capture = makeWeakDominanceCapture()
        let result = await CaptureBasedValidationGateAutoAdjuster().adjustment(
            for: capture,
            minPeakAmplitude: 0.001,
            initialThresholds: .standard
        )
        let adjustment = try XCTUnwrap(result)

        XCTAssertLessThan(adjustment.adjustedThresholds.minimumRotationYDominance, 0.15)
        XCTAssertLessThan(
            adjustment.adjustedThresholds.minimumRotationYJitterBandDominance,
            0.15
        )
        XCTAssertTrue(PeakAmplitudeCalibration.validationPassed(
            detectedCount: adjustment.adjustedEvents.count
        ))
    }

    func testAdjustedValidationArtifactsKeepBeforeAndAfterResults() throws {
        let initialEvents = [event(count: 1, timestamp: 0.5)]
        let adjustedThresholds = ChewingGateThresholds(
            minimumRotationYStd: 0.030,
            minimumRotationYDominance: 0.032,
            minimumRotationYJitterBandDominance: 0.040
        )
        let adjustedEvents = (0..<10).map { index in
            event(count: index + 1, timestamp: Double(index) * 0.75)
        }
        var validationRun = MeasurementValidationRun(initialEvents: initialEvents)
        validationRun.begin(with: .standard)
        validationRun.record(ValidationGateAdjustment(
            initialThresholds: .standard,
            adjustedThresholds: adjustedThresholds,
            adjustedEvents: adjustedEvents
        ))

        let bundle = MeasurementCalibrationArtifactFactory.makeBundle(input: .init(
            calibrationId: UUID(),
            measurementCapture: nil,
            validationCapture: nil,
            calibrationEvents: [],
            validationRun: validationRun,
            threshold: 0.006,
            gateThresholds: adjustedThresholds,
            naturalChewInterval: 0.75,
            representativeAmplitudes: [],
            guidedExpectedCount: 10,
            outcome: .passedAfterAdjustment
        ))

        let summaryData = try XCTUnwrap(bundle.artifacts.first { $0.kind == .summary }?.data)
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: summaryData) as? [String: Any]
        )
        XCTAssertEqual(summary["outcome"] as? String, "passedAfterAdjustment")
        XCTAssertEqual(summary["validationDetectedCountBeforeAdjustment"] as? Int, 1)
        XCTAssertEqual(summary["validationDetectedCountAfterAdjustment"] as? Int, 10)
        XCTAssertEqual(summary["validationAdjustmentApplied"] as? Bool, true)

        let eventsData = try XCTUnwrap(bundle.artifacts.first { $0.kind == .events }?.data)
        let eventsCSV = try XCTUnwrap(String(data: eventsData, encoding: .utf8))
        XCTAssertTrue(eventsCSV.contains("validation_initial"))
        XCTAssertTrue(eventsCSV.contains("validation_adjusted"))
    }

    private func makeWeakDominanceCapture() -> MeasurementCalibrationCapture {
        let startedAt = Date()
        let samples = (0..<350).map { index in
            let elapsed = Double(index) / 50
            let chew = sin(2 * Double.pi * 1.4 * elapsed)
            return HeadphoneMotionSample(
                timestamp: elapsed,
                rotationRateMagnitude: abs(chew),
                userAccelerationMagnitude: 0,
                attitudeRoll: 0,
                attitudePitch: 0,
                attitudeYaw: 0,
                rotationX: 0.26 * chew,
                rotationY: 0.08 * chew,
                rotationZ: 0.26 * chew,
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
        return MeasurementCalibrationCapture(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(7),
            samples: samples
        )
    }

    private func event(count: Int, timestamp: TimeInterval) -> ChewDetectionEvent {
        ChewDetectionEvent(count: count, timestamp: timestamp, amplitude: 0.02)
    }
}

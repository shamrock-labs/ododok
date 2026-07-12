import XCTest
@testable import ChewChewIOS

final class ChewCounterTests: XCTestCase {
    func testDefaultSensitivityKeepsCurrentDeviceTuning() {
        XCTAssertEqual(ChewSensitivity.defaults.minPeakGap, 16)
        XCTAssertEqual(ChewSensitivity.defaults.exitSampleCount, 10)
    }

    func testSensitivityCanBeUpdatedWhileCounterIsRunning() async {
        let counter = ChewCounter()
        var sensitivity = ChewSensitivity.defaults
        sensitivity.minPeakAmplitude = 0.012
        sensitivity.bypassChewingGate = true

        await counter.setSensitivity(sensitivity)

        let current = await counter.currentSensitivity
        XCTAssertEqual(current, sensitivity)
    }

    func testDiagnosticsTrackSamplesAndHeadingBlocks() async {
        let counter = ChewCounter()

        _ = await counter.feed(
            rotX: 1,
            rotY: 0,
            rotZ: 0,
            accelX: 0,
            accelY: 0,
            accelZ: 0
        )

        let diagnostics = await counter.diagnostics()
        XCTAssertEqual(diagnostics.sampleCount, 1)
        XCTAssertEqual(diagnostics.headingBlockedCount, 1)
        XCTAssertEqual(diagnostics.chewCount, 0)
        XCTAssertEqual(diagnostics.lastRotMag, 1, accuracy: 0.000_001)
    }

}

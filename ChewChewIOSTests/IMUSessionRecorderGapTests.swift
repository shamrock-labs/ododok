import XCTest
@testable import ChewChewIOS

/// 통화 등 인터럽트로 측정이 멈췄다 이어질 때, 그 구간이 IMU 세션의 갭으로
/// 기록되는지 검증한다. 통화 감지·갭 시작 기록은 `CallInterruptionMonitor`(CXCallObserver) →
/// `AppState.interruptionBeganAt` 경로가 담당한다. 백그라운드 오디오 keep-alive(변경 2)는
/// 잠금 중 IMU 콜백 유지 + 씹기 페이스 톤 역할만 맡고, 갭 기록에는 관여하지 않는다.
final class IMUSessionRecorderGapTests: XCTestCase {

    func testRecordInterruptionGap_appearsInOutput() {
        let recorder = IMUSessionRecorder(startedAt: Date())
        let began = Date(timeIntervalSinceNow: -10)
        let ended = Date(timeIntervalSinceNow: -5)

        recorder.recordInterruptionGap(began: began, ended: ended)

        let output = recorder.finalize(endedAt: Date())
        XCTAssertEqual(output.interruptionGaps.count, 1, "갭 1건이 Output에 포함되어야 한다")
        XCTAssertEqual(output.interruptionGaps[0].began, began)
        XCTAssertEqual(output.interruptionGaps[0].ended, ended)
    }

    func testNoGap_outputHasEmptyGaps() {
        let recorder = IMUSessionRecorder(startedAt: Date())
        let output = recorder.finalize(endedAt: Date())
        XCTAssertTrue(output.interruptionGaps.isEmpty, "갭 없이 finalize 시 interruptionGaps는 빈 배열이어야 한다")
    }
}

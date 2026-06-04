import XCTest
@testable import ChewChewIOS

/// 전화/재난문자 인터럽트 후 "자동 재개 vs 사용자 선택" 분기 로직 검증.
/// 전화는 중단 알림에서 직접 이어가므로 자동 재개하지 않고, 그 외(재난문자 등)는 자동 재개한다.
final class CallInterruptionResumeTests: XCTestCase {

    @MainActor
    func testShouldAutoResume_nonCallInterruptionResumes() {
        // 재난문자 등 통화가 아닌 인터럽트 + shouldResume → 자동 재개
        XCTAssertTrue(AppState.shouldAutoResume(interruptionWasCall: false, shouldResume: true))
    }

    @MainActor
    func testShouldAutoResume_callInterruptionDoesNotAutoResume() {
        // 전화 + shouldResume → 자동 재개하지 않고 알림 "계속하기"를 기다린다
        XCTAssertFalse(AppState.shouldAutoResume(interruptionWasCall: true, shouldResume: true))
    }

    @MainActor
    func testShouldAutoResume_withoutShouldResumeNeverResumes() {
        // shouldResume이 없으면 통화 여부와 무관하게 재개 안 함
        XCTAssertFalse(AppState.shouldAutoResume(interruptionWasCall: false, shouldResume: false))
        XCTAssertFalse(AppState.shouldAutoResume(interruptionWasCall: true, shouldResume: false))
    }

    func testCallMonitor_startStop_doesNotCrash() {
        let monitor = CallInterruptionMonitor()
        monitor.onCallStarted = {}
        monitor.start()
        monitor.stop()
    }
}

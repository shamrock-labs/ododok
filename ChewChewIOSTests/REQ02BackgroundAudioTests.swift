import AVFoundation
import XCTest
@testable import ChewChewIOS

final class REQ02BackgroundAudioTests: XCTestCase {

    // MARK: - keepAliveVolume

    func testKeepAliveVolume_isGreaterThanZero() {
        let keepAlive = BackgroundAudioKeepAlive()
        XCTAssertGreaterThan(keepAlive.keepAliveVolume, 0.0,
            "keepAliveVolume는 App Store 2.5.4 정책 준수를 위해 0보다 커야 한다")
    }

    // MARK: - 번들 리소스

    func testAmbientLoopBundleURL_isNotNil() {
        let url = Bundle.main.url(forResource: "ambient_loop", withExtension: "m4a")
        XCTAssertNotNil(url, "ambient_loop.m4a가 번들에 포함되어 있어야 한다")
    }

    // MARK: - handleInterruption
    // 인터럽트 로직은 실기기 전용(#if !targetEnvironment(simulator)).
    // 시뮬레이터 빌드에선 stub이 no-op이므로 XCTSkip으로 건너뛴다.

    func testHandleInterruption_began_callsOnInterruptWithFalse() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("인터럽트 핸들링은 실기기 전용")
        #else
        let keepAlive = BackgroundAudioKeepAlive()
        var interruptCalled = false
        var resumeFlag: Bool?
        keepAlive.onInterrupt = { shouldResume in
            interruptCalled = true
            resumeFlag = shouldResume
        }

        keepAlive.handleInterruption(type: .began, options: [])

        XCTAssertTrue(interruptCalled, "began 시 onInterrupt가 호출되어야 한다")
        XCTAssertEqual(resumeFlag, false, "began 시 shouldResume=false로 전달되어야 한다")
        #endif
    }

    func testHandleInterruption_endedWithShouldResume_callsOnInterruptWithTrue() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("인터럽트 핸들링은 실기기 전용")
        #else
        let keepAlive = BackgroundAudioKeepAlive()
        var resumeFlag: Bool?
        keepAlive.onInterrupt = { shouldResume in
            resumeFlag = shouldResume
        }

        keepAlive.handleInterruption(type: .ended, options: .shouldResume)

        XCTAssertEqual(resumeFlag, true, "ended + shouldResume 시 onInterrupt(true)가 호출되어야 한다")
        #endif
    }

    func testHandleInterruption_endedWithoutShouldResume_doesNotResume() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("인터럽트 핸들링은 실기기 전용")
        #else
        let keepAlive = BackgroundAudioKeepAlive()
        var resumeFlag: Bool?
        keepAlive.onInterrupt = { shouldResume in
            resumeFlag = shouldResume
        }

        keepAlive.handleInterruption(type: .ended, options: [])

        XCTAssertEqual(resumeFlag, false, "ended이지만 shouldResume 없으면 onInterrupt(false)로 자동 재개 안 함")
        #endif
    }

    func testHandleInterruption_beganSetsInterruptionBeganAt() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("interruptionBeganAt은 실기기 전용")
        #else
        let keepAlive = BackgroundAudioKeepAlive()
        let before = Date()
        keepAlive.handleInterruption(type: .began, options: [])
        let after = Date()

        guard let beganAt = keepAlive.interruptionBeganAt else {
            XCTFail("began 후 interruptionBeganAt이 설정되어야 한다")
            return
        }
        XCTAssertGreaterThanOrEqual(beganAt, before)
        XCTAssertLessThanOrEqual(beganAt, after)
        #endif
    }

    // MARK: - IMUSessionRecorder 갭 기록

    func testIMUSessionRecorder_recordInterruptionGap_appearsInOutput() {
        let recorder = IMUSessionRecorder(startedAt: Date())
        let began = Date(timeIntervalSinceNow: -10)
        let ended = Date(timeIntervalSinceNow: -5)

        recorder.recordInterruptionGap(began: began, ended: ended)

        let output = recorder.finalize(endedAt: Date())
        XCTAssertEqual(output.interruptionGaps.count, 1, "갭 1건이 Output에 포함되어야 한다")
        XCTAssertEqual(output.interruptionGaps[0].began, began)
        XCTAssertEqual(output.interruptionGaps[0].ended, ended)
    }

    func testIMUSessionRecorder_noGap_outputHasEmptyGaps() {
        let recorder = IMUSessionRecorder(startedAt: Date())
        let output = recorder.finalize(endedAt: Date())
        XCTAssertTrue(output.interruptionGaps.isEmpty, "갭 없이 finalize 시 interruptionGaps는 빈 배열이어야 한다")
    }

    // MARK: - setMuted (crash 없음 assert)

    func testSetMuted_doesNotCrash() {
        let keepAlive = BackgroundAudioKeepAlive()
        // 플레이어 없이 호출해도 crash 없이 종료되어야 한다
        keepAlive.setMuted(true)
        keepAlive.setMuted(false)
    }
}

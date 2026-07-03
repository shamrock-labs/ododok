import AVFoundation
import XCTest
@testable import ChewChewIOS

/// 실기기 오디오 엔진을 직접 띄우지 않고, 볼륨 정책과 페이스→톤 분류만 검증한다.
final class REQ02BackgroundAudioTests: XCTestCase {

    // MARK: - volume

    func testVolume_defaultIsAudible() {
        let keepAlive = BackgroundAudioKeepAlive()
        XCTAssertGreaterThan(keepAlive.volume, 0.0,
            "기본 볼륨은 0보다 커야 한다")
    }

    func testVolume_isInjectable() {
        let keepAlive = BackgroundAudioKeepAlive()
        keepAlive.volume = 0.5
        XCTAssertEqual(keepAlive.volume, 0.5, accuracy: 0.0001,
            "원격 볼륨 주입을 위해 volume은 외부에서 세팅 가능해야 한다")
    }

    func testVolume_isClampedToSupportedRange() {
        let keepAlive = BackgroundAudioKeepAlive()

        keepAlive.volume = 2.0
        XCTAssertEqual(keepAlive.volume, 1.0, accuracy: 0.0001)

        keepAlive.volume = -1.0
        XCTAssertEqual(keepAlive.volume, 0.0, accuracy: 0.0001)
    }

    // MARK: - toneKind

    func testToneKind_notChewing_isNone() {
        let pace = ChewPaceSample(isChewing: false, avgInterval: 1.0)
        XCTAssertEqual(BackgroundAudioKeepAlive.toneKind(for: pace), .none,
            "안 씹는 중이면 소리를 내지 않는다")
    }

    func testToneKind_noIntervalData_isGoodFallback() {
        let pace = ChewPaceSample(isChewing: true, avgInterval: 0)
        XCTAssertEqual(BackgroundAudioKeepAlive.toneKind(for: pace), .good,
            "3초 지속 씹기 이벤트가 온 상태면 간격 데이터가 아직 없어도 기본 낮은 톤을 낸다")
    }

    func testToneKind_fastChewing_isTooFast() {
        let pace = ChewPaceSample(isChewing: true, avgInterval: 0.65)
        XCTAssertEqual(BackgroundAudioKeepAlive.toneKind(for: pace), .tooFast,
            "간격이 임계값보다 짧으면 너무 빠른 것으로 보고 경고 톤")
    }

    func testToneKind_slowChewing_isGood() {
        let pace = ChewPaceSample(isChewing: true, avgInterval: 1.2)
        XCTAssertEqual(BackgroundAudioKeepAlive.toneKind(for: pace), .good,
            "간격이 임계값 이상이면 적정 페이스로 보고 낮은 톤")
    }

    func testToneKind_atThreshold_isGood() {
        let pace = ChewPaceSample(isChewing: true, avgInterval: 0.8)
        XCTAssertEqual(BackgroundAudioKeepAlive.toneKind(for: pace, fastThreshold: 0.8), .good,
            "정확히 임계값이면 적정(경계 포함)")
    }
}

import AVFoundation
import XCTest
@testable import ChewChewIOS

/// 오디오 엔진은 실기기 전용이라 시뮬레이터 유닛테스트에선 하드웨어 없이 검증 가능한
/// 볼륨 기본값과 씹기 페이스→톤 분류(`toneKind`)만 확인한다.
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

    // MARK: - toneKind (신호등 분류, 순수 함수)

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
        // fastThreshold(기본 0.8초)보다 짧은 간격 = 빨리 씹음 → 경고 톤.
        // 0.65초는 ChewCounter minPeakGap(0.64초) 바로 위 — 실측 가능한 빠른 페이스.
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
        // 경계값(== fastThreshold)은 '적정'으로 — tooFast는 strict less-than.
        let pace = ChewPaceSample(isChewing: true, avgInterval: 0.8)
        XCTAssertEqual(BackgroundAudioKeepAlive.toneKind(for: pace, fastThreshold: 0.8), .good,
            "정확히 임계값이면 적정(경계 포함)")
    }
}

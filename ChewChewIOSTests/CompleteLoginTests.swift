import XCTest
@testable import ChewChewIOS

/// `completeLogin(onboardingCompleted:)` 핵심 회귀 테스트.
/// 로그아웃 → 재로그인 시 온보딩이 다시 뜨던 버그(ODO-47)가 재발하지 않음을 보장한다.
@MainActor
final class CompleteLoginTests: XCTestCase {
    override func tearDown() {
        TokenManager.clear()
        super.tearDown()
    }

    // MARK: - onboardingCompleted: true

    func testCompleteLogin_onboardingTrue_setsHasCompletedOnboarding() {
        let state = AppState(remoteStore: SpyRemoteStore())

        state.completeLogin(onboardingCompleted: true)

        XCTAssertTrue(state.hasCompletedOnboarding,
            "서버가 onboardingCompleted=true를 반환하면 hasCompletedOnboarding이 true여야 한다")
    }

    func testCompleteLogin_onboardingTrue_setsIsLoggedIn() {
        let state = AppState(remoteStore: SpyRemoteStore())

        state.completeLogin(onboardingCompleted: true)

        XCTAssertTrue(state.isLoggedIn, "completeLogin 후 isLoggedIn이 true여야 한다")
    }

    // MARK: - onboardingCompleted: false

    func testCompleteLogin_onboardingFalse_doesNotSetHasCompletedOnboarding() {
        let state = AppState(remoteStore: SpyRemoteStore())

        state.completeLogin(onboardingCompleted: false)

        XCTAssertFalse(state.hasCompletedOnboarding,
            "서버가 onboardingCompleted=false를 반환하면 hasCompletedOnboarding이 false로 유지돼야 한다")
    }

    // MARK: - clearLocalSessionCache 이후에도 서버 값이 살아남는 불변식

    /// 핵심 회귀 케이스:
    /// completeLogin 내부에서 clearLocalSessionCache()가 hasCompletedOnboarding을 false로
    /// 리셋하는데, 그 뒤에 서버 값(true)이 재적용돼야 온보딩 재노출 버그가 재발하지 않는다.
    func testCompleteLogin_onboardingTrue_survivesInternalCacheClear() {
        let state = AppState(remoteStore: SpyRemoteStore())
        // 로그아웃으로 캐시가 한 번 지워진 상태를 시뮬레이션
        state.hasCompletedOnboarding = false

        state.completeLogin(onboardingCompleted: true)

        XCTAssertTrue(state.hasCompletedOnboarding,
            "clearLocalSessionCache()의 리셋이 서버 값(true)을 덮어쓰면 안 된다")
    }

    /// 반대 케이스: false일 때는 clearLocalSessionCache 이후에도 false로 남아야 한다.
    func testCompleteLogin_onboardingFalse_remainsFalseAfterCacheClear() {
        let state = AppState(remoteStore: SpyRemoteStore())
        // 로컬에 true가 캐시된 상태에서 재로그인
        state.hasCompletedOnboarding = true

        state.completeLogin(onboardingCompleted: false)

        XCTAssertFalse(state.hasCompletedOnboarding,
            "서버가 false를 반환하면 기존 로컬 캐시(true)가 우선되면 안 된다")
    }

    // MARK: - 기존 로컬 캐시 초기화 확인

    func testCompleteLogin_clearsLocalCache() {
        let state = AppState(remoteStore: SpyRemoteStore())
        state.points = 100
        state.streak = 5
        state.displayName = "이전계정"

        state.completeLogin(onboardingCompleted: true)

        XCTAssertEqual(state.points, 0, "completeLogin은 이전 계정의 points를 초기화해야 한다")
        XCTAssertEqual(state.streak, 0, "completeLogin은 이전 계정의 streak을 초기화해야 한다")
        XCTAssertNil(state.displayName, "completeLogin은 이전 계정의 displayName을 초기화해야 한다")
    }
}

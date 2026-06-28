import XCTest
@testable import ChewChewIOS

final class SocialLoginAndInviteConfigTests: XCTestCase {
    func testLoginProviderOptions_includeAppleGoogleKakaoInDisplayOrder() {
        XCTAssertEqual(LoginProviderOption.allCases, [.apple, .google, .kakao])
        XCTAssertEqual(LoginProviderOption.allCases.map(\.title), [
            "Apple로 계속하기",
            "Google로 계속하기",
            "카카오로 계속하기"
        ])
    }

    func testKakaoInviteFallbackURL_ignoresMissingBuildSettingPlaceholder() {
        XCTAssertNil(KakaoInviteSharer.mobileWebFallbackURL(from: "$(KAKAO_INVITE_MOBILE_WEB_URL)"))
        XCTAssertNil(KakaoInviteSharer.mobileWebFallbackURL(from: ""))
    }

    func testKakaoInviteFallbackURL_acceptsConfiguredHTTPSURL() {
        let url = KakaoInviteSharer.mobileWebFallbackURL(from: "https://apps.apple.com/app/id1234567890")

        XCTAssertEqual(url?.absoluteString, "https://apps.apple.com/app/id1234567890")
    }
}

import XCTest
@testable import ChewChewIOS

final class OnboardingNicknameTests: XCTestCase {
    func testNormalizedDisplayName_limitsNameToEightCharacters() {
        XCTAssertEqual(AppState.normalizedDisplayName("가나다라마바사아자"), "가나다라마바사아")
    }

    func testNormalizedDisplayName_trimsWhitespaceBeforeLimitingLength() {
        XCTAssertEqual(AppState.normalizedDisplayName("  다람이 1234  "), "다람이 1234")
    }

    func testNormalizedDisplayName_rejectsWhitespaceOnlyName() {
        XCTAssertNil(AppState.normalizedDisplayName("   "))
    }

    func testGeneratedNickname_usesDaramPrefixAndFourDigits() {
        XCTAssertEqual(AppState.generatedNickname(number: 1234), "다람이 1234")
    }

    func testGeneratedNickname_padsSmallNumbers() {
        XCTAssertEqual(AppState.generatedNickname(number: 7), "다람이 0007")
    }
}

import XCTest
@testable import ChewChewIOS

final class OnboardingNicknameTests: XCTestCase {
    func testGeneratedNickname_usesDaramPrefixAndFourDigits() {
        XCTAssertEqual(AppState.generatedNickname(number: 1234), "다람이 1234")
    }

    func testGeneratedNickname_padsSmallNumbers() {
        XCTAssertEqual(AppState.generatedNickname(number: 7), "다람이 0007")
    }
}

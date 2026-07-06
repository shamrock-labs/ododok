import XCTest
@testable import ChewChewIOS

final class MealReminderDraftTests: XCTestCase {
    func testDismissDecision_whenDraftChangedRequiresConfirmationWithoutSaving() {
        var original = MealReminderSettings.default
        original.breakfast = MealSlot(enabled: false, hour: 8, minute: 0)
        var edited = original
        edited.breakfast.enabled = true

        let draft = MealReminderDraft(settings: edited, lastSaved: original)

        XCTAssertTrue(draft.hasUnsavedChanges)
        XCTAssertEqual(draft.dismissDecision, .confirmDiscard)
    }

    func testDismissDecision_whenDraftUnchangedDismissesImmediately() {
        let settings = MealReminderSettings.default
        let draft = MealReminderDraft(settings: settings, lastSaved: settings)

        XCTAssertFalse(draft.hasUnsavedChanges)
        XCTAssertEqual(draft.dismissDecision, .dismiss)
    }
}

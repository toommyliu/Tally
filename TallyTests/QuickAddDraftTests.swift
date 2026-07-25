import XCTest
@testable import Tally

@MainActor
final class QuickAddDraftTests: XCTestCase {
    func testDraftStartsWithConfiguredBehavior() {
        let settings = makeSettings()
        settings.quickAddBehavior = .keepOpen

        let draft = QuickAddDraft(settingsStore: settings)

        XCTAssertTrue(draft.keepsOpenAfterAdd)
    }

    func testRequestUsesStableSelectedListIdentifierAndParsedMetadata() throws {
        let settings = makeSettings()
        let draft = QuickAddDraft(settingsStore: settings)
        let work = ReminderListInfo(id: "work-id", title: "Work")
        draft.text = "Call Sam 2026-08-14 3:30pm @phone P1 // Ask about renewal"
        draft.notes = "Agenda attached"
        draft.selectList(work)

        let request = try XCTUnwrap(draft.makeRequest())

        XCTAssertEqual(request.title, "Call Sam")
        XCTAssertEqual(request.userNotes, "Agenda attached")
        XCTAssertEqual(request.inlineNotes, "Ask about renewal")
        XCTAssertEqual(request.tags, ["phone"])
        XCTAssertEqual(request.priority, 1)
        XCTAssertEqual(request.listIdentifier, "work-id")
        XCTAssertEqual(request.listName, "Work")
    }

    func testRequestUsesConfiguredDefaultListWithoutAddingVisibleToken() throws {
        let settings = makeSettings()
        settings.defaultListIdentifier = "personal-id"
        let draft = QuickAddDraft(settingsStore: settings)
        draft.text = "Buy milk"

        let request = try XCTUnwrap(draft.makeRequest())

        XCTAssertEqual(request.listIdentifier, "personal-id")
        XCTAssertNil(request.listName)
        XCTAssertEqual(draft.text, "Buy milk")
    }

    func testSaveFailurePreservesDraftAndSuccessfulSaveResetsIt() {
        let settings = makeSettings()
        let draft = QuickAddDraft(settingsStore: settings)
        draft.text = "Call Sam tomorrow"
        draft.notes = "Bring the agenda"

        draft.reportSaveFailure("No writable list")

        XCTAssertEqual(draft.text, "Call Sam tomorrow")
        XCTAssertEqual(draft.notes, "Bring the agenda")
        XCTAssertEqual(draft.errorMessage, "No writable list")

        draft.didSave(to: "Work")

        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(draft.notes, "")
        XCTAssertNil(draft.errorMessage)
        XCTAssertEqual(draft.confirmationMessage, "Added to Work")
    }

    private func makeSettings() -> AppSettingsStore {
        let suiteName = "TallyTests.QuickAddDraft.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return AppSettingsStore(userDefaults: userDefaults)
    }
}

import XCTest
@testable import Tally

final class ReminderCreationRequestTests: XCTestCase {
    func testCombinedNotesTrimsInputAndPreservesInlineNotesAndTags() {
        let request = makeRequest(
            userNotes: "  Supporting context\n",
            inlineNotes: "Ask about renewal",
            tags: ["phone", "follow-up"]
        )

        XCTAssertEqual(
            request.combinedNotes,
            "Supporting context\nAsk about renewal\nTags: @phone @follow-up"
        )
    }

    func testCombinedNotesDoesNotDuplicateMatchingInlineNotes() {
        let request = makeRequest(
            userNotes: "Ask about renewal",
            inlineNotes: "  Ask about renewal  "
        )

        XCTAssertEqual(request.combinedNotes, "Ask about renewal")
    }

    private func makeRequest(
        userNotes: String? = nil,
        inlineNotes: String? = nil,
        tags: [String] = []
    ) -> ReminderCreationRequest {
        ReminderCreationRequest(
            title: "Call Sam",
            userNotes: userNotes,
            inlineNotes: inlineNotes,
            tags: tags,
            listIdentifier: nil,
            listName: nil,
            dueDate: nil,
            priority: 0
        )
    }
}

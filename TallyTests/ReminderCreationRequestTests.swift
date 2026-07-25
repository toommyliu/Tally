import XCTest
@testable import Tally

final class ReminderCreationRequestTests: XCTestCase {
    func testMissingConfiguredListDoesNotFallBackToDefault() {
        let inbox = ReminderListInfo(id: "inbox-id", title: "Inbox")
        let request = makeRequest(listIdentifier: "deleted-list-id")

        let resolved = ReminderDestinationResolver.resolve(
            request: request,
            writableDestinations: [inbox],
            defaultDestination: inbox,
            identifier: \.id,
            title: \.title
        )

        XCTAssertNil(resolved)
    }

    func testAutomaticDestinationStillUsesDefaultList() {
        let inbox = ReminderListInfo(id: "inbox-id", title: "Inbox")
        let request = makeRequest()

        let resolved = ReminderDestinationResolver.resolve(
            request: request,
            writableDestinations: [inbox],
            defaultDestination: inbox,
            identifier: \.id,
            title: \.title
        )

        XCTAssertEqual(resolved, inbox)
    }

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
        tags: [String] = [],
        listIdentifier: String? = nil,
        listName: String? = nil
    ) -> ReminderCreationRequest {
        ReminderCreationRequest(
            title: "Call Sam",
            userNotes: userNotes,
            inlineNotes: inlineNotes,
            tags: tags,
            listIdentifier: listIdentifier,
            listName: listName,
            dueDate: nil,
            priority: 0
        )
    }
}

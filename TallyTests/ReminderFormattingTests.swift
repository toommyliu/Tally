import XCTest
@testable import Tally

final class ReminderFormattingTests: XCTestCase {
    func testPriorityTitlesMatchAppleReminders() {
        XCTAssertEqual(0.reminderPriorityTitle, "None")
        XCTAssertEqual(9.reminderPriorityTitle, "Low")
        XCTAssertEqual(5.reminderPriorityTitle, "Medium")
        XCTAssertEqual(1.reminderPriorityTitle, "High")
    }

    func testMenuTitleIncludesDueDateWhenItFits() {
        let reminder = ReminderItem(
            id: "1",
            title: "Pay rent",
            notes: nil,
            listTitle: "Home",
            dueDate: DateComponents(year: 2026, month: 5, day: 31),
            priority: 0
        )

        XCTAssertTrue(reminder.formattedMenuTitle(maxLength: 80).hasPrefix("Pay rent - "))
    }

    func testMenuTitleIsCappedForMenuBarUse() {
        let reminder = ReminderItem(
            id: "1",
            title: "Prepare the extremely detailed quarterly planning memo",
            notes: nil,
            listTitle: "Work",
            dueDate: nil,
            priority: 0
        )

        let title = reminder.menuTitle

        XCTAssertLessThanOrEqual(title.count, 30)
        XCTAssertTrue(title.hasSuffix("..."))
    }
}

import EventKit

/// Converts Tally's reminder creation values into their EventKit representation.
enum ReminderEventKitMapper {
    static func populate(
        _ reminder: EKReminder,
        from request: ReminderCreationRequest,
        calendar: EKCalendar
    ) {
        reminder.title = request.title
        reminder.calendar = calendar
        reminder.priority = request.priority
        reminder.dueDateComponents = request.dueDate
        reminder.notes = request.combinedNotes

        // Reminders drops count-based ends, so persist the equivalent final date.
        if let recurrence = request.recurrence,
           let rule = EventKitRecurrenceRuleMapper.rule(
                for: recurrence,
                convertingOccurrenceCountFrom: request.dueDate
           ) {
            reminder.addRecurrenceRule(rule)
        }
    }
}

# AGENTS.md

## Project Snapshot

Tally is a Todoist/Things clone for Apple Reminders using the Reminders API. It should sync with the Reminders app and the Apple ecosystem, such as the Calendar.

This repository is a VERY EARLY WIP. Proposing sweeping changes that improve long-term maintainability is encouraged.

## Core Priorities

1. Performance first.
2. Reliability first.
3. Keep behavior predictable under load and during failures (session restarts, reconnects, partial streams).

If a tradeoff is required, choose correctness and robustness over short-term convenience.

## Maintainability

Long term maintainability is a core priority. If you add new functionality, first check if there is shared logic that can be extracted to a separate module. Duplicate logic across multiple files is a code smell and should be avoided. Don't be afraid to change existing code. Don't take shortcuts by just adding local logic to solve a problem.

## Apple Platform References

When working on Reminders or Calendar behavior, prefer Apple's official documentation and APIs over assumptions from third-party examples. Key references:

- [EventKit](https://developer.apple.com/documentation/eventkit): framework for creating, retrieving, editing, and observing calendar events and reminders.
- [EKEventStore](https://developer.apple.com/documentation/eventkit/ekeventstore): the shared access point for calendar and reminder data, permissions, fetches, saves, deletes, commits, and change notifications.
- [EKReminder](https://developer.apple.com/documentation/eventkit/ekreminder): reminder model, including title, calendar/list, due dates, start dates, priority, completion state, and recurrence inherited through `EKCalendarItem`.
- [EKCalendar](https://developer.apple.com/documentation/eventkit/ekcalendar): represents both calendars and reminder lists; check entity type support and write permissions before saving.
- [Retrieving events and reminders](https://developer.apple.com/documentation/eventkit/retrieving_events_and_reminders): fetch behavior, predicates, identifier lookup, and reminder query patterns.
- [Creating events and reminders](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders): save, delete, calendar/list assignment, alarm, and recurrence behavior.
- [Updating with notifications](https://developer.apple.com/documentation/eventkit/updating-with-notifications): use `EKEventStoreChanged` / `.EKEventStoreChanged` notifications to detect external changes from Calendar, Reminders, iCloud, or other apps and refetch stale state.
- [NSRemindersFullAccessUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsremindersfullaccessusagedescription), [NSCalendarsFullAccessUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription), and [NSCalendarsWriteOnlyAccessUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarswriteonlyaccessusagedescription): required privacy strings when requesting Reminders or Calendar access.


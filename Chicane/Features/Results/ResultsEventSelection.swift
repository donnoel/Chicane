import Foundation

enum ResultsEventSelection {
    static func defaultEvent(
        in events: [RaceEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RaceEvent? {
        let sortedEvents = events.sorted { $0.raceDate < $1.raceDate }

        if let todayEvent = sortedEvents.first(where: { calendar.isDate($0.raceDate, inSameDayAs: now) }) {
            return todayEvent
        }

        if let latestPastEvent = sortedEvents.last(where: { $0.raceDate < now }) {
            return latestPastEvent
        }

        return sortedEvents.first
    }
}

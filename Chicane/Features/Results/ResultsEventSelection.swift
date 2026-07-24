import Foundation

enum ResultsEventSelection {
    static func defaultEvent(
        in events: [RaceEvent],
        results: [RaceResult],
        now: Date = Date()
    ) -> RaceEvent? {
        RaceEvent.nextDisplayEvent(in: events, results: results, at: now)
    }
}

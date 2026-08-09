import Foundation

enum ResultsEventSelection {
    static func defaultEvent(
        in events: [RaceEvent],
        results: [RaceResult],
        series: RaceSeries? = nil,
        now: Date = Date()
    ) -> RaceEvent? {
        let eligibleEvents = series.map { selectedSeries in
            events.filter { $0.series == selectedSeries }
        } ?? events

        return RaceEvent.nextDisplayEvent(in: eligibleEvents, results: results, at: now)
    }
}

import XCTest
@testable import Chicane

final class ResultsEventSelectionTests: XCTestCase {
    func testDefaultEventPrefersTodayOverPastLockedCandidate() {
        let now = date("2026-06-28T13:04:00Z")
        let events = [
            event(id: "mgp-czechia", raceDate: date("2026-06-21T12:00:00Z")),
            event(id: "mgp-netherlands", raceDate: date("2026-06-28T15:00:00Z"))
        ]

        let selected = ResultsEventSelection.defaultEvent(in: events, now: now, calendar: utcCalendar)

        XCTAssertEqual(selected?.id, "mgp-netherlands")
    }

    func testDefaultEventUsesLatestPastEventWhenThereIsNoRaceToday() {
        let now = date("2026-06-28T13:04:00Z")
        let events = [
            event(id: "mgp-older", raceDate: date("2026-06-14T12:00:00Z")),
            event(id: "mgp-recent", raceDate: date("2026-06-21T12:00:00Z")),
            event(id: "mgp-future", raceDate: date("2026-07-05T12:00:00Z"))
        ]

        let selected = ResultsEventSelection.defaultEvent(in: events, now: now, calendar: utcCalendar)

        XCTAssertEqual(selected?.id, "mgp-recent")
    }

    func testDefaultEventUsesFirstFutureEventBeforeSeasonStarts() {
        let now = date("2026-02-01T12:00:00Z")
        let events = [
            event(id: "mgp-r2", raceDate: date("2026-03-08T12:00:00Z")),
            event(id: "mgp-r1", raceDate: date("2026-03-01T12:00:00Z"))
        ]

        let selected = ResultsEventSelection.defaultEvent(in: events, now: now, calendar: utcCalendar)

        XCTAssertEqual(selected?.id, "mgp-r1")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func event(id: String, raceDate: Date) -> RaceEvent {
        RaceEvent(
            id: id,
            series: .motoGP,
            season: 2026,
            round: 1,
            title: id,
            circuit: "Test Circuit",
            raceDate: raceDate
        )
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}

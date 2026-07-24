import XCTest
@testable import Chicane

final class ResultsEventSelectionTests: XCTestCase {
    func testDefaultEventUsesUpcomingWeekendBeforeRaceDay() {
        let now = date("2026-07-24T21:58:00Z")
        let events = [
            event(id: "f1-belgium", raceDate: date("2026-07-19T12:00:00Z")),
            event(id: "f1-hungary", raceDate: date("2026-07-26T12:00:00Z"))
        ]

        let selected = ResultsEventSelection.defaultEvent(
            in: events,
            results: [result(eventID: "f1-belgium")],
            now: now
        )

        XCTAssertEqual(selected?.id, "f1-hungary")
    }

    func testDefaultEventHoldsStartedRaceUntilResultIsFetched() {
        let now = date("2026-07-26T14:00:00Z")
        let events = [
            event(id: "f1-hungary", raceDate: date("2026-07-26T12:00:00Z")),
            event(id: "f1-netherlands", raceDate: date("2026-08-23T13:00:00Z"))
        ]

        let selected = ResultsEventSelection.defaultEvent(in: events, results: [], now: now)

        XCTAssertEqual(selected?.id, "f1-hungary")
    }

    func testDefaultEventAdvancesAfterResultIsFetched() {
        let now = date("2026-07-26T14:00:00Z")
        let events = [
            event(id: "f1-hungary", raceDate: date("2026-07-26T12:00:00Z")),
            event(id: "f1-netherlands", raceDate: date("2026-08-23T13:00:00Z"))
        ]

        let selected = ResultsEventSelection.defaultEvent(
            in: events,
            results: [result(eventID: "f1-hungary")],
            now: now
        )

        XCTAssertEqual(selected?.id, "f1-netherlands")
    }

    func testDefaultEventUsesFirstFutureEventBeforeSeasonStarts() {
        let now = date("2026-02-01T12:00:00Z")
        let events = [
            event(id: "mgp-r2", raceDate: date("2026-03-08T12:00:00Z")),
            event(id: "mgp-r1", raceDate: date("2026-03-01T12:00:00Z"))
        ]

        let selected = ResultsEventSelection.defaultEvent(in: events, results: [], now: now)

        XCTAssertEqual(selected?.id, "mgp-r1")
    }

    private func event(id: String, raceDate: Date) -> RaceEvent {
        RaceEvent(
            id: id,
            series: id.hasPrefix("f1-") ? .formula1 : .motoGP,
            season: 2026,
            round: 1,
            title: id,
            circuit: "Test Circuit",
            raceDate: raceDate
        )
    }

    private func result(eventID: String) -> RaceResult {
        RaceResult(
            series: eventID.hasPrefix("f1-") ? .formula1 : .motoGP,
            eventID: eventID,
            podium: Podium(p1: "one", p2: "two", p3: "three"),
            isLocked: true,
            updatedAt: date("2026-07-26T14:00:00Z")
        )
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}

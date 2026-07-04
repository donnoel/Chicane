import XCTest
@testable import Chicane

final class RaceEventDisplaySelectionTests: XCTestCase {
    func testNextDisplayEventHoldsLatestStartedRaceUntilResultExists() {
        let silverstone = event(
            id: "f1-2026-great-britain",
            round: 11,
            title: "British Grand Prix",
            raceDate: date("2026-07-05T12:00:00Z")
        )
        let spa = event(
            id: "f1-2026-belgium",
            round: 12,
            title: "Belgian Grand Prix",
            raceDate: date("2026-07-26T13:00:00Z")
        )

        let selected = RaceEvent.nextDisplayEvent(
            in: [silverstone, spa],
            results: [],
            at: date("2026-07-05T20:00:00Z")
        )

        XCTAssertEqual(selected?.id, silverstone.id)
    }

    func testNextDisplayEventAdvancesAfterLatestStartedRaceHasResult() {
        let silverstone = event(
            id: "f1-2026-great-britain",
            round: 11,
            title: "British Grand Prix",
            raceDate: date("2026-07-05T12:00:00Z")
        )
        let spa = event(
            id: "f1-2026-belgium",
            round: 12,
            title: "Belgian Grand Prix",
            raceDate: date("2026-07-26T13:00:00Z")
        )

        let selected = RaceEvent.nextDisplayEvent(
            in: [silverstone, spa],
            results: [result(for: silverstone)],
            at: date("2026-07-05T20:00:00Z")
        )

        XCTAssertEqual(selected?.id, spa.id)
    }

    func testNextDisplayEventDoesNotLetOlderMissingResultsBlockProgress() {
        let monaco = event(
            id: "f1-2026-monaco",
            round: 8,
            title: "Monaco Grand Prix",
            raceDate: date("2026-05-24T13:00:00Z")
        )
        let silverstone = event(
            id: "f1-2026-great-britain",
            round: 11,
            title: "British Grand Prix",
            raceDate: date("2026-07-05T12:00:00Z")
        )
        let spa = event(
            id: "f1-2026-belgium",
            round: 12,
            title: "Belgian Grand Prix",
            raceDate: date("2026-07-26T13:00:00Z")
        )

        let selected = RaceEvent.nextDisplayEvent(
            in: [monaco, silverstone, spa],
            results: [result(for: silverstone)],
            at: date("2026-07-05T20:00:00Z")
        )

        XCTAssertEqual(selected?.id, spa.id)
    }

    func testNextDisplayEventUsesUpcomingRaceBeforeRaceStart() {
        let silverstone = event(
            id: "f1-2026-great-britain",
            round: 11,
            title: "British Grand Prix",
            raceDate: date("2026-07-05T12:00:00Z")
        )
        let spa = event(
            id: "f1-2026-belgium",
            round: 12,
            title: "Belgian Grand Prix",
            raceDate: date("2026-07-26T13:00:00Z")
        )

        let selected = RaceEvent.nextDisplayEvent(
            in: [silverstone, spa],
            results: [],
            at: date("2026-07-05T11:59:00Z")
        )

        XCTAssertEqual(selected?.id, silverstone.id)
    }

    func testNextDisplayEventUsesUpcomingRaceWhenPastRaceIsStaleWithoutResult() {
        let dutchGP = event(
            id: "mgp-2026-netherlands",
            series: .motoGP,
            round: 11,
            title: "Dutch GP",
            raceDate: date("2026-06-28T12:00:00Z")
        )
        let silverstone = event(
            id: "f1-2026-great-britain",
            series: .formula1,
            round: 11,
            title: "British Grand Prix",
            raceDate: date("2026-07-05T12:00:00Z")
        )

        let selected = RaceEvent.nextDisplayEvent(
            in: [dutchGP, silverstone],
            results: [],
            at: date("2026-07-04T21:48:00Z")
        )

        XCTAssertEqual(selected?.id, silverstone.id)
    }

    private func event(
        id: String,
        series: RaceSeries = .formula1,
        round: Int,
        title: String,
        raceDate: Date
    ) -> RaceEvent {
        RaceEvent(
            id: id,
            series: series,
            season: 2026,
            round: round,
            title: title,
            circuit: "Test Circuit",
            raceDate: raceDate
        )
    }

    private func result(for event: RaceEvent) -> RaceResult {
        RaceResult(
            series: event.series,
            eventID: event.id,
            podium: Podium(p1: "one", p2: "two", p3: "three"),
            isLocked: true,
            updatedAt: date("2026-07-05T20:00:00Z")
        )
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}

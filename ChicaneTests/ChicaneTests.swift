import XCTest
@testable import Chicane

final class ChicaneTests: XCTestCase {
    private let scoringService = ScoringService()
    private let calculator = ScoreboardCalculator()

    func testExactPositionAwardsThreePoints() {
        let pick = Podium(p1: "a", p2: "b", p3: "c")
        let result = Podium(p1: "a", p2: "b", p3: "c")

        XCTAssertEqual(scoringService.points(for: pick, result: result), 3)
    }

    func testSameDriversDifferentOrderAwardsZeroPoints() {
        let pick = Podium(p1: "a", p2: "b", p3: "c")
        let result = Podium(p1: "b", p2: "c", p3: "a")

        XCTAssertEqual(scoringService.points(for: pick, result: result), 0)
    }

    func testDuplicatePodiumSelectionIsRejected() {
        let draft = PodiumDraft(p1: "a", p2: "a", p3: "b")

        XCTAssertTrue(draft.hasDuplicates)
        XCTAssertNil(draft.toPodium())
    }

    func testStandingsAggregateAcrossSeries() {
        let mom = Player(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Mom")
        let don = Player(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Don")

        let events = [
            RaceEvent(id: "f1-r1", series: .formula1, season: 2026, round: 1, title: "F1 R1", circuit: "Circuit 1", raceDate: Date(timeIntervalSince1970: 1)),
            RaceEvent(id: "mgp-r1", series: .motoGP, season: 2026, round: 1, title: "MotoGP R1", circuit: "Circuit 2", raceDate: Date(timeIntervalSince1970: 2))
        ]

        let picks = [
            RacePick(id: UUID(), series: .formula1, eventID: "f1-r1", playerID: mom.id, podium: Podium(p1: "a", p2: "b", p3: "c"), updatedAt: Date()),
            RacePick(id: UUID(), series: .formula1, eventID: "f1-r1", playerID: don.id, podium: Podium(p1: "x", p2: "y", p3: "z"), updatedAt: Date()),
            RacePick(id: UUID(), series: .motoGP, eventID: "mgp-r1", playerID: mom.id, podium: Podium(p1: "x", p2: "b", p3: "c"), updatedAt: Date()),
            RacePick(id: UUID(), series: .motoGP, eventID: "mgp-r1", playerID: don.id, podium: Podium(p1: "a", p2: "b", p3: "c"), updatedAt: Date())
        ]

        let results = [
            RaceResult(series: .formula1, eventID: "f1-r1", podium: Podium(p1: "a", p2: "b", p3: "c"), isLocked: true, updatedAt: Date()),
            RaceResult(series: .motoGP, eventID: "mgp-r1", podium: Podium(p1: "a", p2: "b", p3: "c"), isLocked: true, updatedAt: Date())
        ]

        let standings = calculator.standings(
            players: [mom, don],
            picks: picks,
            results: results,
            events: events,
            scope: .combined
        )

        XCTAssertEqual(standings.first?.player.name, "Mom")
        XCTAssertEqual(standings.first?.points, 5)
        XCTAssertEqual(standings.last?.player.name, "Don")
        XCTAssertEqual(standings.last?.points, 3)
    }
}

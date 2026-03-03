import XCTest
@testable import Chicane

final class ScoringServiceTests: XCTestCase {
    private let scoring = ScoringService()
    private let calculator = ScoreboardCalculator()

    // MARK: - points(for:result:)

    func testOneCorrectPositionAwardsOnePoint() {
        let pick = Podium(p1: "a", p2: "x", p3: "y")
        let result = Podium(p1: "a", p2: "b", p3: "c")

        XCTAssertEqual(scoring.points(for: pick, result: result), 1)
    }

    func testTwoCorrectPositionsAwardsTwoPoints() {
        let pick = Podium(p1: "a", p2: "b", p3: "x")
        let result = Podium(p1: "a", p2: "b", p3: "c")

        XCTAssertEqual(scoring.points(for: pick, result: result), 2)
    }

    func testNoMatchesAwardsZeroPoints() {
        let pick = Podium(p1: "x", p2: "y", p3: "z")
        let result = Podium(p1: "a", p2: "b", p3: "c")

        XCTAssertEqual(scoring.points(for: pick, result: result), 0)
    }

    func testRightDriversWrongPositionsAwardsZero() {
        // All 3 correct drivers but shifted positions
        let pick = Podium(p1: "c", p2: "a", p3: "b")
        let result = Podium(p1: "a", p2: "b", p3: "c")

        XCTAssertEqual(scoring.points(for: pick, result: result), 0)
    }

    // MARK: - pointsByPlayer

    func testPointsByPlayerReturnsZeroForPlayerWithNoPick() {
        let player = TestFixtures.player(name: "Alice")
        let result = TestFixtures.result()

        let points = scoring.pointsByPlayer(
            players: [player],
            picks: [], // no picks at all
            result: result,
            series: .formula1,
            eventID: "f1-r1"
        )

        XCTAssertEqual(points[player.id], 0)
    }

    func testPointsByPlayerMatchesCorrectEventAndSeries() {
        let player = TestFixtures.player(name: "Bob")
        let pick = TestFixtures.pick(series: .formula1, eventID: "f1-r1", playerID: player.id, p1: "a", p2: "b", p3: "c")
        let result = TestFixtures.result(series: .formula1, eventID: "f1-r1")

        let points = scoring.pointsByPlayer(
            players: [player],
            picks: [pick],
            result: result,
            series: .formula1,
            eventID: "f1-r1"
        )

        XCTAssertEqual(points[player.id], 3)
    }

    func testPointsByPlayerIgnoresPicksFromDifferentEvent() {
        let player = TestFixtures.player(name: "Carol")
        // Pick is for a different event
        let pick = TestFixtures.pick(series: .formula1, eventID: "f1-r2", playerID: player.id, p1: "a", p2: "b", p3: "c")
        let result = TestFixtures.result(series: .formula1, eventID: "f1-r1")

        let points = scoring.pointsByPlayer(
            players: [player],
            picks: [pick],
            result: result,
            series: .formula1,
            eventID: "f1-r1"
        )

        XCTAssertEqual(points[player.id], 0)
    }

    func testPointsByPlayerMatchesLegacyMotoGPPickToLiveEventAndDriverIDs() {
        let player = TestFixtures.player(name: "Mom")
        let event = TestFixtures.event(
            id: "mgp-live-qatar",
            series: .motoGP,
            title: "Qatar Grand Prix"
        )
        let liveDrivers = [
            TestFixtures.driver(id: "mgp-live-bagnaia", series: .motoGP, name: "Francesco Bagnaia", team: "Ducati"),
            TestFixtures.driver(id: "mgp-live-martin", series: .motoGP, name: "Jorge Martin", team: "Aprilia"),
            TestFixtures.driver(id: "mgp-live-mmarquez", series: .motoGP, name: "Marc Marquez", team: "Ducati")
        ]
        let pick = TestFixtures.pick(
            series: .motoGP,
            eventID: "mgp-2026-qatar",
            playerID: player.id,
            p1: "mgp-bagnaia",
            p2: "mgp-legacy-other",
            p3: "mgp-legacy-third"
        )
        let result = TestFixtures.result(
            series: .motoGP,
            eventID: event.id,
            p1: "mgp-live-bagnaia",
            p2: "mgp-live-martin",
            p3: "mgp-live-mmarquez"
        )

        let points = scoring.pointsByPlayer(
            players: [player],
            picks: [pick],
            result: result,
            series: .motoGP,
            eventID: event.id,
            events: [event],
            participants: liveDrivers
        )

        XCTAssertEqual(points[player.id], 1)
    }

    // MARK: - ScoreboardCalculator.standings — scope filtering

    func testStandingsFiltersBySeries() {
        let player = TestFixtures.player(name: "Dave")
        let f1Event = TestFixtures.event(id: "f1-r1", series: .formula1)
        let mgpEvent = TestFixtures.event(id: "mgp-r1", series: .motoGP)

        let picks = [
            TestFixtures.pick(series: .formula1, eventID: "f1-r1", playerID: player.id),
            TestFixtures.pick(series: .motoGP, eventID: "mgp-r1", playerID: player.id)
        ]

        let results = [
            TestFixtures.result(series: .formula1, eventID: "f1-r1"),
            TestFixtures.result(series: .motoGP, eventID: "mgp-r1")
        ]

        let f1Only = calculator.standings(
            players: [player], picks: picks, results: results,
            events: [f1Event, mgpEvent], scope: .formula1
        )

        XCTAssertEqual(f1Only.first?.points, 3, "F1 scope should only count F1 results")
    }

    func testStandingsCountLegacySeedPickAgainstLiveMotoGPResult() {
        let player = TestFixtures.player(name: "Mom")
        let event = TestFixtures.event(
            id: "mgp-live-qatar",
            series: .motoGP,
            title: "Qatar Grand Prix"
        )
        let pick = TestFixtures.pick(
            series: .motoGP,
            eventID: "mgp-2026-qatar",
            playerID: player.id,
            p1: "mgp-bagnaia",
            p2: "mgp-legacy-other",
            p3: "mgp-legacy-third"
        )
        let result = TestFixtures.result(
            series: .motoGP,
            eventID: event.id,
            p1: "mgp-live-bagnaia",
            p2: "mgp-live-martin",
            p3: "mgp-live-mmarquez"
        )
        let liveDrivers = [
            TestFixtures.driver(id: "mgp-live-bagnaia", series: .motoGP, name: "Francesco Bagnaia", team: "Ducati"),
            TestFixtures.driver(id: "mgp-live-martin", series: .motoGP, name: "Jorge Martin", team: "Aprilia"),
            TestFixtures.driver(id: "mgp-live-mmarquez", series: .motoGP, name: "Marc Marquez", team: "Ducati")
        ]

        let standings = calculator.standings(
            players: [player],
            picks: [pick],
            results: [result],
            events: [event],
            scope: .motoGP,
            driversBySeries: [.motoGP: liveDrivers]
        )

        XCTAssertEqual(standings.first?.points, 1)
    }

    func testSeasonChampionBonusMatchesLegacyMotoGPPickToLiveDriverID() {
        let player = TestFixtures.player(name: "Mom")
        let liveDrivers = [
            TestFixtures.driver(id: "mgp-live-bagnaia", series: .motoGP, name: "Francesco Bagnaia", team: "Ducati")
        ]
        let championPick = SeasonChampionPick(
            id: UUID(),
            series: .motoGP,
            playerID: player.id,
            driverID: "mgp-bagnaia",
            updatedAt: Date()
        )
        let championResult = SeasonChampionResult(
            series: .motoGP,
            driverID: "mgp-live-bagnaia",
            isLocked: true,
            updatedAt: Date()
        )

        let bonus = scoring.seasonChampionBonusByPlayer(
            players: [player],
            championPicks: [championPick],
            championResult: championResult,
            series: .motoGP,
            participants: liveDrivers
        )

        XCTAssertEqual(bonus[player.id], 5)
    }

    func testStandingsWithNoResultsReturnsAllPlayersAtZero() {
        let players = [TestFixtures.player(name: "A"), TestFixtures.player(name: "B")]

        let standings = calculator.standings(
            players: players, picks: [], results: [],
            events: [], scope: .combined
        )

        XCTAssertEqual(standings.count, 2)
        XCTAssertTrue(standings.allSatisfy { $0.points == 0 })
    }

    func testStandingsTieBreaksAlphabetically() {
        let zara = TestFixtures.player(name: "Zara")
        let alice = TestFixtures.player(name: "Alice")

        let standings = calculator.standings(
            players: [zara, alice], picks: [], results: [],
            events: [], scope: .combined
        )

        // Both at 0 points, should be alphabetical
        XCTAssertEqual(standings.map(\.player.name), ["Alice", "Zara"])
    }

    // MARK: - ScoreboardCalculator.leaderText

    func testLeaderTextWithNoStandings() {
        let text = calculator.leaderText(for: [])
        XCTAssertEqual(text, "No scores yet")
    }

    func testLeaderTextShowsTie() {
        let standings = [
            PlayerStanding(id: UUID(), player: Player(id: UUID(), name: "A"), points: 5),
            PlayerStanding(id: UUID(), player: Player(id: UUID(), name: "B"), points: 5)
        ]

        let text = calculator.leaderText(for: standings)
        XCTAssertEqual(text, "It's a tie at 5")
    }

    func testLeaderTextShowsLeader() {
        let standings = [
            PlayerStanding(id: UUID(), player: Player(id: UUID(), name: "Max"), points: 10),
            PlayerStanding(id: UUID(), player: Player(id: UUID(), name: "Lando"), points: 7)
        ]

        let text = calculator.leaderText(for: standings)
        XCTAssertEqual(text, "Max leads with 10")
    }
}

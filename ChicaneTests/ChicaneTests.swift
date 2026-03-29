import AppIntents
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

    func testTrackTimeZoneResolvesFromF1EventSlug() {
        let event = RaceEvent(
            id: "f1-2026-japan",
            series: .formula1,
            season: 2026,
            round: 3,
            title: "Japanese Grand Prix",
            circuit: "Unknown Circuit",
            raceDate: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(event.trackTimeZone?.identifier, "Asia/Tokyo")
    }

    func testTrackTimeZoneResolvesFromCircuitNameFallback() {
        let event = RaceEvent(
            id: "mgp-12345",
            series: .motoGP,
            season: 2026,
            round: 17,
            title: "Valencia Grand Prix",
            circuit: "Ricardo Tormo",
            raceDate: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(event.trackTimeZone?.identifier, "Europe/Madrid")
    }

    func testTrackTimeZoneCanonicalizesUppercasePayloadIdentifier() {
        let event = RaceEvent(
            id: "mgp-abc",
            series: .motoGP,
            season: 2026,
            round: 1,
            title: "Qatar Grand Prix",
            circuit: "Lusail",
            raceDate: Date(timeIntervalSince1970: 1),
            trackTimeZoneID: "ASIA/QATAR"
        )

        XCTAssertEqual(event.trackTimeZone?.identifier, "Asia/Qatar")
        XCTAssertNotNil(event.trackLocalTimeString(at: Date(timeIntervalSince1970: 1)))
    }

    func testAppSettingsDecodesLegacyPayloadWithoutPlayerBets() throws {
        let json = """
        {
          "seasonBetText": "Winner determines.",
          "spoilerGateEnabled": true,
          "spoilersDontAskAgain": false,
          "showSpoilersSection": false
        }
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.seasonBetText, "Winner determines.")
        XCTAssertTrue(settings.playerBetTextByPlayerID.isEmpty)
    }

    func testTrackLocalTimeIncludesTodayWhenTrackAndViewerShareDate() {
        let viewerTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        let event = RaceEvent(
            id: "f1-2026-usa",
            series: .formula1,
            season: 2026,
            round: 1,
            title: "US Grand Prix",
            circuit: "Austin",
            raceDate: Date(timeIntervalSince1970: 1),
            trackTimeZoneID: "America/Chicago"
        )

        let referenceDate = date(
            year: 2026,
            month: 3,
            day: 6,
            hour: 12,
            minute: 0,
            timeZoneID: "America/Los_Angeles"
        )

        let display = event.trackLocalTimeString(at: referenceDate, relativeTo: viewerTimeZone)
        XCTAssertNotNil(display)
        XCTAssertTrue(display?.contains("Today") == true)
    }

    func testTrackLocalTimeIncludesTomorrowWhenTrackIsNextDay() {
        let viewerTimeZone = TimeZone(identifier: "America/Los_Angeles")!
        let event = RaceEvent(
            id: "f1-2026-japan",
            series: .formula1,
            season: 2026,
            round: 3,
            title: "Japanese Grand Prix",
            circuit: "Suzuka",
            raceDate: Date(timeIntervalSince1970: 1),
            trackTimeZoneID: "Asia/Tokyo"
        )

        let referenceDate = date(
            year: 2026,
            month: 3,
            day: 6,
            hour: 8,
            minute: 0,
            timeZoneID: "America/Los_Angeles"
        )

        let display = event.trackLocalTimeString(at: referenceDate, relativeTo: viewerTimeZone)
        XCTAssertNotNil(display)
        XCTAssertTrue(display?.contains("Tomorrow") == true)
    }

    func testTrackLocalTimeIncludesYesterdayWhenTrackIsPriorDay() {
        let viewerTimeZone = TimeZone(identifier: "Asia/Tokyo")!
        let event = RaceEvent(
            id: "f1-2026-usa",
            series: .formula1,
            season: 2026,
            round: 1,
            title: "US Grand Prix",
            circuit: "Austin",
            raceDate: Date(timeIntervalSince1970: 1),
            trackTimeZoneID: "America/Los_Angeles"
        )

        let referenceDate = date(
            year: 2026,
            month: 3,
            day: 7,
            hour: 7,
            minute: 0,
            timeZoneID: "Asia/Tokyo"
        )

        let display = event.trackLocalTimeString(at: referenceDate, relativeTo: viewerTimeZone)
        XCTAssertNotNil(display)
        XCTAssertTrue(display?.contains("Yesterday") == true)
    }

    func testF1DriverParserParsesUniqueDriverCards() throws {
        let gaslyContext = try base64Context([
            "actionType": "driver_card_clicked",
            "driverName": "Pierre Gasly",
            "driverTeam": "Alpine"
        ])
        let norrisContext = try base64Context([
            "actionType": "driver_card_clicked",
            "driverName": "Lando Norris",
            "driverTeam": "McLaren"
        ])

        let html = """
        <a data-f1rd-a7s-click="driver_card_click" data-f1rd-a7s-context="\(gaslyContext)" href="/en/drivers/pierre-gasly">
        <a data-f1rd-a7s-click="driver_card_click" data-f1rd-a7s-context="\(norrisContext)" href="/en/drivers/lando-norris">
        <a data-f1rd-a7s-click="driver_card_click" data-f1rd-a7s-context="\(gaslyContext)" href="/en/drivers/pierre-gasly">
        """

        let drivers = F1OfficialHTMLParser.parseDrivers(from: html)
        XCTAssertEqual(drivers.count, 2)
        XCTAssertEqual(drivers.map(\.id), ["f1-lando-norris", "f1-pierre-gasly"])
    }

    func testF1CalendarParserSkipsTestingAndParsesRaceDate() throws {
        let testingContext = try base64Context([
            "raceName": "FORMULA 1 PRE-SEASON TESTING 2026",
            "trackName": "Bahrain"
        ])
        let round3Context = try base64Context([
            "raceName": "FORMULA 1 ARAMCO JAPANESE GRAND PRIX 2026",
            "trackName": "Suzuka"
        ])
        let round4Context = try base64Context([
            "raceName": "FORMULA 1 GULF AIR BAHRAIN GRAND PRIX 2026",
            "trackName": "Sakhir"
        ])

        let html = """
        <a class="group" data-f1rd-a7s-context="\(testingContext)" href="/en/racing/2026/pre-season-testing">
            <span>TESTING</span>
            <span>18 - 20 Feb</span>
        </a>
        <a class="group" data-f1rd-a7s-context="\(round3Context)" href="/en/racing/2026/japan">
            <span>ROUND 3</span>
            <span>27 - 29 Mar</span>
        </a>
        <a class="group" data-f1rd-a7s-context="\(round4Context)" href="/en/racing/2026/bahrain">
            <span>ROUND 4</span>
            <span>10 - 12 Apr</span>
        </a>
        """

        let events = F1OfficialHTMLParser.parseEvents(from: html, expectedSeason: 2026)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.round), [3, 4])
        XCTAssertEqual(events.first?.circuit, "Suzuka")

        let dateComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: events.first!.raceDate)
        XCTAssertEqual(dateComponents.year, 2026)
        XCTAssertEqual(dateComponents.month, 3)
        XCTAssertEqual(dateComponents.day, 29)
    }

    func testF1ResultsParserExtractsTopThreeDriverNames() {
        let html = """
        <table>
            <tbody>
                <tr class="Table-module_body-row__shKd-">
                    <td>1</td><td>4</td>
                    <td><span class="max-lg:hidden">Lando</span>&nbsp;<span class="max-md:hidden">Norris</span><span class="md:hidden">NOR</span></td>
                </tr>
                <tr class="Table-module_body-row__shKd-">
                    <td>2</td><td>1</td>
                    <td><span class="max-lg:hidden">Max</span>&nbsp;<span class="max-md:hidden">Verstappen</span><span class="md:hidden">VER</span></td>
                </tr>
                <tr class="Table-module_body-row__shKd-">
                    <td>3</td><td>63</td>
                    <td><span class="max-lg:hidden">George</span>&nbsp;<span class="max-md:hidden">Russell</span><span class="md:hidden">RUS</span></td>
                </tr>
            </tbody>
        </table>
        """

        let names = OnlineResultRepository.parseF1PodiumNames(from: html)
        XCTAssertEqual(names, ["Lando Norris", "Max Verstappen", "George Russell"])
    }

    func testF1ResultLinkFallbackUsesMeetingOrderForRoundLookup() {
        let repository = OnlineResultRepository()
        let event = RaceEvent(
            id: "f1-2026-miami-grand-prix",
            series: .formula1,
            season: 2026,
            round: 2,
            title: "Miami Grand Prix",
            circuit: "Miami",
            raceDate: Date(timeIntervalSince1970: 1)
        )

        let links: [F1ResultLink] = [
            F1ResultLink(season: 2026, meetingID: 3, slug: "japan-grand-prix", path: "/en/results/2026/races/1303/japan-grand-prix/race-result"),
            F1ResultLink(season: 2026, meetingID: 1, slug: "australian-grand-prix", path: "/en/results/2026/races/1301/australian-grand-prix/race-result"),
            F1ResultLink(season: 2026, meetingID: 2, slug: "miami-gp-renamed", path: "/en/results/2026/races/1302/miami-gp-renamed/race-result")
        ]

        let selected = repository.selectF1ResultLink(for: event, links: links)
        XCTAssertEqual(selected?.meetingID, 2)
        XCTAssertEqual(selected?.slug, "miami-gp-renamed")
    }

    func testMotoGPResultsEventDecodesWithNullToadUUID() throws {
        let json = """
        [
          {
            "id": "results-event-1",
            "toad_api_uuid": null,
            "test": false,
            "legacy_id": [
              { "categoryId": 3, "eventId": 1 }
            ]
          }
        ]
        """

        let payload = try JSONDecoder().decode([MotoGPResultsEventPayload].self, from: Data(json.utf8))
        XCTAssertEqual(payload.count, 1)
        XCTAssertNil(payload[0].toadAPIUUID)
        XCTAssertEqual(payload[0].legacyEventID, 1)
    }

    func testMotoGPResultsEventSelectionFallsBackToLegacyRound() {
        let repository = OnlineResultRepository()
        let event = RaceEvent(
            id: "mgp-calendar-event-uuid",
            series: .motoGP,
            season: 2026,
            round: 1,
            title: "Round 1",
            circuit: "Buriram",
            raceDate: Date(timeIntervalSince1970: 1)
        )

        let resultsEvents = [
            MotoGPResultsEventPayload(
                id: "test-event",
                toadAPIUUID: nil,
                test: true,
                sequence: nil,
                legacyIDs: [MotoGPResultsEventLegacyIDPayload(categoryID: 3, eventID: 1)]
            ),
            MotoGPResultsEventPayload(
                id: "race-event",
                toadAPIUUID: nil,
                test: false,
                sequence: nil,
                legacyIDs: [MotoGPResultsEventLegacyIDPayload(categoryID: 3, eventID: 1)]
            )
        ]

        let selected = repository.selectMotoGPResultsEvent(for: event, events: resultsEvents)
        XCTAssertEqual(selected?.id, "race-event")
    }

    func testMotoGPRaceSessionDatePrefersRACSessionDate() {
        let repository = OnlineCalendarRepository()
        let expectedRaceDate = Date(timeIntervalSince1970: 1_774_800_000)
        let sessions = [
            MotoGPRaceSessionPayload(type: "Q", date: Date(timeIntervalSince1970: 1_774_700_000), status: "FINISHED"),
            MotoGPRaceSessionPayload(type: "RAC", date: expectedRaceDate, status: "NOT-STARTED"),
            MotoGPRaceSessionPayload(type: "WUP", date: Date(timeIntervalSince1970: 1_774_750_000), status: "FINISHED")
        ]

        XCTAssertEqual(repository.preferredMotoGPRaceSessionDate(from: sessions), expectedRaceDate)
    }

    func testMotoGPRaceSessionDateIgnoresCancelledRaceSession() {
        let repository = OnlineCalendarRepository()
        let sessions = [
            MotoGPRaceSessionPayload(type: "RAC", date: Date(timeIntervalSince1970: 1_774_800_000), status: "CANCELLED"),
            MotoGPRaceSessionPayload(type: "Q", date: Date(timeIntervalSince1970: 1_774_700_000), status: "FINISHED")
        ]

        XCTAssertNil(repository.preferredMotoGPRaceSessionDate(from: sessions))
    }

    private func base64Context(_ dictionary: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return data.base64EncodedString()
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        timeZoneID: String
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components)!
    }
}

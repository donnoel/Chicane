import XCTest
@testable import Chicane

final class F1HTMLParserTests: XCTestCase {

    // MARK: - parseDrivers — malformed HTML

    func testParseDriversReturnsEmptyForNoDriverCards() {
        let html = "<html><body><p>No driver data here</p></body></html>"
        let drivers = F1OfficialHTMLParser.parseDrivers(from: html)
        XCTAssertTrue(drivers.isEmpty)
    }

    func testParseDriversSkipsMissingContextAttribute() {
        // Driver card anchor with no context attribute
        let html = """
        <a data-f1rd-a7s-click="driver_card_click" href="/en/drivers/lando-norris">
        """

        let drivers = F1OfficialHTMLParser.parseDrivers(from: html)
        XCTAssertTrue(drivers.isEmpty)
    }

    func testParseDriversSkipsInvalidBase64Context() {
        let html = """
        <a data-f1rd-a7s-click="driver_card_click" data-f1rd-a7s-context="not-valid-base64!!!" href="/en/drivers/lando-norris">
        """

        let drivers = F1OfficialHTMLParser.parseDrivers(from: html)
        XCTAssertTrue(drivers.isEmpty)
    }

    func testParseDriversSkipsEmptyDriverName() throws {
        let context = try base64Context(["driverName": "", "driverTeam": "McLaren"])

        let html = """
        <a data-f1rd-a7s-click="driver_card_click" data-f1rd-a7s-context="\(context)" href="/en/drivers/test-driver">
        """

        let drivers = F1OfficialHTMLParser.parseDrivers(from: html)
        XCTAssertTrue(drivers.isEmpty)
    }

    func testParseDriversSkipsMissingTeam() throws {
        // Context has driverName but no driverTeam
        let data = try JSONSerialization.data(withJSONObject: ["driverName": "Lando Norris"])
        let context = data.base64EncodedString()

        let html = """
        <a data-f1rd-a7s-click="driver_card_click" data-f1rd-a7s-context="\(context)" href="/en/drivers/lando-norris">
        """

        let drivers = F1OfficialHTMLParser.parseDrivers(from: html)
        XCTAssertTrue(drivers.isEmpty)
    }

    func testParseDriversHandlesEmptyString() {
        let drivers = F1OfficialHTMLParser.parseDrivers(from: "")
        XCTAssertTrue(drivers.isEmpty)
    }

    // MARK: - parseEvents — malformed HTML

    func testParseEventsReturnsEmptyForNoEventCards() {
        let html = "<html><body><p>No events here</p></body></html>"
        let events = F1OfficialHTMLParser.parseEvents(from: html, expectedSeason: 2026)
        XCTAssertTrue(events.isEmpty)
    }

    func testParseEventsSkipsCardWithNoRound() throws {
        let context = try base64Context(["raceName": "FORMULA 1 SOME GP 2026", "trackName": "Monaco"])

        let html = """
        <a class="group" data-f1rd-a7s-context="\(context)" href="/en/racing/2026/monaco">
            <span>NO ROUND HERE</span>
            <span>27 - 29 Mar</span>
        </a>
        """

        let events = F1OfficialHTMLParser.parseEvents(from: html, expectedSeason: 2026)
        XCTAssertTrue(events.isEmpty)
    }

    func testParseEventsSkipsCardWithNoDate() throws {
        let context = try base64Context(["raceName": "FORMULA 1 SOME GP 2026", "trackName": "Monaco"])

        let html = """
        <a class="group" data-f1rd-a7s-context="\(context)" href="/en/racing/2026/monaco">
            <span>ROUND 1</span>
            <span>TBD</span>
        </a>
        """

        let events = F1OfficialHTMLParser.parseEvents(from: html, expectedSeason: 2026)
        XCTAssertTrue(events.isEmpty)
    }

    func testParseEventsFiltersWrongSeason() throws {
        let context = try base64Context(["raceName": "FORMULA 1 SOME GP 2025", "trackName": "Monaco"])

        let html = """
        <a class="group" data-f1rd-a7s-context="\(context)" href="/en/racing/2025/monaco">
            <span>ROUND 1</span>
            <span>27 - 29 Mar</span>
        </a>
        """

        let events = F1OfficialHTMLParser.parseEvents(from: html, expectedSeason: 2026)
        XCTAssertTrue(events.isEmpty)
    }

    func testParseEventsHandlesYearBoundaryDate() throws {
        let context = try base64Context(["raceName": "FORMULA 1 ABU DHABI GP 2026", "trackName": "Yas Marina"])

        let html = """
        <a class="group" data-f1rd-a7s-context="\(context)" href="/en/racing/2026/abu-dhabi">
            <span>ROUND 24</span>
            <span>30 Dec - 1 Jan</span>
        </a>
        """

        let events = F1OfficialHTMLParser.parseEvents(from: html, expectedSeason: 2026)
        XCTAssertEqual(events.count, 1)

        // Race date (Jan 1) should be in 2027 since the range spans Dec→Jan
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: events.first!.raceDate)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    func testParseEventsHandlesEmptyString() {
        let events = F1OfficialHTMLParser.parseEvents(from: "", expectedSeason: 2026)
        XCTAssertTrue(events.isEmpty)
    }

    func testParseRaceSessionDetailsParsesRaceStartDateAndTimeZone() {
        let html = #"""
        <script>
        self.__next_f.push([1,"{\"race\":{\"meetingSessions\":[{\"session\":\"q\",\"shortName\":\"Qualifying\",\"startTime\":\"2026-03-07T16:00:00\",\"gmtOffset\":\"+11:00\",\"timezone\":\"Australia/Melbourne\"},{\"session\":\"r\",\"shortName\":\"Race\",\"description\":\"Race\",\"startTime\":\"2026-03-08T15:00:00\",\"endTime\":\"2026-03-08T17:00:00\",\"gmtOffset\":\"+11:00\",\"state\":\"upcoming\",\"sessionType\":\"Race\",\"timezone\":\"Australia/Melbourne\"}]}}"])
        </script>
        """#

        let details = F1OfficialHTMLParser.parseRaceSessionDetails(fromRacePageHTML: html)

        XCTAssertEqual(details?.timeZoneID, "Australia/Melbourne")
        XCTAssertEqual(details?.startDate, Date(timeIntervalSince1970: 1_772_942_400))
    }

    func testParseRaceSessionDetailsReturnsNilWithoutRaceSession() {
        let html = #"""
        <script>
        self.__next_f.push([1,"{\"race\":{\"meetingSessions\":[{\"session\":\"q\",\"shortName\":\"Qualifying\",\"startTime\":\"2026-03-07T16:00:00\",\"gmtOffset\":\"+11:00\",\"timezone\":\"Australia/Melbourne\"}]}}"])
        </script>
        """#

        XCTAssertNil(F1OfficialHTMLParser.parseRaceSessionDetails(fromRacePageHTML: html))
    }

    func testParseRaceSessionDetailsFallsBackToJSONLDRaceStartDate() {
        let html = #"""
        <script type="application/ld+json">{"@context":"http://schema.org","@type":"SportsEvent","subEvent":[{"@type":"SportsEvent","name":"Practice 1 - Miami Grand Prix","startDate":"2026-05-01T16:30:00.000Z"},{"@type":"SportsEvent","name":"Race - Miami Grand Prix","startDate":"2026-05-03T20:00:00.000Z"}]}</script>
        """#

        let details = F1OfficialHTMLParser.parseRaceSessionDetails(fromRacePageHTML: html)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = formatter.date(from: "2026-05-03T20:00:00.000Z")

        XCTAssertEqual(details?.startDate, expectedDate)
        XCTAssertNil(details?.timeZoneID)
    }

    // MARK: - parseF1PodiumNames — malformed HTML

    func testParseF1PodiumNamesReturnsEmptyForNoTable() {
        let html = "<html><body><p>No table here</p></body></html>"
        let names = OnlineResultRepository.parseF1PodiumNames(from: html)
        XCTAssertTrue(names.isEmpty)
    }

    func testParseF1PodiumNamesReturnsEmptyForEmptyTable() {
        let html = """
        <table>
            <tbody></tbody>
        </table>
        """

        let names = OnlineResultRepository.parseF1PodiumNames(from: html)
        XCTAssertTrue(names.isEmpty)
    }

    func testParseF1PodiumNamesSkipsRowsWithInsufficientCells() {
        let html = """
        <table>
            <tbody>
                <tr class="Table-module_body-row__shKd-">
                    <td>1</td><td>4</td>
                </tr>
            </tbody>
        </table>
        """

        let names = OnlineResultRepository.parseF1PodiumNames(from: html)
        XCTAssertTrue(names.isEmpty)
    }

    func testParseF1PodiumNamesIgnoresPositionsBeyondThird() {
        let html = """
        <table>
            <tbody>
                <tr class="Table-module_body-row__shKd-">
                    <td>4</td><td>55</td>
                    <td><span class="max-lg:hidden">Carlos</span>&nbsp;<span class="max-md:hidden">Sainz</span><span class="md:hidden">SAI</span></td>
                </tr>
                <tr class="Table-module_body-row__shKd-">
                    <td>5</td><td>14</td>
                    <td><span class="max-lg:hidden">Fernando</span>&nbsp;<span class="max-md:hidden">Alonso</span><span class="md:hidden">ALO</span></td>
                </tr>
            </tbody>
        </table>
        """

        let names = OnlineResultRepository.parseF1PodiumNames(from: html)
        XCTAssertTrue(names.isEmpty)
    }

    func testParseF1PodiumNamesHandlesPartialResults() {
        // Only 2 of 3 positions present — should return only those 2
        let html = """
        <table>
            <tbody>
                <tr class="Table-module_body-row__shKd-">
                    <td>1</td><td>4</td>
                    <td><span class="max-lg:hidden">Lando</span>&nbsp;<span class="max-md:hidden">Norris</span><span class="md:hidden">NOR</span></td>
                </tr>
                <tr class="Table-module_body-row__shKd-">
                    <td>3</td><td>63</td>
                    <td><span class="max-lg:hidden">George</span>&nbsp;<span class="max-md:hidden">Russell</span><span class="md:hidden">RUS</span></td>
                </tr>
            </tbody>
        </table>
        """

        let names = OnlineResultRepository.parseF1PodiumNames(from: html)
        XCTAssertEqual(names, ["Lando Norris", "George Russell"])
    }

    func testParseF1PodiumNamesHandlesEmptyString() {
        let names = OnlineResultRepository.parseF1PodiumNames(from: "")
        XCTAssertTrue(names.isEmpty)
    }

    // MARK: - parseTopThreeDriverStandings

    func testParseTopThreeDriverStandingsParsesTopThreeRows() {
        let html = """
        <table>
            <tbody class="Table-module_tbody__KEiSx">
                <tr class="Table-module_body-row__shKd-">
                    <td>1</td>
                    <td><a href="/en/results/2026/drivers/GEORUS01/george-russell"><span>George</span>&nbsp;<span>Russell</span><span>RUS</span></a></td>
                    <td>GBR</td>
                    <td><a href="/en/results/2026/team/Mercedes">Mercedes</a></td>
                    <td>51</td>
                </tr>
                <tr class="Table-module_body-row__shKd-">
                    <td>2</td>
                    <td><a href="/en/results/2026/drivers/ANDANT01/kimi-antonelli"><span>Kimi</span>&nbsp;<span>Antonelli</span><span>ANT</span></a></td>
                    <td>ITA</td>
                    <td><a href="/en/results/2026/team/Mercedes">Mercedes</a></td>
                    <td>47</td>
                </tr>
                <tr class="Table-module_body-row__shKd-">
                    <td>3</td>
                    <td><a href="/en/results/2026/drivers/CHALEC01/charles-leclerc"><span>Charles</span>&nbsp;<span>Leclerc</span><span>LEC</span></a></td>
                    <td>MON</td>
                    <td><a href="/en/results/2026/team/Ferrari">Ferrari</a></td>
                    <td>34</td>
                </tr>
            </tbody>
        </table>
        """

        let leaders = F1OfficialHTMLParser.parseTopThreeDriverStandings(from: html)

        XCTAssertEqual(leaders.count, 3)
        XCTAssertEqual(leaders[0].position, 1)
        XCTAssertEqual(leaders[0].name, "George Russell")
        XCTAssertEqual(leaders[0].team, "Mercedes")
        XCTAssertEqual(leaders[0].points, 51)
        XCTAssertEqual(leaders[2].position, 3)
        XCTAssertEqual(leaders[2].name, "Charles Leclerc")
    }

    func testParseTopThreeDriverStandingsReturnsEmptyForMissingBody() {
        let html = "<html><body>No standings table</body></html>"
        let leaders = F1OfficialHTMLParser.parseTopThreeDriverStandings(from: html)
        XCTAssertTrue(leaders.isEmpty)
    }

    // MARK: - Helpers

    private func base64Context(_ dictionary: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return data.base64EncodedString()
    }
}

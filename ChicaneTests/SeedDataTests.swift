import XCTest
@testable import Chicane

final class SeedDataTests: XCTestCase {
    func testBundledCalendarHasFullFallbackSchedules() throws {
        let payload = try loadCalendarPayload()
        let counts = Dictionary(grouping: payload.events, by: \.series).mapValues(\.count)

        XCTAssertEqual(counts[.formula1, default: 0], 22)
        XCTAssertEqual(counts[.motoGP, default: 0], 22)
    }

    func testBundledCalendarMatchesOfficial2026Rounds() throws {
        let payload = try loadCalendarPayload()

        assertEvent("f1-2026-great-britain", in: payload.events, hasRound: 9)
        assertEvent("f1-2026-belgium", in: payload.events, hasRound: 10)
        assertEvent("f1-2026-abu-dhabi", in: payload.events, hasRound: 22)
        assertEvent("mgp-2026-netherlands", in: payload.events, hasRound: 10)
        assertEvent("mgp-2026-germany", in: payload.events, hasRound: 11)
        assertEvent("mgp-2026-great-britain", in: payload.events, hasRound: 12)
        assertEvent("mgp-2026-valencia", in: payload.events, hasRound: 22)

        for series in RaceSeries.allCases {
            let rounds = payload.events
                .filter { $0.series == series }
                .map(\.round)
                .sorted()
            XCTAssertEqual(rounds, Array(1...22), "\(series.rawValue) seed rounds should be contiguous")
        }
    }

    func testBundledDriversHaveFullFallbackFields() throws {
        let payload = try loadDriverPayload()
        let counts = Dictionary(grouping: payload.drivers, by: \.series).mapValues(\.count)

        XCTAssertGreaterThanOrEqual(counts[.formula1, default: 0], 20)
        XCTAssertGreaterThanOrEqual(counts[.motoGP, default: 0], 22)
    }

    private func loadCalendarPayload() throws -> CalendarPayload {
        let url = repositoryRoot
            .appendingPathComponent("Chicane")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Seed")
            .appendingPathComponent("calendar.json")
        return try decode(CalendarPayload.self, from: url)
    }

    private func loadDriverPayload() throws -> DriverPayload {
        let url = repositoryRoot
            .appendingPathComponent("Chicane")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Seed")
            .appendingPathComponent("drivers.json")
        return try decode(DriverPayload.self, from: url)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func assertEvent(
        _ id: String,
        in events: [RaceEvent],
        hasRound expectedRound: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let event = events.first { $0.id == id }
        XCTAssertEqual(event?.round, expectedRound, file: file, line: line)
    }
}

private struct CalendarPayload: Decodable {
    let events: [RaceEvent]
}

private struct DriverPayload: Decodable {
    let drivers: [Driver]
}

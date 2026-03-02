import XCTest
@testable import Chicane

final class SeedDataTests: XCTestCase {
    func testBundledCalendarHasFullFallbackSchedules() throws {
        let payload = try loadCalendarPayload()
        let counts = Dictionary(grouping: payload.events, by: \.series).mapValues(\.count)

        XCTAssertGreaterThanOrEqual(counts[.formula1, default: 0], 24)
        XCTAssertGreaterThanOrEqual(counts[.motoGP, default: 0], 17)
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
}

private struct CalendarPayload: Decodable {
    let events: [RaceEvent]
}

private struct DriverPayload: Decodable {
    let drivers: [Driver]
}

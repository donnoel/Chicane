import Foundation
@testable import Chicane

// MARK: - Mock Repositories

final class MockDriverRepository: DriverRepository, @unchecked Sendable {
    var stubbedDrivers: [RaceSeries: [Driver]] = [:]
    var errorToThrow: Error?

    func drivers(for series: RaceSeries) async throws -> [Driver] {
        if let error = errorToThrow { throw error }
        return stubbedDrivers[series] ?? []
    }
}

final class MockCalendarRepository: CalendarRepository, @unchecked Sendable {
    var stubbedEvents: [RaceSeries: [RaceEvent]] = [:]
    var errorToThrow: Error?

    func events(for series: RaceSeries) async throws -> [RaceEvent] {
        if let error = errorToThrow { throw error }
        return stubbedEvents[series] ?? []
    }

    func allEvents() async throws -> [RaceEvent] {
        if let error = errorToThrow { throw error }
        return stubbedEvents.values.flatMap { $0 }
    }
}

final class MockResultRepository: ResultRepository, @unchecked Sendable {
    var stubbedPodiums: [String: [String]] = [:]
    var errorToThrow: Error?

    func podium(for event: RaceEvent) async throws -> [String] {
        if let error = errorToThrow { throw error }
        return stubbedPodiums[event.id] ?? []
    }
}

// MARK: - Factories

enum TestFixtures {
    static func player(name: String = "Player") -> Player {
        Player(id: UUID(), name: name)
    }

    static func event(
        id: String = "f1-r1",
        series: RaceSeries = .formula1,
        season: Int = 2026,
        round: Int = 1,
        title: String = "Test GP",
        circuit: String = "Test Circuit",
        raceDate: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> RaceEvent {
        RaceEvent(id: id, series: series, season: season, round: round, title: title, circuit: circuit, raceDate: raceDate)
    }

    static func pick(
        series: RaceSeries = .formula1,
        eventID: String = "f1-r1",
        playerID: UUID,
        p1: String = "a",
        p2: String = "b",
        p3: String = "c"
    ) -> RacePick {
        RacePick(id: UUID(), series: series, eventID: eventID, playerID: playerID, podium: Podium(p1: p1, p2: p2, p3: p3), updatedAt: Date())
    }

    static func result(
        series: RaceSeries = .formula1,
        eventID: String = "f1-r1",
        p1: String = "a",
        p2: String = "b",
        p3: String = "c",
        isLocked: Bool = true
    ) -> RaceResult {
        RaceResult(series: series, eventID: eventID, podium: Podium(p1: p1, p2: p2, p3: p3), isLocked: isLocked, updatedAt: Date())
    }

    static func driver(
        id: String = "f1-test",
        series: RaceSeries = .formula1,
        name: String = "Test Driver",
        team: String = "Test Team"
    ) -> Driver {
        Driver(id: id, series: series, name: name, team: team, number: "1")
    }
}

// MARK: - Errors for testing

enum MockError: Error {
    case simulated
}

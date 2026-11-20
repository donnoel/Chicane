import XCTest
@testable import Chicane

final class FallbackDriverRepositoryTests: XCTestCase {
    func testDriversUsePrimaryWhenPrimaryReturnsData() async throws {
        let primaryDriver = TestFixtures.driver(id: "primary-driver")
        let fallbackDriver = TestFixtures.driver(id: "fallback-driver")
        let primary = MockDriverRepository()
        primary.stubbedDrivers[.formula1] = [primaryDriver]
        let fallback = MockDriverRepository()
        fallback.stubbedDrivers[.formula1] = [fallbackDriver]
        let repository = FallbackDriverRepository(primary: primary, fallback: fallback)

        let drivers = try await repository.drivers(for: .formula1)

        XCTAssertEqual(drivers.map(\.id), [primaryDriver.id])
    }

    func testDriversUseFallbackWhenPrimaryReturnsEmpty() async throws {
        let fallbackDriver = TestFixtures.driver(id: "fallback-driver")
        let primary = MockDriverRepository()
        primary.stubbedDrivers[.formula1] = []
        let fallback = MockDriverRepository()
        fallback.stubbedDrivers[.formula1] = [fallbackDriver]
        let repository = FallbackDriverRepository(primary: primary, fallback: fallback)

        let drivers = try await repository.drivers(for: .formula1)

        XCTAssertEqual(drivers.map(\.id), [fallbackDriver.id])
    }

    func testDriversUseFallbackWhenPrimaryThrows() async throws {
        let fallbackDriver = TestFixtures.driver(id: "fallback-driver")
        let primary = MockDriverRepository()
        primary.errorToThrow = MockError.simulated
        let fallback = MockDriverRepository()
        fallback.stubbedDrivers[.formula1] = [fallbackDriver]
        let repository = FallbackDriverRepository(primary: primary, fallback: fallback)

        let drivers = try await repository.drivers(for: .formula1)

        XCTAssertEqual(drivers.map(\.id), [fallbackDriver.id])
    }
}

final class FallbackCalendarRepositoryTests: XCTestCase {
    func testSuccessfulCalendarSurvivesColdOfflineReopensAndEmptyResponses() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = MockCalendarRepository()
        let seeds = MockCalendarRepository()
        let now = ISO8601DateFormatter().date(from: "2026-11-20T18:00:00Z")!
        let vegas = TestFixtures.event(id: "vegas", series: .formula1, raceDate: now.addingTimeInterval(24 * 3600))
        let portugal = TestFixtures.event(id: "portugal", series: .motoGP, raceDate: now.addingTimeInterval(2 * 24 * 3600))
        live.stubbedEvents = [.formula1: [vegas], .motoGP: [portugal]]
        seeds.stubbedEvents = [.motoGP: [TestFixtures.event(id: "obsolete", series: .motoGP, raceDate: now)]]
        let online = FallbackCalendarRepository(primary: live, fallback: seeds, cacheDirectoryURL: directory)
        let loaded = try await online.allEvents()
        XCTAssertEqual(loaded, [vegas, portugal])
        let onlineWarning = await online.freshnessWarning()
        XCTAssertNil(onlineWarning)

        for failure in [true, false, true] {
            let unavailable = MockCalendarRepository()
            unavailable.errorToThrow = failure ? MockError.simulated : nil
            let reopened = FallbackCalendarRepository(primary: unavailable, fallback: seeds, cacheDirectoryURL: directory)
            let restored = try await reopened.allEvents()
            XCTAssertEqual(restored, loaded)
            XCTAssertEqual(RaceEvent.nextDisplayEvent(in: restored, results: [], at: now)?.id, vegas.id)
            let warning = await reopened.freshnessWarning()
            XCTAssertTrue(warning?.contains("Using saved Formula 1 calendar") == true)
            XCTAssertTrue(warning?.contains("Using saved MotoGP calendar") == true)
        }
    }

    func testUnreadableCacheUsesClearlyLabeledSeeds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid json".utf8).write(to: directory.appendingPathComponent("formula1-v1.json"))
        let seeds = MockCalendarRepository()
        let event = TestFixtures.event(id: "seed")
        seeds.stubbedEvents[.formula1] = [event]
        let repository = FallbackCalendarRepository(primary: MockCalendarRepository(), fallback: seeds, cacheDirectoryURL: directory)
        let loaded = try await repository.events(for: .formula1)
        XCTAssertEqual(loaded, [event])
        let warning = await repository.freshnessWarning()
        XCTAssertTrue(warning?.contains("Using bundled Formula 1 calendar") == true)
    }

    func testCacheSaveFailureStillReturnsLiveCalendarAndWarns() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let live = MockCalendarRepository()
        let event = TestFixtures.event(id: "live")
        live.stubbedEvents[.formula1] = [event]
        let repository = FallbackCalendarRepository(primary: live, fallback: MockCalendarRepository(), cacheDirectoryURL: directory)
        let loaded = try await repository.events(for: .formula1)
        XCTAssertEqual(loaded, [event])
        let warning = await repository.freshnessWarning()
        XCTAssertTrue(warning?.contains("offline copy could not be saved") == true)
    }

    func testEventsUsePrimaryWhenPrimaryReturnsData() async throws {
        let primaryEvent = TestFixtures.event(id: "primary-event")
        let fallbackEvent = TestFixtures.event(id: "fallback-event")
        let primary = MockCalendarRepository()
        primary.stubbedEvents[.formula1] = [primaryEvent]
        let fallback = MockCalendarRepository()
        fallback.stubbedEvents[.formula1] = [fallbackEvent]
        let repository = FallbackCalendarRepository(primary: primary, fallback: fallback)

        let events = try await repository.events(for: .formula1)

        XCTAssertEqual(events.map(\.id), [primaryEvent.id])
    }

    func testEventsUseFallbackWhenPrimaryReturnsEmpty() async throws {
        let fallbackEvent = TestFixtures.event(id: "fallback-event")
        let primary = MockCalendarRepository()
        primary.stubbedEvents[.formula1] = []
        let fallback = MockCalendarRepository()
        fallback.stubbedEvents[.formula1] = [fallbackEvent]
        let repository = FallbackCalendarRepository(primary: primary, fallback: fallback)

        let events = try await repository.events(for: .formula1)

        XCTAssertEqual(events.map(\.id), [fallbackEvent.id])
    }

    func testEventsUseFallbackWhenPrimaryThrows() async throws {
        let fallbackEvent = TestFixtures.event(id: "fallback-event")
        let primary = MockCalendarRepository()
        primary.errorToThrow = MockError.simulated
        let fallback = MockCalendarRepository()
        fallback.stubbedEvents[.formula1] = [fallbackEvent]
        let repository = FallbackCalendarRepository(primary: primary, fallback: fallback)

        let events = try await repository.events(for: .formula1)

        XCTAssertEqual(events.map(\.id), [fallbackEvent.id])
    }

    func testAllEventsFallsBackWhenPrimaryAllEventsReturnsEmpty() async throws {
        let f1Fallback = TestFixtures.event(id: "fallback-f1", series: .formula1)
        let motoGPFallback = TestFixtures.event(id: "fallback-mgp", series: .motoGP)
        let primary = MockCalendarRepository()
        let fallback = MockCalendarRepository()
        fallback.stubbedEvents[.formula1] = [f1Fallback]
        fallback.stubbedEvents[.motoGP] = [motoGPFallback]
        let repository = FallbackCalendarRepository(primary: primary, fallback: fallback)

        let events = try await repository.allEvents()

        XCTAssertEqual(Set(events.map(\.id)), Set([f1Fallback.id, motoGPFallback.id]))
    }
}

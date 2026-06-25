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

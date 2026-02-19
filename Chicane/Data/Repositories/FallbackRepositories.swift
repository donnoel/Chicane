import Foundation

struct FallbackDriverRepository: DriverRepository {
    private let primary: DriverRepository
    private let fallback: DriverRepository

    init(primary: DriverRepository, fallback: DriverRepository) {
        self.primary = primary
        self.fallback = fallback
    }

    func drivers(for series: RaceSeries) async throws -> [Driver] {
        if let online = try? await primary.drivers(for: series), !online.isEmpty {
            return online
        }
        return try await fallback.drivers(for: series)
    }
}

struct FallbackCalendarRepository: CalendarRepository {
    private let primary: CalendarRepository
    private let fallback: CalendarRepository

    init(primary: CalendarRepository, fallback: CalendarRepository) {
        self.primary = primary
        self.fallback = fallback
    }

    func events(for series: RaceSeries) async throws -> [RaceEvent] {
        if let online = try? await primary.events(for: series), !online.isEmpty {
            return online
        }
        return try await fallback.events(for: series)
    }

    func allEvents() async throws -> [RaceEvent] {
        if let online = try? await primary.allEvents(), !online.isEmpty {
            return online
        }
        return try await fallback.allEvents()
    }
}

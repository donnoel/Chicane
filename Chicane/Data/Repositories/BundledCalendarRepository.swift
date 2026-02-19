import Foundation

struct BundledCalendarRepository: CalendarRepository {
    private struct CalendarPayload: Codable {
        let events: [RaceEvent]
    }

    private let loader: BundleJSONLoader

    init(loader: BundleJSONLoader = BundleJSONLoader()) {
        self.loader = loader
    }

    func events(for series: RaceSeries) async throws -> [RaceEvent] {
        let payload = try loader.decode(CalendarPayload.self, fileName: "calendar")
        return payload.events
            .filter { $0.series == series }
            .sorted { $0.raceDate < $1.raceDate }
    }

    func allEvents() async throws -> [RaceEvent] {
        let payload = try loader.decode(CalendarPayload.self, fileName: "calendar")
        return payload.events.sorted { $0.raceDate < $1.raceDate }
    }
}

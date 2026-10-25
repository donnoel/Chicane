import Foundation
import WidgetKit
import OSLog

enum RaceWeekendWidgetSnapshotStore {
    private static let writer = RaceWeekendWidgetSnapshotWriter()

    static func saveResults(_ results: [RaceResult], events: [RaceEvent], canceledEvents: [RaceEvent] = []) {
        // apply(state:) also runs before calendars finish loading. Preserve the
        // last good schedule until the app can publish a complete replacement.
        guard !events.isEmpty, let url = RaceWeekendWidgetSnapshot.sharedURL else { return }
        let snapshot = snapshot(results: results, events: events, canceledEvents: canceledEvents)
        let requestedAt = ContinuousClock.now
        Task {
            do { try await writer.save(snapshot, to: url, requestedAt: requestedAt) }
            catch {
                Logger(subsystem: "dn.thepodium", category: "WidgetCalendar").error("Could not save widget calendar: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func snapshot(results: [RaceResult], events: [RaceEvent], canceledEvents: [RaceEvent] = []) -> RaceWeekendWidgetSnapshot {
        RaceWeekendWidgetSnapshot(
            events: events.map { event in
                WidgetRaceEvent(id: event.id, series: event.series == .formula1 ? .formula1 : .motoGP,
                                season: event.season, round: event.round, title: event.title,
                                circuit: event.circuit, raceDate: event.raceDate)
            },
            completedEventKeys: completedEventKeys(results: results.filter(\.isLocked), events: events),
            canceledEventKeys: canceledEvents.map { completedEventKey(for: $0) }.sorted()
        )
    }

    static func completedEventKeys(results: [RaceResult], events: [RaceEvent]) -> [String] {
        Set(
            results.compactMap { result in
                let resolver = StoredIdentityResolver(
                    series: result.series,
                    events: events,
                    participants: []
                )
                guard let event = resolver.resolvedEvent(for: result.eventID) else {
                    return nil
                }
                return completedEventKey(for: event)
            }
        )
        .sorted()
    }

    private static func completedEventKey(for event: RaceEvent) -> String {
        "\(event.series.rawValue)|\(event.season)|\(event.round)"
    }
}

/// Serial disk I/O stays off the UI actor. Request ordering also prevents a
/// delayed task from replacing a newer calendar/cancellation snapshot.
actor RaceWeekendWidgetSnapshotWriter {
    private var latestRequest: ContinuousClock.Instant?

    func save(_ snapshot: RaceWeekendWidgetSnapshot, to url: URL, requestedAt: ContinuousClock.Instant) throws {
        if let latestRequest, requestedAt < latestRequest { return }
        let changed = try snapshot.write(to: url)
        latestRequest = requestedAt
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: "RaceWeekendWidget") }
    }
}

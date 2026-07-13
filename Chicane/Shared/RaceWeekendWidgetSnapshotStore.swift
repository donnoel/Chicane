import Foundation
import WidgetKit

enum RaceWeekendWidgetSnapshotStore {
    static let appGroupID = "group.dn.thepodium"
    static let completedEventKeysKey = "race_weekend_widget_completed_event_keys_v2"
    private static let widgetKind = "RaceWeekendWidget"

    static func saveResults(_ results: [RaceResult], events: [RaceEvent]) {
        guard results.isEmpty || !events.isEmpty else {
            return
        }

        let completedEventKeys = completedEventKeys(results: results, events: events)

        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return
        }

        guard defaults.stringArray(forKey: completedEventKeysKey) != completedEventKeys else {
            return
        }

        defaults.set(completedEventKeys, forKey: completedEventKeysKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
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

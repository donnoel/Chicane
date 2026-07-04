import Foundation
import WidgetKit

enum RaceWeekendWidgetSnapshotStore {
    static let appGroupID = "group.dn.thepodium"
    static let resultKeysKey = "race_weekend_widget_result_keys_v1"
    private static let widgetKind = "RaceWeekendWidget"

    static func saveResults(_ results: [RaceResult]) {
        let resultKeys = results
            .map { result in "\(result.series.rawValue)|\(result.eventID)" }
            .sorted()

        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return
        }

        guard defaults.stringArray(forKey: resultKeysKey) != resultKeys else {
            return
        }

        defaults.set(resultKeys, forKey: resultKeysKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

import AppIntents
import SwiftUI

@main
struct ChicaneApp: App {
    @StateObject private var viewModel: AppViewModel

    init() {
        Self.updateSettingsVersionDisplay()

        let bundledDrivers = BundledDriverRepository()
        let bundledCalendar = BundledCalendarRepository()
        let onlineDrivers = OnlineDriverRepository()
        let onlineCalendar = OnlineCalendarRepository()
        let onlineResults = OnlineResultRepository()
        let onlineChampionships = OnlineChampionshipRepository()
        let localSeasonRepository = LocalSeasonRepository()

        let viewModel = AppViewModel(
            driverRepository: FallbackDriverRepository(
                primary: onlineDrivers,
                fallback: bundledDrivers
            ),
            calendarRepository: FallbackCalendarRepository(
                primary: onlineCalendar,
                fallback: bundledCalendar
            ),
            resultRepository: onlineResults,
            championshipRepository: onlineChampionships,
            seasonRepository: CloudSyncSeasonRepository(
                localRepository: localSeasonRepository
            )
        )
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
    private static func updateSettingsVersionDisplay() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        let displayValue: String
        if let version, !version.isEmpty {
            if let build, !build.isEmpty {
                displayValue = "\(version) (\(build))"
            } else {
                displayValue = version
            }
        } else {
            displayValue = "--"
        }

        UserDefaults.standard.set(displayValue, forKey: "app_version_display")
    }
}

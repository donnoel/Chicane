import AppIntents
import SwiftUI

@main
struct ChicaneApp: App {
    @StateObject private var viewModel: AppViewModel

    init() {
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
}

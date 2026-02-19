import SwiftUI

@main
struct ChicaneApp: App {
    @StateObject private var viewModel: AppViewModel

    init() {
        let viewModel = AppViewModel(
            driverRepository: BundledDriverRepository(),
            calendarRepository: BundledCalendarRepository(),
            seasonRepository: LocalSeasonRepository()
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

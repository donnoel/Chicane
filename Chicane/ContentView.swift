import SwiftUI

struct ContentView: View {
    var body: some View {
        RootTabView()
    }
}

#Preview {
    let viewModel = AppViewModel(
        driverRepository: BundledDriverRepository(),
        calendarRepository: BundledCalendarRepository(),
        resultRepository: OnlineResultRepository(),
        seasonRepository: LocalSeasonRepository()
    )
    ContentView()
        .environmentObject(viewModel)
}

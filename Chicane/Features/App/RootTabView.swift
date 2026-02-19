import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            TabView {
                NavigationStack {
                    HomeView()
                }
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

                NavigationStack {
                    PicksView()
                }
                .tabItem {
                    Label("Picks", systemImage: "checklist")
                }

                NavigationStack {
                    ResultsView()
                }
                .tabItem {
                    Label("Results", systemImage: "flag.checkered")
                }

                NavigationStack {
                    ScoreboardView()
                }
                .tabItem {
                    Label("Scoreboard", systemImage: "chart.bar.fill")
                }

                if viewModel.settings.showSpoilersSection {
                    NavigationStack {
                        NewsView()
                    }
                    .tabItem {
                        Label("Spoilers", systemImage: "newspaper.fill")
                    }
                }

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

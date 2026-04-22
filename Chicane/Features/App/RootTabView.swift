import SwiftUI

struct RootTabView: View {
    private enum Constants {
        static let leagueAutoSyncIntervalNanoseconds: UInt64 = 20_000_000_000
    }

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dismissBannerTask: Task<Void, Never>?

    var body: some View {
        ZStack {
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


                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .tint(.accentColor)

            // Initial-load overlay — shown only while the very first load is in flight.
            // Pull-to-refresh has its own built-in spinner so we suppress this overlay
            // once hasLoaded is true (tracked via the tab content becoming non-empty).
            if viewModel.isLoading {
                InitialLoadOverlay()
            }

            BannerOverlay(message: viewModel.banner) {
                dismissBanner(animated: true)
            }
            .padding(.top, 10)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: leagueAutoSyncTaskID) {
            await runLeagueAutoSyncLoop()
        }
        .onChange(of: viewModel.banner?.id) { _, _ in
            scheduleBannerAutoDismissIfNeeded()
        }
    }

    private func scheduleBannerAutoDismissIfNeeded() {
        dismissBannerTask?.cancel()
        guard let banner = viewModel.banner else { return }

        let seconds: UInt64?
        switch banner.style {
        case .info:
            seconds = 3
        case .error:
            // Keep errors on-screen until manually dismissed so users can read
            // and report CloudKit sync failures accurately.
            seconds = nil
        }

        guard let seconds else { return }
        dismissBannerTask = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            await MainActor.run {
                dismissBanner(animated: true)
            }
        }
    }

    private func dismissBanner(animated: Bool) {
        dismissBannerTask?.cancel()
        dismissBannerTask = nil

        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                viewModel.banner = nil
            }
        } else {
            viewModel.banner = nil
        }
    }

    private var leagueAutoSyncTaskID: String {
        let phaseLabel = scenePhase == .active ? "active" : "inactive"
        let code = viewModel.settings.leagueCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        return "\(phaseLabel)-\(code)"
    }

    private func runLeagueAutoSyncLoop() async {
        guard scenePhase == .active else { return }

        await viewModel.syncLeagueIfNeeded()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: Constants.leagueAutoSyncIntervalNanoseconds)
            } catch {
                return
            }
            guard scenePhase == .active else { return }
            await viewModel.syncLeagueIfNeeded()
        }
    }
}

// MARK: - Initial Load Overlay

/// Full-screen spinner shown during the first cold-start data load.
/// Rendered above the tab bar so the UI never looks like a blank shell.
private struct InitialLoadOverlay: View {
    var body: some View {
        ZStack {
            // Dim the tab content without completely hiding it, so the tab bar
            // items are still visible and orientation/layout settle naturally.
            Color(.systemBackground)
                .opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(.primary)

                Text("Loading…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading app data")
        }
    }
}

// MARK: - Banner

private struct BannerOverlay: View {
    let message: BannerMessage?
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            if let message {
                BannerView(message: message, onDismiss: onDismiss)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(message != nil)
    }
}

private struct BannerView: View {
    let message: BannerMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .imageScale(.medium)
                .accessibilityHidden(true)

            Text(message.text)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            Spacer(minLength: 8)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 12)
        .onTapGesture {
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var iconName: String {
        switch message.style {
        case .info:
            return "info.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

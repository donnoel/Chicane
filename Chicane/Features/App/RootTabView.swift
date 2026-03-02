import SwiftUI

struct RootTabView: View {
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
                    NewsView()
                }
                .tabItem {
                    Label("News", systemImage: "newspaper.fill")
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
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await viewModel.syncLeagueIfNeeded()
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            guard let message = newValue, !message.isEmpty else { return }
            viewModel.banner = BannerMessage(style: .error, text: message)
            viewModel.errorMessage = nil
        }
        .onChange(of: viewModel.banner?.id) { _, _ in
            scheduleBannerAutoDismissIfNeeded()
        }
    }

    private func scheduleBannerAutoDismissIfNeeded() {
        dismissBannerTask?.cancel()
        guard let banner = viewModel.banner else { return }

        let seconds: UInt64
        switch banner.style {
        case .info:
            seconds = 3
        case .error:
            seconds = 6
        }

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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 10)
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

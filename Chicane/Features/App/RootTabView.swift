import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dismissBannerTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

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
            .tint(.accentColor)

            BannerOverlay(message: viewModel.banner) {
                dismissBanner(animated: true)
            }
            .padding(.top, 10)
        }
        .task {
            await viewModel.loadIfNeeded()
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

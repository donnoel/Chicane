import SwiftUI
import UIKit

struct RootTabView: View {
    private enum Constants {
        static let leagueAutoSyncIntervalNanoseconds: UInt64 = 20_000_000_000
        static let minimumInitialSplashNanoseconds: UInt64 = 900_000_000
    }

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dismissBannerTask: Task<Void, Never>?
    @State private var hasStartedInitialLoad = false
    @State private var isInitialSplashVisible = true

    var body: some View {
        ZStack {
            TabView {
                NavigationStack {
                    HomeView()
                }
                .tabItem {
                    Label("Weekend", systemImage: "flag.checkered.2.crossed")
                }

                NavigationStack {
                    ScoreboardView()
                }
                .tabItem {
                    Label("Standings", systemImage: "chart.bar.fill")
                }

                NavigationStack {
                    ResultsView()
                }
                .tabItem {
                    Label("Results", systemImage: "flag.checkered")
                }

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .tint(.accentColor)

            if isInitialSplashVisible {
                InitialLoadOverlay()
                    .transition(.opacity)
                    .zIndex(2)
            }

            BannerOverlay(message: viewModel.banner) {
                dismissBanner(animated: true)
            }
            .padding(.top, 10)
        }
        .task {
            await performInitialLoad()
        }
        .task(id: leagueAutoSyncTaskID) {
            await runLeagueAutoSyncLoop()
        }
        .onChange(of: viewModel.banner?.id) { _, _ in
            scheduleBannerAutoDismissIfNeeded()
            announceBannerIfNeeded()
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
        let bannerID = banner.id
        dismissBannerTask = Task {
            do {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            } catch {
                return
            }
            await MainActor.run {
                guard viewModel.banner?.id == bannerID else { return }
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

    private func announceBannerIfNeeded() {
        guard let banner = viewModel.banner else { return }
        postAccessibilityAnnouncement(banner.text)
    }

    private func postAccessibilityAnnouncement(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: trimmed)
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

    private func performInitialLoad() async {
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true

        async let load: Void = viewModel.loadIfNeeded()
        async let minimumDuration: Void = waitForMinimumInitialSplashDuration()

        await load
        await minimumDuration
        guard !Task.isCancelled else { return }

        if reduceMotion {
            isInitialSplashVisible = false
        } else {
            withAnimation(.easeInOut(duration: 0.55)) {
                isInitialSplashVisible = false
            }
        }
    }

    private func waitForMinimumInitialSplashDuration() async {
        do {
            try await Task.sleep(nanoseconds: Constants.minimumInitialSplashNanoseconds)
        } catch {
            // The view is going away; no cleanup is needed.
        }
    }
}

// MARK: - Initial Load Overlay

/// Full-screen splash shown during the first cold-start data load.
/// Rendered above the tab bar so the UI never exposes partially loaded content.
private struct InitialLoadOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                Image("LaunchSplash")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(reduceMotion ? 1 : (hasAppeared ? 1.02 : 1.08))
                    .opacity(hasAppeared ? 1 : 0.88)
                    .clipped()
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.46), location: 0),
                    .init(color: .black.opacity(0.08), location: 0.36),
                    .init(color: .black.opacity(0.2), location: 0.64),
                    .init(color: .black.opacity(0.62), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack {
                Text("The Podium")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 4)
                    .padding(.top, 26)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (hasAppeared ? 0 : -8))

                Spacer()

                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)

                    Text("Preparing race weekend")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.94))
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 16)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (hasAppeared ? 0 : 12))
                .padding(.bottom, 50)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading app data")
        }
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.9)) {
                    hasAppeared = true
                }
            }
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

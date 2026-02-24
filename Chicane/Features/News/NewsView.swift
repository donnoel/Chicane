import SwiftUI
import SafariServices

// MARK: - NewsView

struct NewsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var hasConfirmedSpoilerGate  = false
    @State private var dontShowAgain            = false
    @State private var selectedSeries: RaceSeries = .formula1
    @State private var articlesBySeriesF1:      [NewsArticle] = []
    @State private var articlesBySeriesMotoGP:  [NewsArticle] = []
    @State private var isLoading  = false
    @State private var loadError: String?
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedArticle: NewsArticle?

    private let repository: NewsRepository = RSSNewsRepository()

    private var currentArticles: [NewsArticle] {
        selectedSeries == .formula1 ? articlesBySeriesF1 : articlesBySeriesMotoGP
    }

    var body: some View {
        Group {
            if shouldShowGate {
                ScrollView {
                    spoilerGate
                        .padding(24)
                }
                .chicaneBackground()
            } else {
                newsFeed
            }
        }
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedArticle) { article in
            ArticleReaderView(article: article)
        }
        .task {
            dontShowAgain = viewModel.settings.spoilersDontAskAgain
            if !isGateEnabled { hasConfirmedSpoilerGate = true }
        }
    }

    // MARK: Spoiler gate

    private var shouldShowGate: Bool { isGateEnabled && !hasConfirmedSpoilerGate }

    private var isGateEnabled: Bool {
        viewModel.settings.spoilerGateEnabled && !viewModel.settings.spoilersDontAskAgain
    }

    private var spoilerGate: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("Spoiler warning", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(ChicaneTheme.glowAmber)

            Text("This section contains the latest race news and may spoil recent results.")
                .font(.body)
                .foregroundStyle(.primary)

            Toggle("Don't show this warning again", isOn: $dontShowAgain)
                .font(.body)

            Button("Continue") {
                Task { await confirmSpoilerGate() }
            }
            .buttonStyle(LargeActionButtonStyle())
            .accessibilityHint("Opens the news feed")
        }
        .glassCard()
    }

    // MARK: News feed

    private var newsFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Picker("Series", selection: $selectedSeries) {
                    ForEach(RaceSeries.allCases) { series in
                        Text(series.title).tag(series)
                    }
                }
                .pickerStyle(.segmented)

                if isLoading && currentArticles.isEmpty {
                    loadingCard
                } else if let error = loadError, currentArticles.isEmpty {
                    errorCard(message: error)
                } else if currentArticles.isEmpty {
                    emptyCard
                } else {
                    articleList
                }
            }
            .padding(24)
            .trackingScrollOffset { scrollOffset = $0 }
        }
        .chicaneBackground(scrollOffset: scrollOffset)
        .refreshable { await loadArticles() }
        .task {
            if articlesBySeriesF1.isEmpty && articlesBySeriesMotoGP.isEmpty {
                await loadArticles()
            }
        }
        .onChange(of: selectedSeries) {
            if currentArticles.isEmpty { Task { await loadArticles() } }
        }
    }

    // MARK: Article list

    private var articleList: some View {
        VStack(spacing: 16) {
            ForEach(currentArticles) { article in
                ArticleRowView(article: article)
                    .onTapGesture { selectedArticle = article }
            }
        }
    }

    // MARK: State cards

    private var loadingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
                .tint(ChicaneTheme.seriesColor(selectedSeries))
            Text("Loading latest news…")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .glassCard()
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Could not load news", systemImage: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(ChicaneTheme.glowAmber)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await loadArticles() }
            }
            .buttonStyle(LargeActionButtonStyle())
        }
        .glassCard()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No articles found", systemImage: "newspaper")
                .font(.headline)
            Text("Pull down to refresh.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    // MARK: Data loading

    private func loadArticles() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        async let f1Task   = repository.articles(for: .formula1)
        async let motoTask = repository.articles(for: .motoGP)

        do {
            let (f1, moto) = try await (f1Task, motoTask)
            articlesBySeriesF1    = f1
            articlesBySeriesMotoGP = moto
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: Gate confirmation

    private func confirmSpoilerGate() async {
        if dontShowAgain {
            var updated = viewModel.settings
            updated.spoilersDontAskAgain = true
            do {
                try await viewModel.saveSettings(updated)
            } catch {
                viewModel.showError(error.localizedDescription)
            }
        }
        hasConfirmedSpoilerGate = true
    }
}

// MARK: - Article Row

private struct ArticleRowView: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(article.series.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ChicaneTheme.seriesColor(article.series), in: Capsule())
                Spacer()
                Text(article.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(article.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !article.description.isEmpty {
                Text(article.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Spacer()
                Label("Read more", systemImage: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ChicaneTheme.seriesColor(article.series))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            ChicaneTheme.seriesColor(article.series).opacity(0.25),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Article reader sheet

/// Full-screen sheet that shows a branded loading card while the article and
/// Reader mode finish loading, then cross-fades to the clean Safari content.
private struct ArticleReaderView: View {
    let article: NewsArticle
    @State private var isLoaded = false
    @State private var didFailToLoad = false
    @State private var loadStart = Date()
    @State private var hasTriggeredLoadedTransition = false

    var body: some View {
        ZStack {
            SafariView(url: article.url, onLoaded: { didLoadSuccessfully in
                guard !hasTriggeredLoadedTransition else { return }
                hasTriggeredLoadedTransition = true

                if !didLoadSuccessfully {
                    didFailToLoad = true
                    return
                }

                // Safari Reader mode often does a second-stage transition after the initial load.
                // Keep the branded overlay up for a minimum duration and a small settle delay
                // to avoid a blank/flash during the Reader handoff.
                let elapsed = Date().timeIntervalSince(loadStart)
                let minimumOverlay: TimeInterval = 0.65
                let settleDelay: TimeInterval = 0.30
                let remaining = max(0, minimumOverlay - elapsed)
                let totalDelay = remaining + settleDelay

                Task { @MainActor in
                    if totalDelay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
                    }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isLoaded = true
                    }
                }
            })
            .ignoresSafeArea()
            .onAppear {
                loadStart = Date()
                isLoaded = false
                didFailToLoad = false
                hasTriggeredLoadedTransition = false
            }

            if !isLoaded {
                if didFailToLoad {
                    articleLoadFailedCard
                        .transition(.opacity)
                        // Touches pass through so Safari's Done button stays reachable.
                        .allowsHitTesting(false)
                } else {
                    articleLoadingCard
                        .transition(.opacity)
                        // Touches pass through so Safari's Done button stays reachable.
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var articleLoadingCard: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text(article.series.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ChicaneTheme.seriesColor(article.series), in: Capsule())

                Text(article.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 32)

                ProgressView()
                    .tint(ChicaneTheme.seriesColor(article.series))
                    .padding(.top, 4)
            }
        }
    }

    private var articleLoadFailedCard: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Label("Couldn't load article", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(ChicaneTheme.glowAmber)

                Text(article.title)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 32)

                Link(destination: article.url) {
                    Label("Open in Safari", systemImage: "safari")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(LargeActionButtonStyle())
            }
            .padding(24)
            .glassCard()
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - In-app Safari

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onLoaded: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoaded: onLoaded) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        let vc = SFSafariViewController(url: url, configuration: configuration)
        vc.preferredControlTintColor = UIColor(ChicaneTheme.motoBlue)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onLoaded: (Bool) -> Void

        init(onLoaded: @escaping (Bool) -> Void) {
            self.onLoaded = onLoaded
        }

        func safariViewController(_ controller: SFSafariViewController,
                                  didCompleteInitialLoad didLoadSuccessfully: Bool) {
            onLoaded(didLoadSuccessfully)
        }
    }
}

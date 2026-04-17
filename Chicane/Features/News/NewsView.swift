import SwiftUI

// MARK: - NewsView

struct NewsView: View {
    @Environment(\.openURL) private var openURL
    @State private var showsEntryGate = true
    @State private var selectedSeries: RaceSeries = .formula1
    @State private var articlesBySeriesF1:      [NewsArticle] = []
    @State private var articlesBySeriesMotoGP:  [NewsArticle] = []
    @State private var isLoading  = false
    @State private var loadError: String?
    @State private var scrollOffset: CGFloat = 0

    private let repository: NewsRepository = RSSNewsRepository()

    private var currentArticles: [NewsArticle] {
        selectedSeries == .formula1 ? articlesBySeriesF1 : articlesBySeriesMotoGP
    }

    var body: some View {
        ZStack {
            newsFeed
                .blur(radius: showsEntryGate ? 14 : 0)
                .allowsHitTesting(!showsEntryGate)

            if showsEntryGate {
                entryGateOverlay
            }
        }
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            showsEntryGate = true
        }
    }

    private var entryGateOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Label("News may contain spoilers", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.glowAmber)

                Text("Latest stories can reveal recent race results. Tap below when you're ready to continue.")
                    .font(.body)
                    .foregroundStyle(.primary)

                Button("OK to Continue") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showsEntryGate = false
                    }
                }
                .buttonStyle(LargeActionButtonStyle())
                .accessibilityHint("Opens the news feed")
            }
            .glassCard(accent: ChicaneTheme.glowAmber)
            .padding(24)
        }
        .transition(.opacity)
    }

    // MARK: News feed

    private var newsFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
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
        VStack(spacing: 0) {
            ForEach(Array(currentArticles.enumerated()), id: \.element.id) { index, article in
                ArticleRowView(article: article)
                    .onTapGesture { openURL(article.url) }
                if index < currentArticles.count - 1 {
                    Divider()
                }
            }
        }
        .sectionCard()
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
        .sectionCard()
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
            .buttonStyle(SecondaryActionButtonStyle(tint: ChicaneTheme.seriesColor(selectedSeries)))
        }
        .sectionCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No articles found", systemImage: "newspaper")
                .font(.headline)
            Text("Pull down to refresh.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .sectionCard()
    }

    // MARK: Data loading

    private func loadArticles() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        async let f1Task = fetchArticles(for: .formula1)
        async let motoTask = fetchArticles(for: .motoGP)

        let (f1Result, motoResult) = await (f1Task, motoTask)
        var errors: [String] = []

        switch f1Result {
        case let .success(articles):
            articlesBySeriesF1 = articles
        case let .failure(error):
            errors.append("F1: \(error.localizedDescription)")
        }

        switch motoResult {
        case let .success(articles):
            articlesBySeriesMotoGP = articles
        case let .failure(error):
            errors.append("MotoGP: \(error.localizedDescription)")
        }

        loadError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func fetchArticles(for series: RaceSeries) async -> Result<[NewsArticle], Error> {
        do {
            return .success(try await repository.articles(for: series))
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Article Row

private struct ArticleRowView: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

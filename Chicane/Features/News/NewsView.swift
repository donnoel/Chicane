import SwiftUI

struct NewsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var hasConfirmedSpoilerGate = false
    @State private var dontShowAgain = false

    private let placeholderArticles: [SpoilerArticle] = [
        SpoilerArticle(id: "1", title: "Weekend recap placeholder", subtitle: "Connect RSS feeds in a future phase", publishedAt: "Updated after race"),
        SpoilerArticle(id: "2", title: "Driver interviews placeholder", subtitle: "No live network calls in MVP", publishedAt: "When manually added"),
        SpoilerArticle(id: "3", title: "Team strategy analysis placeholder", subtitle: "Architecture ready for a feed service", publishedAt: "Future data source")
    ]

    var body: some View {
        Group {
            if shouldShowGate {
                spoilerGate
            } else {
                spoilerList
            }
        }
        .padding(20)
        .navigationTitle("Spoilers")
        .navigationBarTitleDisplayMode(.inline)
        .chicaneBackground()
        .task {
            dontShowAgain = viewModel.settings.spoilersDontAskAgain
            if !isGateEnabled {
                hasConfirmedSpoilerGate = true
            }
        }
    }

    private var shouldShowGate: Bool {
        isGateEnabled && !hasConfirmedSpoilerGate
    }

    private var isGateEnabled: Bool {
        viewModel.settings.spoilerGateEnabled && !viewModel.settings.spoilersDontAskAgain
    }

    private var spoilerGate: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Spoiler warning", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(ChicaneTheme.glowAmber)

            Text("This section may contain spoilers. Continue?")
                .font(.title3)
                .foregroundStyle(.primary)

            Toggle("Don't show this warning again", isOn: $dontShowAgain)
                .font(.body)

            Button("Continue") {
                Task {
                    await confirmSpoilerGate()
                }
            }
            .buttonStyle(LargeActionButtonStyle())
            .accessibilityHint("Opens spoiler content")
        }
        .glassCard()
    }

    private var spoilerList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Latest News", systemImage: "newspaper")
                .font(.title2.weight(.bold))

            Text("Live articles will appear here in a future update.")
                .font(.body)
                .foregroundStyle(.secondary)

            ForEach(placeholderArticles) { article in
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title)
                        .font(.body.weight(.semibold))
                    Text(article.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(article.publishedAt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
        }
        .glassCard()
    }

    private func confirmSpoilerGate() async {
        if dontShowAgain {
            var updated = viewModel.settings
            updated.spoilersDontAskAgain = true
            do {
                try await viewModel.saveSettings(updated)
                viewModel.showInfo("Spoiler warning disabled")
            } catch {
                viewModel.showError(error.localizedDescription)
            }
        }
        hasConfirmedSpoilerGate = true
    }
}

private struct SpoilerArticle: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let publishedAt: String
}

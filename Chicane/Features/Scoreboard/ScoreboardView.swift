import SwiftUI

struct ScoreboardView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Season scoreboard")
                    .font(.title2.weight(.bold))

                Picker("Scope", selection: $selectedScope) {
                    ForEach(ScoreboardScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .tint(ChicaneTheme.motoBlue)
                .accessibilityLabel("Scoreboard scope")

                standingsCard
                historyCard
            }
            .padding(20)
            .trackingScrollOffset { scrollOffset = $0 }
        }
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.inline)
        .chicaneBackground(scrollOffset: scrollOffset)
        .refreshable {
            await viewModel.reload()
            // If reload failed it will have shown an error banner already.
            if viewModel.banner == nil {
                viewModel.showInfo("Updated")
            }
        }
    }

    private var standingsCard: some View {
        let standings = viewModel.standings(for: selectedScope)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Totals")
                .font(.headline)

            if standings.isEmpty {
                Text("No points yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    HStack {
                        Text("\(index + 1). \(standing.player.name)")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        AnimatedScoreText(value: standing.points)
                            .font(.title3.weight(.bold))
                    }
                }

                Text(viewModel.leaderText(for: selectedScope))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }
        }
        .glassCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }

    private var historyCard: some View {
        let history = viewModel.history(for: selectedScope)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Event history")
                .font(.headline)

            if history.isEmpty {
                Text("No event results entered yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(row.event.title)
                                .font(.body.weight(.semibold))
                            Spacer()
                            Text(row.series.shortTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ChicaneTheme.seriesColor(row.series), in: Capsule())
                        }

                        Text(DateFormatter.dayMonthYear.string(from: row.event.raceDate))
                            .font(.body)
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.players) { player in
                            HStack {
                                Text(player.name)
                                    .font(.body.weight(.medium))
                                Spacer()
                                AnimatedScoreText(value: row.pointsByPlayerID[player.id, default: 0], entryDelay: 0.22)
                                    .font(.body.weight(.bold))
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
        }
        .glassCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }
}

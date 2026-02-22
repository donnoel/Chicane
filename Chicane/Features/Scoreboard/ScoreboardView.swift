import SwiftUI

struct ScoreboardView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
        }
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.inline)
        .chicaneBackground()
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

        return VStack(alignment: .leading, spacing: 10) {
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
                        Text("\(standing.points)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                    }
                }

                Text(viewModel.leaderText(for: selectedScope))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }
        }
        .glassCard()
    }

    private var historyCard: some View {
        let history = viewModel.history(for: selectedScope)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Event history")
                .font(.headline)

            if history.isEmpty {
                Text("No event results entered yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history) { row in
                    VStack(alignment: .leading, spacing: 6) {
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
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.players) { player in
                            HStack {
                                Text(player.name)
                                    .font(.footnote)
                                Spacer()
                                Text("\(row.pointsByPlayerID[player.id, default: 0])")
                                    .font(.footnote.weight(.bold))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
        }
        .glassCard()
    }
}

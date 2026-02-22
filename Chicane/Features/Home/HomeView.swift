import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Picker("Series", selection: $selectedScope) {
                    ForEach(ScoreboardScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .tint(ChicaneTheme.motoBlue)
                .accessibilityLabel("Standings series")

                nextRaceCard
                standingsCard
                betCard
            }
            .padding(20)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.reload()
            // If reload failed it will have shown an error banner already.
            if viewModel.banner == nil {
                viewModel.showInfo("Updated")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ChicaneTheme.actionGradient)
                Text("Weekend Podium Bets")
                    .font(.largeTitle.weight(.bold))
                    .minimumScaleFactor(0.8)
            }
            Text("Friendly picks for Formula 1 and MotoGP")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var nextRaceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Next race", systemImage: "calendar")
                .font(.headline)

            if let event = viewModel.nextEvent(for: selectedScope) {
                Text(event.title)
                    .font(.title2.weight(.semibold))
                Text(event.circuit)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(DateFormatter.dayMonthYear.string(from: event.raceDate))
                    .font(.body.weight(.medium))
                Text(event.series.title)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                    .background(ChicaneTheme.seriesColor(event.series), in: Capsule())
            } else {
                Text("No upcoming race in the sample calendar")
                    .font(.body)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private var standingsCard: some View {
        let standings = viewModel.standings(for: selectedScope)

        return VStack(alignment: .leading, spacing: 12) {
            Label("Current standings", systemImage: "chart.bar")
                .font(.headline)

            if standings.isEmpty {
                Text("No scores yet")
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
                    .padding(.vertical, 4)
                }
            }

            Text(viewModel.leaderText(for: selectedScope))
                .font(.body.weight(.semibold))
                .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
        }
        .glassCard()
        .accessibilityElement(children: .contain)
    }

    private var betCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Season bet", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(ChicaneTheme.actionGradient)
            Text(viewModel.settings.seasonBetText)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .glassCard()
    }
}

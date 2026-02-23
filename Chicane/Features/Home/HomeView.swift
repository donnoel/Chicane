import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined
    @State private var scrollOffset: CGFloat = 0

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
            .trackingScrollOffset { scrollOffset = $0 }
        }
        .navigationTitle("")
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
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ChicaneTheme.actionGradient)
                Text("The Podium")
                    .font(.largeTitle.weight(.bold))
                    .minimumScaleFactor(0.8)
            }
            Text("Friendly picks for Formula 1 and MotoGP")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var nextRaceCard: some View {
        if let event = viewModel.nextEvent(for: selectedScope) {
            RaceCountdownCard(event: event)
                .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Next race", systemImage: "calendar")
                    .font(.headline)
                Text("No upcoming races in the calendar")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .glassCard()
        }
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
                        AnimatedScoreText(value: standing.points)
                            .font(.title3.weight(.bold))
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Text(viewModel.leaderText(for: selectedScope))
                .font(.body.weight(.semibold))
                .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
        }
        .glassCard(accent: ChicaneTheme.scopeColor(selectedScope))
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
        .glassCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }
}

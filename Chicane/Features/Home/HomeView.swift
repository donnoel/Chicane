import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
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
            .padding(24)
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
                .font(.callout)
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
                Label("Next Race", systemImage: "calendar")
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
        
        return VStack(alignment: .leading, spacing: 20) {
            Label("Current Standings", systemImage: "chart.bar")
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
                    .padding(.vertical, 8)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Bet Ledger", systemImage: "sparkles.rectangle.stack.fill")
                    .font(.headline)
                    .foregroundStyle(ChicaneTheme.actionGradient)
                Spacer()
                Text("\(viewModel.players.count) players")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if viewModel.players.isEmpty {
                Text("Add players in Settings to track each player's bet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: betLedgerColumns, spacing: 10) {
                    ForEach(Array(viewModel.players.enumerated()), id: \.element.id) { index, player in
                        let betText = playerBetText(for: player)
                        PlayerBetLedgerRow(
                            playerName: player.name,
                            betText: betText,
                            accentColor: ledgerAccentColor(at: index)
                        )
                    }
                }
            }
        }
        .glassCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }

    private var betLedgerColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
        return [GridItem(.flexible())]
    }

    private func playerBetText(for player: Player) -> String? {
        let personalBet = viewModel.settings.playerBetTextByPlayerID[player.id]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let personalBet, !personalBet.isEmpty {
            return personalBet
        }
        return nil
    }

    private func ledgerAccentColor(at index: Int) -> Color {
        switch index % 3 {
        case 0:
            return ChicaneTheme.f1Red
        case 1:
            return ChicaneTheme.motoBlue
        default:
            return ChicaneTheme.glowAmber
        }
    }
}

private struct PlayerBetLedgerRow: View {
    let playerName: String
    let betText: String?
    let accentColor: Color

    var body: some View {
        let hasBet = (betText?.isEmpty == false)

        HStack(alignment: .top, spacing: 12) {
            Text(initials(from: playerName))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(accentColor)
                        .overlay(
                            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(playerName)
                    .font(.subheadline.weight(.semibold))
                Text(hasBet ? (betText ?? "") : "No personal bet entered")
                    .font(.subheadline)
                    .foregroundStyle(hasBet ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Label(hasBet ? "Set" : "Missing", systemImage: hasBet ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(hasBet ? accentColor : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill((hasBet ? accentColor : .orange).opacity(0.16))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

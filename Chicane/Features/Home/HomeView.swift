import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                supportingModules
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .trackingScrollOffset { scrollOffset = $0 }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .chicanePremiumBackground(scrollOffset: scrollOffset)
        .refreshable {
            await viewModel.reload()
            // If reload failed it will have shown an error banner already.
            if viewModel.banner == nil {
                viewModel.showInfo("Updated")
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ChicaneTheme.actionGradient)
                Text("The Podium")
                    .font(.largeTitle.weight(.bold))
                    .minimumScaleFactor(0.8)
            }
            Text("Friendly picks for Formula 1 and MotoGP")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var supportingModules: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 20) {
                standingsCard
                    .frame(maxWidth: 330)
                betCard
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                standingsCard
                betCard
            }
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
            .groupedCard()
        }
    }
    
    private var standingsCard: some View {
        let standings = viewModel.standings(for: selectedScope)
        
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Standings")
                        .font(.headline.weight(.semibold))
                    Text(selectedScope.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }

            if let leader = standings.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Leader")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline) {
                        Text(leader.player.name)
                            .font(.title3.weight(.bold))
                        Spacer()
                        AnimatedScoreText(value: leader.points)
                            .font(.title2.weight(.bold))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ChicaneTheme.fieldFill(for: colorScheme))
                )
            }

            if standings.isEmpty {
                Text("No scores yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(standings.dropFirst().enumerated()), id: \.element.id) { index, standing in
                        HStack(spacing: 12) {
                            Text(standing.player.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            AnimatedScoreText(value: standing.points)
                                .font(.subheadline.weight(.bold))
                        }
                        .padding(.vertical, 10)

                        if index < standings.dropFirst().count - 1 {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }

            Text(viewModel.leaderText(for: selectedScope))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
        }
        .groupedCard(accent: ChicaneTheme.scopeColor(selectedScope))
        .accessibilityElement(children: .contain)
    }
    
    private var betCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bet Ledger")
                        .font(.headline.weight(.semibold))
                    Text("Who owes what this week")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(viewModel.players.count) players")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if viewModel.players.isEmpty {
                Text("Add players in Settings to track each player's bet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                LazyVGrid(columns: betLedgerColumns, spacing: 12) {
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
        .padding(.top, 4)
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

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(playerName)
                        .font(.subheadline.weight(.semibold))
                    Text(hasBet ? "Personal wager saved" : "Needs a personal wager")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            Text(hasBet ? (betText ?? "") : "No personal bet entered")
                .font(.body)
                .foregroundStyle(hasBet ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.14), lineWidth: 0.8)
                )
        )
    }

    private func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

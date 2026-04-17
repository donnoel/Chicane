import SwiftUI

struct ScoreboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Season Scoreboard")
                        .font(.title2.weight(.bold))
                    Text("Standings first, then official leaders and race-by-race scoring.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Scope", selection: $selectedScope) {
                    ForEach(ScoreboardScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .tint(ChicaneTheme.motoBlue)
                .accessibilityLabel("Scoreboard scope")

                standingsCard
                scoreboardDetailLayout
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
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

    @ViewBuilder
    private var scoreboardDetailLayout: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    officialChampionshipCard
                }
                .frame(maxWidth: 320, alignment: .leading)

                historyCard
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                officialChampionshipCard
                historyCard
            }
        }
    }

    private var standingsCard: some View {
        let standings = viewModel.standings(for: selectedScope)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Season Totals")
                        .font(.headline.weight(.semibold))
                    Text(selectedScope.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }

            if standings.isEmpty {
                Text("No points yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                if let leader = standings.first {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Leader")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(leader.player.name)
                                .font(.title3.weight(.bold))
                        }
                        Spacer()
                        AnimatedScoreText(value: leader.points)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    .padding(.bottom, 6)
                }

                VStack(spacing: 0) {
                    ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(index == 0 ? ChicaneTheme.scopeColor(selectedScope) : .secondary)
                                .frame(width: 18, alignment: .leading)
                            Text(standing.player.name)
                                .font(.body.weight(index == 0 ? .bold : .semibold))
                            Spacer()
                            AnimatedScoreText(value: standing.points)
                                .font(.body.weight(.bold))
                        }
                        .padding(.vertical, 10)

                        if index < standings.count - 1 {
                            Divider().opacity(0.28)
                        }
                    }
                }

                Text(viewModel.leaderText(for: selectedScope))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }
        }
        .glassCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }

    private var historyCard: some View {
        let history = viewModel.history(for: selectedScope)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event History")
                        .font(.headline.weight(.semibold))
                    Text("Compact race summaries")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .foregroundStyle(.secondary)
            }

            if history.isEmpty {
                Text("No event results entered yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(history) { row in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.event.title)
                                        .font(.body.weight(.semibold))
                                    Text(DateFormatter.dayMonthYear.string(from: row.event.raceDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.series.shortTitle)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ChicaneTheme.seriesColor(row.series), in: Capsule())
                            }

                            ForEach(viewModel.players) { player in
                                HStack(spacing: 12) {
                                    Text(player.name)
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    AnimatedScoreText(value: row.pointsByPlayerID[player.id, default: 0], entryDelay: 0.22)
                                        .font(.subheadline.weight(.bold))
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.thinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(ChicaneTheme.groupedStroke(for: colorScheme), lineWidth: 0.8)
                                )
                        )
                    }
                }
            }
        }
    }

    private var officialChampionshipCard: some View {
        let seriesToShow: [RaceSeries]
        if let selectedSeries = selectedScope.series {
            seriesToShow = [selectedSeries]
        } else {
            seriesToShow = [.formula1, .motoGP]
        }

        return VStack(alignment: .leading, spacing: 16) {
            Text("Official Championship Top 3")
                .font(.headline.weight(.semibold))

            if seriesToShow.allSatisfy({ viewModel.championshipLeaders(for: $0).isEmpty }) {
                Text("Leaders unavailable. Fetch Results to refresh.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(seriesToShow) { series in
                    let leaders = viewModel.championshipLeaders(for: series)
                    if !leaders.isEmpty {
                        Text(series.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ChicaneTheme.seriesColor(series))
                            .padding(.bottom, 2)

                        ForEach(leaders) { leader in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("\(leader.position). \(leader.name)")
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                    Text("\(leader.points) pts")
                                        .font(.body.weight(.bold))
                                }
                                Text(leader.team)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .groupedCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }
}

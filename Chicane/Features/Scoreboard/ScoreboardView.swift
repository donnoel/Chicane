import SwiftUI

struct ScoreboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Season Scoreboard")
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
                officialChampionshipCard
                historyCard
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

    private var standingsCard: some View {
        let standings = viewModel.standings(for: selectedScope)

        return VStack(alignment: .leading, spacing: 14) {
            Label("Season Totals", systemImage: "trophy")
                .font(.headline)

            if standings.isEmpty {
                Text("No points yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    HStack {
                        Text("\(index + 1). \(standing.player.name)")
                            .font(.body.weight(.semibold))
                        Spacer()
                        AnimatedScoreText(value: standing.points)
                            .font(.body.weight(.bold))
                    }
                    if index < standings.count - 1 {
                        Divider().opacity(0.35)
                    }
                }

                Text(viewModel.leaderText(for: selectedScope))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }
        }
        .sectionCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }

    private var historyCard: some View {
        let history = viewModel.history(for: selectedScope)

        return VStack(alignment: .leading, spacing: 14) {
            Label("Event History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.headline)

            if history.isEmpty {
                Text("No event results entered yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().opacity(0.3)
                    }
                    VStack(alignment: .leading, spacing: 14) {
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
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(ChicaneTheme.groupedStroke(for: colorScheme), lineWidth: 0.8)
                            )
                    )
                }
            }
        }
        .sectionCard()
    }

    private var officialChampionshipCard: some View {
        let seriesToShow: [RaceSeries]
        if let selectedSeries = selectedScope.series {
            seriesToShow = [selectedSeries]
        } else {
            seriesToShow = [.formula1, .motoGP]
        }

        return VStack(alignment: .leading, spacing: 14) {
            Label("Official Championship Top 3", systemImage: "flag.checkered")
                .font(.headline)

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
                            HStack {
                                Text("\(leader.position). \(leader.name)")
                                    .font(.body.weight(.semibold))
                                Spacer()
                                Text("\(leader.points) pts")
                                    .font(.body.weight(.bold))
                            }
                            Divider().opacity(0.2)

                            Text(leader.team)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 6)
                        }
                    }
                }
            }
        }
        .sectionCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }
}

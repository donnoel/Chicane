import SwiftUI

struct ScoreboardView: View {
    private struct ScoreboardDerivedData {
        let standings: [PlayerStanding]
        let history: [EventScoreRow]
        let leaderText: String
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedScope: ScoreboardScope = .combined
    @State private var championDraftsBySeries: [RaceSeries: [UUID: String]] = [:]
    @State private var derivedData: ScoreboardDerivedData?

    var body: some View {
        let derived = derivedData ?? makeDerivedData()

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

                standingsCard(
                    standings: derived.standings,
                    leaderText: derived.leaderText
                )
                scoreboardDetailLayout(history: derived.history)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
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
        .task {
            hydrateChampionDrafts()
            refreshDerivedData()
        }
        .onChange(of: selectedScope) {
            hydrateChampionDrafts()
            refreshDerivedData()
        }
        .onChange(of: viewModel.players) {
            hydrateChampionDrafts()
            refreshDerivedData()
        }
        .onChange(of: viewModel.championPicks) {
            hydrateChampionDrafts()
            refreshDerivedData()
        }
        .onChange(of: viewModel.picks) {
            refreshDerivedData()
        }
        .onChange(of: viewModel.results) {
            refreshDerivedData()
        }
        .onChange(of: viewModel.championResults) {
            refreshDerivedData()
        }
        .onChange(of: viewModel.eventsBySeries) {
            refreshDerivedData()
        }
        .onChange(of: viewModel.driversBySeries) {
            refreshDerivedData()
        }
    }

    @ViewBuilder
    private func scoreboardDetailLayout(history: [EventScoreRow]) -> some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    seasonChampionPicksCard
                    officialChampionshipCard
                }
                .frame(maxWidth: 320, alignment: .leading)

                historyCard(history: history)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                seasonChampionPicksCard
                officialChampionshipCard
                historyCard(history: history)
            }
        }
    }

    private func standingsCard(
        standings: [PlayerStanding],
        leaderText: String
    ) -> some View {
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

                Text(leaderText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }
        }
        .glassCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }

    private var seasonChampionPicksCard: some View {
        let seriesToShow = championSeriesToShow

        return VStack(alignment: .leading, spacing: 12) {
            Text("Season Champion Picks")
                .font(.headline.weight(.semibold))

            if viewModel.players.isEmpty {
                Text("No players yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(seriesToShow) { series in
                    VStack(alignment: .leading, spacing: 6) {
                        if seriesToShow.count > 1 {
                            Text(series.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ChicaneTheme.seriesColor(series))
                        }

                        let participants = viewModel.drivers(for: series)
                        let picksAreLocked = viewModel.championResult(for: series)?.isLocked ?? false

                        ForEach(viewModel.players) { player in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                    .font(.footnote.weight(.semibold))

                                ChampionPickerSection(
                                    title: "",
                                    drivers: participants,
                                    participantSingular: series == .motoGP ? "rider" : "driver",
                                    selection: championBinding(for: series, playerID: player.id),
                                    isDisabled: picksAreLocked
                                )

                                championStatusText(for: player, series: series)
                            }

                            if player.id != viewModel.players.last?.id {
                                Divider().opacity(0.24)
                            }
                        }
                    }

                    if series != seriesToShow.last {
                        Divider().opacity(0.28)
                    }
                }
            }
        }
        .groupedCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }

    private func historyCard(history: [EventScoreRow]) -> some View {
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
                LazyVStack(spacing: 12) {
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

    private var championSeriesToShow: [RaceSeries] {
        if let selectedSeries = selectedScope.series {
            return [selectedSeries]
        } else {
            return [.formula1, .motoGP]
        }
    }

    private func makeDerivedData() -> ScoreboardDerivedData {
        let standings = viewModel.standings(for: selectedScope)
        return ScoreboardDerivedData(
            standings: standings,
            history: viewModel.history(for: selectedScope),
            leaderText: viewModel.leaderText(for: standings)
        )
    }

    private func refreshDerivedData() {
        derivedData = makeDerivedData()
    }

    private func championBinding(for series: RaceSeries, playerID: UUID) -> Binding<String?> {
        Binding(
            get: { championDraft(for: series, playerID: playerID) },
            set: { newValue in
                setChampionDraft(newValue, for: series, playerID: playerID)
                guard let player = viewModel.players.first(where: { $0.id == playerID }) else { return }
                autosaveChampionPickIfNeeded(for: player, series: series, driverID: newValue)
            }
        )
    }

    private func championDraft(for series: RaceSeries, playerID: UUID) -> String? {
        championDraftsBySeries[series]?[playerID]
    }

    private func setChampionDraft(_ driverID: String?, for series: RaceSeries, playerID: UUID) {
        var drafts = championDraftsBySeries[series] ?? [:]
        if let driverID {
            drafts[playerID] = driverID
        } else {
            drafts.removeValue(forKey: playerID)
        }
        championDraftsBySeries[series] = drafts
    }

    private func hydrateChampionDrafts() {
        let currentPlayerIDs = Set(viewModel.players.map(\.id))
        championDraftsBySeries = championDraftsBySeries.reduce(into: [RaceSeries: [UUID: String]]()) { output, entry in
            let filtered = entry.value.filter { currentPlayerIDs.contains($0.key) }
            if !filtered.isEmpty {
                output[entry.key] = filtered
            }
        }

        for series in RaceSeries.allCases {
            var updated = championDraftsBySeries[series] ?? [:]
            for player in viewModel.players {
                let savedSelection = viewModel.championPick(for: series, playerID: player.id)?.driverID
                let currentSelection = updated[player.id]

                if currentSelection == nil || currentSelection == savedSelection {
                    if let savedSelection {
                        updated[player.id] = savedSelection
                    } else {
                        updated.removeValue(forKey: player.id)
                    }
                }
            }
            championDraftsBySeries[series] = updated
        }
    }

    private func autosaveChampionPickIfNeeded(for player: Player, series: RaceSeries, driverID: String?) {
        guard let driverID else { return }
        guard viewModel.championResult(for: series)?.isLocked != true else { return }

        let savedDriverID = viewModel.championPick(for: series, playerID: player.id)?.driverID
        guard savedDriverID != driverID else { return }

        Task {
            await saveChampionPick(for: player, series: series)
        }
    }

    private func championStatusText(for player: Player, series: RaceSeries) -> some View {
        Group {
            if viewModel.championResult(for: series)?.isLocked == true {
                Label("Locked once the official season champion is entered.", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }
        }
    }

    private func saveChampionPick(for player: Player, series: RaceSeries) async {
        guard let driverID = championDraft(for: series, playerID: player.id) else { return }

        do {
            let warning = try await viewModel.saveChampionPick(
                series: series,
                playerID: player.id,
                driverID: driverID
            )
            viewModel.showSaveOutcome(
                warning: warning,
                successMessage: "Saved \(player.name)'s world champion pick."
            )
            setChampionDraft(
                viewModel.championPick(for: series, playerID: player.id)?.driverID,
                for: series,
                playerID: player.id
            )
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}

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
    @State private var savedChampionDraftsBySeries: [RaceSeries: [UUID: String]] = [:]
    @State private var pendingChampionLock: ChampionLockRequest?

    private struct ChampionLockRequest: Identifiable {
        let player: Player
        let series: RaceSeries
        let driverID: String

        var id: String {
            "\(series.rawValue)-\(player.id.uuidString)"
        }
    }

    var body: some View {
        scoreboardContent
            .navigationTitle("Standings")
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
            }
            .onChange(of: selectedScope) {
                hydrateChampionDrafts()
            }
            .onChange(of: viewModel.players) {
                hydrateChampionDrafts()
            }
            .onChange(of: viewModel.championPicks) {
                hydrateChampionDrafts()
            }
            .alert("Lock champion pick?", isPresented: championLockConfirmationIsPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Lock Pick") { confirmPendingChampionLock() }
            } message: {
                Text(pendingChampionLock.map(championLockMessage) ?? "")
            }
    }

    private var championLockConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingChampionLock != nil },
            set: { isPresented in
                if !isPresented {
                    pendingChampionLock = nil
                }
            }
        )
    }

    private var scoreboardContent: some View {
        let derived = makeDerivedData()

        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Standings")
                        .font(ChicaneTypography.screenTitle)
                    Text("Who's winning now, with details below when you want them.")
                        .font(ChicaneTypography.subtitle)
                        .foregroundStyle(.secondary)
                }

                scopePicker
                standingsCard(
                    standings: derived.standings,
                    leaderText: derived.leaderText
                )
                scoreboardDetailLayout(history: derived.history)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $selectedScope) {
            ForEach(ScoreboardScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .tint(ChicaneTheme.motoBlue)
        .accessibilityLabel("Scoreboard scope")
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
                        .font(ChicaneTypography.cardTitle)
                    Text(selectedScope.title)
                        .font(ChicaneTypography.subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }

            if standings.isEmpty {
                Text("No points yet")
                    .font(ChicaneTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                let leaderPoints = standings.first?.points ?? 0

                if let leader = standings.first {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Leader")
                                .font(ChicaneTypography.captionSemibold)
                                .foregroundStyle(.secondary)
                            Text(leader.player.name)
                                .font(ChicaneTypography.cardTitleStrong)
                        }
                        Spacer()
                        AnimatedScoreText(value: leader.points)
                            .font(ChicaneTypography.leaderScore)
                    }
                    .padding(.bottom, 6)
                }

                VStack(spacing: 0) {
                    ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(ChicaneTypography.captionBold)
                                .foregroundStyle(index == 0 ? ChicaneTheme.scopeColor(selectedScope) : .secondary)
                                .frame(width: 18, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(standing.player.name)
                                    .font(index == 0 ? ChicaneTypography.bodyBold : ChicaneTypography.bodySemibold)
                                if index > 0 {
                                    Text("\(leaderPoints - standing.points) back")
                                        .font(ChicaneTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            AnimatedScoreText(value: standing.points)
                                .font(ChicaneTypography.score)
                        }
                        .padding(.vertical, 10)

                        if index < standings.count - 1 {
                            Divider().opacity(0.28)
                        }
                    }
                }

                Text(leaderText)
                    .font(ChicaneTypography.footnoteSemibold)
                    .foregroundStyle(ChicaneTheme.scopeColor(selectedScope))
            }
        }
        .glassCard(accent: ChicaneTheme.scopeColor(selectedScope))
    }

    private var seasonChampionPicksCard: some View {
        let seriesToShow = championSeriesToShow

        return VStack(alignment: .leading, spacing: 12) {
            Text("Season Champion Picks")
                .font(ChicaneTypography.cardTitle)

            if viewModel.players.isEmpty {
                Text("No players yet")
                    .font(ChicaneTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(seriesToShow) { series in
                    VStack(alignment: .leading, spacing: 6) {
                        if seriesToShow.count > 1 {
                            Text(series.title)
                                .font(ChicaneTypography.sectionTitle)
                                .foregroundStyle(ChicaneTheme.seriesColor(series))
                        }

                        let participants = viewModel.drivers(for: series)
                        let seriesIsLocked = viewModel.championResult(for: series)?.isLocked ?? false

                        ForEach(viewModel.players) { player in
                            let pick = viewModel.championPick(for: series, playerID: player.id)
                            let pickIsLocked = seriesIsLocked || pick?.isLocked == true

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .center, spacing: 8) {
                                    Text(player.name)
                                        .font(ChicaneTypography.footnoteSemibold)
                                    Spacer()
                                    if !pickIsLocked {
                                        championLockButton(for: player, series: series)
                                    }
                                }

                                ChampionPickerSection(
                                    title: "",
                                    drivers: participants,
                                    participantSingular: series == .motoGP ? "rider" : "driver",
                                    selection: championBinding(for: series, playerID: player.id),
                                    isDisabled: pickIsLocked
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

    private func championLockButton(for player: Player, series: RaceSeries) -> some View {
        Button {
            guard let driverID = championDraft(for: series, playerID: player.id) else { return }
            pendingChampionLock = ChampionLockRequest(
                player: player,
                series: series,
                driverID: driverID
            )
        } label: {
            Image(systemName: "lock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(.thinMaterial)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(championDraft(for: series, playerID: player.id) == nil)
        .accessibilityLabel("Lock \(series.title) champion pick for \(player.name)")
        .accessibilityHint("Makes this champion pick final")
    }

    private func historyCard(history: [EventScoreRow]) -> some View {
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event History")
                        .font(ChicaneTypography.cardTitle)
                    Text("Compact race summaries")
                        .font(ChicaneTypography.subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .foregroundStyle(.secondary)
            }

            if history.isEmpty {
                Text("No event results entered yet")
                    .font(ChicaneTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(history) { row in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.event.title)
                                        .font(ChicaneTypography.bodySemibold)
                                    Text(DateFormatter.dayMonthYear.string(from: row.event.raceDate))
                                        .font(ChicaneTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.series.shortTitle)
                                    .font(ChicaneTypography.badgeStrong)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ChicaneTheme.seriesColor(row.series), in: Capsule())
                            }

                            ForEach(viewModel.players) { player in
                                HStack(spacing: 12) {
                                    Text(player.name)
                                        .font(ChicaneTypography.subtitleMedium)
                                    Spacer()
                                    AnimatedScoreText(value: row.pointsByPlayerID[player.id, default: 0], entryDelay: 0.22)
                                        .font(ChicaneTypography.subtitleSemibold)
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
                .font(ChicaneTypography.cardTitle)

            if seriesToShow.allSatisfy({ viewModel.championshipLeaders(for: $0).isEmpty }) {
                Text("Leaders unavailable. Fetch Results to refresh.")
                    .font(ChicaneTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(seriesToShow) { series in
                    let leaders = viewModel.championshipLeaders(for: series)
                    if !leaders.isEmpty {
                        Text(series.title)
                            .font(ChicaneTypography.sectionTitle)
                            .foregroundStyle(ChicaneTheme.seriesColor(series))
                            .padding(.bottom, 2)

                        ForEach(leaders) { leader in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("\(leader.position). \(leader.name)")
                                        .font(ChicaneTypography.bodySemibold)
                                    Spacer()
                                    Text("\(leader.points) pts")
                                        .font(ChicaneTypography.bodyBold)
                                }
                                Text(leader.team)
                                    .font(ChicaneTypography.caption)
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
        savedChampionDraftsBySeries = savedChampionDraftsBySeries.reduce(into: [RaceSeries: [UUID: String]]()) { output, entry in
            let filtered = entry.value.filter { currentPlayerIDs.contains($0.key) }
            if !filtered.isEmpty {
                output[entry.key] = filtered
            }
        }

        for series in RaceSeries.allCases {
            let currentDrafts = championDraftsBySeries[series] ?? [:]
            let previousSavedDrafts = savedChampionDraftsBySeries[series] ?? [:]
            var updatedDrafts: [UUID: String] = [:]
            var updatedSavedDrafts: [UUID: String] = [:]
            for player in viewModel.players {
                let savedSelection = viewModel.championPick(for: series, playerID: player.id)?.driverID
                let currentSelection = currentDrafts[player.id]
                let previousSavedSelection = previousSavedDrafts[player.id]

                if let savedSelection {
                    updatedSavedDrafts[player.id] = savedSelection
                }
                if DraftHydrationDecision.shouldAdoptSavedSelection(
                    current: currentSelection,
                    previousSaved: previousSavedSelection,
                    saved: savedSelection
                ) {
                    if let savedSelection {
                        updatedDrafts[player.id] = savedSelection
                    }
                } else if let currentSelection {
                    updatedDrafts[player.id] = currentSelection
                }
            }
            championDraftsBySeries[series] = updatedDrafts
            savedChampionDraftsBySeries[series] = updatedSavedDrafts
        }
    }

    private func autosaveChampionPickIfNeeded(for player: Player, series: RaceSeries, driverID: String?) {
        let isLocked = viewModel.championResult(for: series)?.isLocked == true
        let savedPick = viewModel.championPick(for: series, playerID: player.id)
        let savedDriverID = savedPick?.driverID
        guard AutosaveDecision.shouldAutosaveChampionPick(
            selectedDriverID: driverID,
            savedDriverID: savedDriverID,
            isLocked: isLocked || savedPick?.isLocked == true
        ) else { return }

        Task {
            await saveChampionPick(for: player, series: series)
        }
    }

    @ViewBuilder
    private func championStatusText(for player: Player, series: RaceSeries) -> some View {
        let savedPick = viewModel.championPick(for: series, playerID: player.id)

        Group {
            if viewModel.championResult(for: series)?.isLocked == true {
                Label("Locked once the official season champion is entered.", systemImage: "lock.fill")
                    .font(ChicaneTypography.caption2)
                    .foregroundStyle(.secondary)
            } else if savedPick?.isLocked == true {
                Label("Locked in.", systemImage: "lock.fill")
                    .font(ChicaneTypography.caption2)
                    .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }
        }
    }

    private func championLockMessage(for request: ChampionLockRequest) -> String {
        "Lock \(request.player.name)'s \(request.series.title) champion pick? This pick will become final."
    }

    private func confirmPendingChampionLock() {
        guard let request = pendingChampionLock else { return }
        confirmChampionLock(request)
        pendingChampionLock = nil
    }

    private func confirmChampionLock(_ request: ChampionLockRequest) {
        Task {
            await lockChampionPick(request)
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
            if let warning, !warning.isEmpty {
                viewModel.showError(warning)
            }
            setChampionDraft(
                viewModel.championPick(for: series, playerID: player.id)?.driverID,
                for: series,
                playerID: player.id
            )
            let savedSelection = viewModel.championPick(for: series, playerID: player.id)?.driverID
            var savedDrafts = savedChampionDraftsBySeries[series] ?? [:]
            if let savedSelection {
                savedDrafts[player.id] = savedSelection
            } else {
                savedDrafts.removeValue(forKey: player.id)
            }
            savedChampionDraftsBySeries[series] = savedDrafts
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func lockChampionPick(_ request: ChampionLockRequest) async {
        do {
            let warning = try await viewModel.saveChampionPick(
                series: request.series,
                playerID: request.player.id,
                driverID: request.driverID,
                isLocked: true
            )
            viewModel.showSaveOutcome(
                warning: warning,
                successMessage: "Locked \(request.player.name)'s world champion pick."
            )
            setChampionDraft(
                viewModel.championPick(for: request.series, playerID: request.player.id)?.driverID,
                for: request.series,
                playerID: request.player.id
            )
            let savedSelection = viewModel.championPick(for: request.series, playerID: request.player.id)?.driverID
            var savedDrafts = savedChampionDraftsBySeries[request.series] ?? [:]
            if let savedSelection {
                savedDrafts[request.player.id] = savedSelection
            } else {
                savedDrafts.removeValue(forKey: request.player.id)
            }
            savedChampionDraftsBySeries[request.series] = savedDrafts
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}

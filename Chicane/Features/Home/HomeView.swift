import SwiftUI

struct HomeView: View {
    private enum Constants {
        static let weekendQueueWindow: TimeInterval = 3 * 24 * 3600
    }

    private struct DisplayedPlayerBet: Identifiable {
        let player: Player
        let text: String

        var id: UUID {
            player.id
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedEventID: String?
    @State private var selectedPlayerID: UUID?
    @State private var draftsByPlayer: [UUID: PodiumDraft] = [:]
    @State private var savedDraftsByPlayer: [UUID: PodiumDraft] = [:]
    @State private var hasInitialized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let selectedEvent {
                    hero(for: selectedEvent)
                    pickFlow(for: selectedEvent)
                    weekendQueueCard
                    standingsPreview
                    if !playerBetRows.isEmpty {
                        playerBetsPreview
                    }
                    allRacesLink
                } else {
                    emptyCalendarCard
                    allRacesLink
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 110)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .chicanePremiumBackground()
        .refreshable {
            await viewModel.reload()
            if viewModel.banner == nil {
                viewModel.showInfo("Updated")
            }
        }
        .task {
            guard !hasInitialized else { return }
            hasInitialized = true
            initializeIfNeeded()
        }
        .onChange(of: viewModel.eventsBySeries) {
            initializeIfNeeded()
        }
        .onChange(of: selectedEventID) {
            hydrateDrafts()
            ensureSelectedPlayer()
        }
        .onChange(of: viewModel.players) {
            hydrateAvailablePicks()
            ensureSelectedPlayer()
        }
        .onChange(of: viewModel.picks) {
            hydrateAvailablePicks()
            ensureSelectedPlayer()
        }
        .onChange(of: viewModel.results) {
            hydrateAvailablePicks()
            ensureSelectedPlayer()
        }
    }

    private var raceQueue: [RaceEvent] {
        let events = viewModel.allEvents()
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let visibleEvents = events.filter { $0.raceDate >= startOfToday }

        guard let firstVisibleEvent = visibleEvents.first else {
            return events.last.map { [$0] } ?? []
        }

        let weekendEnd = firstVisibleEvent.raceDate.addingTimeInterval(Constants.weekendQueueWindow)
        return visibleEvents.filter { $0.raceDate <= weekendEnd }
    }

    private var selectedEvent: RaceEvent? {
        if let selectedEventID {
            return raceQueue.first { $0.id == selectedEventID }
        }
        return raceQueue.first
    }

    private var selectedPlayer: Player? {
        guard let selectedPlayerID else { return viewModel.players.first }
        return viewModel.players.first { $0.id == selectedPlayerID } ?? viewModel.players.first
    }

    private var playerBetRows: [DisplayedPlayerBet] {
        viewModel.players.compactMap { player in
            let text = viewModel.settings.playerBetTextByPlayerID[player.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return DisplayedPlayerBet(player: player, text: text)
        }
    }

    private var isPhoneLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var allRacesLink: some View {
        NavigationLink {
            PicksView()
        } label: {
            Label("Manage race and champion picks", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(SecondaryActionButtonStyle(tint: .accentColor))
        .accessibilityHint("Opens the full race picker for older or custom entries")
    }

    private var emptyCalendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No race calendar", systemImage: "calendar.badge.exclamationmark")
                .font(ChicaneTypography.cardTitle)
            Text("Pull to refresh, or check Settings if the calendar still does not load.")
                .font(ChicaneTypography.body)
                .foregroundStyle(.secondary)
        }
        .groupedCard()
    }

    private func hero(for event: RaceEvent) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Race Weekend")
                        .font(ChicaneTypography.heroEyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.82))
                    Text("Next up")
                        .font(ChicaneTypography.heroKicker)
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(event.series.shortTitle)
                    .font(ChicaneTypography.chip)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(ChicaneTypography.heroTitle(isPhoneLayout: isPhoneLayout))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.circuit)
                    .font(ChicaneTypography.heroSubtitle)
                    .foregroundStyle(.white.opacity(0.84))
            }

            HStack(alignment: .center, spacing: 12) {
                startTimePill(for: event)
                Spacer(minLength: 8)
                pickProgressPill(for: event)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(heroGradient(for: event))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
        )
        .shadow(color: ChicaneTheme.seriesColor(event.series).opacity(0.24), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Race weekend. Next up, \(event.accessibilitySummary)")
    }

    private var weekendQueueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(raceQueue.count > 1 ? "This weekend" : "Pick queue")
                        .font(ChicaneTypography.cardTitle)
                    Text(raceQueue.count > 1 ? "Start with the earliest race, then move to the next." : "Chicane starts with the next race automatically.")
                        .font(ChicaneTypography.subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(currentQueueIndex + 1) of \(max(raceQueue.count, 1))")
                    .font(ChicaneTypography.captionBold)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(Array(raceQueue.enumerated()), id: \.element.id) { index, event in
                    queueRow(event: event, index: index)
                }
            }
        }
        .groupedCard(accent: selectedEvent.map { ChicaneTheme.seriesColor($0.series) } ?? .accentColor)
    }

    private func queueRow(event: RaceEvent, index: Int) -> some View {
        Button {
            selectedEventID = event.id
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(ChicaneTypography.captionHeavy)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(ChicaneTheme.seriesColor(event.series), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(ChicaneTypography.subtitleSemibold)
                        .foregroundStyle(.primary)
                    Text(queueDateText(for: event))
                        .font(ChicaneTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if allPlayersReady(for: event) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(ChicaneTheme.seriesColor(event.series))
                        .accessibilityLabel("Ready")
                } else if selectedEventID == event.id {
                    Text("Now")
                        .font(ChicaneTypography.badgeStrong)
                        .foregroundStyle(ChicaneTheme.seriesColor(event.series))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ChicaneTheme.seriesColor(event.series).opacity(0.14), in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Race \(index + 1), \(event.title)")
        .accessibilityHint("Selects this race for podium picks")
    }

    @ViewBuilder
    private func pickFlow(for event: RaceEvent) -> some View {
        if viewModel.players.isEmpty {
            noPlayersCard
        } else if let player = selectedPlayer {
            VStack(alignment: .leading, spacing: 16) {
                pickFlowHeader(for: event)
                playerPickerStrip(for: event)
                activePlayerCard(player: player, event: event)
                nextActionRow(for: player, event: event)
            }
            .glassCard(accent: ChicaneTheme.seriesColor(event.series))
        }
    }

    private func pickFlowHeader(for event: RaceEvent) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make your picks")
                    .font(ChicaneTypography.screenTitle)
                Text("\(readyPlayerCount(for: event)) of \(viewModel.players.count) players ready")
                    .font(ChicaneTypography.subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SeriesArtwork(series: event.series)
        }
    }

    private func playerPickerStrip(for event: RaceEvent) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.players) { player in
                    Button {
                        selectedPlayerID = player.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(initials(from: player.name))
                                .font(ChicaneTypography.initialsSmall)
                                .foregroundStyle(.white)
                                .frame(width: 25, height: 25)
                                .background(playerAccent(for: player, event: event), in: Circle())

                            Text(player.name)
                                .font(ChicaneTypography.captionSemibold)
                                .lineLimit(1)

                            if playerIsReady(player, for: event) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(ChicaneTypography.caption)
                            }
                        }
                        .foregroundStyle(selectedPlayerID == player.id ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedPlayerID == player.id ? playerAccent(for: player, event: event) : Color.primary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(player.name) picks")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func activePlayerCard(player: Player, event: RaceEvent) -> some View {
        let picksAreLocked = viewModel.resultIsLocked(for: event.series, eventID: event.id)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(initials(from: player.name))
                    .font(ChicaneTypography.initialsLarge)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(playerAccent(for: player, event: event), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(ChicaneTypography.cardTitleStrong)
                    if picksAreLocked {
                        Text("Locked after official result")
                            .font(ChicaneTypography.subtitle)
                            .foregroundStyle(.secondary)
                    } else if playerIsReady(player, for: event) {
                        Text("Saved automatically")
                            .font(ChicaneTypography.subtitle)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                statusBadge(
                    title: picksAreLocked ? "Locked" : (playerIsReady(player, for: event) ? "Ready" : "Open"),
                    tint: picksAreLocked ? .green : playerAccent(for: player, event: event)
                )
            }

            PodiumPickerSection(
                title: "Podium",
                drivers: viewModel.drivers(for: event.series),
                participantSingular: participantSingular(for: event.series),
                participantPlural: participantPlural(for: event.series),
                draft: binding(for: player.id, event: event),
                isDisabled: picksAreLocked
            )

            if picksAreLocked {
                Label("Locked once official results are retrieved.", systemImage: "lock.fill")
                    .font(ChicaneTypography.footnoteSemibold)
                    .foregroundStyle(.secondary)
            }
        }
        .groupedCard(accent: playerAccent(for: player, event: event))
    }

    @ViewBuilder
    private func nextActionRow(for player: Player, event: RaceEvent) -> some View {
        let currentComplete = playerIsReady(player, for: event)
        let weekendReady = allPlayersReady(for: event)

        HStack(spacing: 10) {
            if currentComplete, let nextActionTitle = nextActionTitle(for: player, event: event) {
                Button(nextActionTitle) {
                    advanceAfterCurrentPlayer(player, event: event)
                }
                .buttonStyle(LargeActionButtonStyle(tint: ChicaneTheme.seriesColor(event.series)))
                .accessibilityHint("Moves to the next unfinished picker or race")
            } else if !currentComplete {
                Label("Picks save automatically when P1, P2, and P3 are set.", systemImage: "checkmark.circle")
                    .font(ChicaneTypography.footnoteSemibold)
                    .foregroundStyle(.secondary)
            }

            if weekendReady && nextQueuedEvent(after: event) == nil {
                Label("Weekend ready", systemImage: "flag.checkered")
                    .font(ChicaneTypography.footnoteBold)
                    .foregroundStyle(ChicaneTheme.seriesColor(event.series))
            }
        }
    }

    private var noPlayersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add players to start", systemImage: "person.2")
                .font(ChicaneTypography.cardTitle)
            Text("Once players are set up, this screen becomes the one-stop place for podium picks.")
                .font(ChicaneTypography.body)
                .foregroundStyle(.secondary)

            NavigationLink {
                SettingsView()
            } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: .accentColor))
        }
        .groupedCard()
    }

    private var standingsPreview: some View {
        let standings = viewModel.standings(for: .combined)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Who's winning")
                        .font(ChicaneTypography.cardTitle)
                    Text("Combined standings")
                        .font(ChicaneTypography.subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink {
                    ScoreboardView()
                } label: {
                    Label("Standings", systemImage: "chart.bar.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: ChicaneTheme.glowAmber))
                .frame(width: 54)
                .accessibilityLabel("Open standings")
            }

            if standings.isEmpty {
                Text("No points yet")
                    .font(ChicaneTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(standings.prefix(3).enumerated()), id: \.element.id) { index, standing in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(ChicaneTypography.captionHeavy)
                            .foregroundStyle(index == 0 ? ChicaneTheme.glowAmber : .secondary)
                            .frame(width: 20)
                        Text(standing.player.name)
                            .font(index == 0 ? ChicaneTypography.bodyBold : ChicaneTypography.bodySemibold)
                        Spacer()
                        AnimatedScoreText(value: standing.points)
                            .font(ChicaneTypography.score)
                    }

                    if index < min(standings.count, 3) - 1 {
                        Divider().opacity(0.28)
                    }
                }
            }
        }
        .groupedCard(accent: ChicaneTheme.glowAmber)
    }

    private var playerBetsPreview: some View {
        let bets = playerBetRows

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Player bets")
                    .font(ChicaneTypography.cardTitle)
                Text("Settled after the final season points are tallied")
                    .font(ChicaneTypography.subtitle)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(bets.enumerated()), id: \.element.id) { index, bet in
                VStack(alignment: .leading, spacing: 6) {
                    Text(bet.player.name)
                        .font(ChicaneTypography.bodySemibold)
                    Text(bet.text)
                        .font(ChicaneTypography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if index < bets.count - 1 {
                    Divider().opacity(0.28)
                }
            }
        }
        .groupedCard(accent: .accentColor)
        .accessibilityElement(children: .contain)
    }

    private var currentQueueIndex: Int {
        guard let selectedEvent else { return 0 }
        return raceQueue.firstIndex(where: { $0.id == selectedEvent.id }) ?? 0
    }

    private func startTimePill(for event: RaceEvent) -> some View {
        Label(queueDateText(for: event), systemImage: "clock")
            .font(ChicaneTypography.chip)
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private func pickProgressPill(for event: RaceEvent) -> some View {
        Text(viewModel.players.isEmpty ? "Add players" : "\(readyPlayerCount(for: event))/\(viewModel.players.count) ready")
            .font(ChicaneTypography.chip)
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private func heroGradient(for event: RaceEvent) -> LinearGradient {
        let seriesColor = ChicaneTheme.seriesColor(event.series)
        return LinearGradient(
            colors: [
                seriesColor.opacity(0.96),
                ChicaneTheme.deepNavy.opacity(0.96),
                ChicaneTheme.glowAmber.opacity(event.series == .formula1 ? 0.82 : 0.64)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func queueDateText(for event: RaceEvent) -> String {
        HomeRaceDateFormatter.shared.string(from: event.raceDate)
    }

    private func participantSingular(for series: RaceSeries) -> String {
        series == .motoGP ? "rider" : "driver"
    }

    private func participantPlural(for series: RaceSeries) -> String {
        series == .motoGP ? "riders" : "drivers"
    }

    private func readyPlayerCount(for event: RaceEvent) -> Int {
        viewModel.players.filter { playerIsReady($0, for: event) }.count
    }

    private func allPlayersReady(for event: RaceEvent) -> Bool {
        !viewModel.players.isEmpty && readyPlayerCount(for: event) == viewModel.players.count
    }

    private func playerIsReady(_ player: Player, for event: RaceEvent) -> Bool {
        if viewModel.pick(for: event.series, eventID: event.id, playerID: player.id) != nil {
            return true
        }
        return draftsByPlayer[player.id]?.toPodium() != nil
    }

    private func playerAccent(for player: Player, event: RaceEvent) -> Color {
        playerIsReady(player, for: event) ? ChicaneTheme.seriesColor(event.series) : .secondary
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(ChicaneTypography.badgeStrong)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private func nextActionTitle(for player: Player, event: RaceEvent) -> String? {
        if nextIncompletePlayer(after: player, event: event) != nil {
            return "Next Player"
        }
        if nextQueuedEvent(after: event) != nil {
            return "Next Race"
        }
        return nil
    }

    private func advanceAfterCurrentPlayer(_ player: Player, event: RaceEvent) {
        if let nextPlayer = nextIncompletePlayer(after: player, event: event) {
            selectedPlayerID = nextPlayer.id
            return
        }

        if let nextEvent = nextQueuedEvent(after: event) {
            selectedEventID = nextEvent.id
            hydrateDrafts(for: nextEvent)
            selectFirstOpenPlayer(for: nextEvent)
            return
        }

        viewModel.showInfo("Weekend picks are ready.")
    }

    private func nextIncompletePlayer(after player: Player, event: RaceEvent) -> Player? {
        let players = viewModel.players
        guard let currentIndex = players.firstIndex(where: { $0.id == player.id }) else {
            return players.first { !playerIsReady($0, for: event) }
        }

        for offset in 1...players.count {
            let candidate = players[(currentIndex + offset) % players.count]
            if !playerIsReady(candidate, for: event) {
                return candidate
            }
        }
        return nil
    }

    private func nextQueuedEvent(after event: RaceEvent) -> RaceEvent? {
        guard let currentIndex = raceQueue.firstIndex(where: { $0.id == event.id }) else {
            return nil
        }
        let nextIndex = raceQueue.index(after: currentIndex)
        guard nextIndex < raceQueue.count else { return nil }
        return raceQueue[nextIndex]
    }

    private func binding(for playerID: UUID, event: RaceEvent) -> Binding<PodiumDraft> {
        Binding(
            get: { draftsByPlayer[playerID] ?? .empty },
            set: { newDraft in
                draftsByPlayer[playerID] = newDraft
                guard let player = viewModel.players.first(where: { $0.id == playerID }) else { return }
                autosavePickIfNeeded(for: player, event: event, draft: newDraft)
            }
        )
    }

    private func initializeIfNeeded() {
        guard selectedEventID == nil || !raceQueue.contains(where: { $0.id == selectedEventID }) else {
            hydrateDrafts()
            ensureSelectedPlayer()
            return
        }

        selectedEventID = raceQueue.first?.id
        hydrateDrafts()
        ensureSelectedPlayer()
    }

    private func ensureSelectedPlayer() {
        guard let selectedEvent else {
            selectedPlayerID = viewModel.players.first?.id
            return
        }

        if let selectedPlayerID, viewModel.players.contains(where: { $0.id == selectedPlayerID }) {
            return
        }

        selectFirstOpenPlayer(for: selectedEvent)
    }

    private func selectFirstOpenPlayer(for event: RaceEvent) {
        selectedPlayerID = viewModel.players.first(where: { !playerIsReady($0, for: event) })?.id
            ?? viewModel.players.first?.id
    }

    private func hydrateDrafts() {
        guard let selectedEvent else {
            draftsByPlayer = [:]
            savedDraftsByPlayer = [:]
            return
        }
        hydrateDrafts(for: selectedEvent)
    }

    private func hydrateDrafts(for event: RaceEvent) {
        var updated: [UUID: PodiumDraft] = [:]
        for player in viewModel.players {
            if let pick = viewModel.pick(for: event.series, eventID: event.id, playerID: player.id) {
                updated[player.id] = PodiumDraft(podium: pick.podium)
            } else {
                updated[player.id] = .empty
            }
        }
        draftsByPlayer = updated
        savedDraftsByPlayer = updated
    }

    private func hydrateAvailablePicks() {
        guard let selectedEvent else {
            draftsByPlayer = [:]
            savedDraftsByPlayer = [:]
            return
        }

        var updatedDrafts: [UUID: PodiumDraft] = [:]
        var updatedSavedDrafts: [UUID: PodiumDraft] = [:]
        for player in viewModel.players {
            let savedDraft: PodiumDraft
            if let pick = viewModel.pick(for: selectedEvent.series, eventID: selectedEvent.id, playerID: player.id) {
                savedDraft = PodiumDraft(podium: pick.podium)
            } else {
                savedDraft = .empty
            }

            let currentDraft = draftsByPlayer[player.id] ?? .empty
            let previousSavedDraft = savedDraftsByPlayer[player.id] ?? .empty
            updatedSavedDrafts[player.id] = savedDraft
            if DraftHydrationDecision.shouldAdoptSavedDraft(
                current: currentDraft,
                previousSaved: previousSavedDraft,
                saved: savedDraft,
                empty: PodiumDraft.empty
            ) {
                updatedDrafts[player.id] = savedDraft
            } else {
                updatedDrafts[player.id] = currentDraft
            }
        }
        draftsByPlayer = updatedDrafts
        savedDraftsByPlayer = updatedSavedDrafts
    }

    private func autosavePickIfNeeded(for player: Player, event: RaceEvent, draft: PodiumDraft) {
        guard !viewModel.resultIsLocked(for: event.series, eventID: event.id) else { return }

        let savedDraft: PodiumDraft
        if let savedPick = viewModel.pick(for: event.series, eventID: event.id, playerID: player.id) {
            savedDraft = PodiumDraft(podium: savedPick.podium)
        } else {
            savedDraft = .empty
        }

        guard AutosaveDecision.shouldAutosavePodiumPick(draft: draft, savedDraft: savedDraft) else { return }

        Task {
            await savePick(for: player, event: event, draft: draft)
        }
    }

    private func savePick(for player: Player, event: RaceEvent, draft: PodiumDraft) async {
        do {
            let warning = try await viewModel.savePick(
                series: event.series,
                eventID: event.id,
                playerID: player.id,
                draft: draft
            )
            viewModel.showSaveOutcome(
                warning: warning,
                successMessage: "Saved \(player.name)'s picks for \(event.title)."
            )
            guard selectedEvent?.id == event.id else { return }
            if let savedPick = viewModel.pick(for: event.series, eventID: event.id, playerID: player.id) {
                let savedDraft = PodiumDraft(podium: savedPick.podium)
                draftsByPlayer[player.id] = savedDraft
                savedDraftsByPlayer[player.id] = savedDraft
            } else {
                draftsByPlayer[player.id] = .empty
                savedDraftsByPlayer[player.id] = .empty
            }
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}

private struct SeriesArtwork: View {
    let series: RaceSeries

    var body: some View {
        Image(series.artworkName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: 34)
            .alignmentGuide(.firstTextBaseline) { context in
                context[VerticalAlignment.center]
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var width: CGFloat {
        series == .formula1 ? 58 : 46
    }
}

private enum HomeRaceDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

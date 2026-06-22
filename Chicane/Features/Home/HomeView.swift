import SwiftUI

struct HomeView: View {
    private enum Constants {
        static let weekendQueueWindow: TimeInterval = 3 * 24 * 3600
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedEventID: String?
    @State private var selectedPlayerID: UUID?
    @State private var draftsByPlayer: [UUID: PodiumDraft] = [:]
    @State private var hasInitialized = false
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let selectedEvent {
                    hero(for: selectedEvent)
                    pickFlow(for: selectedEvent)
                    weekendQueueCard
                    standingsPreview
                    allRacesLink
                } else {
                    emptyCalendarCard
                    allRacesLink
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 110)
            .trackingScrollOffset { scrollOffset = $0 }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .chicanePremiumBackground(scrollOffset: scrollOffset)
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
            hydrateDrafts()
            ensureSelectedPlayer()
        }
        .onChange(of: viewModel.picks) {
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

    private var isPhoneLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var allRacesLink: some View {
        NavigationLink {
            PicksView()
        } label: {
            Label("All races and manual picks", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(SecondaryActionButtonStyle(tint: .accentColor))
        .accessibilityHint("Opens the full race picker for older or custom entries")
    }

    private var emptyCalendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No race calendar", systemImage: "calendar.badge.exclamationmark")
                .font(.headline)
            Text("Pull to refresh, or check Settings if the calendar still does not load.")
                .font(.body)
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
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.82))
                    Text("Next up")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(event.series.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.system(size: isPhoneLayout ? 28 : 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.circuit)
                    .font(.headline.weight(.semibold))
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
                        .font(.headline.weight(.semibold))
                    Text(raceQueue.count > 1 ? "Start with the earliest race, then move to the next." : "Chicane starts with the next race automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(currentQueueIndex + 1) of \(max(raceQueue.count, 1))")
                    .font(.caption.weight(.bold))
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
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(ChicaneTheme.seriesColor(event.series), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(queueDateText(for: event))
                        .font(.caption)
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
                        .font(.caption2.weight(.bold))
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
                    .font(.title2.weight(.bold))
                Text("\(readyPlayerCount(for: event)) of \(viewModel.players.count) players ready")
                    .font(.subheadline)
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
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                                .frame(width: 25, height: 25)
                                .background(playerAccent(for: player, event: event), in: Circle())

                            Text(player.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            if playerIsReady(player, for: event) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(initials(from: player.name))
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(playerAccent(for: player, event: event), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.title3.weight(.bold))
                    Text(playerIsReady(player, for: event) ? "Saved automatically" : "Choose P1, P2, and P3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(
                    title: playerIsReady(player, for: event) ? "Ready" : "Open",
                    tint: playerAccent(for: player, event: event)
                )
            }

            PodiumPickerSection(
                title: participantPrompt(for: event),
                drivers: viewModel.drivers(for: event.series),
                participantSingular: participantSingular(for: event.series),
                participantPlural: participantPlural(for: event.series),
                draft: binding(for: player.id, event: event)
            )
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
                Label("Picks save as soon as all three spots are unique.", systemImage: "checkmark.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if weekendReady && nextQueuedEvent(after: event) == nil {
                Label("Weekend ready", systemImage: "flag.checkered")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(ChicaneTheme.seriesColor(event.series))
            }
        }
    }

    private var noPlayersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add players to start", systemImage: "person.2")
                .font(.headline)
            Text("Once players are set up, this screen becomes the one-stop place for podium picks.")
                .font(.body)
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
                        .font(.headline.weight(.semibold))
                    Text("Combined standings")
                        .font(.subheadline)
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
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(standings.prefix(3).enumerated()), id: \.element.id) { index, standing in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.black))
                            .foregroundStyle(index == 0 ? ChicaneTheme.glowAmber : .secondary)
                            .frame(width: 20)
                        Text(standing.player.name)
                            .font(.body.weight(index == 0 ? .bold : .semibold))
                        Spacer()
                        AnimatedScoreText(value: standing.points)
                            .font(.body.weight(.bold))
                    }

                    if index < min(standings.count, 3) - 1 {
                        Divider().opacity(0.28)
                    }
                }
            }
        }
        .groupedCard(accent: ChicaneTheme.glowAmber)
    }

    private var currentQueueIndex: Int {
        guard let selectedEvent else { return 0 }
        return raceQueue.firstIndex(where: { $0.id == selectedEvent.id }) ?? 0
    }

    private func startTimePill(for event: RaceEvent) -> some View {
        Label(queueDateText(for: event), systemImage: "clock")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private func pickProgressPill(for event: RaceEvent) -> some View {
        Text(viewModel.players.isEmpty ? "Add players" : "\(readyPlayerCount(for: event))/\(viewModel.players.count) ready")
            .font(.caption.weight(.bold))
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

    private func participantPrompt(for event: RaceEvent) -> String {
        "Pick 3 unique \(participantPlural(for: event.series))"
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
            .font(.caption2.weight(.bold))
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
    }

    private func hydrateAvailablePicks() {
        guard let selectedEvent else { return }

        for player in viewModel.players {
            let savedDraft: PodiumDraft
            if let pick = viewModel.pick(for: selectedEvent.series, eventID: selectedEvent.id, playerID: player.id) {
                savedDraft = PodiumDraft(podium: pick.podium)
            } else {
                savedDraft = .empty
            }

            let currentDraft = draftsByPlayer[player.id] ?? .empty
            if currentDraft == .empty || currentDraft == savedDraft {
                draftsByPlayer[player.id] = savedDraft
            }
        }
    }

    private func autosavePickIfNeeded(for player: Player, event: RaceEvent, draft: PodiumDraft) {
        let savedDraft: PodiumDraft
        if let savedPick = viewModel.pick(for: event.series, eventID: event.id, playerID: player.id) {
            savedDraft = PodiumDraft(podium: savedPick.podium)
        } else {
            savedDraft = .empty
        }

        guard AutosaveDecision.shouldAutosavePodiumPick(draft: draft, savedDraft: savedDraft) else { return }

        Task {
            await savePick(for: player, event: event)
        }
    }

    private func savePick(for player: Player, event: RaceEvent) async {
        guard let draft = draftsByPlayer[player.id] else { return }

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
            if let savedPick = viewModel.pick(for: event.series, eventID: event.id, playerID: player.id) {
                draftsByPlayer[player.id] = PodiumDraft(podium: savedPick.podium)
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

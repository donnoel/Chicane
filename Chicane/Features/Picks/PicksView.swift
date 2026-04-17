import SwiftUI

struct PicksView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var selectedSeries: RaceSeries = .formula1
    @State private var selectedEventID: String?
    @State private var draftsByPlayer: [UUID: PodiumDraft] = [:]
    @State private var championDraftsBySeries: [RaceSeries: [UUID: String]] = [:]
    @State private var scrollOffset: CGFloat = 0
    @State private var hasInitialized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EventPickerHeader(
                    title: "Podium Picks",
                    selectedSeries: $selectedSeries,
                    selectedEventID: $selectedEventID,
                    events: events,
                    eventPickerLabel: "Race event"
                )

                if let selectedEvent {
                    EventSummaryCard(event: selectedEvent, subtitleOpacity: 0.88)
                    playerCards
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No event selected", systemImage: "calendar")
                            .font(.headline)
                        Text("Choose an event above to enter picks.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .groupedCard()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .trackingScrollOffset { scrollOffset = $0 }
        }
        .navigationTitle("Picks")
        .navigationBarTitleDisplayMode(.inline)
        .chicaneBackground(scrollOffset: scrollOffset)
        .task {
            guard !hasInitialized else { return }
            hasInitialized = true
            initializeIfNeeded()
        }
        .onChange(of: eventIDs) {
            ensureValidSelection()
            hydrateDrafts()
        }
        .onChange(of: selectedSeries) {
            initializeSelectionForSeries()
            hydrateDrafts()
            hydrateChampionDrafts()
        }
        .onChange(of: selectedEventID) {
            hydrateDrafts()
        }
        .onChange(of: viewModel.players) {
            hydrateDrafts()
            hydrateChampionDrafts()
        }
        .onChange(of: viewModel.picks) {
            hydrateAvailablePicks()
        }
        .onChange(of: viewModel.championPicks) {
            hydrateAvailableChampionPicks()
        }
    }

    private var events: [RaceEvent] {
        viewModel.events(for: selectedSeries)
    }

    private var eventIDs: [String] {
        events.map(\.id)
    }

    private var selectedEvent: RaceEvent? {
        guard let selectedEventID else { return nil }
        return events.first(where: { $0.id == selectedEventID })
    }

    private var drivers: [Driver] {
        viewModel.drivers(for: selectedSeries)
    }

    private var participantSingular: String {
        selectedSeries == .motoGP ? "rider" : "driver"
    }

    private var participantPlural: String {
        selectedSeries == .motoGP ? "riders" : "drivers"
    }

    private var championPicksAreLocked: Bool {
        viewModel.championResult(for: selectedSeries)?.isLocked ?? false
    }

    private var championDraftsByPlayer: [UUID: String] {
        championDraftsBySeries[selectedSeries] ?? [:]
    }

    private var isPhoneLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var playerCards: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(viewModel.players) { player in
                playerCard(for: player)
            }
        }
    }

    private func playerCard(for player: Player) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLayout ? 14 : 16) {
            playerHeader(for: player)

            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 18) {
                    championPane(for: player, grouped: true)
                        .frame(maxWidth: 290, alignment: .leading)
                    podiumPane(for: player, grouped: true)
                }
            } else {
                championPane(for: player, grouped: false)
                Divider().opacity(0.22)
                podiumPane(for: player, grouped: false)
            }
        }
        .sectionCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private func playerHeader(for player: Player) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(initials(from: player.name))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(ChicaneTheme.seriesColor(selectedSeries))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(.title3.weight(.bold))
                Text(selectedEvent?.title ?? "Champion and podium picks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isPhoneLayout {
                statusBadge(
                    title: playerSummaryStatus(for: player),
                    tint: playerStatusTint(for: player)
                )
            } else {
                VStack(alignment: .trailing, spacing: 8) {
                    statusBadge(
                        title: championPicksAreLocked
                            ? "Champion Locked"
                            : (viewModel.championPick(for: selectedSeries, playerID: player.id) != nil ? "Champion Saved" : "Champion Open"),
                        tint: championPicksAreLocked
                            ? .green
                            : (viewModel.championPick(for: selectedSeries, playerID: player.id) != nil ? ChicaneTheme.seriesColor(selectedSeries) : .secondary)
                    )

                    statusBadge(
                        title: viewModel.pick(for: selectedSeries, eventID: selectedEventID ?? "", playerID: player.id) != nil ? "Podium Saved" : "Podium Open",
                        tint: viewModel.pick(for: selectedSeries, eventID: selectedEventID ?? "", playerID: player.id) != nil ? ChicaneTheme.seriesColor(selectedSeries) : .secondary
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func championPane(for player: Player, grouped: Bool) -> some View {
        let content = VStack(alignment: .leading, spacing: isPhoneLayout ? 10 : 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("World Champion")
                    .font(.headline.weight(.semibold))
                Spacer()
                statusBadge(
                    title: championPicksAreLocked ? "Locked" : "Season pick",
                    tint: championPicksAreLocked ? .green : .secondary
                )
            }

            ChampionPickerSection(
                title: "Champion pick",
                drivers: drivers,
                participantSingular: participantSingular,
                selection: championBinding(for: player.id),
                isDisabled: championPicksAreLocked
            )

            championStatusText(for: player)

            Button("Save \(player.name)'s Champion Pick") {
                Task {
                    await saveChampionPick(for: player)
                }
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: ChicaneTheme.seriesColor(selectedSeries)))
            .disabled(championDraftsByPlayer[player.id] == nil || championPicksAreLocked)
            .accessibilityLabel("Save world champion pick for \(player.name)")
        }

        if grouped {
            content.groupedCard()
        } else {
            content
        }
    }

    @ViewBuilder
    private func podiumPane(for player: Player, grouped: Bool) -> some View {
        let content = VStack(alignment: .leading, spacing: isPhoneLayout ? 10 : 12) {
            HStack {
                Text("Race Podium")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("Pick P1, P2, P3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            PodiumPickerSection(
                title: "Podium picks",
                drivers: drivers,
                participantSingular: participantSingular,
                participantPlural: participantPlural,
                draft: binding(for: player.id)
            )

            podiumStatusText(for: player)

            Button("Save \(player.name)'s Picks") {
                Task {
                    await savePick(for: player)
                }
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: ChicaneTheme.seriesColor(selectedSeries)))
            .disabled(!(draftsByPlayer[player.id] ?? .empty).isComplete)
            .accessibilityLabel("Save picks for \(player.name)")
        }

        if grouped {
            content.groupedCard()
        } else {
            content
        }
    }

    private func playerSummaryStatus(for player: Player) -> String {
        let championSaved = viewModel.championPick(for: selectedSeries, playerID: player.id) != nil
        let podiumSaved = viewModel.pick(for: selectedSeries, eventID: selectedEventID ?? "", playerID: player.id) != nil

        if championPicksAreLocked && podiumSaved {
            return "Ready"
        }
        if championSaved && podiumSaved {
            return "Ready"
        }
        if championSaved || podiumSaved {
            return "In Progress"
        }
        return "Open"
    }

    private func playerStatusTint(for player: Player) -> Color {
        let summary = playerSummaryStatus(for: player)
        switch summary {
        case "Ready":
            return ChicaneTheme.seriesColor(selectedSeries)
        case "In Progress":
            return .secondary
        default:
            return .secondary
        }
    }

    private func championStatusText(for player: Player) -> some View {
        Group {
            if championPicksAreLocked {
                Label("Locked once the official season champion is entered.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.championPick(for: selectedSeries, playerID: player.id) != nil {
                Label("Saved and still editable until the season champion is entered.", systemImage: "flag.checkered.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("Choose one \(participantSingular) for the season title.", systemImage: "person.crop.square")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func podiumStatusText(for player: Player) -> some View {
        Group {
            if viewModel.pick(for: selectedSeries, eventID: selectedEventID ?? "", playerID: player.id) != nil {
                Label("Saved. Edit and save again anytime before results are locked.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("Choose three unique \(participantPlural) in finishing order.", systemImage: "list.number")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private func binding(for playerID: UUID) -> Binding<PodiumDraft> {
        Binding(
            get: { draftsByPlayer[playerID] ?? .empty },
            set: { draftsByPlayer[playerID] = $0 }
        )
    }

    private func championBinding(for playerID: UUID) -> Binding<String?> {
        Binding(
            get: { championDraft(for: playerID) },
            set: { newValue in
                setChampionDraft(newValue, for: playerID)
            }
        )
    }

    private func championDraft(for playerID: UUID) -> String? {
        championDraftsBySeries[selectedSeries]?[playerID]
    }

    private func setChampionDraft(_ driverID: String?, for playerID: UUID) {
        var drafts = championDraftsBySeries[selectedSeries] ?? [:]
        if let driverID {
            drafts[playerID] = driverID
        } else {
            drafts.removeValue(forKey: playerID)
        }
        championDraftsBySeries[selectedSeries] = drafts
    }

    private func initializeIfNeeded() {
        if selectedEventID == nil {
            initializeSelectionForSeries()
        }
        ensureValidSelection()
        hydrateDrafts()
        hydrateChampionDrafts()
    }

    private func initializeSelectionForSeries() {
        let now = Date()
        // Default to the next upcoming event (most likely needs picks entered).
        // If the season is complete, fall back to the most recent event.
        if let next = events.filter({ $0.raceDate >= now }).min(by: { $0.raceDate < $1.raceDate }) {
            selectedEventID = next.id
        } else {
            selectedEventID = events.max(by: { $0.raceDate < $1.raceDate })?.id
        }
    }

    private func ensureValidSelection() {
        guard !events.isEmpty else { return }
        guard let selectedEventID, eventIDs.contains(selectedEventID) else {
            initializeSelectionForSeries()
            return
        }
    }

    private func hydrateDrafts() {
        guard let selectedEventID else {
            draftsByPlayer = [:]
            return
        }

        var updated: [UUID: PodiumDraft] = [:]
        for player in viewModel.players {
            if let pick = viewModel.pick(for: selectedSeries, eventID: selectedEventID, playerID: player.id) {
                updated[player.id] = PodiumDraft(podium: pick.podium)
            } else {
                updated[player.id] = .empty
            }
        }
        draftsByPlayer = updated
    }

    private func hydrateChampionDrafts() {
        let currentPlayerIDs = Set(viewModel.players.map(\.id))
        championDraftsBySeries = championDraftsBySeries.reduce(into: [RaceSeries: [UUID: String]]()) { output, entry in
            let filtered = entry.value.filter { currentPlayerIDs.contains($0.key) }
            if !filtered.isEmpty {
                output[entry.key] = filtered
            }
        }

        var updated = championDraftsBySeries[selectedSeries] ?? [:]
        for player in viewModel.players {
            let savedSelection = viewModel.championPick(for: selectedSeries, playerID: player.id)?.driverID
            let currentSelection = updated[player.id]

            if currentSelection == nil || currentSelection == savedSelection {
                if let savedSelection {
                    updated[player.id] = savedSelection
                } else {
                    updated.removeValue(forKey: player.id)
                }
            }
        }
        championDraftsBySeries[selectedSeries] = updated
    }

    /// Called when `viewModel.picks` changes (e.g. after initial async load or after a save).
    /// Only updates a player's draft if they have no in-progress edits, so concurrent edits
    /// for other players are never clobbered.
    private func hydrateAvailablePicks() {
        guard let selectedEventID else { return }
        for player in viewModel.players {
            let savedDraft: PodiumDraft
            if let pick = viewModel.pick(for: selectedSeries, eventID: selectedEventID, playerID: player.id) {
                savedDraft = PodiumDraft(podium: pick.podium)
            } else {
                savedDraft = .empty
            }
            let currentDraft = draftsByPlayer[player.id] ?? .empty
            // Only overwrite if the draft is blank or already reflects the saved pick.
            // If it differs, the player has unsaved edits in progress — leave them alone.
            if currentDraft == .empty || currentDraft == savedDraft {
                draftsByPlayer[player.id] = savedDraft
            }
        }
    }

    private func hydrateAvailableChampionPicks() {
        hydrateChampionDrafts()
    }

    private func saveChampionPick(for player: Player) async {
        guard let driverID = championDraft(for: player.id) else { return }

        do {
            let warning = try await viewModel.saveChampionPick(
                series: selectedSeries,
                playerID: player.id,
                driverID: driverID
            )
            viewModel.showSaveOutcome(
                warning: warning,
                successMessage: "Saved \(player.name)'s world champion pick."
            )
            setChampionDraft(viewModel.championPick(
                for: selectedSeries,
                playerID: player.id
            )?.driverID, for: player.id)
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func savePick(for player: Player) async {
        guard let selectedEventID else { return }
        guard let draft = draftsByPlayer[player.id] else { return }

        do {
            let warning = try await viewModel.savePick(
                series: selectedSeries,
                eventID: selectedEventID,
                playerID: player.id,
                draft: draft
            )
            viewModel.showSaveOutcome(
                warning: warning,
                successMessage: "Saved \(player.name)'s picks for this event."
            )
            // Only refresh this player's draft to avoid clobbering in-progress edits for others.
            if let savedPick = viewModel.pick(for: selectedSeries, eventID: selectedEventID, playerID: player.id) {
                draftsByPlayer[player.id] = PodiumDraft(podium: savedPick.podium)
            }
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}

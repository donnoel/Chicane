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

    private var playerCards: some View {
        Group {
            if horizontalSizeClass == .regular {
                LazyVGrid(columns: playerColumns, spacing: 16) {
                    ForEach(viewModel.players) { player in
                        playerCard(for: player)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(viewModel.players) { player in
                        playerCard(for: player)
                    }
                }
            }
        }
    }

    private var playerColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 14, alignment: .top),
            GridItem(.flexible(), spacing: 14, alignment: .top)
        ]
    }

    private func playerCard(for player: Player) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(initials(from: player.name))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(ChicaneTheme.seriesColor(selectedSeries))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.title3.weight(.semibold))
                    Text("Champion and podium picks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ChampionPickerSection(
                title: "World Champion",
                drivers: drivers,
                participantSingular: participantSingular,
                selection: championBinding(for: player.id),
                isDisabled: championPicksAreLocked
            )

            Button("Save \(player.name)'s Champion Pick") {
                Task {
                    await saveChampionPick(for: player)
                }
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: ChicaneTheme.seriesColor(selectedSeries)))
            .disabled(championDraftsByPlayer[player.id] == nil || championPicksAreLocked)
            .accessibilityLabel("Save world champion pick for \(player.name)")

            if championPicksAreLocked {
                Label("Locked. The official season champion has been entered for this series.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.championPick(for: selectedSeries, playerID: player.id) != nil {
                Label("Saved. Update it anytime before the season champion is entered.", systemImage: "flag.checkered.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.35)

            PodiumPickerSection(
                title: "Podium Picks",
                drivers: drivers,
                participantSingular: participantSingular,
                participantPlural: participantPlural,
                draft: binding(for: player.id)
            )

            Button("Save \(player.name)'s Picks") {
                Task {
                    await savePick(for: player)
                }
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: ChicaneTheme.seriesColor(selectedSeries)))
            .disabled(!(draftsByPlayer[player.id] ?? .empty).isComplete)
            .accessibilityLabel("Save picks for \(player.name)")

            if viewModel.pick(for: selectedSeries, eventID: selectedEventID ?? "", playerID: player.id) != nil {
                Label("Saved. Edit and save again anytime before results are locked.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sectionCard(accent: ChicaneTheme.seriesColor(selectedSeries))
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

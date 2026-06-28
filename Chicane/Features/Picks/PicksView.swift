import SwiftUI

struct PicksView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var selectedSeries: RaceSeries = .formula1
    @State private var selectedEventID: String?
    @State private var draftsByPlayer: [UUID: PodiumDraft] = [:]
    @State private var savedDraftsByPlayer: [UUID: PodiumDraft] = [:]
    @State private var championDraftsBySeries: [RaceSeries: [UUID: String]] = [:]
    @State private var savedChampionDraftsBySeries: [RaceSeries: [UUID: String]] = [:]
    @State private var pendingChampionLock: ChampionLockRequest?
    @State private var hasInitialized = false

    private struct ChampionLockRequest: Identifiable {
        let player: Player
        let series: RaceSeries
        let driverID: String

        var id: String {
            "\(series.rawValue)-\(player.id.uuidString)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                EventPickerHeader(
                    title: "Podium Picks",
                    selectedSeries: $selectedSeries,
                    selectedEventID: $selectedEventID,
                    events: events,
                    eventPickerLabel: "Race event"
                )

                if let selectedEvent {
                    EventSummaryCard(event: selectedEvent, subtitleOpacity: 0.88)

                    if viewModel.players.isEmpty {
                        noPlayersCard
                    } else {
                        playerCards
                    }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .navigationTitle("Picks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPhoneLayout {
                ToolbarItem(placement: .topBarTrailing) {
                    phoneSettingsLink
                }
            }
        }
        .chicaneBackground()
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
            hydrateAvailablePicks()
            hydrateChampionDrafts()
        }
        .onChange(of: viewModel.picks) {
            hydrateAvailablePicks()
        }
        .onChange(of: viewModel.results) {
            hydrateAvailablePicks()
        }
        .onChange(of: viewModel.championPicks) {
            hydrateAvailableChampionPicks()
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

    private var podiumPicksAreLocked: Bool {
        guard let selectedEventID else { return false }
        return viewModel.resultIsLocked(for: selectedSeries, eventID: selectedEventID)
    }

    private var championDraftsByPlayer: [UUID: String] {
        championDraftsBySeries[selectedSeries] ?? [:]
    }

    private var isPhoneLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var playerCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(viewModel.players) { player in
                playerCard(for: player)
            }
        }
    }

    private var phoneSettingsLink: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Image(systemName: "gear")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Settings")
        .accessibilityHint("Opens league, player, bet, and app settings")
    }

    private var noPlayersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No players yet", systemImage: "person.2")
                .font(.headline)

            Text("Add at least one player in Settings to enter podium picks on this \(isPhoneLayout ? "iPhone" : "iPad").")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .groupedCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private func playerCard(for player: Player) -> some View {
        VStack(alignment: .leading, spacing: isPhoneLayout ? 10 : 14) {
            playerHeader(for: player)
            podiumPane(for: player, grouped: horizontalSizeClass == .regular)
            championPane(for: player, grouped: horizontalSizeClass == .regular)
        }
        .sectionCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private func playerHeader(for player: Player) -> some View {
        let summaryStatus = playerSummaryStatus(for: player)
        let summaryTint = summaryStatus == "Open" ? Color.secondary : ChicaneTheme.seriesColor(selectedSeries)

        return HStack(alignment: .top, spacing: 10) {
            Text(initials(from: player.name))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: isPhoneLayout ? 36 : 40, height: isPhoneLayout ? 36 : 40)
                .background(
                    Circle()
                        .fill(ChicaneTheme.seriesColor(selectedSeries))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.title3.weight(.bold))
                Text("Podium and champion picks")
                    .font(isPhoneLayout ? .footnote : .subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isPhoneLayout {
                if summaryStatus != "Open" {
                    statusBadge(
                        title: summaryStatus,
                        tint: summaryTint
                    )
                }
            } else {
                statusBadge(
                    title: summaryStatus,
                    tint: summaryTint
                )
            }
        }
    }

    @ViewBuilder
    private func championPane(for player: Player, grouped: Bool) -> some View {
        let pick = viewModel.championPick(for: selectedSeries, playerID: player.id)
        let isLocked = championPicksAreLocked || pick?.isLocked == true

        let content = VStack(alignment: .leading, spacing: isPhoneLayout ? 8 : 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("World Champion")
                    .font(.headline.weight(.semibold))
                Spacer()
                statusBadge(
                    title: isLocked ? "Locked" : "Season pick",
                    tint: isLocked ? .green : .secondary
                )
                if !isLocked {
                    championLockButton(for: player)
                }
            }

            ChampionPickerSection(
                title: "Champion pick",
                drivers: drivers,
                participantSingular: participantSingular,
                selection: championBinding(for: player.id),
                isDisabled: isLocked
            )

            championStatusText(for: player)
        }

        if grouped {
            content.groupedCard()
        } else {
            content
        }
    }

    private func championLockButton(for player: Player) -> some View {
        Button {
            guard let driverID = championDraft(for: player.id) else { return }
            pendingChampionLock = ChampionLockRequest(
                player: player,
                series: selectedSeries,
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
        .disabled(championDraft(for: player.id) == nil)
        .accessibilityLabel("Lock world champion pick for \(player.name)")
        .accessibilityHint("Makes this \(selectedSeries.title) champion pick final")
    }

    @ViewBuilder
    private func podiumPane(for player: Player, grouped: Bool) -> some View {
        let content = VStack(alignment: .leading, spacing: isPhoneLayout ? 8 : 12) {
            Text("Podium")
                .font(.headline.weight(.semibold))

            PodiumPickerSection(
                title: "",
                drivers: drivers,
                participantSingular: participantSingular,
                participantPlural: participantPlural,
                draft: binding(for: player.id),
                isDisabled: podiumPicksAreLocked
            )

            podiumStatusText(for: player)
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

    @ViewBuilder
    private func championStatusText(for player: Player) -> some View {
        let savedPick = viewModel.championPick(for: selectedSeries, playerID: player.id)

        Group {
            if championPicksAreLocked {
                Label("Locked once the official season champion is entered.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if savedPick?.isLocked == true {
                Label("Locked in as a final champion pick.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if savedPick != nil {
                Label("Saved quietly. Lock it in when ready.", systemImage: "flag.checkered.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Choose one \(participantSingular) for the season title, then lock it in when ready.", systemImage: "person.crop.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func podiumStatusText(for player: Player) -> some View {
        Group {
            if podiumPicksAreLocked {
                Label("Locked once official results are retrieved.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.pick(for: selectedSeries, eventID: selectedEventID ?? "", playerID: player.id) != nil {
                Label("Saved automatically. Edit anytime before results are locked.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Choose P1, P2, and P3.", systemImage: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
            set: { newDraft in
                draftsByPlayer[playerID] = newDraft
                guard let player = viewModel.players.first(where: { $0.id == playerID }) else { return }
                autosavePickIfNeeded(for: player, draft: newDraft)
            }
        )
    }

    private func championBinding(for playerID: UUID) -> Binding<String?> {
        Binding(
            get: { championDraft(for: playerID) },
            set: { newValue in
                setChampionDraft(newValue, for: playerID)
                guard let player = viewModel.players.first(where: { $0.id == playerID }) else { return }
                autosaveChampionPickIfNeeded(for: player, driverID: newValue)
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
            savedDraftsByPlayer = [:]
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
        savedDraftsByPlayer = updated
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

        let currentDrafts = championDraftsBySeries[selectedSeries] ?? [:]
        let previousSavedDrafts = savedChampionDraftsBySeries[selectedSeries] ?? [:]
        var updatedDrafts: [UUID: String] = [:]
        var updatedSavedDrafts: [UUID: String] = [:]
        for player in viewModel.players {
            let savedSelection = viewModel.championPick(for: selectedSeries, playerID: player.id)?.driverID
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
        championDraftsBySeries[selectedSeries] = updatedDrafts
        savedChampionDraftsBySeries[selectedSeries] = updatedSavedDrafts
    }

    private func hydrateAvailablePicks() {
        guard let selectedEventID else {
            draftsByPlayer = [:]
            savedDraftsByPlayer = [:]
            return
        }
        var updatedDrafts: [UUID: PodiumDraft] = [:]
        var updatedSavedDrafts: [UUID: PodiumDraft] = [:]
        for player in viewModel.players {
            let savedDraft: PodiumDraft
            if let pick = viewModel.pick(for: selectedSeries, eventID: selectedEventID, playerID: player.id) {
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

    private func hydrateAvailableChampionPicks() {
        hydrateChampionDrafts()
    }

    private func autosavePickIfNeeded(for player: Player, draft: PodiumDraft) {
        guard let selectedEventID else { return }
        let series = selectedSeries
        let eventID = selectedEventID
        guard !viewModel.resultIsLocked(for: series, eventID: eventID) else { return }

        let savedDraft: PodiumDraft
        if let savedPick = viewModel.pick(for: series, eventID: eventID, playerID: player.id) {
            savedDraft = PodiumDraft(podium: savedPick.podium)
        } else {
            savedDraft = .empty
        }

        guard AutosaveDecision.shouldAutosavePodiumPick(draft: draft, savedDraft: savedDraft) else { return }

        Task {
            await savePick(for: player, series: series, eventID: eventID, draft: draft)
        }
    }

    private func autosaveChampionPickIfNeeded(for player: Player, driverID: String?) {
        let savedPick = viewModel.championPick(for: selectedSeries, playerID: player.id)
        let isLocked = championPicksAreLocked || savedPick?.isLocked == true
        guard AutosaveDecision.shouldAutosaveChampionPick(
            selectedDriverID: driverID,
            savedDriverID: savedPick?.driverID,
            isLocked: isLocked
        ) else { return }

        Task {
            await saveChampionPick(for: player)
        }
    }

    private func saveChampionPick(for player: Player) async {
        guard let driverID = championDraft(for: player.id) else { return }

        do {
            let warning = try await viewModel.saveChampionPick(
                series: selectedSeries,
                playerID: player.id,
                driverID: driverID
            )
            if let warning, !warning.isEmpty {
                viewModel.showError(warning)
            }
            setChampionDraft(viewModel.championPick(
                for: selectedSeries,
                playerID: player.id
            )?.driverID, for: player.id)
            let savedDraft = viewModel.championPick(
                for: selectedSeries,
                playerID: player.id
            )?.driverID
            var savedDrafts = savedChampionDraftsBySeries[selectedSeries] ?? [:]
            if let savedDraft {
                savedDrafts[player.id] = savedDraft
            } else {
                savedDrafts.removeValue(forKey: player.id)
            }
            savedChampionDraftsBySeries[selectedSeries] = savedDrafts
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
            if request.series == selectedSeries {
                setChampionDraft(
                    viewModel.championPick(for: request.series, playerID: request.player.id)?.driverID,
                    for: request.player.id
                )
            }
            let savedDraft = viewModel.championPick(
                for: request.series,
                playerID: request.player.id
            )?.driverID
            var savedDrafts = savedChampionDraftsBySeries[request.series] ?? [:]
            if let savedDraft {
                savedDrafts[request.player.id] = savedDraft
            } else {
                savedDrafts.removeValue(forKey: request.player.id)
            }
            savedChampionDraftsBySeries[request.series] = savedDrafts
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }

    private func savePick(for player: Player, series: RaceSeries, eventID: String, draft: PodiumDraft) async {
        do {
            let warning = try await viewModel.savePick(
                series: series,
                eventID: eventID,
                playerID: player.id,
                draft: draft
            )
            viewModel.showSaveOutcome(
                warning: warning,
                successMessage: "Saved \(player.name)'s picks for this event."
            )
            guard selectedSeries == series, selectedEventID == eventID else { return }
            if let savedPick = viewModel.pick(for: series, eventID: eventID, playerID: player.id) {
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

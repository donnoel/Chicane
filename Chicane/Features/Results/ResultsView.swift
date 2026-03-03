import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var selectedSeries: RaceSeries = .formula1
    @State private var selectedEventID: String?
    @State private var championDraft: String?
    @State private var isUpdatingResults = false
    @State private var scrollOffset: CGFloat = 0
    @State private var hasInitialized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                EventPickerHeader(
                    title: "Race Results Podium",
                    selectedSeries: $selectedSeries,
                    selectedEventID: $selectedEventID,
                    events: events,
                    eventPickerLabel: "Event result"
                )

                seasonChampionCard

                if let selectedEvent {
                    EventSummaryCard(event: selectedEvent)
                    resultEditorCard
                    pointsCard
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No event selected", systemImage: "calendar")
                            .font(.headline)
                        Text("Choose an event above to enter the result.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .glassCard()
                }
            }
            .padding(24)
            .trackingScrollOffset { scrollOffset = $0 }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .chicaneBackground(scrollOffset: scrollOffset)
        .task {
            guard !hasInitialized else { return }
            hasInitialized = true
            initializeIfNeeded()
        }
        .onChange(of: eventIDs) {
            ensureValidSelection()
        }
        .onChange(of: selectedSeries) {
            initializeSelectionForSeries()
            hydrateChampionDraft()
        }
        .onChange(of: viewModel.championResults) {
            hydrateChampionDraft()
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

    private var currentResult: RaceResult? {
        guard let selectedEventID else { return nil }
        return viewModel.result(for: selectedSeries, eventID: selectedEventID)
    }

    private var currentChampionResult: SeasonChampionResult? {
        viewModel.championResult(for: selectedSeries)
    }

    private var participantSingular: String {
        selectedSeries == .motoGP ? "rider" : "driver"
    }

    private var participantPlural: String {
        selectedSeries == .motoGP ? "riders" : "drivers"
    }

    private var resultEditorCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let currentResult {
                resultStatusLabel

                PodiumPickerSection(
                    title: "Official Podium",
                    drivers: viewModel.drivers(for: selectedSeries),
                    participantSingular: participantSingular,
                    participantPlural: participantPlural,
                    draft: .constant(PodiumDraft(podium: currentResult.podium)),
                    isDisabled: true
                )

                Text("Official results are locked once retrieved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap below to fetch the official top three for this event.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await updateResults()
                    }
                } label: {
                    if isUpdatingResults {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Fetching…")
                        }
                    } else {
                        Text("Fetch Official Results")
                    }
                }
                .buttonStyle(LargeActionButtonStyle())
                .disabled(isUpdatingResults)
                .accessibilityLabel("Fetch official results")
                .accessibilityHint("Fetches the official top three and locks this result")
            }
        }
        .glassCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private var seasonChampionCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let currentChampionResult {
                Label(
                    currentChampionResult.isLocked ? "Season champion is locked" : "Season champion saved",
                    systemImage: currentChampionResult.isLocked ? "lock.fill" : "checkmark.seal.fill"
                )
                    .font(.headline)
                    .foregroundStyle(currentChampionResult.isLocked ? .green : .orange)
            }

            ChampionPickerSection(
                title: "Season Champion",
                drivers: viewModel.drivers(for: selectedSeries),
                participantSingular: participantSingular,
                selection: $championDraft,
                isDisabled: currentChampionResult?.isLocked ?? false
            )

            Button("Save Season Champion") {
                Task {
                    await saveChampionResult()
                }
            }
            .buttonStyle(LargeActionButtonStyle())
            .disabled(championDraft == nil || (currentChampionResult?.isLocked ?? false))

            Text(
                currentChampionResult?.isLocked == true
                ? "The season champion is final. Matching picks already receive the 5-point bonus."
                : "This awards 5 bonus points to each player whose world champion pick matches."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .glassCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private var resultStatusLabel: some View {
        HStack {
            Label("Official result is locked", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var pointsCard: some View {
        let points = selectedEventID.map { viewModel.eventPoints(series: selectedSeries, eventID: $0) } ?? [:]
        let hasAnySavedPickForEvent = selectedEventID.map { eventID in
            viewModel.players.contains { player in
                viewModel.pick(for: selectedSeries, eventID: eventID, playerID: player.id) != nil
            }
        } ?? false

        return VStack(alignment: .leading, spacing: 18) {
            Text("Event Points")
                .font(.headline)

            if points.isEmpty {
                Text("Fetch official results to compute points.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if !hasAnySavedPickForEvent {
                Text("No saved picks for this event.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.players) { player in
                    HStack {
                        Text(player.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        AnimatedScoreText(value: points[player.id, default: 0])
                            .font(.body.weight(.bold))
                    }
                }
            }
        }
        .glassCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private func initializeIfNeeded() {
        if selectedEventID == nil {
            initializeSelectionForSeries()
        }
        ensureValidSelection()
        hydrateChampionDraft()
    }

    private func initializeSelectionForSeries() {
        let now = Date()
        if let recent = events.filter({ $0.raceDate < now }).max(by: { $0.raceDate < $1.raceDate }) {
            selectedEventID = recent.id
        } else {
            selectedEventID = events.min(by: { $0.raceDate < $1.raceDate })?.id
        }
    }

    private func ensureValidSelection() {
        guard !events.isEmpty else { return }
        guard let selectedEventID, eventIDs.contains(selectedEventID) else {
            initializeSelectionForSeries()
            return
        }
    }

    private func hydrateChampionDraft() {
        championDraft = currentChampionResult?.driverID
    }

    private func updateResults() async {
        guard let selectedEventID else { return }
        guard !isUpdatingResults else { return }
        isUpdatingResults = true
        defer { isUpdatingResults = false }

        do {
            let warning = try await viewModel.updateResultFromOfficialSource(
                series: selectedSeries,
                eventID: selectedEventID,
                lockResult: true
            )
            viewModel.showInfo(warning ?? "Results updated and locked.")
        } catch {
            if error is OfficialResultRepositoryError {
                viewModel.showInfo("Official results aren't available yet. Try again later.")
            } else {
                viewModel.showError(error.localizedDescription)
            }
        }
    }

    private func saveChampionResult() async {
        guard let championDraft else { return }

        do {
            let warning = try await viewModel.saveChampionResult(series: selectedSeries, driverID: championDraft)
            viewModel.showInfo(warning ?? "Season champion saved. Bonus points are now included in standings.")
            hydrateChampionDraft()
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}

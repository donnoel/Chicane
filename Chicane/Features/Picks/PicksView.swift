import SwiftUI

struct PicksView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var selectedSeries: RaceSeries = .formula1
    @State private var selectedEventID: String?
    @State private var draftsByPlayer: [UUID: PodiumDraft] = [:]
    @State private var scrollOffset: CGFloat = 0
    @State private var hasInitialized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
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
                    .glassCard()
                }
            }
            .padding(24)
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
        .onChange(of: selectedSeries) {
            initializeSelectionForSeries()
            hydrateDrafts()
        }
        .onChange(of: selectedEventID) {
            hydrateDrafts()
        }
        .onChange(of: viewModel.players) {
            hydrateDrafts()
        }
        .onChange(of: viewModel.picks) {
            hydrateDrafts()
        }
    }

    private var events: [RaceEvent] {
        viewModel.events(for: selectedSeries)
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

    private var playerCards: some View {
        ForEach(viewModel.players) { player in
            VStack(alignment: .leading, spacing: 24) {
                PodiumPickerSection(
                    title: "\(player.name)'s Podium",
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
                .buttonStyle(LargeActionButtonStyle())
                .disabled(!(draftsByPlayer[player.id] ?? .empty).isComplete)
                .accessibilityLabel("Save picks for \(player.name)")

                if viewModel.pick(for: selectedSeries, eventID: selectedEventID ?? "", playerID: player.id) != nil {
                    Label("Saved. Edit and save again anytime before results are locked.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .glassCard(accent: ChicaneTheme.seriesColor(selectedSeries))
        }
    }

    private func binding(for playerID: UUID) -> Binding<PodiumDraft> {
        Binding(
            get: { draftsByPlayer[playerID] ?? .empty },
            set: { draftsByPlayer[playerID] = $0 }
        )
    }

    private func initializeIfNeeded() {
        if selectedEventID == nil {
            initializeSelectionForSeries()
        }
        hydrateDrafts()
    }

    private func initializeSelectionForSeries() {
        let now = Date()
        // Default to the next upcoming event (most likely needs picks entered).
        if let next = events.filter({ $0.raceDate >= now }).min(by: { $0.raceDate < $1.raceDate }) {
            selectedEventID = next.id
        } else {
            // Season is over — pick the most recent event.
            selectedEventID = events.max(by: { $0.raceDate < $1.raceDate })?.id
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

    private func savePick(for player: Player) async {
        guard let selectedEventID else { return }
        guard let draft = draftsByPlayer[player.id] else { return }

        do {
            try await viewModel.savePick(
                series: selectedSeries,
                eventID: selectedEventID,
                playerID: player.id,
                draft: draft
            )
            viewModel.showInfo("Saved \(player.name)'s picks for this event.")
            hydrateDrafts()
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}


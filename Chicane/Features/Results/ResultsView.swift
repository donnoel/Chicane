import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var selectedSeries: RaceSeries = .formula1
    @State private var selectedEventID: String?
    @State private var draft: PodiumDraft = .empty
    @State private var showUnlockConfirmation = false
    @State private var isUpdatingResults = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EventPickerHeader(
                    title: "Update race result podium",
                    selectedSeries: $selectedSeries,
                    selectedEventID: $selectedEventID,
                    events: events,
                    eventPickerLabel: "Event result"
                )

                if let selectedEvent {
                    EventSummaryCard(event: selectedEvent)
                    resultEditorCard
                    pointsCard
                } else {
                    Text("Choose an event to enter the podium result")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            initializeIfNeeded()
        }
        .onChange(of: selectedSeries) {
            initializeSelectionForSeries()
            hydrateDraft()
        }
        .onChange(of: selectedEventID) {
            hydrateDraft()
        }
        .onChange(of: viewModel.results) {
            hydrateDraft()
        }
        .alert("Unlock result?", isPresented: $showUnlockConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Unlock", role: .destructive) {
                Task {
                    await unlockCurrentResult()
                }
            }
        } message: {
            Text("This allows editing this race result again.")
        }
    }

    private var events: [RaceEvent] {
        viewModel.events(for: selectedSeries)
    }

    private var selectedEvent: RaceEvent? {
        guard let selectedEventID else { return nil }
        return events.first(where: { $0.id == selectedEventID })
    }

    private var currentResult: RaceResult? {
        guard let selectedEventID else { return nil }
        return viewModel.result(for: selectedSeries, eventID: selectedEventID)
    }

    private var participantSingular: String {
        selectedSeries == .motoGP ? "rider" : "driver"
    }

    private var participantPlural: String {
        selectedSeries == .motoGP ? "riders" : "drivers"
    }

    private var resultEditorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let currentResult {
                resultStatusLabel(currentResult)
            }

            PodiumPickerSection(
                title: "Actual podium",
                drivers: viewModel.drivers(for: selectedSeries),
                participantSingular: participantSingular,
                participantPlural: participantPlural,
                draft: $draft,
                isDisabled: currentResult?.isLocked ?? false
            )

            if currentResult?.isLocked == true {
                Button("Unlock result") {
                    showUnlockConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .frame(minHeight: 44)
                .accessibilityHint("Confirm to edit this locked result")
            } else {
                Button("Update Results") {
                    Task {
                        await updateResults()
                    }
                }
                .buttonStyle(LargeActionButtonStyle())
                .disabled(isUpdatingResults)
                .accessibilityLabel("Update results")
                .accessibilityHint("Fetches official top three and locks this result")
            }
        }
        .glassCard()
    }

    private func resultStatusLabel(_ result: RaceResult) -> some View {
        HStack {
            Label(
                result.isLocked ? "Result is locked" : "Result is editable",
                systemImage: result.isLocked ? "lock.fill" : "lock.open.fill"
            )
            .font(.headline)
            .foregroundStyle(result.isLocked ? .green : .orange)

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var pointsCard: some View {
        let points = selectedEventID.map { viewModel.eventPoints(series: selectedSeries, eventID: $0) } ?? [:]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Event points")
                .font(.headline)

            if points.isEmpty {
                Text("Update results to compute points.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.players) { player in
                    HStack {
                        Text(player.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("\(points[player.id, default: 0])")
                            .font(.body.weight(.bold))
                            .monospacedDigit()
                    }
                }
            }
        }
        .glassCard()
    }

    private func initializeIfNeeded() {
        if selectedEventID == nil {
            initializeSelectionForSeries()
        }
        hydrateDraft()
    }

    private func initializeSelectionForSeries() {
        selectedEventID = events.first?.id
    }

    private func hydrateDraft() {
        guard let selectedEventID,
              let existingResult = viewModel.result(for: selectedSeries, eventID: selectedEventID) else {
            draft = .empty
            return
        }

        draft = PodiumDraft(podium: existingResult.podium)
    }

    private func updateResults() async {
        guard let selectedEventID else { return }
        guard !isUpdatingResults else { return }
        isUpdatingResults = true
        defer { isUpdatingResults = false }

        do {
            try await viewModel.updateResultFromOfficialSource(
                series: selectedSeries,
                eventID: selectedEventID,
                lockResult: true
            )
            // Always show the banner — the auto-dismiss timer in RootTabView ensures
            // the old banner has been cleared well before the user can tap Update Results
            // a second time, so duplicate suppression is unnecessary and was causing
            // the banner to silently not appear after the first auto-dismiss.
            viewModel.showInfo("Results updated and locked.")
            hydrateDraft()
        } catch {
            if let officialError = error as? OfficialResultRepositoryError {
                switch officialError {
                case .resultsUnavailable:
                    viewModel.showInfo("Official results aren't available yet. Try again later.")
                @unknown default:
                    viewModel.showInfo("We couldn't pull official results right now. We'll use local data for now.")
                }
            } else {
                viewModel.showError(error.localizedDescription)
            }
        }
    }

    private func unlockCurrentResult() async {
        guard let selectedEventID else { return }
        do {
            try await viewModel.unlockResult(series: selectedSeries, eventID: selectedEventID)
            viewModel.showInfo("Result unlocked. Tap Update Results to refresh official podium.")
            hydrateDraft()
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}


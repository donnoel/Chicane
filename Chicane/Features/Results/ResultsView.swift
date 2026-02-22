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
                pickerHeader

                if let selectedEvent {
                    eventHeader(event: selectedEvent)
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

    private var pickerHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update race result podium")
                .font(.title2.weight(.bold))

            Picker("Series", selection: $selectedSeries) {
                ForEach(RaceSeries.allCases) { series in
                    Text(series.title).tag(series)
                }
            }
            .pickerStyle(.segmented)
            .tint(ChicaneTheme.motoBlue)

            Picker("Event", selection: $selectedEventID) {
                Text("Choose event").tag(Optional<String>.none)
                ForEach(events) { event in
                    Text("R\(event.round) \(event.title)")
                        .tag(Optional(event.id))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .accessibilityLabel("Event result")
        }
    }

    private func eventHeader(event: RaceEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(event.title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(event.series.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ChicaneTheme.seriesColor(event.series), in: Capsule())
            }
            Text("Round \(event.round) · \(event.circuit)")
                .font(.body)
                .foregroundStyle(.secondary)
            Text(DateFormatter.dayMonthYear.string(from: event.raceDate))
                .font(.body)
        }
        .glassCard()
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

    private func showInfoOnce(_ message: String) {
        if viewModel.banner?.text != message {
            viewModel.showInfo(message)
        }
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
            showInfoOnce("Results updated and locked.")
            hydrateDraft()
        } catch {
            if let officialError = error as? OfficialResultRepositoryError {
                switch officialError {
                case .resultsUnavailable:
                    showInfoOnce("Official results aren’t available yet. Try again later.")
                @unknown default:
                    showInfoOnce("We couldn’t pull official results right now. We’ll use local data for now.")
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

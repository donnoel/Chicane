import SwiftUI

struct ResultsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSeries: RaceSeries = .formula1
    @State private var selectedEventID: String?
    @State private var championDraft: String?
    @State private var isUpdatingResults = false
    @State private var scrollOffset: CGFloat = 0
    @State private var hasInitialized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EventPickerHeader(
                    title: "Race Results Podium",
                    selectedSeries: $selectedSeries,
                    selectedEventID: $selectedEventID,
                    events: events,
                    eventPickerLabel: "Event result"
                )

                if selectedEvent != nil {
                    resultsContent
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No event selected", systemImage: "calendar")
                            .font(.headline)
                        Text("Choose an event above to enter the result.")
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

    private var participantsByID: [String: Driver] {
        Dictionary(uniqueKeysWithValues: viewModel.drivers(for: selectedSeries).map { ($0.id, $0) })
    }

    private var resultFeatureCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let selectedEvent {
                resultHeroHeader(for: selectedEvent)
            }

            if let currentResult {
                resultStatusLabel
                officialPodiumSection(for: currentResult.podium)

                Text("Official results are locked once retrieved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Official Event Result")
                        .font(.headline.weight(.semibold))
                    Text("Tap below to fetch the official top three for this event.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

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
        VStack(alignment: .leading, spacing: 16) {
            Text("Season Champion")
                .font(.headline.weight(.semibold))
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
            .buttonStyle(SecondaryActionButtonStyle(tint: ChicaneTheme.seriesColor(selectedSeries)))
            .disabled(championDraft == nil || (currentChampionResult?.isLocked ?? false))

            Text(
                currentChampionResult?.isLocked == true
                ? "The season champion is final. Matching picks already receive the 5-point bonus."
                : "This awards 5 bonus points to each player whose world champion pick matches."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sectionCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            resultFeatureCard

            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 14) {
                    seasonChampionCard
                    pointsCard
                }
            } else {
                supportCard
            }
        }
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

    private func resultHeroHeader(for event: RaceEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Official Event Result")
                        .font(.headline.weight(.semibold))
                    Text(event.title)
                        .font(.title2.weight(.bold))
                    Text("Round \(event.round) · \(event.circuit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(event.series.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ChicaneTheme.seriesColor(event.series), in: Capsule())
            }

            Text(DateFormatter.dayMonthYear.string(from: event.raceDate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func officialPodiumSection(for podium: Podium) -> some View {
        VStack(alignment: .leading, spacing: horizontalSizeClass == .regular ? 20 : 14) {
            Text("Official Podium")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            officialPodiumRow(position: 1, title: "P1", participantID: podium.p1)
            officialPodiumRow(position: 2, title: "P2", participantID: podium.p2)
            officialPodiumRow(position: 3, title: "P3", participantID: podium.p3)
        }
    }

    private func officialPodiumRow(position: Int, title: String, participantID: String) -> some View {
        let label = participantDisplayLabel(for: participantID)

        return HStack(spacing: 14) {
            PodiumMedalView(position: position, isSelected: true)

            Text(label)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ChicaneTheme.fieldFill(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(ChicaneTheme.fieldStroke(for: colorScheme), lineWidth: 0.8)
                        )
                )
                .shadow(color: ChicaneTheme.fieldShadow(for: colorScheme), radius: 4, x: 0, y: 2)
                .accessibilityLabel("\(title) \(label)")
        }
    }

    private func participantDisplayLabel(for participantID: String) -> String {
        if let participant = participantsByID[participantID] {
            return "\(participant.name) (\(participant.team))"
        }
        return fallbackParticipantLabel(from: participantID)
    }

    private func fallbackParticipantLabel(from participantID: String) -> String {
        let trimmed = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown participant"
        }

        let tokens = trimmed
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)

        let filtered = tokens.enumerated().compactMap { index, token -> String? in
            let lowered = token.lowercased()
            if index == 0 && (lowered == "f1" || lowered == "mgp" || lowered == "motogp" || lowered == "formula1") {
                return nil
            }
            return token
        }

        guard !filtered.isEmpty else {
            return trimmed
        }
        return filtered.map { $0.capitalized }.joined(separator: " ")
    }

    private var pointsCard: some View {
        let points = selectedEventID.map { viewModel.eventPoints(series: selectedSeries, eventID: $0) } ?? [:]
        let hasAnySavedPickForEvent = selectedEventID.map { eventID in
            viewModel.players.contains { player in
                viewModel.pick(for: selectedSeries, eventID: eventID, playerID: player.id) != nil
            }
        } ?? false

        return VStack(alignment: .leading, spacing: 12) {
            Text("Event Points")
                .font(.headline.weight(.semibold))

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
                    if player.id != viewModel.players.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .sectionCard()
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            seasonChampionSection
            Divider().opacity(0.24)
            pointsSection
        }
        .groupedCard()
    }

    private var seasonChampionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Season Champion")
                .font(.headline.weight(.semibold))

            if let currentChampionResult {
                Label(
                    currentChampionResult.isLocked ? "Season champion is locked" : "Season champion saved",
                    systemImage: currentChampionResult.isLocked ? "lock.fill" : "checkmark.seal.fill"
                )
                .font(.subheadline.weight(.semibold))
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
            .buttonStyle(SecondaryActionButtonStyle(tint: ChicaneTheme.seriesColor(selectedSeries)))
            .disabled(championDraft == nil || (currentChampionResult?.isLocked ?? false))

            Text(
                currentChampionResult?.isLocked == true
                ? "The season champion is final. Matching picks already receive the 5-point bonus."
                : "This awards 5 bonus points to each player whose world champion pick matches."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var pointsSection: some View {
        let points = selectedEventID.map { viewModel.eventPoints(series: selectedSeries, eventID: $0) } ?? [:]
        let hasAnySavedPickForEvent = selectedEventID.map { eventID in
            viewModel.players.contains { player in
                viewModel.pick(for: selectedSeries, eventID: eventID, playerID: player.id) != nil
            }
        } ?? false

        return VStack(alignment: .leading, spacing: 12) {
            Text("Event Points")
                .font(.headline.weight(.semibold))

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
                    if player.id != viewModel.players.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
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
            viewModel.showSaveOutcome(
                warning: warning,
                successMessage: "Results updated and locked."
            )
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
            viewModel.showSaveOutcome(
                warning: warning,
                successMessage: "Season champion saved. Bonus points are now included in standings."
            )
            hydrateChampionDraft()
        } catch {
            viewModel.showError(error.localizedDescription)
        }
    }
}

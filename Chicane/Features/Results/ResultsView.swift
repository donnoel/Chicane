import SwiftUI
import UIKit

struct ResultsView: View {
    private enum InlineStatusStyle {
        case info
        case error
    }

    private struct InlineStatus {
        let text: String
        let style: InlineStatusStyle
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @State private var selectedSeries: RaceSeries = .formula1
    @State private var selectedEventID: String?
    @State private var isUpdatingResults = false
    @State private var hasInitialized = false
    @State private var inlineResultStatus: InlineStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .chicaneBackground()
        .task {
            guard !hasInitialized else { return }
            hasInitialized = true
            initializeIfNeeded()
        }
        .onChange(of: eventIDs) {
            ensureValidSelection()
            clearInlineStatus()
        }
        .onChange(of: selectedSeries) {
            initializeSelectionForSeries()
            clearInlineStatus()
        }
        .onChange(of: selectedEventID) {
            clearInlineStatus()
        }
        .onChange(of: inlineResultStatus?.text) { _, _ in
            announceInlineStatusIfNeeded()
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
        VStack(alignment: .leading, spacing: 16) {
            if let selectedEvent {
                resultHeroHeader(for: selectedEvent)
            }

            if let currentResult {
                resultStatusLabel
                officialPodiumSection(for: currentResult.podium)

                Text("Official results stay locked once retrieved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fetch the official top three for this event.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if let inlineResultStatus {
                    inlineStatusCard(inlineResultStatus)
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
        VStack(alignment: .leading, spacing: 12) {
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

            if let currentChampionResult,
               let champion = participantsByID[currentChampionResult.driverID] {
                Text("Official season champion")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(champion.name) (\(champion.team))")
                    .font(.body.weight(.semibold))
            } else {
                Text("This will be filled in automatically at the end of the season.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Matching picks receive a 5-point season bonus.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sectionCard(accent: ChicaneTheme.seriesColor(selectedSeries))
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            resultFeatureCard

            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 12) {
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
            if differentiateWithoutColor {
                Label("Locked result: Official result is locked", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            } else {
                Label("Official result is locked", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func inlineStatusCard(_ status: InlineStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.style == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(status.style == .error ? .orange : .blue)
                .accessibilityHidden(true)

            Text(status.text)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
                        : AnyShapeStyle(.thinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    (status.style == .error ? Color.orange : Color.blue).opacity(0.28),
                    lineWidth: reduceTransparency ? 1.1 : 0.8
                )
        )
        .overlay(alignment: .topLeading) {
            if differentiateWithoutColor {
                Text(status.style == .error ? "Error" : "Info")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                    .padding(8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(differentiateWithoutColor ? "\(status.style == .error ? "Error" : "Info"). \(status.text)" : status.text)
    }

    private func resultHeroHeader(for event: RaceEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Official Event Result")
                        .font(.headline.weight(.semibold))
                    Text(event.title)
                        .font(.title3.weight(.bold))
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
                .font(.headline.weight(.semibold))
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
                .font(.subheadline.weight(.semibold))

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
        VStack(alignment: .leading, spacing: 14) {
            seasonChampionSection
            Divider().opacity(0.24)
            pointsSection
        }
        .groupedCard()
    }

    private var seasonChampionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Season Champion")
                .font(.subheadline.weight(.semibold))

            if let currentChampionResult {
                Label(
                    currentChampionResult.isLocked ? "Season champion is locked" : "Season champion saved",
                    systemImage: currentChampionResult.isLocked ? "lock.fill" : "checkmark.seal.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(currentChampionResult.isLocked ? .green : .orange)
            }

            if let currentChampionResult,
               let champion = participantsByID[currentChampionResult.driverID] {
                Text("Official season champion")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(champion.name) (\(champion.team))")
                    .font(.body.weight(.semibold))
            } else {
                Text("This will be filled in automatically at the end of the season.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Matching picks receive a 5-point season bonus.")
                .font(.caption)
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
                .font(.subheadline.weight(.semibold))

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
            inlineResultStatus = nil
        } catch {
            if error is OfficialResultRepositoryError {
                viewModel.showInfo("Official results aren't available yet. Try again later.")
                inlineResultStatus = InlineStatus(
                    text: "Official top-3 results are not available yet for this event. Try again later.",
                    style: .info
                )
            } else {
                viewModel.showError(error.localizedDescription)
                inlineResultStatus = InlineStatus(
                    text: "Could not fetch official results right now. Check your connection and try again.",
                    style: .error
                )
            }
        }
    }

    private func clearInlineStatus() {
        inlineResultStatus = nil
    }

    private func announceInlineStatusIfNeeded() {
        guard let inlineResultStatus else { return }
        // Avoid duplicate speech when the same moment already surfaced a banner.
        guard viewModel.banner == nil else { return }
        postAccessibilityAnnouncement(inlineResultStatus.text)
    }

    private func postAccessibilityAnnouncement(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: trimmed)
    }
}

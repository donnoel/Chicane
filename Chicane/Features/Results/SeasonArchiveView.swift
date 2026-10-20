import SwiftUI

struct SeasonArchiveListView: View {
    let reviews: [SeasonReview]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if reviews.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your story starts this season", systemImage: "books.vertical")
                        .font(ChicaneTypography.cardTitleStrong)
                    Text("A season review is saved automatically when you fetch a series’ final official race result. Each new year joins the archive.")
                        .font(ChicaneTypography.body)
                    Text("Complete the earlier race results and confirm the season champions to finalize the combined winner. Reviews stay here after a season reset.")
                        .font(ChicaneTypography.subtitle)
                        .foregroundStyle(.secondary)
                }
                .groupedCard(accent: ChicaneTheme.glowAmber)
                .accessibilityIdentifier("SeasonArchiveEmptyState")
            }
            ForEach(reviews) { review in
                NavigationLink {
                    SeasonReviewDetailView(review: review)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("\(String(review.season)) Season Review", systemImage: review.isComplete ? "trophy.fill" : "book.closed")
                                .font(ChicaneTypography.cardTitleStrong)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        Text(review.isComplete ? "Final standings" : "Awaiting results")
                            .font(ChicaneTypography.captionBold)
                            .foregroundStyle(.secondary)
                        Text(review.recap)
                            .font(ChicaneTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                        if reviews.filter({ $0.season == review.season }).count > 1 {
                            Text(review.leagueCode.map { "League \($0)" } ?? "On this device")
                                .font(ChicaneTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .groupedCard(accent: ChicaneTheme.glowAmber)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("SeasonReview-\(review.season)")
            }
        }
    }
}

struct SeasonReviewDetailView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    private let originalReview: SeasonReview
    private var review: SeasonReview { viewModel.seasonReviews.first { $0.id == originalReview.id } ?? originalReview }
    @State private var championToConfirm: ArchivedSeason?
    @State private var scope: ScoreboardScope = .combined

    init(review: SeasonReview) {
        originalReview = review
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                standings
                if !review.highlights.isEmpty { highlights }
                predictionRecords
                champions
                if review.standings.contains(where: { $0.bet?.isEmpty == false }) { stakes }
                raceHistory
                Text("Scoring: 1 point per exact podium position, plus 5 points for each correct season champion. Archived names, picks and results are preserved through season resets.")
                    .font(ChicaneTypography.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .navigationTitle("\(String(review.season)) Season Review")
        .navigationBarTitleDisplayMode(.inline)
        .chicaneBackground()
        .sheet(item: $championToConfirm) { archive in
            SeasonChampionConfirmationView(archive: archive)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(review.isComplete ? "The season, remembered" : "Your season is being preserved", systemImage: review.isComplete ? "trophy.fill" : "hourglass")
                .font(ChicaneTypography.cardTitleStrong)
                .accessibilityAddTraits(.isHeader)
            Text(review.recap).font(ChicaneTypography.body)
                .accessibilityIdentifier("SeasonReviewRecap")
            ForEach(RaceSeries.allCases) { series in
                let snapshot = review.seriesArchives.first { $0.series == series }
                Label {
                    Text("\(series.title): \(snapshot?.pendingDescription ?? "Awaiting final official race result")")
                } icon: {
                    Image(systemName: snapshot?.isComplete == true ? "checkmark.seal" : "clock")
                }
                .font(ChicaneTypography.subtitle)
            }
            if !review.isComplete {
                Text("Fetch missing races on Results and confirm any remaining season champions below.")
                    .font(ChicaneTypography.subtitle)
                    .foregroundStyle(.secondary)
            }
            if let updated = review.seriesArchives.map(\.updatedAt).max() {
                Text("Updated \(updated.formatted(date: .abbreviated, time: .omitted))")
                    .font(ChicaneTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .groupedCard(accent: ChicaneTheme.glowAmber)
    }

    private var standings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(review.isComplete ? "Final standings" : "Season standings").font(ChicaneTypography.cardTitleStrong)
                .accessibilityAddTraits(.isHeader)
            Picker("Standings scope", selection: $scope) {
                ForEach(ScoreboardScope.allCases) { value in Text(value.title).tag(value) }
            }
            .pickerStyle(.segmented)
            let selectedArchives = review.seriesArchives.filter { scope.series == nil || $0.series == scope.series }
            if selectedArchives.isEmpty {
                Text("Awaiting this series’ final official race result.")
                    .font(ChicaneTypography.body).foregroundStyle(.secondary)
            } else {
                if scope == .combined ? !review.isComplete : !selectedArchives.allSatisfy(\.isComplete) {
                    Text("Recorded points so far — the final winner is not confirmed.")
                        .font(ChicaneTypography.subtitle).foregroundStyle(.secondary)
                }
                let rows = review.standingsByScope[scope] ?? []
                ForEach(rows) { row in
                    let rank = (rows.firstIndex { $0.total == row.total } ?? 0) + 1
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(rank)").font(ChicaneTypography.score)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(ChicaneTypography.bodySemibold)
                            Text("Race points \(row.racePoints) · Champion bonus +\(row.championBonus)")
                                .font(ChicaneTypography.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(row.total)").font(ChicaneTypography.leaderScore)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .groupedCard(accent: ChicaneTheme.glowAmber)
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Season highlights").font(ChicaneTypography.cardTitleStrong)
                .accessibilityAddTraits(.isHeader)
            ForEach(review.highlights) { highlight in
                VStack(alignment: .leading, spacing: 4) {
                    Text(highlight.title).font(ChicaneTypography.bodySemibold)
                    Text(highlight.detail).font(ChicaneTypography.body).foregroundStyle(.secondary)
                }
            }
        }
        .groupedCard()
    }

    private var predictionRecords: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your prediction records").font(ChicaneTypography.cardTitleStrong)
                .accessibilityAddTraits(.isHeader)
            ForEach(review.standings) { row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.name).font(ChicaneTypography.bodySemibold)
                    Text("\(row.racePoints) correct podium positions · \(row.perfectPodiums) perfect podiums · \(row.picksMade) race picks")
                        .font(ChicaneTypography.subtitle).foregroundStyle(.secondary)
                    ForEach(review.seriesArchives) { archive in
                        if let pick = archive.championPicks.first(where: { $0.playerID == row.id }) {
                            let outcome = archive.championResult.map { $0.driverID == pick.driverID ? "Correct (+5)" : "No bonus" } ?? "Awaiting champion"
                            Text("\(archive.series.shortTitle) champion pick: \(participantName(pick.driverID, in: archive)) · \(outcome)")
                                .font(ChicaneTypography.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .groupedCard()
    }

    private var champions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The racing champions").font(ChicaneTypography.cardTitleStrong)
                .accessibilityAddTraits(.isHeader)
            ForEach(review.seriesArchives) { archive in
                VStack(alignment: .leading, spacing: 4) {
                    Text(archive.series.title).font(ChicaneTypography.bodySemibold)
                    Text(archive.championResult.map { participantName($0.driverID, in: archive) } ?? "Awaiting confirmed season champion")
                        .font(ChicaneTypography.body).foregroundStyle(.secondary)
                    if archive.championResult == nil,
                       archive.leagueCode == viewModel.settings.normalizedLeagueCode,
                       viewModel.events(for: archive.series).map(\.season).max() == archive.season,
                       viewModel.results.contains(where: { $0.series == archive.series && $0.isOfficial }),
                       viewModel.championResult(for: archive.series) == nil {
                        Button("Confirm \(archive.series.shortTitle) champion") { championToConfirm = archive }
                            .font(ChicaneTypography.bodySemibold)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .groupedCard()
    }

    private var stakes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What was at stake").font(ChicaneTypography.cardTitleStrong)
                .accessibilityAddTraits(.isHeader)
            ForEach(review.standings.filter { $0.bet?.isEmpty == false }) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(ChicaneTypography.bodySemibold)
                    Text(row.bet ?? "").font(ChicaneTypography.body).foregroundStyle(.secondary)
                }
            }
        }
        .groupedCard()
    }

    private var raceHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Race by race").font(ChicaneTypography.cardTitleStrong)
                .accessibilityAddTraits(.isHeader)
            ForEach(review.seriesArchives) { archive in
                Text(archive.series.title).font(ChicaneTypography.bodySemibold)
                ForEach(archive.events.sorted { $0.raceDate < $1.raceDate }) { event in
                    DisclosureGroup("R\(event.round) · \(event.title)") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(event.raceDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                            if let result = archive.results.first(where: { $0.eventID == event.id }) {
                                Text("Result: \(podiumText(result.podium, in: archive))")
                                ForEach(archive.players) { player in
                                    if let pick = archive.picks.first(where: { $0.playerID == player.id && $0.eventID == event.id }) {
                                        Text("\(player.name): \(podiumText(pick.podium, in: archive)) — \(SeasonArchiveService().points(pick.podium, result.podium)) points")
                                    } else {
                                        Text("\(player.name): No pick recorded")
                                    }
                                }
                            } else {
                                Text("Result not recorded").foregroundStyle(.secondary)
                            }
                        }
                        .font(ChicaneTypography.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    .font(ChicaneTypography.subtitle)
                    .padding(.vertical, 6)
                }
            }
        }
        .groupedCard()
    }

    private func participantName(_ id: String, in archive: ArchivedSeason) -> String {
        archive.participants.first { $0.id == id }?.name ?? "Participant not recorded"
    }

    private func podiumText(_ podium: Podium, in archive: ArchivedSeason) -> String {
        [podium.p1, podium.p2, podium.p3].enumerated().map { "\($0.offset + 1). \(participantName($0.element, in: archive))" }.joined(separator: " · ")
    }
}

private struct SeasonChampionConfirmationView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let archive: ArchivedSeason
    @State private var selectedID = ""
    @State private var showsConfirmation = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose the official \(String(archive.season)) \(archive.series.title) world champion. Correct predictions receive the 5-point season bonus.")
                    Picker("Official champion", selection: $selectedID) {
                        Text("Choose champion").tag("")
                        ForEach(archive.participants) { driver in Text(driver.name).tag(driver.id) }
                    }
                    .accessibilityIdentifier("ArchiveChampionSelection")
                    if let leader = viewModel.championshipLeaders(for: archive.series).first {
                        Text("Latest official standings leader: \(leader.name). Confirm against the final championship standings.")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Once confirmed, the season champion and everyone’s champion predictions are locked.")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button("Confirm champion") { showsConfirmation = true }
                    .disabled(selectedID.isEmpty || isSaving)
            }
            .navigationTitle("\(archive.series.shortTitle) champion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Confirm season champion?", isPresented: $showsConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Confirm") { Task { await save() } }
            } message: {
                Text("This settles the season bonus and locks champion selections.")
            }
        }
    }

    private func save() async {
        guard let selected = archive.participants.first(where: { $0.id == selectedID }) else { return }
        isSaving = true
        defer { isSaving = false }
        let liveID = viewModel.drivers(for: archive.series).first {
            ParticipantNameMatcher.normalizedName($0.name) == ParticipantNameMatcher.normalizedName(selected.name)
        }?.id ?? selected.id
        do {
            let warning = try await viewModel.saveChampionResult(series: archive.series, driverID: liveID)
            viewModel.showSaveOutcome(warning: warning, successMessage: "Season champion confirmed.")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

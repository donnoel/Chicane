import Foundation
import Combine
import OSLog

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var players: [Player] = []
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var picks: [RacePick] = []
    @Published private(set) var results: [RaceResult] = []
    @Published private(set) var driversBySeries: [RaceSeries: [Driver]] = [:]
    @Published private(set) var eventsBySeries: [RaceSeries: [RaceEvent]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var banner: BannerMessage?

    private let driverRepository: DriverRepository
    private let calendarRepository: CalendarRepository
    private let resultRepository: ResultRepository
    private let seasonRepository: SeasonRepository
    private let scoringService = ScoringService()
    private let scoreboardCalculator = ScoreboardCalculator()
    private let logger = Logger(subsystem: "dn.chicane", category: "AppViewModel")

    private var hasLoaded = false

    init(
        driverRepository: DriverRepository,
        calendarRepository: CalendarRepository,
        resultRepository: ResultRepository,
        seasonRepository: SeasonRepository
    ) {
        self.driverRepository = driverRepository
        self.calendarRepository = calendarRepository
        self.resultRepository = resultRepository
        self.seasonRepository = seasonRepository
    }

    func showInfo(_ message: String) {
        banner = BannerMessage(style: .info, text: message)
    }

    func showError(_ message: String) {
        banner = BannerMessage(style: .error, text: message)
        errorMessage = message
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let state = try await seasonRepository.loadState()
            apply(state: state)

            // Fan out all four network fetches concurrently, then assign atomically.
            // If any single fetch throws, none of the four assignments are committed,
            // so we never leave driversBySeries / eventsBySeries in a partially-updated state.
            async let f1Drivers = driverRepository.drivers(for: .formula1)
            async let motoGPDrivers = driverRepository.drivers(for: .motoGP)
            async let f1Events = calendarRepository.events(for: .formula1)
            async let motoGPEvents = calendarRepository.events(for: .motoGP)

            let (resolvedF1Drivers, resolvedMotoGPDrivers, resolvedF1Events, resolvedMotoGPEvents) =
                try await (f1Drivers, motoGPDrivers, f1Events, motoGPEvents)

            // All four succeeded — apply as a single synchronous batch.
            driversBySeries[.formula1] = resolvedF1Drivers
            driversBySeries[.motoGP]   = resolvedMotoGPDrivers
            eventsBySeries[.formula1]  = resolvedF1Events
            eventsBySeries[.motoGP]    = resolvedMotoGPEvents
            hasLoaded = true
        } catch {
            logger.error("Failed loading app data: \(error.localizedDescription, privacy: .public)")
            showError(error.localizedDescription)
        }
    }

    func drivers(for series: RaceSeries) -> [Driver] {
        driversBySeries[series] ?? []
    }

    func events(for series: RaceSeries) -> [RaceEvent] {
        eventsBySeries[series] ?? []
    }

    func allEvents() -> [RaceEvent] {
        RaceSeries.allCases
            .flatMap { eventsBySeries[$0] ?? [] }
            .sorted { $0.raceDate < $1.raceDate }
    }

    func nextEvent(for scope: ScoreboardScope) -> RaceEvent? {
        let eventsToSearch: [RaceEvent]
        if let series = scope.series {
            eventsToSearch = events(for: series)
        } else {
            eventsToSearch = allEvents()
        }

        let now = Date()
        return eventsToSearch.first(where: { $0.raceDate >= now }) ?? eventsToSearch.last
    }

    func pick(for series: RaceSeries, eventID: String, playerID: UUID) -> RacePick? {
        identityResolver(for: series).matchingPick(
            for: playerID,
            targetEventID: eventID,
            in: picks
        )
    }

    func result(for series: RaceSeries, eventID: String) -> RaceResult? {
        identityResolver(for: series).matchingResult(
            targetEventID: eventID,
            in: results
        )
    }

    func savePick(
        series: RaceSeries,
        eventID: String,
        playerID: UUID,
        draft: PodiumDraft
    ) async throws {
        guard let podium = draft.toPodium() else {
            throw RepositoryError.invalidPodium
        }

        let existingPick = pick(for: series, eventID: eventID, playerID: playerID)
        let existingID = existingPick?.id ?? UUID()
        let newPick = RacePick(
            id: existingID,
            series: series,
            eventID: existingPick?.eventID ?? eventID,
            playerID: playerID,
            podium: podium,
            updatedAt: Date()
        )

        let state = try await seasonRepository.upsertPick(newPick)
        apply(state: state)
    }

    func saveResult(
        series: RaceSeries,
        eventID: String,
        draft: PodiumDraft,
        lockResult: Bool = true
    ) async throws {
        guard let podium = draft.toPodium() else {
            throw RepositoryError.invalidPodium
        }

        if let existing = result(for: series, eventID: eventID), existing.isLocked {
            throw AppViewModelError.resultLocked
        }

        let existingResult = result(for: series, eventID: eventID)
        let result = RaceResult(
            series: series,
            eventID: existingResult?.eventID ?? eventID,
            podium: podium,
            isLocked: lockResult,
            updatedAt: Date()
        )
        let state = try await seasonRepository.upsertResult(result)
        apply(state: state)
    }

    func updateResultFromOfficialSource(
        series: RaceSeries,
        eventID: String,
        lockResult: Bool = true
    ) async throws {
        guard let event = events(for: series).first(where: { $0.id == eventID }) else {
            throw AppViewModelError.eventNotFound
        }

        let officialNames = try await resultRepository.podium(for: event)
        guard officialNames.count == 3 else {
            throw AppViewModelError.resultUnavailable
        }

        let ids: [String] = try officialNames.map { name in
            if let id = matchingParticipantID(for: name, series: series) {
                return id
            }
            throw AppViewModelError.participantNotFound(name: name)
        }

        let draft = PodiumDraft(p1: ids[0], p2: ids[1], p3: ids[2])
        try await saveResult(series: series, eventID: eventID, draft: draft, lockResult: lockResult)
    }

    func unlockResult(series: RaceSeries, eventID: String) async throws {
        guard var existing = result(for: series, eventID: eventID) else {
            return
        }
        existing.isLocked = false
        existing.updatedAt = Date()
        let state = try await seasonRepository.upsertResult(existing)
        apply(state: state)
    }

    func standings(for scope: ScoreboardScope) -> [PlayerStanding] {
        scoreboardCalculator.standings(
            players: players,
            picks: picks,
            results: results,
            events: allEvents(),
            scope: scope,
            driversBySeries: driversBySeries
        )
    }

    func history(for scope: ScoreboardScope) -> [EventScoreRow] {
        scoreboardCalculator.eventHistory(
            players: players,
            picks: picks,
            results: results,
            events: allEvents(),
            scope: scope,
            driversBySeries: driversBySeries
        )
    }

    func eventPoints(series: RaceSeries, eventID: String) -> [UUID: Int] {
        guard let result = result(for: series, eventID: eventID) else {
            return [:]
        }
        return scoringService.pointsByPlayer(
            players: players,
            picks: picks,
            result: result,
            series: series,
            eventID: eventID,
            events: events(for: series),
            participants: drivers(for: series)
        )
    }

    func leaderText(for scope: ScoreboardScope) -> String {
        scoreboardCalculator.leaderText(for: standings(for: scope))
    }

    func savePlayers(_ players: [Player]) async throws {
        let state = try await seasonRepository.savePlayers(players)
        apply(state: state)
    }

    func addPlayer(named name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updatedPlayers = players
        updatedPlayers.append(Player(id: UUID(), name: trimmed))
        try await savePlayers(updatedPlayers)
    }

    func removePlayers(withIDs ids: Set<UUID>) async throws {
        let updatedPlayers = players.filter { !ids.contains($0.id) }
        try await savePlayers(updatedPlayers)
    }

    func saveSettings(_ settings: AppSettings) async throws {
        let state = try await seasonRepository.saveSettings(settings)
        apply(state: state)
    }

    func resetSeason() async throws {
        let state = try await seasonRepository.resetSeason()
        apply(state: state)
    }

    private func apply(state: PersistedState) {
        players = state.players
        picks = state.picks
        results = state.results
        settings = state.settings
    }

    private func identityResolver(for series: RaceSeries) -> StoredIdentityResolver {
        StoredIdentityResolver(
            series: series,
            events: events(for: series),
            participants: drivers(for: series)
        )
    }

    // MARK: - Participant Name Matching

    /// Resolves an official result name (from the F1/MotoGP website) to a local
    /// driver ID using a three-tier strategy:
    ///
    /// - **Tier 1 – Exact:** Diacritic/case-folded full-name equality.
    /// - **Tier 2 – Surname:** The result name is a surname-only token (≥ 4 characters)
    ///   that matches exactly one token in a candidate's normalised name.  The 4-character
    ///   minimum prevents short tokens like "de", "van", or "al" from producing false
    ///   positives against multi-part surnames.
    /// - **Tier 3 – Token set:** Two or more tokens from the result name overlap with
    ///   tokens in the candidate name.  Requires both sides to contribute ≥ 2 tokens so
    ///   a single-word result name never triggers this tier.
    private func matchingParticipantID(for name: String, series: RaceSeries) -> String? {
        let normalizedTarget = normalizedParticipantName(name)
        guard !normalizedTarget.isEmpty else { return nil }

        let participants = drivers(for: series)

        // Tier 1: exact normalised match.
        if let exact = participants.first(where: { normalizedParticipantName($0.name) == normalizedTarget }) {
            return exact.id
        }

        // Tier 2: surname-only match.
        // Split the result name into tokens and consider each token a potential surname,
        // but only if it is long enough to be unambiguous (>= 4 characters).
        let targetTokens = normalizedTarget.split(separator: " ").map(String.init)
        let surnameCandidates = targetTokens.filter { $0.count >= 4 }

        if !surnameCandidates.isEmpty {
            // Find a participant whose normalised name contains at least one of the
            // surname candidates as an exact token — not just a substring.
            if let surnameMatch = participants.first(where: { participant in
                let participantTokens = Set(normalizedParticipantName(participant.name).split(separator: " ").map(String.init))
                return surnameCandidates.contains(where: { participantTokens.contains($0) })
            }) {
                return surnameMatch.id
            }
        }

        // Tier 3: token-set intersection (at least 2 shared tokens, both sides must be multi-token).
        let targetTokenSet = Set(targetTokens)
        if targetTokenSet.count >= 2 {
            if let tokenMatch = participants.first(where: { participant in
                let candidateTokens = Set(normalizedParticipantName(participant.name).split(separator: " ").map(String.init))
                guard candidateTokens.count >= 2 else { return false }
                return candidateTokens.intersection(targetTokenSet).count >= 2
            }) {
                return tokenMatch.id
            }
        }

        logger.debug("Name matching failed for '\(name, privacy: .public)' in \(series.rawValue, privacy: .public)")
        return nil
    }

    private func normalizedParticipantName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"[^a-zA-Z0-9 ]"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum AppViewModelError: LocalizedError {
    case resultLocked
    case eventNotFound
    case resultUnavailable
    case participantNotFound(name: String)

    var errorDescription: String? {
        switch self {
        case .resultLocked:
            return "Results are locked. Unlock first to edit."
        case .eventNotFound:
            return "Selected event could not be found."
        case .resultUnavailable:
            return "Official top-3 results are not available for this event yet."
        case let .participantNotFound(name):
            return "Could not match \(name) with the current participant list."
        }
    }
}

struct BannerMessage: Identifiable, Equatable {
    enum Style: Equatable {
        case info
        case error
    }

    let id: UUID
    let style: Style
    let text: String

    init(id: UUID = UUID(), style: Style, text: String) {
        self.id = id
        self.style = style
        self.text = text
    }
}

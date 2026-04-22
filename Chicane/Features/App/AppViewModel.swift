import Foundation
import Combine
import OSLog

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var players: [Player] = []
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var picks: [RacePick] = []
    @Published private(set) var results: [RaceResult] = []
    @Published private(set) var championPicks: [SeasonChampionPick] = []
    @Published private(set) var championResults: [SeasonChampionResult] = []
    @Published private(set) var driversBySeries: [RaceSeries: [Driver]] = [:]
    @Published private(set) var eventsBySeries: [RaceSeries: [RaceEvent]] = [:]
    @Published private(set) var championshipLeadersBySeries: [RaceSeries: [ChampionshipLeader]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?
    @Published var banner: BannerMessage?

    private let driverRepository: DriverRepository
    private let calendarRepository: CalendarRepository
    private let resultRepository: ResultRepository
    private let championshipRepository: ChampionshipRepository
    private let seasonRepository: SeasonRepository
    private let scoringService = ScoringService()
    private let scoreboardCalculator = ScoreboardCalculator()
    private let logger = Logger(subsystem: "dn.chicane", category: "AppViewModel")

    private var hasLoaded = false

    init(
        driverRepository: DriverRepository,
        calendarRepository: CalendarRepository,
        resultRepository: ResultRepository,
        championshipRepository: ChampionshipRepository = EmptyChampionshipRepository(),
        seasonRepository: SeasonRepository
    ) {
        self.driverRepository = driverRepository
        self.calendarRepository = calendarRepository
        self.resultRepository = resultRepository
        self.championshipRepository = championshipRepository
        self.seasonRepository = seasonRepository
    }

    func showInfo(_ message: String) {
        banner = BannerMessage(style: .info, text: message)
    }

    func showError(_ message: String) {
        banner = BannerMessage(style: .error, text: message)
        errorMessage = message
    }

    func showSaveOutcome(warning: String?, successMessage: String) {
        if let warning, !warning.isEmpty {
            showError(warning)
        } else {
            showInfo(successMessage)
        }
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

            // Preserve stable local IDs/titles when refresh switches from bundled
            // source data to online source data.
            let mergedF1Drivers = mergeDriversPreservingStableIDs(
                existing: driversBySeries[.formula1] ?? [],
                refreshed: resolvedF1Drivers
            )
            let mergedMotoGPDrivers = mergeDriversPreservingStableIDs(
                existing: driversBySeries[.motoGP] ?? [],
                refreshed: resolvedMotoGPDrivers
            )
            let mergedF1Events = mergeEventsPreservingStableIdentity(
                existing: eventsBySeries[.formula1] ?? [],
                refreshed: resolvedF1Events
            )
            let mergedMotoGPEvents = mergeEventsPreservingStableIdentity(
                existing: eventsBySeries[.motoGP] ?? [],
                refreshed: resolvedMotoGPEvents
            )

            // All four succeeded — apply as a single synchronous batch.
            driversBySeries[.formula1] = mergedF1Drivers
            driversBySeries[.motoGP]   = mergedMotoGPDrivers
            eventsBySeries[.formula1]  = mergedF1Events
            eventsBySeries[.motoGP]    = mergedMotoGPEvents
            await refreshChampionshipLeaders()
            hasLoaded = true
        } catch {
            logger.error("Failed loading app data: \(error.localizedDescription, privacy: .public)")
            showError(error.localizedDescription)
        }
    }

    func syncLeagueIfNeeded(showBannerOnSuccess: Bool = false) async {
        guard activeLeagueCode != nil else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let state = try await (showBannerOnSuccess
                ? seasonRepository.refreshState()
                : seasonRepository.loadState())
            apply(state: state)
            if showBannerOnSuccess {
                showInfo("League Synced")
            }
        } catch {
            logger.error("Failed syncing league: \(error.localizedDescription, privacy: .public)")
            if showBannerOnSuccess {
                showError(CloudSyncErrorFormatter.describe(error))
            }
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

    func championshipLeaders(for series: RaceSeries) -> [ChampionshipLeader] {
        championshipLeadersBySeries[series] ?? []
    }

    @discardableResult
    func savePick(
        series: RaceSeries,
        eventID: String,
        playerID: UUID,
        draft: PodiumDraft
    ) async throws -> String? {
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

        return try await persistState {
            try await seasonRepository.upsertPick(newPick)
        }
    }

    @discardableResult
    func saveResult(
        series: RaceSeries,
        eventID: String,
        draft: PodiumDraft,
        lockResult: Bool = true
    ) async throws -> String? {
        guard let podium = draft.toPodium() else {
            throw RepositoryError.invalidPodium
        }

        if result(for: series, eventID: eventID) != nil {
            throw AppViewModelError.resultLocked
        }

        let result = RaceResult(
            series: series,
            eventID: eventID,
            podium: podium,
            isLocked: lockResult,
            updatedAt: Date()
        )
        return try await persistState {
            try await seasonRepository.upsertResult(result)
        }
    }

    @discardableResult
    func updateResultFromOfficialSource(
        series: RaceSeries,
        eventID: String,
        lockResult: Bool = true
    ) async throws -> String? {
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
        let warning = try await saveResult(
            series: series,
            eventID: eventID,
            draft: draft,
            lockResult: lockResult
        )
        await refreshChampionshipLeaders()
        return warning
    }

    func standings(for scope: ScoreboardScope) -> [PlayerStanding] {
        scoreboardCalculator.standings(
            players: players,
            picks: picks,
            results: results,
            championPicks: championPicks,
            championResults: championResults,
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

    func championPick(for series: RaceSeries, playerID: UUID) -> SeasonChampionPick? {
        championPicks
            .filter { $0.series == series && $0.playerID == playerID }
            .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
    }

    func championResult(for series: RaceSeries) -> SeasonChampionResult? {
        championResults
            .filter { $0.series == series }
            .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
    }

    @discardableResult
    func saveChampionPick(
        series: RaceSeries,
        playerID: UUID,
        driverID: String
    ) async throws -> String? {
        if let existingResult = championResult(for: series), existingResult.isLocked {
            throw AppViewModelError.championPickLocked
        }

        let existingPick = championPick(for: series, playerID: playerID)
        let pick = SeasonChampionPick(
            id: existingPick?.id ?? UUID(),
            series: series,
            playerID: playerID,
            driverID: driverID,
            updatedAt: Date()
        )

        return try await persistState {
            try await seasonRepository.upsertChampionPick(pick)
        }
    }

    @discardableResult
    func saveChampionResult(series: RaceSeries, driverID: String) async throws -> String? {
        if let existing = championResult(for: series), existing.isLocked {
            throw AppViewModelError.championResultLocked
        }

        let result = SeasonChampionResult(
            series: series,
            driverID: driverID,
            isLocked: true,
            updatedAt: Date()
        )

        return try await persistState {
            try await seasonRepository.upsertChampionResult(result)
        }
    }

    func leaderText(for scope: ScoreboardScope) -> String {
        scoreboardCalculator.leaderText(for: standings(for: scope))
    }

    @discardableResult
    func savePlayers(_ players: [Player]) async throws -> String? {
        let sanitizedPlayers = players.map { player in
            var copy = player
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
        if sanitizedPlayers.contains(where: { $0.name.isEmpty }) {
            throw AppViewModelError.playerNameEmpty
        }

        return try await persistState {
            try await seasonRepository.savePlayers(sanitizedPlayers)
        }
    }

    @discardableResult
    func addPlayer(named name: String) async throws -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var updatedPlayers = players
        updatedPlayers.append(Player(id: UUID(), name: trimmed))
        return try await savePlayers(updatedPlayers)
    }

    @discardableResult
    func removePlayers(withIDs ids: Set<UUID>) async throws -> String? {
        let updatedPlayers = players.filter { !ids.contains($0.id) }
        return try await savePlayers(updatedPlayers)
    }

    @discardableResult
    func saveSettings(_ settings: AppSettings) async throws -> String? {
        try await persistState {
            try await seasonRepository.saveSettings(settings)
        }
    }

    @discardableResult
    func resetSeason() async throws -> String? {
        try await persistState {
            try await seasonRepository.resetSeason()
        }
    }

    @discardableResult
    func createLeague() async -> String? {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let state = try await seasonRepository.createLeague()
            apply(state: state)
            if let code = state.settings.leagueCode {
                showInfo("League ready: \(code)")
            } else {
                showInfo("League created")
            }
            return nil
        } catch {
            logger.error("Failed creating league: \(error.localizedDescription, privacy: .public)")
            showError(error.localizedDescription)
            return error.localizedDescription
        }
    }

    @discardableResult
    func joinLeague(code: String) async -> String? {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let state = try await seasonRepository.joinLeague(code: code)
            apply(state: state)
            if let joinedCode = state.settings.leagueCode {
                showInfo("Joined league \(joinedCode)")
            } else {
                showInfo("Joined league")
            }
            return nil
        } catch {
            logger.error("Failed joining league: \(error.localizedDescription, privacy: .public)")
            showError(error.localizedDescription)
            return error.localizedDescription
        }
    }

    private func apply(state: PersistedState) {
        players = state.players
        picks = state.picks
        results = state.results
        championPicks = state.championPicks
        championResults = state.championResults
        settings = state.settings
    }

    private func identityResolver(for series: RaceSeries) -> StoredIdentityResolver {
        StoredIdentityResolver(
            series: series,
            events: events(for: series),
            participants: drivers(for: series)
        )
    }

    private var activeLeagueCode: String? {
        let trimmed = settings.leagueCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func persistState(
        _ operation: () async throws -> PersistedState
    ) async throws -> String? {
        do {
            let state = try await operation()
            apply(state: state)
            return nil
        } catch let warning as DeferredCloudSyncWarning {
            apply(state: warning.state)
            let prefix = warning.errorDescription ?? "Saved locally, but shared league sync failed."
            let detail = CloudSyncErrorFormatter.describe(warning.underlyingError)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty else {
                return prefix
            }
            return "\(prefix) \(detail)"
        }
    }

    private func refreshChampionshipLeaders() async {
        async let f1Fetch = championshipRepository.topThree(for: .formula1)
        async let motoGPFetch = championshipRepository.topThree(for: .motoGP)

        let f1Leaders = try? await f1Fetch
        let motoGPLeaders = try? await motoGPFetch

        var updated = championshipLeadersBySeries
        if let f1Leaders, f1Leaders.count == 3 {
            updated[.formula1] = f1Leaders
        }
        if let motoGPLeaders, motoGPLeaders.count == 3 {
            updated[.motoGP] = motoGPLeaders
        }
        championshipLeadersBySeries = updated
    }

    private func mergeDriversPreservingStableIDs(
        existing: [Driver],
        refreshed: [Driver]
    ) -> [Driver] {
        guard !existing.isEmpty else { return refreshed }

        let existingIDByNameKey = existing.reduce(into: [String: String]()) { output, driver in
            output[normalizedParticipantName(driver.name)] = driver.id
        }

        return refreshed.map { driver in
            guard let stableID = existingIDByNameKey[normalizedParticipantName(driver.name)] else {
                return driver
            }
            return Driver(
                id: stableID,
                series: driver.series,
                name: driver.name,
                team: driver.team,
                number: driver.number
            )
        }
    }

    private func mergeEventsPreservingStableIdentity(
        existing: [RaceEvent],
        refreshed: [RaceEvent]
    ) -> [RaceEvent] {
        guard !existing.isEmpty else { return refreshed }
        let existingPool = existing

        return refreshed.map { event in
            guard let stableEvent = matchedExistingEvent(for: event, in: existingPool) else {
                return event
            }

            return RaceEvent(
                id: stableEvent.id,
                series: event.series,
                season: event.season,
                round: event.round,
                title: preferredDisplayText(existing: stableEvent.title, refreshed: event.title),
                circuit: preferredDisplayText(existing: stableEvent.circuit, refreshed: event.circuit),
                raceDate: event.raceDate,
                trackTimeZoneID: event.trackTimeZoneID ?? stableEvent.trackTimeZoneID
            )
        }
        .sorted {
            if $0.round == $1.round {
                return $0.raceDate < $1.raceDate
            }
            return $0.round < $1.round
        }
    }

    private func matchedExistingEvent(for refreshed: RaceEvent, in existing: [RaceEvent]) -> RaceEvent? {
        let sameSeriesSeason = existing.filter {
            $0.series == refreshed.series && $0.season == refreshed.season
        }

        if let exactIDMatch = sameSeriesSeason.first(where: { $0.id == refreshed.id }) {
            return exactIDMatch
        }

        let maxAllowedDateDelta: TimeInterval = 72 * 60 * 60
        let candidates = sameSeriesSeason.filter {
            abs($0.raceDate.timeIntervalSince(refreshed.raceDate)) <= maxAllowedDateDelta
        }

        guard !candidates.isEmpty else {
            return nil
        }

        return candidates.min {
            let lhsDelta = abs($0.raceDate.timeIntervalSince(refreshed.raceDate))
            let rhsDelta = abs($1.raceDate.timeIntervalSince(refreshed.raceDate))

            if lhsDelta == rhsDelta {
                return identityScore(existing: $0, refreshed: refreshed) >
                    identityScore(existing: $1, refreshed: refreshed)
            }

            return lhsDelta < rhsDelta
        }
    }

    private func preferredDisplayText(existing: String, refreshed: String) -> String {
        let existingTrimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshedTrimmed = refreshed.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !refreshedTrimmed.isEmpty else { return existingTrimmed }
        guard !existingTrimmed.isEmpty else { return refreshedTrimmed }

        // If refreshed looks less descriptive (e.g. "Spanish GP" vs
        // "Estrella Galicia 0,0 Grand Prix Of Spain"), preserve the richer local text.
        if refreshedTrimmed.count < existingTrimmed.count {
            return existingTrimmed
        }
        return refreshedTrimmed
    }

    private func identityScore(existing: RaceEvent, refreshed: RaceEvent) -> Int {
        let existingTokens = eventIdentityTokens(for: existing)
        let refreshedTokens = eventIdentityTokens(for: refreshed)
        return existingTokens.intersection(refreshedTokens).count
    }

    private func eventIdentityTokens(for event: RaceEvent) -> Set<String> {
        Set(
            normalizedEventIdentityText("\(event.title) \(event.circuit)")
                .split(separator: " ")
                .map(String.init)
        )
    }

    private func normalizedEventIdentityText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"\b(grand|prix|gp|circuit|autodromo|international|motorcycle|motogp|formula|one|de|del|of|the|and)\b"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[^a-z0-9 ]"#,
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
        if let exact = uniquelyMatchedParticipant(
            in: participants,
            where: { normalizedParticipantName($0.name) == normalizedTarget }
        ) {
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
            if let surnameMatch = uniquelyMatchedParticipant(
                in: participants,
                where: { participant in
                    let participantTokens = Set(normalizedParticipantName(participant.name).split(separator: " ").map(String.init))
                    return surnameCandidates.contains(where: { participantTokens.contains($0) })
                }
            ) {
                return surnameMatch.id
            }
        }

        // Tier 3: token-set intersection (at least 2 shared tokens, both sides must be multi-token).
        let targetTokenSet = Set(targetTokens)
        if targetTokenSet.count >= 2 {
            if let tokenMatch = uniquelyMatchedParticipant(
                in: participants,
                where: { participant in
                    let candidateTokens = Set(normalizedParticipantName(participant.name).split(separator: " ").map(String.init))
                    guard candidateTokens.count >= 2 else { return false }
                    return candidateTokens.intersection(targetTokenSet).count >= 2
                }
            ) {
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

    private func uniquelyMatchedParticipant(
        in participants: [Driver],
        where predicate: (Driver) -> Bool
    ) -> Driver? {
        let matches = participants.filter(predicate)
        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }
}

enum AppViewModelError: LocalizedError {
    case resultLocked
    case championPickLocked
    case championResultLocked
    case playerNameEmpty
    case eventNotFound
    case resultUnavailable
    case participantNotFound(name: String)

    var errorDescription: String? {
        switch self {
        case .resultLocked:
            return "Official results are final once retrieved."
        case .championPickLocked:
            return "Champion picks lock once the official season champion is entered."
        case .championResultLocked:
            return "Season champion is locked and cannot be changed."
        case .playerNameEmpty:
            return "Player names cannot be blank. Use Remove to delete a player."
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

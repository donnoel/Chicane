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

            async let f1Drivers = driverRepository.drivers(for: .formula1)
            async let motoGPDrivers = driverRepository.drivers(for: .motoGP)
            async let f1Events = calendarRepository.events(for: .formula1)
            async let motoGPEvents = calendarRepository.events(for: .motoGP)

            driversBySeries[.formula1] = try await f1Drivers
            driversBySeries[.motoGP] = try await motoGPDrivers
            eventsBySeries[.formula1] = try await f1Events
            eventsBySeries[.motoGP] = try await motoGPEvents
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
        picks.first {
            $0.series == series &&
            $0.eventID == eventID &&
            $0.playerID == playerID
        }
    }

    func result(for series: RaceSeries, eventID: String) -> RaceResult? {
        results.first {
            $0.series == series && $0.eventID == eventID
        }
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

        let existingID = pick(for: series, eventID: eventID, playerID: playerID)?.id ?? UUID()
        let newPick = RacePick(
            id: existingID,
            series: series,
            eventID: eventID,
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

        let result = RaceResult(
            series: series,
            eventID: eventID,
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
            scope: scope
        )
    }

    func history(for scope: ScoreboardScope) -> [EventScoreRow] {
        scoreboardCalculator.eventHistory(
            players: players,
            picks: picks,
            results: results,
            events: allEvents(),
            scope: scope
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
            eventID: eventID
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

    private func matchingParticipantID(for name: String, series: RaceSeries) -> String? {
        let normalizedTarget = normalizedParticipantName(name)
        guard !normalizedTarget.isEmpty else { return nil }

        let participants = drivers(for: series)

        if let exact = participants.first(where: { normalizedParticipantName($0.name) == normalizedTarget }) {
            return exact.id
        }

        if let partial = participants.first(where: {
            let candidate = normalizedParticipantName($0.name)
            return candidate.contains(normalizedTarget) || normalizedTarget.contains(candidate)
        }) {
            return partial.id
        }

        let targetTokens = Set(normalizedTarget.split(separator: " ").map(String.init))
        if let tokenMatch = participants.first(where: {
            let candidateTokens = Set(normalizedParticipantName($0.name).split(separator: " ").map(String.init))
            return candidateTokens.intersection(targetTokens).count >= 2
        }) {
            return tokenMatch.id
        }

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

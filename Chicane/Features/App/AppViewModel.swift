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

    private let driverRepository: DriverRepository
    private let calendarRepository: CalendarRepository
    private let seasonRepository: SeasonRepository
    private let scoringService = ScoringService()
    private let scoreboardCalculator = ScoreboardCalculator()
    private let logger = Logger(subsystem: "dn.chicane", category: "AppViewModel")

    private var hasLoaded = false

    init(
        driverRepository: DriverRepository,
        calendarRepository: CalendarRepository,
        seasonRepository: SeasonRepository
    ) {
        self.driverRepository = driverRepository
        self.calendarRepository = calendarRepository
        self.seasonRepository = seasonRepository
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
            errorMessage = error.localizedDescription
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
}

enum AppViewModelError: LocalizedError {
    case resultLocked

    var errorDescription: String? {
        switch self {
        case .resultLocked:
            return "Results are locked. Unlock first to edit."
        }
    }
}

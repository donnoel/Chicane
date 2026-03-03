import Foundation

protocol DriverRepository: Sendable {
    func drivers(for series: RaceSeries) async throws -> [Driver]
}

protocol CalendarRepository: Sendable {
    func events(for series: RaceSeries) async throws -> [RaceEvent]
    func allEvents() async throws -> [RaceEvent]
}

protocol ResultRepository: Sendable {
    func podium(for event: RaceEvent) async throws -> [String]
}

protocol SeasonRepository: Sendable {
    func loadState() async throws -> PersistedState
    func refreshState() async throws -> PersistedState
    func savePlayers(_ players: [Player]) async throws -> PersistedState
    func saveSettings(_ settings: AppSettings) async throws -> PersistedState
    func upsertPick(_ pick: RacePick) async throws -> PersistedState
    func upsertResult(_ result: RaceResult) async throws -> PersistedState
    func upsertChampionPick(_ pick: SeasonChampionPick) async throws -> PersistedState
    func upsertChampionResult(_ result: SeasonChampionResult) async throws -> PersistedState
    func resetSeason() async throws -> PersistedState
    func createLeague() async throws -> PersistedState
    func joinLeague(code: String) async throws -> PersistedState
}

enum RepositoryError: LocalizedError {
    case missingBundleResource(name: String)
    case invalidPodium
    case cloudSyncUnavailable
    case leagueNotConfigured
    case leagueNotFound(code: String)

    var errorDescription: String? {
        switch self {
        case let .missingBundleResource(name):
            return "Missing bundled resource: \(name)."
        case .invalidPodium:
            return "Pick 3 unique podium selections."
        case .cloudSyncUnavailable:
            return "iCloud league sync is not available right now."
        case .leagueNotConfigured:
            return "Create or join a shared league first."
        case let .leagueNotFound(code):
            return "No shared league found for code \(code)."
        }
    }
}

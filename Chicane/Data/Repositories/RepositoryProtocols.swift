import Foundation

protocol DriverRepository: Sendable {
    func drivers(for series: RaceSeries) async throws -> [Driver]
}

protocol CalendarRepository: Sendable {
    func events(for series: RaceSeries) async throws -> [RaceEvent]
    func allEvents() async throws -> [RaceEvent]
}

protocol SeasonRepository: Sendable {
    func loadState() async throws -> PersistedState
    func savePlayers(_ players: [Player]) async throws -> PersistedState
    func saveSettings(_ settings: AppSettings) async throws -> PersistedState
    func upsertPick(_ pick: RacePick) async throws -> PersistedState
    func upsertResult(_ result: RaceResult) async throws -> PersistedState
    func resetSeason() async throws -> PersistedState
}

enum RepositoryError: LocalizedError {
    case missingBundleResource(name: String)
    case invalidPodium

    var errorDescription: String? {
        switch self {
        case let .missingBundleResource(name):
            return "Missing bundled resource: \(name)."
        case .invalidPodium:
            return "Pick 3 unique drivers."
        }
    }
}

import Foundation
import OSLog

actor FileStateStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private let logger = Logger(subsystem: "dn.chicane", category: "FileStateStore")

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        fileName: String = "season_state_v1.json"
    ) {
        self.fileManager = fileManager
        let baseURL = baseDirectoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.fileURL = baseURL
            .appendingPathComponent("Chicane", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func load() throws -> PersistedState {
        try ensureDirectoryExists()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return PersistedState.default
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PersistedState.self, from: data)
        return state.normalized()
    }

    func save(_ state: PersistedState) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state.normalized())
        try data.write(to: fileURL, options: .atomic)
        logger.debug("Persisted state to disk at \(self.fileURL.path, privacy: .private(mask: .hash))")
    }

    private func ensureDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}

actor LocalSeasonRepository: SeasonRepository {
    private enum MutationKind {
        case players
        case settings
        case picks
        case results
        case championPicks
        case championResults
        case reset
    }

    private let store: FileStateStore

    /// In-memory mirror of the last persisted state.
    ///
    /// **Known limitation — intentional for this use-case:**
    /// `cachedState` is populated on first load and updated on every write that goes
    /// through this actor.  It is *not* invalidated if the backing file is modified
    /// externally (e.g. by iCloud Drive sync, a future Share Extension, or direct
    /// file-system access in tests).  For the current single-process, no-cloud design
    /// this is safe: all writes flow through `mutateState` which always refreshes the
    /// cache.  If a background-sync or multi-process scenario is added in future, replace
    /// this with a file-coordinator / NSFilePresenter based approach, or simply set
    /// `cachedState = nil` before any load that must see external changes.
    private var cachedState: PersistedState?

    init(store: FileStateStore = FileStateStore()) {
        self.store = store
    }

    func loadState() async throws -> PersistedState {
        if let cachedState {
            return cachedState
        }
        let loaded = try await store.load()
        let normalized = loaded.normalized()
        cachedState = normalized
        return normalized
    }

    func refreshState() async throws -> PersistedState {
        try await loadState()
    }

    func savePlayers(_ players: [Player]) async throws -> PersistedState {
        try await mutateState(kind: .players) { state in
            state.players = players
                .map { player in
                    var copy = player
                    copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return copy
                }
                .filter { !$0.name.isEmpty }

            let validPlayerIDs = Set(state.players.map(\.id))
            state.picks = state.picks.filter { validPlayerIDs.contains($0.playerID) }
            state.championPicks = state.championPicks.filter { validPlayerIDs.contains($0.playerID) }
        }
    }

    func saveSettings(_ settings: AppSettings) async throws -> PersistedState {
        try await mutateState(kind: .settings) { state in
            state.settings = settings
        }
    }

    func upsertPick(_ pick: RacePick) async throws -> PersistedState {
        guard pick.podium.isUnique else {
            throw RepositoryError.invalidPodium
        }

        return try await mutateState(kind: .picks) { state in
            state.picks.removeAll {
                $0.series == pick.series &&
                $0.eventID == pick.eventID &&
                $0.playerID == pick.playerID
            }
            state.picks.append(pick)
        }
    }

    func upsertResult(_ result: RaceResult) async throws -> PersistedState {
        guard result.podium.isUnique else {
            throw RepositoryError.invalidPodium
        }

        return try await mutateState(kind: .results) { state in
            state.results.removeAll {
                $0.series == result.series && $0.eventID == result.eventID
            }
            state.results.append(result)
        }
    }

    func upsertChampionPick(_ pick: SeasonChampionPick) async throws -> PersistedState {
        return try await mutateState(kind: .championPicks) { state in
            state.championPicks.removeAll {
                $0.series == pick.series && $0.playerID == pick.playerID
            }
            state.championPicks.append(pick)
        }
    }

    func upsertChampionResult(_ result: SeasonChampionResult) async throws -> PersistedState {
        return try await mutateState(kind: .championResults) { state in
            state.championResults.removeAll { $0.series == result.series }
            state.championResults.append(result)
        }
    }

    func resetSeason() async throws -> PersistedState {
        try await mutateState(kind: .reset) { state in
            state.picks = []
            state.results = []
            state.championPicks = []
            state.championResults = []
        }
    }

    func createLeague() async throws -> PersistedState {
        throw RepositoryError.cloudSyncUnavailable
    }

    func joinLeague(code _: String) async throws -> PersistedState {
        throw RepositoryError.cloudSyncUnavailable
    }

    func replaceState(_ state: PersistedState) async throws -> PersistedState {
        let normalized = state.normalized()
        try await store.save(normalized)
        cachedState = normalized
        return normalized
    }

    private func mutateState(
        kind: MutationKind,
        _ body: (inout PersistedState) -> Void
    ) async throws -> PersistedState {
        var state = try await loadState()
        let mutationDate = Date()
        body(&state)
        switch kind {
        case .players:
            state.playersUpdatedAt = mutationDate
        case .settings:
            state.settingsUpdatedAt = mutationDate
        case .picks, .results, .championPicks, .championResults:
            break
        case .reset:
            state.seasonResetAt = mutationDate
        }
        state.updatedAt = mutationDate
        state = state.normalized()
        try await store.save(state)
        cachedState = state
        return state
    }
}

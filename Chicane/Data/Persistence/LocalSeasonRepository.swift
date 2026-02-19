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
    private let store: FileStateStore
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

    func savePlayers(_ players: [Player]) async throws -> PersistedState {
        try await mutateState { state in
            state.players = players
                .map { player in
                    var copy = player
                    copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return copy
                }
                .filter { !$0.name.isEmpty }

            let validPlayerIDs = Set(state.players.map(\.id))
            state.picks = state.picks.filter { validPlayerIDs.contains($0.playerID) }
        }
    }

    func saveSettings(_ settings: AppSettings) async throws -> PersistedState {
        try await mutateState { state in
            state.settings = settings
        }
    }

    func upsertPick(_ pick: RacePick) async throws -> PersistedState {
        guard pick.podium.isUnique else {
            throw RepositoryError.invalidPodium
        }

        return try await mutateState { state in
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

        return try await mutateState { state in
            state.results.removeAll {
                $0.series == result.series && $0.eventID == result.eventID
            }
            state.results.append(result)
        }
    }

    func resetSeason() async throws -> PersistedState {
        try await mutateState { state in
            state.picks = []
            state.results = []
        }
    }

    private func mutateState(_ body: (inout PersistedState) -> Void) async throws -> PersistedState {
        var state = try await loadState()
        body(&state)
        state = state.normalized()
        try await store.save(state)
        cachedState = state
        return state
    }
}

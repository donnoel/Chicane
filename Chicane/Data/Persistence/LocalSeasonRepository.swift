import Foundation
import OSLog

actor FileStateStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private let logger = Logger(subsystem: "dn.chicane", category: "FileStateStore")
    private var pendingLoadRecoveryMessage: String?

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

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            return state.normalized()
        } catch {
            let quarantinedURL = try? quarantineCorruptStateFile()
            let message = "Recovered local data after a storage issue. A backup of the previous local state was saved and default settings were restored."
            pendingLoadRecoveryMessage = message
            if let quarantinedURL {
                logger.error("Recovered from unreadable persisted state. Quarantined file at \(quarantinedURL.path, privacy: .private(mask: .hash)). Error: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.error("Recovered from unreadable persisted state, but quarantine rename failed. Error: \(error.localizedDescription, privacy: .public)")
            }
            return PersistedState.default
        }
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

    func consumeLoadRecoveryMessage() -> String? {
        defer { pendingLoadRecoveryMessage = nil }
        return pendingLoadRecoveryMessage
    }

    private func quarantineCorruptStateFile() throws -> URL {
        let directoryURL = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())

        var quarantinedName = "\(stem).corrupt-\(timestamp)"
        if !fileExtension.isEmpty {
            quarantinedName += ".\(fileExtension)"
        }
        var quarantinedURL = directoryURL.appendingPathComponent(quarantinedName, isDirectory: false)
        if fileManager.fileExists(atPath: quarantinedURL.path) {
            let suffix = UUID().uuidString.prefix(8)
            var fallbackName = "\(stem).corrupt-\(timestamp)-\(suffix)"
            if !fileExtension.isEmpty {
                fallbackName += ".\(fileExtension)"
            }
            quarantinedURL = directoryURL.appendingPathComponent(fallbackName, isDirectory: false)
        }

        try fileManager.moveItem(at: fileURL, to: quarantinedURL)
        return quarantinedURL
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
    /// `loadState()` returns the warm cache after first load.
    /// `refreshState()` bypasses that cache and re-reads disk so explicit refreshes
    /// can see external file changes or restored backups.
    private var cachedState: PersistedState?
    private var pendingLoadRecoveryMessage: String?

    init(store: FileStateStore = FileStateStore()) {
        self.store = store
    }

    func loadState() async throws -> PersistedState {
        if let cachedState {
            return cachedState
        }
        return try await reloadStateFromDisk()
    }

    func refreshState() async throws -> PersistedState {
        try await reloadStateFromDisk()
    }

    func consumeLoadRecoveryMessage() async -> String? {
        defer { pendingLoadRecoveryMessage = nil }
        return pendingLoadRecoveryMessage
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
            state.settings.playerBetTextByPlayerID = state.settings.playerBetTextByPlayerID.reduce(into: [:]) { partialResult, entry in
                guard validPlayerIDs.contains(entry.key) else { return }
                let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                partialResult[entry.key] = trimmed
            }
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

    private func reloadStateFromDisk() async throws -> PersistedState {
        let loaded = try await store.load()
        pendingLoadRecoveryMessage = await store.consumeLoadRecoveryMessage()
        let normalized = loaded.normalized()
        cachedState = normalized
        return normalized
    }
}

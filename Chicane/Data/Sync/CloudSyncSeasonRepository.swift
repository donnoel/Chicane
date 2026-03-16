import Foundation
import OSLog

struct DeferredCloudSyncWarning: LocalizedError {
    let state: PersistedState
    let underlyingError: Error

    var errorDescription: String? {
        "Saved locally, but shared league sync failed. Try Sync Now."
    }
}

actor CloudSyncSeasonRepository: SeasonRepository {
    private enum Constants {
        static let leagueCodeLength = 6
        static let joinLookupAttempts = 8
        static let joinRetryDelayNanoseconds: UInt64 = 1_000_000_000
        static let synchronizeAttempts = 4
        static let synchronizeRetryDelayNanoseconds: UInt64 = 300_000_000
        static let deferredPushAttempts = 5
        static let deferredPushRetryDelayNanoseconds: UInt64 = 400_000_000
    }

    private let localRepository: LocalSeasonRepository
    private let cloudStore: any LeagueSyncStore
    private let logger = Logger(subsystem: "dn.chicane", category: "CloudSyncSeasonRepository")

    private struct MergePreference {
        var preferLocalPlayers = false
        var preferLocalSettings = false
        var preferLocalReset = false
        var preferredPickKeys: Set<PickKey> = []
        var preferredResultKeys: Set<ResultKey> = []
        var preferredChampionPickKeys: Set<ChampionPickKey> = []
        var preferredChampionResultSeries: Set<RaceSeries> = []

        static let none = MergePreference()
    }

    init(
        localRepository: LocalSeasonRepository = LocalSeasonRepository(),
        cloudStore: any LeagueSyncStore = PublicCloudLeagueStore()
    ) {
        self.localRepository = localRepository
        self.cloudStore = cloudStore
    }

    func loadState() async throws -> PersistedState {
        let state = try await localRepository.loadState()
        return try await synchronize(localState: state, surfaceCloudErrors: false, preference: .none)
    }

    func refreshState() async throws -> PersistedState {
        let state = try await localRepository.refreshState()
        return try await synchronize(localState: state, surfaceCloudErrors: true, preference: .none)
    }

    func savePlayers(_ players: [Player]) async throws -> PersistedState {
        let state = try await localRepository.savePlayers(players)
        return try await pushIfNeeded(state, preference: MergePreference(preferLocalPlayers: true))
    }

    func saveSettings(_ settings: AppSettings) async throws -> PersistedState {
        let state = try await localRepository.saveSettings(settings)
        return try await pushIfNeeded(state, preference: MergePreference(preferLocalSettings: true))
    }

    func upsertPick(_ pick: RacePick) async throws -> PersistedState {
        let state = try await localRepository.upsertPick(pick)
        return try await pushIfNeeded(
            state,
            preference: MergePreference(preferredPickKeys: [PickKey(pick: pick)])
        )
    }

    func upsertResult(_ result: RaceResult) async throws -> PersistedState {
        let state = try await localRepository.upsertResult(result)
        return try await pushIfNeeded(
            state,
            preference: MergePreference(preferredResultKeys: [ResultKey(result: result)])
        )
    }

    func upsertChampionPick(_ pick: SeasonChampionPick) async throws -> PersistedState {
        let state = try await localRepository.upsertChampionPick(pick)
        return try await pushIfNeeded(
            state,
            preference: MergePreference(preferredChampionPickKeys: [ChampionPickKey(pick: pick)])
        )
    }

    func upsertChampionResult(_ result: SeasonChampionResult) async throws -> PersistedState {
        let state = try await localRepository.upsertChampionResult(result)
        return try await pushIfNeeded(
            state,
            preference: MergePreference(preferredChampionResultSeries: [result.series])
        )
    }

    func resetSeason() async throws -> PersistedState {
        let state = try await localRepository.resetSeason()
        return try await pushIfNeeded(state, preference: MergePreference(preferLocalReset: true))
    }

    func createLeague() async throws -> PersistedState {
        let localState = try await localRepository.loadState()
        if normalizedLeagueCode(from: localState) != nil {
            return try await synchronize(
                localState: localState,
                surfaceCloudErrors: true,
                preference: .none
            )
        }

        let sharedState = try await cloudStore.createLeague(from: localState)
        return try await localRepository.replaceState(sharedState)
    }

    func joinLeague(code: String) async throws -> PersistedState {
        let requestedCode = normalizedLeagueCode(code)
            ?? code.trimmingCharacters(in: .whitespacesAndNewlines)
        var sharedState = try await fetchSharedStateForJoin(code: requestedCode)
        if let normalizedCode = normalizedLeagueCode(requestedCode) {
            sharedState.settings.leagueCode = normalizedCode
        }
        return try await localRepository.replaceState(sharedState)
    }

    private func synchronize(
        localState: PersistedState,
        surfaceCloudErrors: Bool,
        preference: MergePreference
    ) async throws -> PersistedState {
        guard let code = normalizedLeagueCode(from: localState) else {
            return localState
        }

        var lastError: Error?
        for attempt in 1 ... Constants.synchronizeAttempts {
            do {
                guard let remoteState = try await cloudStore.fetchState(for: code) else {
                    try await cloudStore.pushState(localState, for: code)
                    return localState
                }

                let mergedState = mergedState(
                    local: localState,
                    remote: remoteState,
                    leagueCode: code,
                    preference: preference
                )

                if mergedState != remoteState {
                    try await cloudStore.pushState(mergedState, for: code)
                }

                if mergedState != localState {
                    return try await localRepository.replaceState(mergedState)
                }

                return mergedState
            } catch {
                lastError = error
                logger.error("Cloud sync attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                guard attempt < Constants.synchronizeAttempts else {
                    break
                }
                try? await Task.sleep(nanoseconds: Constants.synchronizeRetryDelayNanoseconds)
            }
        }

        if surfaceCloudErrors {
            throw lastError ?? RepositoryError.cloudSyncUnavailable
        }
        return localState
    }

    private func pushIfNeeded(
        _ state: PersistedState,
        preference: MergePreference
    ) async throws -> PersistedState {
        guard let code = normalizedLeagueCode(from: state) else {
            return state
        }

        var lastError: Error?
        for attempt in 1 ... Constants.deferredPushAttempts {
            do {
                let remoteState = try await cloudStore.fetchState(for: code)
                let mergedState = mergedState(
                    local: state,
                    remote: remoteState,
                    leagueCode: code,
                    preference: preference
                )

                if remoteState != .some(mergedState) {
                    try await cloudStore.pushState(mergedState, for: code)
                }

                if mergedState != state {
                    return try await localRepository.replaceState(mergedState)
                }
                return state
            } catch {
                lastError = error
                logger.error("Deferred cloud push attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                guard attempt < Constants.deferredPushAttempts else {
                    break
                }
                try? await Task.sleep(nanoseconds: Constants.deferredPushRetryDelayNanoseconds)
            }
        }

        throw DeferredCloudSyncWarning(
            state: state,
            underlyingError: lastError ?? RepositoryError.cloudSyncUnavailable
        )
    }

    private func normalizedLeagueCode(from state: PersistedState) -> String? {
        normalizedLeagueCode(state.settings.leagueCode)
    }

    private func normalizedLeagueCode(_ code: String?) -> String? {
        guard let code else {
            return nil
        }

        let allowed = code.uppercased().filter { $0.isLetter || $0.isNumber }
        let normalized = String(allowed.prefix(Constants.leagueCodeLength))
        guard !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private func fetchSharedStateForJoin(code: String) async throws -> PersistedState {
        for attempt in 1 ... Constants.joinLookupAttempts {
            do {
                return try await cloudStore.joinLeague(code: code)
            } catch let error as RepositoryError {
                guard case .leagueNotFound = error, attempt < Constants.joinLookupAttempts else {
                    throw error
                }
                try await Task.sleep(nanoseconds: Constants.joinRetryDelayNanoseconds)
            }
        }

        throw RepositoryError.leagueNotFound(code: code)
    }

    private func mergedState(
        local: PersistedState,
        remote: PersistedState?,
        leagueCode: String,
        preference: MergePreference
    ) -> PersistedState {
        guard let remote else {
            var state = local
            state.settings.leagueCode = leagueCode
            return state.normalized()
        }

        let resetCutoff: Date? = if preference.preferLocalReset {
            local.seasonResetAt ?? remote.seasonResetAt
        } else {
            [local.seasonResetAt, remote.seasonResetAt]
                .compactMap { $0 }
                .max()
        }

        var merged = PersistedState(
            schemaVersion: PersistedState.currentSchemaVersion,
            updatedAt: max(local.updatedAt, remote.updatedAt),
            playersUpdatedAt: max(local.playersUpdatedAt, remote.playersUpdatedAt),
            settingsUpdatedAt: max(local.settingsUpdatedAt, remote.settingsUpdatedAt),
            seasonResetAt: resetCutoff,
            players: mergePlayers(
                localPlayers: local.players,
                localPlayersUpdatedAt: local.playersUpdatedAt,
                remotePlayers: remote.players,
                remotePlayersUpdatedAt: remote.playersUpdatedAt,
                localStateUpdatedAt: local.updatedAt,
                remoteStateUpdatedAt: remote.updatedAt,
                preferLocalOverride: preference.preferLocalPlayers
            ),
            picks: mergePicks(
                local.picks,
                remote.picks,
                resetCutoff: resetCutoff,
                preferredLocalKeys: preference.preferredPickKeys
            ),
            results: mergeResults(
                local.results,
                remote.results,
                resetCutoff: resetCutoff,
                preferredLocalKeys: preference.preferredResultKeys
            ),
            championPicks: mergeChampionPicks(
                local.championPicks,
                remote.championPicks,
                resetCutoff: resetCutoff,
                preferredLocalKeys: preference.preferredChampionPickKeys
            ),
            championResults: mergeChampionResults(
                local.championResults,
                remote.championResults,
                resetCutoff: resetCutoff,
                preferredLocalSeries: preference.preferredChampionResultSeries
            ),
            settings: mergeSettings(
                localSettings: local.settings,
                localSettingsUpdatedAt: local.settingsUpdatedAt,
                remoteSettings: remote.settings,
                remoteSettingsUpdatedAt: remote.settingsUpdatedAt,
                localStateUpdatedAt: local.updatedAt,
                remoteStateUpdatedAt: remote.updatedAt,
                preferLocalOverride: preference.preferLocalSettings
            )
        )

        merged.settings.leagueCode = leagueCode

        let validPlayerIDs = Set(merged.players.map(\.id))
        merged.picks = merged.picks.filter { validPlayerIDs.contains($0.playerID) }
        merged.championPicks = merged.championPicks.filter { validPlayerIDs.contains($0.playerID) }
        return merged.normalized()
    }

    private func mergePlayers(
        localPlayers: [Player],
        localPlayersUpdatedAt: Date,
        remotePlayers: [Player],
        remotePlayersUpdatedAt: Date,
        localStateUpdatedAt: Date,
        remoteStateUpdatedAt: Date,
        preferLocalOverride: Bool
    ) -> [Player] {
        let preferLocal: Bool
        if preferLocalOverride {
            preferLocal = true
        } else {
            preferLocal = prefersLocalSection(
                localSectionUpdatedAt: localPlayersUpdatedAt,
                remoteSectionUpdatedAt: remotePlayersUpdatedAt,
                localStateUpdatedAt: localStateUpdatedAt,
                remoteStateUpdatedAt: remoteStateUpdatedAt
            )
        }

        var playersByID: [UUID: Player] = [:]
        if preferLocal {
            for player in remotePlayers {
                playersByID[player.id] = player
            }
            for player in localPlayers {
                playersByID[player.id] = player
            }
        } else {
            for player in localPlayers {
                playersByID[player.id] = player
            }
            for player in remotePlayers {
                playersByID[player.id] = player
            }
        }

        return Array(playersByID.values).sorted { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func mergeSettings(
        localSettings: AppSettings,
        localSettingsUpdatedAt: Date,
        remoteSettings: AppSettings,
        remoteSettingsUpdatedAt: Date,
        localStateUpdatedAt: Date,
        remoteStateUpdatedAt: Date,
        preferLocalOverride: Bool
    ) -> AppSettings {
        let preferLocal: Bool
        if preferLocalOverride {
            preferLocal = true
        } else {
            preferLocal = prefersLocalSection(
                localSectionUpdatedAt: localSettingsUpdatedAt,
                remoteSectionUpdatedAt: remoteSettingsUpdatedAt,
                localStateUpdatedAt: localStateUpdatedAt,
                remoteStateUpdatedAt: remoteStateUpdatedAt
            )
        }

        let preferred = preferLocal ? localSettings : remoteSettings
        let fallback = preferLocal ? remoteSettings : localSettings

        var merged = preferred
        var mergedBets = fallback.playerBetTextByPlayerID
        for (playerID, betText) in preferred.playerBetTextByPlayerID {
            mergedBets[playerID] = betText
        }
        merged.playerBetTextByPlayerID = mergedBets
        return merged
    }

    private func mergedSectionValue<T>(
        localValue: T,
        localSectionUpdatedAt: Date,
        remoteValue: T,
        remoteSectionUpdatedAt: Date,
        localStateUpdatedAt: Date,
        remoteStateUpdatedAt: Date
    ) -> T {
        prefersLocalSection(
            localSectionUpdatedAt: localSectionUpdatedAt,
            remoteSectionUpdatedAt: remoteSectionUpdatedAt,
            localStateUpdatedAt: localStateUpdatedAt,
            remoteStateUpdatedAt: remoteStateUpdatedAt
        ) ? localValue : remoteValue
    }

    private func prefersLocalSection(
        localSectionUpdatedAt: Date,
        remoteSectionUpdatedAt: Date,
        localStateUpdatedAt: Date,
        remoteStateUpdatedAt: Date
    ) -> Bool {
        if localSectionUpdatedAt != remoteSectionUpdatedAt {
            return localSectionUpdatedAt > remoteSectionUpdatedAt
        }

        if localStateUpdatedAt != remoteStateUpdatedAt {
            return localStateUpdatedAt > remoteStateUpdatedAt
        }

        return true
    }

    private func mergePicks(
        _ local: [RacePick],
        _ remote: [RacePick],
        resetCutoff: Date?,
        preferredLocalKeys: Set<PickKey>
    ) -> [RacePick] {
        let filteredLocal = local.filter { pick in
            guard let resetCutoff else { return true }
            return pick.updatedAt >= resetCutoff
        }
        let filteredRemote = remote.filter { pick in
            guard let resetCutoff else { return true }
            return pick.updatedAt >= resetCutoff
        }

        var localByKey: [PickKey: RacePick] = [:]
        for pick in filteredLocal {
            let key = PickKey(pick: pick)
            if let existing = localByKey[key], existing.updatedAt > pick.updatedAt {
                continue
            }
            localByKey[key] = pick
        }

        var remoteByKey: [PickKey: RacePick] = [:]
        for pick in filteredRemote {
            let key = PickKey(pick: pick)
            if let existing = remoteByKey[key], existing.updatedAt > pick.updatedAt {
                continue
            }
            remoteByKey[key] = pick
        }

        var picksByKey: [PickKey: RacePick] = [:]
        let allKeys = Set(localByKey.keys).union(remoteByKey.keys)
        for key in allKeys {
            let localPick = localByKey[key]
            let remotePick = remoteByKey[key]

            if preferredLocalKeys.contains(key), let localPick {
                picksByKey[key] = localPick
                continue
            }

            switch (localPick, remotePick) {
            case let (.some(localPick), .some(remotePick)):
                picksByKey[key] = localPick.updatedAt >= remotePick.updatedAt ? localPick : remotePick
            case let (.some(localPick), .none):
                picksByKey[key] = localPick
            case let (.none, .some(remotePick)):
                picksByKey[key] = remotePick
            case (.none, .none):
                break
            }
        }

        return Array(picksByKey.values).sorted { lhs, rhs in
            if lhs.series != rhs.series {
                return lhs.series.rawValue < rhs.series.rawValue
            }
            if lhs.eventID != rhs.eventID {
                return lhs.eventID < rhs.eventID
            }
            return lhs.playerID.uuidString < rhs.playerID.uuidString
        }
    }

    private func mergeResults(
        _ local: [RaceResult],
        _ remote: [RaceResult],
        resetCutoff: Date?,
        preferredLocalKeys: Set<ResultKey>
    ) -> [RaceResult] {
        let filteredLocal = local.filter { result in
            guard let resetCutoff else { return true }
            return result.updatedAt >= resetCutoff
        }
        let filteredRemote = remote.filter { result in
            guard let resetCutoff else { return true }
            return result.updatedAt >= resetCutoff
        }

        var localByKey: [ResultKey: RaceResult] = [:]
        for result in filteredLocal {
            let key = ResultKey(result: result)
            if let existing = localByKey[key], existing.updatedAt > result.updatedAt {
                continue
            }
            localByKey[key] = result
        }

        var remoteByKey: [ResultKey: RaceResult] = [:]
        for result in filteredRemote {
            let key = ResultKey(result: result)
            if let existing = remoteByKey[key], existing.updatedAt > result.updatedAt {
                continue
            }
            remoteByKey[key] = result
        }

        var resultsByKey: [ResultKey: RaceResult] = [:]
        let allKeys = Set(localByKey.keys).union(remoteByKey.keys)
        for key in allKeys {
            let localResult = localByKey[key]
            let remoteResult = remoteByKey[key]

            if preferredLocalKeys.contains(key), let localResult {
                resultsByKey[key] = localResult
                continue
            }

            switch (localResult, remoteResult) {
            case let (.some(localResult), .some(remoteResult)):
                resultsByKey[key] = localResult.updatedAt >= remoteResult.updatedAt ? localResult : remoteResult
            case let (.some(localResult), .none):
                resultsByKey[key] = localResult
            case let (.none, .some(remoteResult)):
                resultsByKey[key] = remoteResult
            case (.none, .none):
                break
            }
        }

        return Array(resultsByKey.values).sorted { lhs, rhs in
            if lhs.series != rhs.series {
                return lhs.series.rawValue < rhs.series.rawValue
            }
            return lhs.eventID < rhs.eventID
        }
    }

    private func mergeChampionPicks(
        _ local: [SeasonChampionPick],
        _ remote: [SeasonChampionPick],
        resetCutoff: Date?,
        preferredLocalKeys: Set<ChampionPickKey>
    ) -> [SeasonChampionPick] {
        let filteredLocal = local.filter { pick in
            guard let resetCutoff else { return true }
            return pick.updatedAt >= resetCutoff
        }
        let filteredRemote = remote.filter { pick in
            guard let resetCutoff else { return true }
            return pick.updatedAt >= resetCutoff
        }

        var localByKey: [ChampionPickKey: SeasonChampionPick] = [:]
        for pick in filteredLocal {
            let key = ChampionPickKey(pick: pick)
            if let existing = localByKey[key], existing.updatedAt > pick.updatedAt {
                continue
            }
            localByKey[key] = pick
        }

        var remoteByKey: [ChampionPickKey: SeasonChampionPick] = [:]
        for pick in filteredRemote {
            let key = ChampionPickKey(pick: pick)
            if let existing = remoteByKey[key], existing.updatedAt > pick.updatedAt {
                continue
            }
            remoteByKey[key] = pick
        }

        var picksByKey: [ChampionPickKey: SeasonChampionPick] = [:]
        let allKeys = Set(localByKey.keys).union(remoteByKey.keys)
        for key in allKeys {
            let localPick = localByKey[key]
            let remotePick = remoteByKey[key]

            if preferredLocalKeys.contains(key), let localPick {
                picksByKey[key] = localPick
                continue
            }

            switch (localPick, remotePick) {
            case let (.some(localPick), .some(remotePick)):
                picksByKey[key] = localPick.updatedAt >= remotePick.updatedAt ? localPick : remotePick
            case let (.some(localPick), .none):
                picksByKey[key] = localPick
            case let (.none, .some(remotePick)):
                picksByKey[key] = remotePick
            case (.none, .none):
                break
            }
        }

        return Array(picksByKey.values).sorted { lhs, rhs in
            if lhs.series != rhs.series {
                return lhs.series.rawValue < rhs.series.rawValue
            }
            return lhs.playerID.uuidString < rhs.playerID.uuidString
        }
    }

    private func mergeChampionResults(
        _ local: [SeasonChampionResult],
        _ remote: [SeasonChampionResult],
        resetCutoff: Date?,
        preferredLocalSeries: Set<RaceSeries>
    ) -> [SeasonChampionResult] {
        let filteredLocal = local.filter { result in
            guard let resetCutoff else { return true }
            return result.updatedAt >= resetCutoff
        }
        let filteredRemote = remote.filter { result in
            guard let resetCutoff else { return true }
            return result.updatedAt >= resetCutoff
        }

        var localByKey: [ChampionResultKey: SeasonChampionResult] = [:]
        for result in filteredLocal {
            let key = ChampionResultKey(result: result)
            if let existing = localByKey[key], existing.updatedAt > result.updatedAt {
                continue
            }
            localByKey[key] = result
        }

        var remoteByKey: [ChampionResultKey: SeasonChampionResult] = [:]
        for result in filteredRemote {
            let key = ChampionResultKey(result: result)
            if let existing = remoteByKey[key], existing.updatedAt > result.updatedAt {
                continue
            }
            remoteByKey[key] = result
        }

        var resultsByKey: [ChampionResultKey: SeasonChampionResult] = [:]
        let allKeys = Set(localByKey.keys).union(remoteByKey.keys)
        for key in allKeys {
            let localResult = localByKey[key]
            let remoteResult = remoteByKey[key]

            if preferredLocalSeries.contains(key.series), let localResult {
                resultsByKey[key] = localResult
                continue
            }

            switch (localResult, remoteResult) {
            case let (.some(localResult), .some(remoteResult)):
                resultsByKey[key] = localResult.updatedAt >= remoteResult.updatedAt ? localResult : remoteResult
            case let (.some(localResult), .none):
                resultsByKey[key] = localResult
            case let (.none, .some(remoteResult)):
                resultsByKey[key] = remoteResult
            case (.none, .none):
                break
            }
        }

        return Array(resultsByKey.values).sorted { $0.series.rawValue < $1.series.rawValue }
    }
}

private struct PickKey: Hashable {
    let series: RaceSeries
    let eventID: String
    let playerID: UUID

    init(pick: RacePick) {
        self.series = pick.series
        self.eventID = pick.eventID
        self.playerID = pick.playerID
    }
}

private struct ResultKey: Hashable {
    let series: RaceSeries
    let eventID: String

    init(result: RaceResult) {
        self.series = result.series
        self.eventID = result.eventID
    }
}

private struct ChampionPickKey: Hashable {
    let series: RaceSeries
    let playerID: UUID

    init(pick: SeasonChampionPick) {
        self.series = pick.series
        self.playerID = pick.playerID
    }
}

private struct ChampionResultKey: Hashable {
    let series: RaceSeries

    init(result: SeasonChampionResult) {
        self.series = result.series
    }
}

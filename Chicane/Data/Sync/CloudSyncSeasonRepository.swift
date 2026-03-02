import Foundation
import OSLog

actor CloudSyncSeasonRepository: SeasonRepository {
    private let localRepository: LocalSeasonRepository
    private let cloudStore: any LeagueSyncStore
    private let logger = Logger(subsystem: "dn.chicane", category: "CloudSyncSeasonRepository")

    init(
        localRepository: LocalSeasonRepository = LocalSeasonRepository(),
        cloudStore: any LeagueSyncStore = PublicCloudLeagueStore()
    ) {
        self.localRepository = localRepository
        self.cloudStore = cloudStore
    }

    func loadState() async throws -> PersistedState {
        let state = try await localRepository.loadState()
        return try await synchronize(localState: state, surfaceCloudErrors: false)
    }

    func refreshState() async throws -> PersistedState {
        let state = try await localRepository.loadState()
        return try await synchronize(localState: state, surfaceCloudErrors: true)
    }

    func savePlayers(_ players: [Player]) async throws -> PersistedState {
        let state = try await localRepository.savePlayers(players)
        return await pushIfNeeded(state)
    }

    func saveSettings(_ settings: AppSettings) async throws -> PersistedState {
        let state = try await localRepository.saveSettings(settings)
        return await pushIfNeeded(state)
    }

    func upsertPick(_ pick: RacePick) async throws -> PersistedState {
        let state = try await localRepository.upsertPick(pick)
        return await pushIfNeeded(state)
    }

    func upsertResult(_ result: RaceResult) async throws -> PersistedState {
        let state = try await localRepository.upsertResult(result)
        return await pushIfNeeded(state)
    }

    func resetSeason() async throws -> PersistedState {
        let state = try await localRepository.resetSeason()
        return await pushIfNeeded(state)
    }

    func createLeague() async throws -> PersistedState {
        let localState = try await localRepository.loadState()
        if normalizedLeagueCode(from: localState) != nil {
            return try await synchronize(localState: localState, surfaceCloudErrors: true)
        }

        let sharedState = try await cloudStore.createLeague(from: localState)
        return try await localRepository.replaceState(sharedState)
    }

    func joinLeague(code: String) async throws -> PersistedState {
        let sharedState = try await cloudStore.joinLeague(code: code)
        return try await localRepository.replaceState(sharedState)
    }

    private func synchronize(localState: PersistedState, surfaceCloudErrors: Bool) async throws -> PersistedState {
        guard let code = normalizedLeagueCode(from: localState) else {
            return localState
        }

        do {
            guard let remoteState = try await cloudStore.fetchState(for: code) else {
                try await cloudStore.pushState(localState, for: code)
                return localState
            }

            let mergedState = mergedState(local: localState, remote: remoteState, leagueCode: code)

            if mergedState != remoteState {
                try await cloudStore.pushState(mergedState, for: code)
            }

            if mergedState != localState {
                return try await localRepository.replaceState(mergedState)
            }

            return mergedState
        } catch {
            logger.error("Cloud sync failed: \(error.localizedDescription, privacy: .public)")
            if surfaceCloudErrors {
                throw error
            }
            return localState
        }
    }

    private func pushIfNeeded(_ state: PersistedState) async -> PersistedState {
        guard let code = normalizedLeagueCode(from: state) else {
            return state
        }

        do {
            let remoteState = try await cloudStore.fetchState(for: code)
            let mergedState = mergedState(
                local: state,
                remote: remoteState,
                leagueCode: code
            )

            if remoteState != .some(mergedState) {
                try await cloudStore.pushState(mergedState, for: code)
            }

            if mergedState != state {
                return try await localRepository.replaceState(mergedState)
            }
        } catch {
            logger.error("Deferred cloud push failed: \(error.localizedDescription, privacy: .public)")
        }

        return state
    }

    private func normalizedLeagueCode(from state: PersistedState) -> String? {
        let trimmed = state.settings.leagueCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func mergedState(
        local: PersistedState,
        remote: PersistedState?,
        leagueCode: String
    ) -> PersistedState {
        guard let remote else {
            var state = local
            state.settings.leagueCode = leagueCode
            return state.normalized()
        }

        let resetCutoff = [local.seasonResetAt, remote.seasonResetAt]
            .compactMap { $0 }
            .max()

        var merged = PersistedState(
            schemaVersion: PersistedState.currentSchemaVersion,
            updatedAt: max(local.updatedAt, remote.updatedAt),
            playersUpdatedAt: max(local.playersUpdatedAt, remote.playersUpdatedAt),
            settingsUpdatedAt: max(local.settingsUpdatedAt, remote.settingsUpdatedAt),
            seasonResetAt: resetCutoff,
            players: local.playersUpdatedAt >= remote.playersUpdatedAt ? local.players : remote.players,
            picks: mergePicks(local.picks, remote.picks, resetCutoff: resetCutoff),
            results: mergeResults(local.results, remote.results, resetCutoff: resetCutoff),
            settings: local.settingsUpdatedAt >= remote.settingsUpdatedAt ? local.settings : remote.settings
        )

        merged.settings.leagueCode = leagueCode

        let validPlayerIDs = Set(merged.players.map(\.id))
        merged.picks = merged.picks.filter { validPlayerIDs.contains($0.playerID) }
        return merged.normalized()
    }

    private func mergePicks(
        _ local: [RacePick],
        _ remote: [RacePick],
        resetCutoff: Date?
    ) -> [RacePick] {
        let filtered = (local + remote).filter { pick in
            guard let resetCutoff else { return true }
            return pick.updatedAt >= resetCutoff
        }

        var picksByKey: [PickKey: RacePick] = [:]
        for pick in filtered {
            let key = PickKey(pick: pick)
            if let existing = picksByKey[key], existing.updatedAt > pick.updatedAt {
                continue
            }
            picksByKey[key] = pick
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
        resetCutoff: Date?
    ) -> [RaceResult] {
        let filtered = (local + remote).filter { result in
            guard let resetCutoff else { return true }
            return result.updatedAt >= resetCutoff
        }

        var resultsByKey: [ResultKey: RaceResult] = [:]
        for result in filtered {
            let key = ResultKey(result: result)
            if let existing = resultsByKey[key], existing.updatedAt > result.updatedAt {
                continue
            }
            resultsByKey[key] = result
        }

        return Array(resultsByKey.values).sorted { lhs, rhs in
            if lhs.series != rhs.series {
                return lhs.series.rawValue < rhs.series.rawValue
            }
            return lhs.eventID < rhs.eventID
        }
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

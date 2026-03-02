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

            if remoteState.updatedAt > localState.updatedAt {
                return try await localRepository.replaceState(remoteState)
            }

            if localState.updatedAt > remoteState.updatedAt {
                try await cloudStore.pushState(localState, for: code)
            }

            return localState
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
            try await cloudStore.pushState(state, for: code)
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
}

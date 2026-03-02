import Foundation

protocol LeagueSyncStore: Sendable {
    func createLeague(from state: PersistedState) async throws -> PersistedState
    func joinLeague(code: String) async throws -> PersistedState
    func fetchState(for code: String) async throws -> PersistedState?
    func pushState(_ state: PersistedState, for code: String) async throws
}

import XCTest
@testable import Chicane

final class PersistedStateMigrationTests: XCTestCase {
    func testVersionOnePayloadDecodesAndBackfillsUpdatedAt() throws {
        let payload = """
        {
          "schemaVersion" : 1,
          "players" : [
            {
              "id" : "E0F6A07A-35D8-4F70-9627-DA06EA2B81E0",
              "name" : " Mom "
            }
          ],
          "picks" : [
            {
              "eventID" : "mgp-r1",
              "id" : "4CBF5A87-6418-47E6-8C0E-5DBAF522B327",
              "playerID" : "E0F6A07A-35D8-4F70-9627-DA06EA2B81E0",
              "podium" : {
                "p1" : "a",
                "p2" : "b",
                "p3" : "c"
              },
              "series" : "motoGP",
              "updatedAt" : "2026-03-01T12:00:00Z"
            }
          ],
          "results" : [],
          "settings" : {
            "seasonBetText" : "Winner determines.",
            "showSpoilersSection" : false,
            "spoilerGateEnabled" : true,
            "spoilersDontAskAgain" : false
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PersistedState.self, from: Data(payload.utf8))
        let normalized = decoded.normalized()

        XCTAssertEqual(normalized.schemaVersion, 2)
        XCTAssertEqual(normalized.players.first?.name, "Mom")
        XCTAssertEqual(
            normalized.updatedAt,
            ISO8601DateFormatter().date(from: "2026-03-01T12:00:00Z")
        )
        XCTAssertNil(normalized.settings.leagueCode)
    }
}

final class CloudSyncSeasonRepositoryTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChicaneCloudRepoTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testLoadStatePullsNewerRemoteLeagueState() async throws {
        let localRepo = LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        let cloudStore = MemoryLeagueSyncStore()
        let repo = CloudSyncSeasonRepository(localRepository: localRepo, cloudStore: cloudStore)

        var localState = PersistedState.default
        localState.settings.leagueCode = "ABC123"
        localState.updatedAt = ISO8601DateFormatter().date(from: "2026-03-01T08:00:00Z")!
        localState.players = [Player(id: UUID(), name: "Local")]
        _ = try await localRepo.replaceState(localState)

        var remoteState = PersistedState.default
        remoteState.settings.leagueCode = "ABC123"
        remoteState.updatedAt = ISO8601DateFormatter().date(from: "2026-03-01T09:00:00Z")!
        remoteState.players = [Player(id: UUID(), name: "Remote")]
        await cloudStore.seed(remoteState, for: "ABC123")

        let loaded = try await repo.loadState()

        XCTAssertEqual(loaded.players.map(\.name), ["Remote"])
        let stored = try await localRepo.loadState()
        XCTAssertEqual(stored.players.map(\.name), ["Remote"])
    }

    func testSavePlayersPushesStateToSharedLeague() async throws {
        let localRepo = LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        let cloudStore = MemoryLeagueSyncStore()
        let repo = CloudSyncSeasonRepository(localRepository: localRepo, cloudStore: cloudStore)

        var linkedState = PersistedState.default
        linkedState.settings.leagueCode = "ABC123"
        _ = try await localRepo.replaceState(linkedState)

        let player = Player(id: UUID(), name: "Mom")
        _ = try await repo.savePlayers([player])

        let remote = await cloudStore.state(for: "ABC123")
        XCTAssertEqual(remote?.players.map(\.name), ["Mom"])
        XCTAssertEqual(remote?.settings.leagueCode, "ABC123")
    }
}

private actor MemoryLeagueSyncStore: LeagueSyncStore {
    private var states: [String: PersistedState] = [:]

    func createLeague(from state: PersistedState) async throws -> PersistedState {
        var sharedState = state
        sharedState.settings.leagueCode = "ABC123"
        sharedState.updatedAt = Date()
        states["ABC123"] = sharedState
        return sharedState
    }

    func joinLeague(code: String) async throws -> PersistedState {
        let normalizedCode = normalize(code)
        guard let state = states[normalizedCode] else {
            throw RepositoryError.leagueNotFound(code: normalizedCode)
        }
        return state
    }

    func fetchState(for code: String) async throws -> PersistedState? {
        states[normalize(code)]
    }

    func pushState(_ state: PersistedState, for code: String) async throws {
        var sharedState = state
        sharedState.settings.leagueCode = normalize(code)
        states[normalize(code)] = sharedState
    }

    func seed(_ state: PersistedState, for code: String) {
        states[normalize(code)] = state
    }

    func state(for code: String) -> PersistedState? {
        states[normalize(code)]
    }

    private func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

import XCTest
@testable import Chicane

final class PersistedStateMigrationTests: XCTestCase {
    func testVersionOnePayloadDecodesAndBackfillsMergeTimestamps() throws {
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

        XCTAssertEqual(normalized.schemaVersion, PersistedState.currentSchemaVersion)
        XCTAssertEqual(normalized.players.first?.name, "Mom")
        XCTAssertEqual(
            normalized.updatedAt,
            ISO8601DateFormatter().date(from: "2026-03-01T12:00:00Z")
        )
        XCTAssertEqual(normalized.playersUpdatedAt, normalized.updatedAt)
        XCTAssertEqual(normalized.settingsUpdatedAt, normalized.updatedAt)
        XCTAssertNil(normalized.seasonResetAt)
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

    func testSavingLocalPickDoesNotOverwriteNewerRemotePickForAnotherPlayer() async throws {
        let localRepo = LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        let cloudStore = MemoryLeagueSyncStore()
        let repo = CloudSyncSeasonRepository(localRepository: localRepo, cloudStore: cloudStore)

        let mom = Player(id: UUID(), name: "Mom")
        let son = Player(id: UUID(), name: "Son")

        var sharedState = PersistedState.default
        sharedState.settings.leagueCode = "ABC123"
        sharedState.players = [mom, son]
        sharedState.playersUpdatedAt = date("2026-03-01T08:00:00Z")
        sharedState.updatedAt = date("2026-03-01T08:00:00Z")
        sharedState.picks = [
            RacePick(
                id: UUID(),
                series: .motoGP,
                eventID: "mgp-r1",
                playerID: mom.id,
                podium: Podium(p1: "a", p2: "b", p3: "c"),
                updatedAt: date("2026-03-01T08:30:00Z")
            )
        ]
        await cloudStore.seed(sharedState, for: "ABC123")
        _ = try await localRepo.replaceState(sharedState)

        let remoteSonPick = TestFixtures.pick(
            series: .motoGP,
            eventID: "mgp-r1",
            playerID: son.id,
            p1: "x", p2: "y", p3: "z"
        )
        var newerRemote = sharedState
        newerRemote.updatedAt = date("2026-03-01T09:05:00Z")
        newerRemote.picks.append(
            RacePick(
                id: remoteSonPick.id,
                series: remoteSonPick.series,
                eventID: remoteSonPick.eventID,
                playerID: remoteSonPick.playerID,
                podium: remoteSonPick.podium,
                updatedAt: date("2026-03-01T09:05:00Z")
            )
        )
        await cloudStore.seed(newerRemote, for: "ABC123")

        let localUpdatedPick = RacePick(
            id: sharedState.picks[0].id,
            series: .motoGP,
            eventID: "mgp-r1",
            playerID: mom.id,
            podium: Podium(p1: "c", p2: "b", p3: "a"),
            updatedAt: date("2026-03-01T09:10:00Z")
        )

        let saved = try await repo.upsertPick(localUpdatedPick)

        XCTAssertEqual(saved.picks.count, 2)
        XCTAssertTrue(saved.picks.contains(where: { $0.playerID == mom.id && $0.podium.p1 == "c" }))
        XCTAssertTrue(saved.picks.contains(where: { $0.playerID == son.id && $0.podium.p1 == "x" }))

        let remote = await cloudStore.state(for: "ABC123")
        XCTAssertEqual(remote?.picks.count, 2)
    }

    func testResetKeepsOlderRemotePicksFromReappearing() async throws {
        let localRepo = LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        let cloudStore = MemoryLeagueSyncStore()
        let repo = CloudSyncSeasonRepository(localRepository: localRepo, cloudStore: cloudStore)

        let player = Player(id: UUID(), name: "Mom")
        var linkedState = PersistedState.default
        linkedState.settings.leagueCode = "ABC123"
        linkedState.players = [player]
        linkedState.playersUpdatedAt = date("2026-03-01T08:00:00Z")
        linkedState.updatedAt = date("2026-03-01T08:00:00Z")
        let oldPick = RacePick(
            id: UUID(),
            series: .motoGP,
            eventID: "mgp-r1",
            playerID: player.id,
            podium: Podium(p1: "a", p2: "b", p3: "c"),
            updatedAt: date("2026-03-01T08:30:00Z")
        )
        linkedState.picks = [oldPick]
        await cloudStore.seed(linkedState, for: "ABC123")
        _ = try await localRepo.replaceState(linkedState)

        let resetState = try await repo.resetSeason()

        XCTAssertTrue(resetState.picks.isEmpty)
        XCTAssertNotNil(resetState.seasonResetAt)

        let remote = await cloudStore.state(for: "ABC123")
        XCTAssertTrue(remote?.picks.isEmpty ?? false)
        XCTAssertNotNil(remote?.seasonResetAt)
    }

    func testUpsertPickThrowsLocalSaveWarningWhenSharedLeagueSyncFails() async throws {
        let localRepo = LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        let cloudStore = FailingMemoryLeagueSyncStore()
        let repo = CloudSyncSeasonRepository(localRepository: localRepo, cloudStore: cloudStore)

        let player = Player(id: UUID(), name: "Mom")
        var linkedState = PersistedState.default
        linkedState.settings.leagueCode = "ABC123"
        linkedState.players = [player]
        _ = try await localRepo.replaceState(linkedState)

        let pick = TestFixtures.pick(
            series: .formula1,
            eventID: "f1-r1",
            playerID: player.id,
            p1: "a", p2: "b", p3: "c"
        )

        do {
            _ = try await repo.upsertPick(pick)
            XCTFail("Expected a local-save warning")
        } catch let warning as DeferredCloudSyncWarning {
            XCTAssertEqual(warning.errorDescription, "Saved locally, but shared league sync failed. Try Sync Now.")
            XCTAssertEqual(warning.state.picks.count, 1)
            XCTAssertEqual(warning.state.picks.first?.playerID, player.id)
        }

        let stored = try await localRepo.loadState()
        XCTAssertEqual(stored.picks.count, 1)
        XCTAssertEqual(stored.picks.first?.playerID, player.id)
    }

    func testRefreshStateReloadsExternalDiskChangesBeforeSync() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let localRepo = LocalSeasonRepository(store: store)
        let cloudStore = MemoryLeagueSyncStore()
        let repo = CloudSyncSeasonRepository(localRepository: localRepo, cloudStore: cloudStore)

        let cachedPlayer = Player(id: UUID(), name: "Cached")
        _ = try await localRepo.savePlayers([cachedPlayer])

        let loaded = try await repo.loadState()
        XCTAssertEqual(loaded.players.map(\.name), ["Cached"])

        var externalState = loaded
        externalState.players = [Player(id: UUID(), name: "External")]
        externalState.playersUpdatedAt = date("2026-03-03T21:30:00Z")
        externalState.updatedAt = date("2026-03-03T21:30:00Z")
        try await store.save(externalState)

        let refreshed = try await repo.refreshState()
        XCTAssertEqual(refreshed.players.map(\.name), ["External"])
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

private actor FailingMemoryLeagueSyncStore: LeagueSyncStore {
    func createLeague(from state: PersistedState) async throws -> PersistedState {
        var sharedState = state
        sharedState.settings.leagueCode = "ABC123"
        return sharedState
    }

    func joinLeague(code: String) async throws -> PersistedState {
        throw MockError.simulated
    }

    func fetchState(for code: String) async throws -> PersistedState? {
        throw MockError.simulated
    }

    func pushState(_ state: PersistedState, for code: String) async throws {
        throw MockError.simulated
    }
}

private func date(_ raw: String) -> Date {
    ISO8601DateFormatter().date(from: raw)!
}

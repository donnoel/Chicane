import XCTest
@testable import Chicane

final class FileStateStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChicaneTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Round-trip persistence

    func testSaveAndLoadRoundTrip() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)

        let players = [TestFixtures.player(name: "Alice"), TestFixtures.player(name: "Bob")]
        var state = PersistedState.default
        state.players = players

        try await store.save(state)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.players.count, 2)
        XCTAssertEqual(loaded.players.map(\.name).sorted(), ["Alice", "Bob"])
    }

    func testLoadReturnsDefaultWhenFileDoesNotExist() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)

        let loaded = try await store.load()

        XCTAssertEqual(loaded.players.count, 0)
        XCTAssertEqual(loaded.picks.count, 0)
        XCTAssertEqual(loaded.results.count, 0)
    }

    func testLoadQuarantinesCorruptFileAndRecoversWithDefaultState() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let persistedDirectory = tempDir
            .appendingPathComponent("Chicane", isDirectory: true)
        try FileManager.default.createDirectory(at: persistedDirectory, withIntermediateDirectories: true)

        let corruptedFileURL = persistedDirectory
            .appendingPathComponent("season_state_v1.json", isDirectory: false)
        let invalidJSON = Data("not-valid-json".utf8)
        try invalidJSON.write(to: corruptedFileURL, options: .atomic)

        let loaded = try await store.load()

        XCTAssertEqual(loaded, .default)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptedFileURL.path))

        let files = try FileManager.default.contentsOfDirectory(atPath: persistedDirectory.path)
        XCTAssertTrue(files.contains(where: { $0.hasPrefix("season_state_v1.corrupt-") }))
        XCTAssertEqual(files.filter { $0.hasPrefix("season_state_v1.corrupt-") }.count, 1)

        let recoveryMessage = await store.consumeLoadRecoveryMessage()
        XCTAssertNotNil(recoveryMessage)
        XCTAssertTrue(recoveryMessage?.contains("Recovered local data") ?? false)
    }

    func testSaveCreatesDirectoryIfNeeded() async throws {
        // tempDir doesn't exist yet — save should create it
        let store = FileStateStore(baseDirectoryURL: tempDir)

        try await store.save(.default)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.schemaVersion, PersistedState.currentSchemaVersion)
    }

    func testRoundTripPreservesPicksAndResults() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)

        let player = TestFixtures.player(name: "Charlie")
        let pick = TestFixtures.pick(playerID: player.id)
        let result = TestFixtures.result()

        var state = PersistedState.default
        state.players = [player]
        state.picks = [pick]
        state.results = [result]

        try await store.save(state)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.picks.count, 1)
        XCTAssertEqual(loaded.picks.first?.playerID, player.id)
        XCTAssertEqual(loaded.results.count, 1)
        XCTAssertEqual(loaded.results.first?.eventID, "f1-r1")
    }

    func testRoundTripPreservesSettings() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)

        let player = TestFixtures.player(name: "Alice")
        var state = PersistedState.default
        state.players = [player]
        state.settings = AppSettings(
            seasonBetText: "Loser buys dinner",
            playerBetTextByPlayerID: [player.id: "Steak dinner"],
            spoilerGateEnabled: false,
            spoilersDontAskAgain: true,
            showSpoilersSection: true
        )

        try await store.save(state)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.settings.seasonBetText, "Loser buys dinner")
        XCTAssertEqual(loaded.settings.playerBetTextByPlayerID[player.id], "Steak dinner")
        XCTAssertFalse(loaded.settings.spoilerGateEnabled)
        XCTAssertTrue(loaded.settings.spoilersDontAskAgain)
    }

    func testRoundTripPreservesChampionPicksAndLockedChampionResults() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)

        let player = TestFixtures.player(name: "Charlie")
        var state = PersistedState.default
        state.players = [player]
        state.championPicks = [
            SeasonChampionPick(
                id: UUID(),
                series: .formula1,
                playerID: player.id,
                driverID: "driver-a",
                updatedAt: Date()
            )
        ]
        state.championResults = [
            SeasonChampionResult(
                series: .formula1,
                driverID: "driver-a",
                isLocked: true,
                updatedAt: Date()
            )
        ]

        try await store.save(state)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.championPicks.count, 1)
        XCTAssertEqual(loaded.championPicks.first?.playerID, player.id)
        XCTAssertEqual(loaded.championResults.count, 1)
        XCTAssertEqual(loaded.championResults.first?.driverID, "driver-a")
        XCTAssertEqual(loaded.championResults.first?.isLocked, true)
    }

    func testSeasonChampionResultDecodeDefaultsMissingLockFlagToLocked() throws {
        let json = """
        {
          "series": "formula1",
          "driverID": "driver-a",
          "updatedAt": "2026-03-03T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try decoder.decode(SeasonChampionResult.self, from: Data(json.utf8))

        XCTAssertTrue(result.isLocked)
    }
}

// MARK: - PersistedState.normalized()

final class PersistedStateNormalizationTests: XCTestCase {
    func testNormalizedTrimsPlayerNames() {
        var state = PersistedState.default
        state.players = [Player(id: UUID(), name: "  Alice  ")]

        let normalized = state.normalized()

        XCTAssertEqual(normalized.players.first?.name, "Alice")
    }

    func testNormalizedRemovesEmptyPlayerNames() {
        var state = PersistedState.default
        state.players = [
            Player(id: UUID(), name: "Valid"),
            Player(id: UUID(), name: "   "),
            Player(id: UUID(), name: "")
        ]

        let normalized = state.normalized()

        XCTAssertEqual(normalized.players.count, 1)
        XCTAssertEqual(normalized.players.first?.name, "Valid")
    }

    func testNormalizedSetsSchemaVersion() {
        var state = PersistedState.default
        state.schemaVersion = 0

        let normalized = state.normalized()

        XCTAssertEqual(normalized.schemaVersion, PersistedState.currentSchemaVersion)
    }

    func testNormalizedDropsPlayerBetsForRemovedPlayers() {
        let keepID = UUID()
        let dropID = UUID()
        var state = PersistedState.default
        state.players = [Player(id: keepID, name: "Keep")]
        state.settings.playerBetTextByPlayerID = [
            keepID: "Winner buys coffee",
            dropID: "Should be removed"
        ]

        let normalized = state.normalized()

        XCTAssertEqual(normalized.settings.playerBetTextByPlayerID.count, 1)
        XCTAssertEqual(normalized.settings.playerBetTextByPlayerID[keepID], "Winner buys coffee")
        XCTAssertNil(normalized.settings.playerBetTextByPlayerID[dropID])
    }

    func testNormalizedDropsRacePicksForRemovedPlayers() {
        let keepID = UUID()
        let dropID = UUID()
        var state = PersistedState.default
        state.players = [Player(id: keepID, name: "Keep")]
        state.picks = [
            TestFixtures.pick(eventID: "f1-r1", playerID: keepID),
            TestFixtures.pick(eventID: "f1-r2", playerID: dropID)
        ]

        let normalized = state.normalized()

        XCTAssertEqual(normalized.picks.count, 1)
        XCTAssertEqual(normalized.picks.first?.playerID, keepID)
        XCTAssertEqual(normalized.picks.first?.eventID, "f1-r1")
    }

    func testNormalizedNormalizesValidLeagueCode() {
        var state = PersistedState.default
        state.settings.leagueCode = " ab-c123 "

        let normalized = state.normalized()

        XCTAssertEqual(normalized.settings.leagueCode, "ABC123")
    }

    func testNormalizedClearsInvalidLeagueCode() {
        var state = PersistedState.default
        state.settings.leagueCode = "ABC"

        let normalized = state.normalized()

        XCTAssertNil(normalized.settings.leagueCode)
    }
}

// MARK: - LocalSeasonRepository

final class LocalSeasonRepositoryTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChicaneRepoTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testUpsertPickRejectsDuplicatePodium() async {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let repo = LocalSeasonRepository(store: store)

        let pick = RacePick(
            id: UUID(),
            series: .formula1,
            eventID: "f1-r1",
            playerID: UUID(),
            podium: Podium(p1: "a", p2: "a", p3: "b"), // duplicate
            updatedAt: Date()
        )

        do {
            _ = try await repo.upsertPick(pick)
            XCTFail("Expected invalidPodium error")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .invalidPodium)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testUpsertResultRejectsDuplicatePodium() async {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let repo = LocalSeasonRepository(store: store)

        let result = RaceResult(
            series: .formula1,
            eventID: "f1-r1",
            podium: Podium(p1: "a", p2: "b", p3: "a"), // duplicate
            isLocked: true,
            updatedAt: Date()
        )

        do {
            _ = try await repo.upsertResult(result)
            XCTFail("Expected invalidPodium error")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .invalidPodium)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRefreshStateBypassesWarmCacheAndReloadsDisk() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let repo = LocalSeasonRepository(store: store)

        let cachedPlayer = Player(id: UUID(), name: "Cached")
        _ = try await repo.savePlayers([cachedPlayer])

        let loaded = try await repo.loadState()
        XCTAssertEqual(loaded.players.map(\.name), ["Cached"])

        var externalState = loaded
        externalState.players = [Player(id: UUID(), name: "External")]
        externalState.playersUpdatedAt = testDate("2026-03-03T21:00:00Z")
        externalState.updatedAt = testDate("2026-03-03T21:00:00Z")
        try await store.save(externalState)

        let stillCached = try await repo.loadState()
        XCTAssertEqual(stillCached.players.map(\.name), ["Cached"])

        let refreshed = try await repo.refreshState()
        XCTAssertEqual(refreshed.players.map(\.name), ["External"])
    }

    func testUpsertPickReplacesExistingPickForSamePlayerAndEvent() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let repo = LocalSeasonRepository(store: store)

        let player = TestFixtures.player(name: "Player")
        let playerID = player.id
        _ = try await repo.savePlayers([player])
        let pick1 = TestFixtures.pick(eventID: "f1-r1", playerID: playerID, p1: "a", p2: "b", p3: "c")
        let pick2 = TestFixtures.pick(eventID: "f1-r1", playerID: playerID, p1: "x", p2: "y", p3: "z")

        _ = try await repo.upsertPick(pick1)
        let state = try await repo.upsertPick(pick2)

        let matchingPicks = state.picks.filter { $0.playerID == playerID && $0.eventID == "f1-r1" }
        XCTAssertEqual(matchingPicks.count, 1)
        XCTAssertEqual(matchingPicks.first?.podium.p1, "x")
    }

    func testDeletePickClearsExistingPickForSamePlayerAndEvent() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let repo = LocalSeasonRepository(store: store)

        let player = TestFixtures.player(name: "Player")
        let otherPlayer = TestFixtures.player(name: "Other")
        _ = try await repo.savePlayers([player, otherPlayer])
        _ = try await repo.upsertPick(TestFixtures.pick(eventID: "f1-r1", playerID: player.id))
        _ = try await repo.upsertPick(TestFixtures.pick(eventID: "f1-r1", playerID: otherPlayer.id))
        _ = try await repo.upsertPick(TestFixtures.pick(eventID: "f1-r2", playerID: player.id))

        let state = try await repo.deletePick(series: .formula1, eventID: "f1-r1", playerID: player.id)

        XCTAssertFalse(state.picks.contains { $0.eventID == "f1-r1" && $0.playerID == player.id })
        XCTAssertTrue(state.picks.contains { $0.eventID == "f1-r1" && $0.playerID == otherPlayer.id })
        XCTAssertTrue(state.picks.contains { $0.eventID == "f1-r2" && $0.playerID == player.id })
    }

    func testResetSeasonClearsPicksResultsAndChampionSelections() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let repo = LocalSeasonRepository(store: store)

        let player = TestFixtures.player(name: "Test")
        _ = try await repo.savePlayers([player])
        _ = try await repo.upsertPick(TestFixtures.pick(playerID: player.id))
        _ = try await repo.upsertResult(TestFixtures.result())
        _ = try await repo.upsertChampionPick(
            SeasonChampionPick(
                id: UUID(),
                series: .formula1,
                playerID: player.id,
                driverID: "driver-a",
                updatedAt: Date()
            )
        )
        _ = try await repo.upsertChampionResult(
            SeasonChampionResult(
                series: .formula1,
                driverID: "driver-a",
                isLocked: true,
                updatedAt: Date()
            )
        )

        let state = try await repo.resetSeason()

        XCTAssertTrue(state.picks.isEmpty)
        XCTAssertTrue(state.results.isEmpty)
        XCTAssertTrue(state.championPicks.isEmpty)
        XCTAssertTrue(state.championResults.isEmpty)
        XCTAssertEqual(state.players.count, 1, "Players should be preserved after reset")
    }

    func testSavePlayersRemovesOrphanedPicks() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let repo = LocalSeasonRepository(store: store)

        let keepPlayer = TestFixtures.player(name: "Keep")
        let removePlayer = TestFixtures.player(name: "Remove")

        _ = try await repo.savePlayers([keepPlayer, removePlayer])
        _ = try await repo.upsertPick(TestFixtures.pick(playerID: keepPlayer.id))
        _ = try await repo.upsertPick(TestFixtures.pick(eventID: "f1-r2", playerID: removePlayer.id))

        // Save with only keepPlayer — removePlayer's picks should be cleaned up
        let state = try await repo.savePlayers([keepPlayer])

        XCTAssertEqual(state.players.count, 1)
        XCTAssertEqual(state.picks.count, 1)
        XCTAssertEqual(state.picks.first?.playerID, keepPlayer.id)
    }

    func testSavePlayersRemovesOrphanedPlayerBets() async throws {
        let store = FileStateStore(baseDirectoryURL: tempDir)
        let repo = LocalSeasonRepository(store: store)

        let keepPlayer = TestFixtures.player(name: "Keep")
        let removePlayer = TestFixtures.player(name: "Remove")

        _ = try await repo.savePlayers([keepPlayer, removePlayer])

        var settings = PersistedState.default.settings
        settings.playerBetTextByPlayerID = [
            keepPlayer.id: "Dinner tab",
            removePlayer.id: "Drinks tab"
        ]
        _ = try await repo.saveSettings(settings)

        let state = try await repo.savePlayers([keepPlayer])

        XCTAssertEqual(state.settings.playerBetTextByPlayerID.count, 1)
        XCTAssertEqual(state.settings.playerBetTextByPlayerID[keepPlayer.id], "Dinner tab")
        XCTAssertNil(state.settings.playerBetTextByPlayerID[removePlayer.id])
    }
}

// MARK: - Equatable conformance for test assertions

extension RepositoryError: @retroactive Equatable {
    public static func == (lhs: RepositoryError, rhs: RepositoryError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidPodium, .invalidPodium):
            return true
        case (.cloudSyncUnavailable, .cloudSyncUnavailable):
            return true
        case (.leagueNotConfigured, .leagueNotConfigured):
            return true
        case let (.leagueNotFound(a), .leagueNotFound(b)):
            return a == b
        case let (.missingBundleResource(a), .missingBundleResource(b)):
            return a == b
        default:
            return false
        }
    }
}

private func testDate(_ raw: String) -> Date {
    ISO8601DateFormatter().date(from: raw)!
}

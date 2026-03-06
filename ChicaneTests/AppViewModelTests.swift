import XCTest
@testable import Chicane

@MainActor
final class AppViewModelTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChicaneAppViewModelTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testUpdateResultFromOfficialSourceLocksOfficialResultAndRejectsFurtherChanges() async throws {
        let event = TestFixtures.event(id: "f1-2026-test", series: .formula1)
        let drivers = [
            TestFixtures.driver(id: "f1-max", series: .formula1, name: "Max Verstappen", team: "Red Bull"),
            TestFixtures.driver(id: "f1-lando", series: .formula1, name: "Lando Norris", team: "McLaren"),
            TestFixtures.driver(id: "f1-charles", series: .formula1, name: "Charles Leclerc", team: "Ferrari")
        ]
        let viewModel = makeViewModel(
            event: event,
            drivers: drivers,
            podiumNames: drivers.map(\.name)
        )

        await viewModel.reload()
        try await viewModel.updateResultFromOfficialSource(series: .formula1, eventID: event.id)

        let storedResult = viewModel.result(for: .formula1, eventID: event.id)
        XCTAssertEqual(storedResult?.isLocked, true)

        do {
            try await viewModel.updateResultFromOfficialSource(series: .formula1, eventID: event.id)
            XCTFail("Expected a locked-result error")
        } catch let error as AppViewModelError {
            if case .resultLocked = error {
                // Expected path.
            } else {
                XCTFail("Unexpected AppViewModelError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUpdateResultFromOfficialSourceFailsClosedOnAmbiguousParticipantMatch() async throws {
        let event = TestFixtures.event(id: "f1-2026-ambiguous", series: .formula1)
        let drivers = [
            TestFixtures.driver(id: "f1-alex", series: .formula1, name: "Alex Smith", team: "Team A"),
            TestFixtures.driver(id: "f1-jamie", series: .formula1, name: "Jamie Smith", team: "Team B"),
            TestFixtures.driver(id: "f1-taylor", series: .formula1, name: "Taylor Driver", team: "Team C")
        ]
        let viewModel = makeViewModel(
            event: event,
            drivers: drivers,
            podiumNames: ["Smith", "Taylor Driver", "Alex Smith"]
        )

        await viewModel.reload()

        do {
            try await viewModel.updateResultFromOfficialSource(series: .formula1, eventID: event.id)
            XCTFail("Expected an ambiguous-name failure")
        } catch let error as AppViewModelError {
            if case let .participantNotFound(name) = error {
                XCTAssertEqual(name, "Smith")
            } else {
                XCTFail("Unexpected AppViewModelError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(viewModel.result(for: .formula1, eventID: event.id))
    }

    func testSaveChampionPickRejectsChangesAfterSeasonChampionIsLocked() async throws {
        let event = TestFixtures.event(id: "f1-2026-champion-lock", series: .formula1)
        let drivers = [
            TestFixtures.driver(id: "f1-max", series: .formula1, name: "Max Verstappen", team: "Red Bull"),
            TestFixtures.driver(id: "f1-lando", series: .formula1, name: "Lando Norris", team: "McLaren"),
            TestFixtures.driver(id: "f1-charles", series: .formula1, name: "Charles Leclerc", team: "Ferrari")
        ]
        let player = Player(id: UUID(), name: "Don")
        let viewModel = makeViewModel(
            event: event,
            drivers: drivers,
            podiumNames: drivers.map(\.name)
        )

        await viewModel.reload()
        try await viewModel.savePlayers([player])
        try await viewModel.saveChampionPick(
            series: .formula1,
            playerID: player.id,
            driverID: drivers[0].id
        )
        try await viewModel.saveChampionResult(series: .formula1, driverID: drivers[0].id)

        do {
            try await viewModel.saveChampionPick(
                series: .formula1,
                playerID: player.id,
                driverID: drivers[1].id
            )
            XCTFail("Expected champion-pick lock error")
        } catch let error as AppViewModelError {
            if case .championPickLocked = error {
                // Expected path.
            } else {
                XCTFail("Unexpected AppViewModelError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            viewModel.championPick(for: .formula1, playerID: player.id)?.driverID,
            drivers[0].id
        )
    }

    func testSavePlayersRejectsBlankNamesWithoutDeletingPlayerData() async throws {
        let event = TestFixtures.event(id: "f1-2026-blank-name", series: .formula1)
        let drivers = [
            TestFixtures.driver(id: "f1-max", series: .formula1, name: "Max Verstappen", team: "Red Bull"),
            TestFixtures.driver(id: "f1-lando", series: .formula1, name: "Lando Norris", team: "McLaren"),
            TestFixtures.driver(id: "f1-charles", series: .formula1, name: "Charles Leclerc", team: "Ferrari")
        ]
        let player = Player(id: UUID(), name: "Mom")
        let viewModel = makeViewModel(
            event: event,
            drivers: drivers,
            podiumNames: drivers.map(\.name)
        )

        await viewModel.reload()
        try await viewModel.savePlayers([player])

        do {
            try await viewModel.savePlayers([Player(id: player.id, name: "   ")])
            XCTFail("Expected a blank-name validation error")
        } catch let error as AppViewModelError {
            if case .playerNameEmpty = error {
                // Expected path.
            } else {
                XCTFail("Unexpected AppViewModelError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(viewModel.players.map(\.name), ["Mom"])
    }

    func testSavePickReturnsWarningAndAppliesLocalStateWhenCloudSyncFails() async throws {
        let event = TestFixtures.event(id: "f1-2026-local-only", series: .formula1)
        let drivers = [
            TestFixtures.driver(id: "f1-max", series: .formula1, name: "Max Verstappen", team: "Red Bull"),
            TestFixtures.driver(id: "f1-lando", series: .formula1, name: "Lando Norris", team: "McLaren"),
            TestFixtures.driver(id: "f1-charles", series: .formula1, name: "Charles Leclerc", team: "Ferrari")
        ]
        let player = Player(id: UUID(), name: "Don")
        let localRepository = LocalSeasonRepository(
            store: FileStateStore(baseDirectoryURL: tempDir)
        )
        var localState = PersistedState.default
        localState.players = [player]
        localState.settings.leagueCode = "ABC123"
        _ = try await localRepository.replaceState(localState)

        let viewModel = makeViewModel(
            event: event,
            drivers: drivers,
            podiumNames: drivers.map(\.name),
            seasonRepository: CloudSyncSeasonRepository(
                localRepository: localRepository,
                cloudStore: FailingLeagueSyncStore()
            )
        )

        await viewModel.reload()

        let warning = try await viewModel.savePick(
            series: .formula1,
            eventID: event.id,
            playerID: player.id,
            draft: PodiumDraft(p1: drivers[0].id, p2: drivers[1].id, p3: drivers[2].id)
        )

        XCTAssertEqual(warning, "Saved locally, but shared league sync failed. Try Sync Now.")
        XCTAssertNotNil(viewModel.pick(for: .formula1, eventID: event.id, playerID: player.id))
    }

    private func makeViewModel(
        event: RaceEvent,
        drivers: [Driver],
        podiumNames: [String],
        seasonRepository: (any SeasonRepository)? = nil
    ) -> AppViewModel {
        let driverRepository = MockDriverRepository()
        driverRepository.stubbedDrivers[.formula1] = drivers

        let calendarRepository = MockCalendarRepository()
        calendarRepository.stubbedEvents[.formula1] = [event]

        let resultRepository = MockResultRepository()
        resultRepository.stubbedPodiums[event.id] = podiumNames

        let resolvedSeasonRepository = seasonRepository ?? LocalSeasonRepository(
            store: FileStateStore(baseDirectoryURL: tempDir)
        )

        return AppViewModel(
            driverRepository: driverRepository,
            calendarRepository: calendarRepository,
            resultRepository: resultRepository,
            seasonRepository: resolvedSeasonRepository
        )
    }
}

private actor FailingLeagueSyncStore: LeagueSyncStore {
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

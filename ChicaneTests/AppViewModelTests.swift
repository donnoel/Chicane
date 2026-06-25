import CloudKit
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

    func testUpdateResultFromOfficialSourceLocksOfficialResultAndRejectsManualChanges() async throws {
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
            try await viewModel.saveResult(
                series: .formula1,
                eventID: event.id,
                draft: PodiumDraft(p1: drivers[2].id, p2: drivers[1].id, p3: drivers[0].id)
            )
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

    func testUpdateResultFromOfficialSourceCanCorrectLockedOfficialResult() async throws {
        let event = TestFixtures.event(id: "f1-2026-correction", series: .formula1)
        let drivers = [
            TestFixtures.driver(id: "f1-max", series: .formula1, name: "Max Verstappen", team: "Red Bull"),
            TestFixtures.driver(id: "f1-lando", series: .formula1, name: "Lando Norris", team: "McLaren"),
            TestFixtures.driver(id: "f1-charles", series: .formula1, name: "Charles Leclerc", team: "Ferrari")
        ]
        let driverRepository = MockDriverRepository()
        driverRepository.stubbedDrivers[.formula1] = drivers

        let calendarRepository = MockCalendarRepository()
        calendarRepository.stubbedEvents[.formula1] = [event]

        let resultRepository = MockResultRepository()
        resultRepository.stubbedPodiums[event.id] = drivers.map(\.name)

        let viewModel = AppViewModel(
            driverRepository: driverRepository,
            calendarRepository: calendarRepository,
            resultRepository: resultRepository,
            championshipRepository: EmptyChampionshipRepository(),
            seasonRepository: LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        )

        await viewModel.reload()
        try await viewModel.updateResultFromOfficialSource(series: .formula1, eventID: event.id)

        resultRepository.stubbedPodiums[event.id] = [
            drivers[2].name,
            drivers[1].name,
            drivers[0].name
        ]
        try await viewModel.updateResultFromOfficialSource(series: .formula1, eventID: event.id)

        let correctedResult = viewModel.result(for: .formula1, eventID: event.id)
        XCTAssertEqual(correctedResult?.isLocked, true)
        XCTAssertEqual(correctedResult?.podium.p1, drivers[2].id)
        XCTAssertEqual(correctedResult?.podium.p2, drivers[1].id)
        XCTAssertEqual(correctedResult?.podium.p3, drivers[0].id)
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

        XCTAssertTrue(warning?.hasPrefix("Saved locally, but shared league sync failed. Try Sync Now.") ?? false)
        XCTAssertNotNil(viewModel.pick(for: .formula1, eventID: event.id, playerID: player.id))
    }

    func testSavePickWarningIncludesCloudKitErrorCodeDetail() async throws {
        let event = TestFixtures.event(id: "f1-2026-cloudkit-error", series: .formula1)
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
                cloudStore: PermissionFailureLeagueSyncStore()
            )
        )

        await viewModel.reload()

        let warning = try await viewModel.savePick(
            series: .formula1,
            eventID: event.id,
            playerID: player.id,
            draft: PodiumDraft(p1: drivers[0].id, p2: drivers[1].id, p3: drivers[2].id)
        )

        XCTAssertTrue(warning?.contains("permissionFailure") ?? false)
    }

    func testSyncNowUsesFormattedCloudKitPermissionMessage() async {
        let viewModel = AppViewModel(
            driverRepository: MockDriverRepository(),
            calendarRepository: MockCalendarRepository(),
            resultRepository: MockResultRepository(),
            seasonRepository: ManualSyncPermissionFailureSeasonRepository()
        )

        await viewModel.reload()
        await viewModel.syncLeagueIfNeeded(showBannerOnSuccess: true)

        let bannerText = viewModel.banner?.text ?? ""
        XCTAssertTrue(bannerText.contains("CloudKit permission failure (`permissionFailure`)"))
        XCTAssertFalse(bannerText.contains("WRITE operation not permitted"))
    }

    func testUpdateResultFromOfficialSourceRefreshesChampionshipLeaders() async throws {
        let event = TestFixtures.event(id: "f1-2026-refresh-championship", series: .formula1)
        let drivers = [
            TestFixtures.driver(id: "f1-max", series: .formula1, name: "Max Verstappen", team: "Red Bull"),
            TestFixtures.driver(id: "f1-lando", series: .formula1, name: "Lando Norris", team: "McLaren"),
            TestFixtures.driver(id: "f1-charles", series: .formula1, name: "Charles Leclerc", team: "Ferrari")
        ]

        let championshipRepository = MockChampionshipRepository()
        await championshipRepository.setLeaders([
            .formula1: [
                ChampionshipLeader(series: .formula1, position: 1, name: "Lando Norris", team: "McLaren", points: 100),
                ChampionshipLeader(series: .formula1, position: 2, name: "Max Verstappen", team: "Red Bull", points: 90),
                ChampionshipLeader(series: .formula1, position: 3, name: "Charles Leclerc", team: "Ferrari", points: 80)
            ],
            .motoGP: [
                ChampionshipLeader(series: .motoGP, position: 1, name: "Rider One", team: "Team One", points: 120),
                ChampionshipLeader(series: .motoGP, position: 2, name: "Rider Two", team: "Team Two", points: 110),
                ChampionshipLeader(series: .motoGP, position: 3, name: "Rider Three", team: "Team Three", points: 95)
            ]
        ])

        let viewModel = makeViewModel(
            event: event,
            drivers: drivers,
            podiumNames: drivers.map(\.name),
            championshipRepository: championshipRepository
        )

        await viewModel.reload()
        let initialRequests = await championshipRepository.requestedSeries.count

        _ = try await viewModel.updateResultFromOfficialSource(series: .formula1, eventID: event.id)

        let finalRequests = await championshipRepository.requestedSeries.count
        XCTAssertEqual(finalRequests, initialRequests + 2)
        XCTAssertEqual(viewModel.championshipLeaders(for: .formula1).count, 3)
        XCTAssertEqual(viewModel.championshipLeaders(for: .motoGP).count, 3)
    }

    func testReloadPreservesStableDriverAndEventIdentityAcrossSourceSwitch() async throws {
        let oldDrivers = [
            TestFixtures.driver(id: "f1-verstappen", series: .formula1, name: "Max Verstappen", team: "Red Bull"),
            TestFixtures.driver(id: "f1-leclerc", series: .formula1, name: "Charles Leclerc", team: "Ferrari"),
            TestFixtures.driver(id: "f1-norris", series: .formula1, name: "Lando Norris", team: "McLaren")
        ]
        let refreshedDrivers = [
            TestFixtures.driver(id: "f1-max-verstappen", series: .formula1, name: "Max Verstappen", team: "Oracle Red Bull Racing"),
            TestFixtures.driver(id: "f1-charles-leclerc", series: .formula1, name: "Charles Leclerc", team: "Scuderia Ferrari HP"),
            TestFixtures.driver(id: "f1-lando-norris", series: .formula1, name: "Lando Norris", team: "McLaren Formula 1 Team")
        ]

        let oldEvent = RaceEvent(
            id: "f1-2026-australia",
            series: .formula1,
            season: 2026,
            round: 1,
            title: "Australian Grand Prix",
            circuit: "Albert Park",
            raceDate: Date(timeIntervalSince1970: 1_000)
        )
        let refreshedEvent = RaceEvent(
            id: "f1-2026-australian-grand-prix",
            series: .formula1,
            season: 2026,
            round: 1,
            title: "Formula 1 Louis Vuitton Australian Grand Prix 2026",
            circuit: "Melbourne Grand Prix Circuit",
            raceDate: Date(timeIntervalSince1970: 2_000)
        )

        let seasonRepository = LocalSeasonRepository(
            store: FileStateStore(baseDirectoryURL: tempDir)
        )
        let viewModel = AppViewModel(
            driverRepository: SequencedDriverRepository(
                queuedDrivers: [
                    .formula1: [oldDrivers, refreshedDrivers],
                    .motoGP: [[], []]
                ]
            ),
            calendarRepository: SequencedCalendarRepository(
                queuedEvents: [
                    .formula1: [[oldEvent], [refreshedEvent]],
                    .motoGP: [[], []]
                ]
            ),
            resultRepository: MockResultRepository(),
            seasonRepository: seasonRepository
        )

        let player = Player(id: UUID(), name: "Son")
        await viewModel.reload()
        try await viewModel.savePlayers([player])
        _ = try await viewModel.savePick(
            series: .formula1,
            eventID: oldEvent.id,
            playerID: player.id,
            draft: PodiumDraft(
                p1: oldDrivers[0].id,
                p2: oldDrivers[1].id,
                p3: oldDrivers[2].id
            )
        )

        await viewModel.reload()

        XCTAssertEqual(
            viewModel.drivers(for: .formula1).map(\.id),
            oldDrivers.map(\.id)
        )
        XCTAssertEqual(viewModel.events(for: .formula1).first?.id, oldEvent.id)
        XCTAssertEqual(viewModel.events(for: .formula1).first?.title, refreshedEvent.title)
        XCTAssertEqual(viewModel.events(for: .formula1).first?.raceDate, refreshedEvent.raceDate)
        XCTAssertNotNil(viewModel.pick(for: .formula1, eventID: oldEvent.id, playerID: player.id))
        XCTAssertNotNil(viewModel.pick(for: .formula1, eventID: refreshedEvent.id, playerID: player.id))
    }

    func testReloadPreservesStableEventIDWhenRefreshedEventHasDifferentSourceID() async {
        let oldEvent = RaceEvent(
            id: "f1-2026-japan-stable",
            series: .formula1,
            season: 2026,
            round: 3,
            title: "Japanese Grand Prix",
            circuit: "Suzuka International Racing Course",
            raceDate: Date(timeIntervalSince1970: 20_000)
        )
        let refreshedEvent = RaceEvent(
            id: "f1-2026-japanese-grand-prix-official",
            series: .formula1,
            season: 2026,
            round: 3,
            title: "Formula 1 Japanese Grand Prix 2026",
            circuit: "Suzuka Circuit",
            raceDate: Date(timeIntervalSince1970: 20_400)
        )

        let viewModel = AppViewModel(
            driverRepository: SequencedDriverRepository(
                queuedDrivers: [
                    .formula1: [[], []],
                    .motoGP: [[], []]
                ]
            ),
            calendarRepository: SequencedCalendarRepository(
                queuedEvents: [
                    .formula1: [[oldEvent], [refreshedEvent]],
                    .motoGP: [[], []]
                ]
            ),
            resultRepository: MockResultRepository(),
            seasonRepository: LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        )

        await viewModel.reload()
        await viewModel.reload()

        let mergedEvent = viewModel.events(for: .formula1).first
        XCTAssertEqual(mergedEvent?.id, oldEvent.id)
        XCTAssertEqual(mergedEvent?.raceDate, refreshedEvent.raceDate)
    }

    func testReloadPrefersRicherExistingDisplayTextWhenRefreshIsShorter() async {
        struct Case {
            let existingTitle: String
            let existingCircuit: String
            let refreshedTitle: String
            let refreshedCircuit: String
        }

        let cases: [Case] = [
            Case(
                existingTitle: "Estrella Galicia 0,0 Grand Prix Of Spain",
                existingCircuit: "Circuito de Jerez - Angel Nieto",
                refreshedTitle: "Spanish GP",
                refreshedCircuit: "Jerez"
            ),
            Case(
                existingTitle: "Qatar Airways British Grand Prix",
                existingCircuit: "Silverstone Circuit",
                refreshedTitle: "British GP",
                refreshedCircuit: "Silverstone"
            )
        ]

        for testCase in cases {
            let oldEvent = RaceEvent(
                id: UUID().uuidString,
                series: .formula1,
                season: 2026,
                round: 7,
                title: testCase.existingTitle,
                circuit: testCase.existingCircuit,
                raceDate: Date(timeIntervalSince1970: 40_000)
            )
            let refreshedEvent = RaceEvent(
                id: UUID().uuidString,
                series: .formula1,
                season: 2026,
                round: 7,
                title: testCase.refreshedTitle,
                circuit: testCase.refreshedCircuit,
                raceDate: Date(timeIntervalSince1970: 40_600)
            )

            let viewModel = AppViewModel(
                driverRepository: SequencedDriverRepository(
                    queuedDrivers: [
                        .formula1: [[], []],
                        .motoGP: [[], []]
                    ]
                ),
                calendarRepository: SequencedCalendarRepository(
                    queuedEvents: [
                        .formula1: [[oldEvent], [refreshedEvent]],
                        .motoGP: [[], []]
                    ]
                ),
                resultRepository: MockResultRepository(),
                seasonRepository: LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
            )

            await viewModel.reload()
            await viewModel.reload()

            let mergedEvent = viewModel.events(for: .formula1).first
            XCTAssertEqual(mergedEvent?.title, testCase.existingTitle)
            XCTAssertEqual(mergedEvent?.circuit, testCase.existingCircuit)
            XCTAssertEqual(mergedEvent?.raceDate, refreshedEvent.raceDate)
        }
    }

    func testReloadUsesDeterministicTieBreakForAmbiguousCandidatesByIdentityScore() async {
        let candidateA = RaceEvent(
            id: "f1-2026-americas-stable",
            series: .formula1,
            season: 2026,
            round: 9,
            title: "Grand Prix of the Americas",
            circuit: "Circuit of the Americas",
            raceDate: Date(timeIntervalSince1970: 80_000)
        )
        let candidateB = RaceEvent(
            id: "f1-2026-qatar-stable",
            series: .formula1,
            season: 2026,
            round: 10,
            title: "Qatar Grand Prix",
            circuit: "Lusail International Circuit",
            raceDate: Date(timeIntervalSince1970: 80_400)
        )
        let refreshedEvent = RaceEvent(
            id: "f1-2026-americas-official",
            series: .formula1,
            season: 2026,
            round: 9,
            title: "Americas GP",
            circuit: "COTA",
            raceDate: Date(timeIntervalSince1970: 80_200)
        )

        let viewModel = AppViewModel(
            driverRepository: SequencedDriverRepository(
                queuedDrivers: [
                    .formula1: [[], []],
                    .motoGP: [[], []]
                ]
            ),
            calendarRepository: SequencedCalendarRepository(
                queuedEvents: [
                    .formula1: [[candidateA, candidateB], [refreshedEvent]],
                    .motoGP: [[], []]
                ]
            ),
            resultRepository: MockResultRepository(),
            seasonRepository: LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        )

        await viewModel.reload()
        await viewModel.reload()

        let mergedEvent = viewModel.events(for: .formula1).first
        XCTAssertEqual(mergedEvent?.id, candidateA.id)
    }

    func testReloadPreservesExistingDriverAndEventStateWhenRefreshFails() async {
        let f1Drivers = [
            TestFixtures.driver(id: "f1-max", series: .formula1, name: "Max Verstappen", team: "Red Bull")
        ]
        let motoGPDrivers = [
            TestFixtures.driver(id: "mgp-bagnaia", series: .motoGP, name: "Francesco Bagnaia", team: "Ducati")
        ]
        let f1Event = TestFixtures.event(id: "f1-2026-australia", series: .formula1)
        let motoGPEvent = TestFixtures.event(id: "mgp-2026-qatar", series: .motoGP)

        let driverRepository = MockDriverRepository()
        driverRepository.stubbedDrivers[.formula1] = f1Drivers
        driverRepository.stubbedDrivers[.motoGP] = motoGPDrivers

        let calendarRepository = MockCalendarRepository()
        calendarRepository.stubbedEvents[.formula1] = [f1Event]
        calendarRepository.stubbedEvents[.motoGP] = [motoGPEvent]

        let viewModel = AppViewModel(
            driverRepository: driverRepository,
            calendarRepository: calendarRepository,
            resultRepository: MockResultRepository(),
            seasonRepository: LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: tempDir))
        )

        await viewModel.reload()
        XCTAssertEqual(viewModel.drivers(for: .formula1).map(\.id), f1Drivers.map(\.id))
        XCTAssertEqual(viewModel.drivers(for: .motoGP).map(\.id), motoGPDrivers.map(\.id))
        XCTAssertEqual(viewModel.events(for: .formula1).map(\.id), [f1Event.id])
        XCTAssertEqual(viewModel.events(for: .motoGP).map(\.id), [motoGPEvent.id])

        driverRepository.errorToThrow = MockError.simulated
        await viewModel.reload()

        XCTAssertEqual(viewModel.drivers(for: .formula1).map(\.id), f1Drivers.map(\.id))
        XCTAssertEqual(viewModel.drivers(for: .motoGP).map(\.id), motoGPDrivers.map(\.id))
        XCTAssertEqual(viewModel.events(for: .formula1).map(\.id), [f1Event.id])
        XCTAssertEqual(viewModel.events(for: .motoGP).map(\.id), [motoGPEvent.id])
        XCTAssertEqual(viewModel.banner?.style, .error)
        XCTAssertFalse(viewModel.banner?.text.isEmpty ?? true)
    }

    private func makeViewModel(
        event: RaceEvent,
        drivers: [Driver],
        podiumNames: [String],
        championshipRepository: ChampionshipRepository = EmptyChampionshipRepository(),
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
            championshipRepository: championshipRepository,
            seasonRepository: resolvedSeasonRepository
        )
    }
}

private actor SequencedDriverRepository: DriverRepository {
    private var queuedDrivers: [RaceSeries: [[Driver]]]

    init(queuedDrivers: [RaceSeries: [[Driver]]]) {
        self.queuedDrivers = queuedDrivers
    }

    func drivers(for series: RaceSeries) async throws -> [Driver] {
        guard var queue = queuedDrivers[series], !queue.isEmpty else {
            return []
        }

        if queue.count == 1 {
            return queue[0]
        }

        let next = queue.removeFirst()
        queuedDrivers[series] = queue
        return next
    }
}

private actor SequencedCalendarRepository: CalendarRepository {
    private var queuedEvents: [RaceSeries: [[RaceEvent]]]

    init(queuedEvents: [RaceSeries: [[RaceEvent]]]) {
        self.queuedEvents = queuedEvents
    }

    func events(for series: RaceSeries) async throws -> [RaceEvent] {
        guard var queue = queuedEvents[series], !queue.isEmpty else {
            return []
        }

        if queue.count == 1 {
            return queue[0]
        }

        let next = queue.removeFirst()
        queuedEvents[series] = queue
        return next
    }

    func allEvents() async throws -> [RaceEvent] {
        let f1 = try await events(for: .formula1)
        let motoGP = try await events(for: .motoGP)
        return f1 + motoGP
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

private actor PermissionFailureLeagueSyncStore: LeagueSyncStore {
    func createLeague(from state: PersistedState) async throws -> PersistedState {
        var sharedState = state
        sharedState.settings.leagueCode = "ABC123"
        return sharedState
    }

    func joinLeague(code: String) async throws -> PersistedState {
        throw CKError(.permissionFailure)
    }

    func fetchState(for code: String) async throws -> PersistedState? {
        throw CKError(.permissionFailure)
    }

    func pushState(_ state: PersistedState, for code: String) async throws {
        throw CKError(.permissionFailure)
    }
}

private actor ManualSyncPermissionFailureSeasonRepository: SeasonRepository {
    private var state: PersistedState

    init() {
        var initial = PersistedState.default
        initial.settings.leagueCode = "ABC123"
        state = initial
    }

    func loadState() async throws -> PersistedState {
        state
    }

    func refreshState() async throws -> PersistedState {
        let nested = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.permissionFailure.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "WRITE operation not permitted"]
        )
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "league-ABC123"): nested]]
        )
        throw partial
    }

    func consumeLoadRecoveryMessage() async -> String? {
        nil
    }

    func savePlayers(_ players: [Player]) async throws -> PersistedState {
        state.players = players
        return state
    }

    func saveSettings(_ settings: AppSettings) async throws -> PersistedState {
        state.settings = settings
        return state
    }

    func upsertPick(_ pick: RacePick) async throws -> PersistedState {
        state.picks.removeAll { $0.id == pick.id }
        state.picks.append(pick)
        return state
    }

    func upsertResult(_ result: RaceResult) async throws -> PersistedState {
        state.results.removeAll {
            $0.series == result.series && $0.eventID == result.eventID
        }
        state.results.append(result)
        return state
    }

    func upsertChampionPick(_ pick: SeasonChampionPick) async throws -> PersistedState {
        state.championPicks.removeAll { $0.id == pick.id }
        state.championPicks.append(pick)
        return state
    }

    func upsertChampionResult(_ result: SeasonChampionResult) async throws -> PersistedState {
        state.championResults.removeAll { $0.id == result.id }
        state.championResults.append(result)
        return state
    }

    func resetSeason() async throws -> PersistedState {
        state.picks = []
        state.results = []
        state.championPicks = []
        state.championResults = []
        return state
    }

    func createLeague() async throws -> PersistedState {
        state
    }

    func joinLeague(code: String) async throws -> PersistedState {
        state.settings.leagueCode = code
        return state
    }
}

import XCTest
@testable import Chicane

final class SeasonArchiveTests: XCTestCase {
    private let service = SeasonArchiveService()
    private let alice = Player(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Alice")
    private let bob = Player(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Bob")
    private let date = ISO8601DateFormatter().date(from: "2026-12-01T12:00:00Z")!

    private var drivers: [Driver] {
        RaceSeries.allCases.flatMap { series in
            ["a", "b", "c"].map { Driver(id: "\(series.rawValue)-\($0)", series: series, name: "Driver \($0.uppercased())", team: "Team", number: "1") }
        }
    }

    private func events(year: Int = 2026) -> [RaceEvent] {
        RaceSeries.allCases.flatMap { series in
            (1...2).map { round in
                RaceEvent(id: "\(series.rawValue)-\(year)-r\(round)", series: series, season: year, round: round, title: "Race \(round)", circuit: "Circuit", raceDate: date.addingTimeInterval(Double(round) * 86_400))
            }
        }
    }

    private func state() -> PersistedState {
        var state = PersistedState.default
        state.players = [alice, bob]
        state.settings.playerBetTextByPlayerID[alice.id] = "Dinner is on me"
        for event in events() {
            let prefix = event.series.rawValue
            let podium = Podium(p1: "\(prefix)-a", p2: "\(prefix)-b", p3: "\(prefix)-c")
            state.results.append(RaceResult(series: event.series, eventID: event.id, podium: podium, isLocked: true, updatedAt: date, isOfficial: true))
            for player in [alice, bob] {
                let pick = player.id == alice.id ? podium : Podium(p1: podium.p1, p2: podium.p3, p3: podium.p2)
                state.picks.append(RacePick(id: UUID(), series: event.series, eventID: event.id, playerID: player.id, podium: pick, updatedAt: date))
            }
        }
        for series in RaceSeries.allCases {
            state.championResults.append(SeasonChampionResult(series: series, driverID: "\(series.rawValue)-a", updatedAt: date, season: 2026))
            for player in [alice, bob] {
                state.championPicks.append(SeasonChampionPick(id: UUID(), series: series, playerID: player.id, driverID: "\(series.rawValue)-\(player.id == alice.id ? "a" : "b")", updatedAt: date, season: 2026))
            }
        }
        return state
    }

    func testOfficialFinalesProduceCompleteCombinedReportWithExistingScoring() throws {
        let archives = service.updatedArchives(state: state(), events: events(), participants: drivers, at: date)
        let review = try XCTUnwrap(service.reviews(from: archives).first)
        XCTAssertEqual(archives.count, 2)
        XCTAssertTrue(review.isComplete)
        XCTAssertEqual(review.winners.map(\.name), ["Alice"])
        XCTAssertEqual(review.standings.first?.racePoints, 12)
        XCTAssertEqual(review.standings.first?.championBonus, 10)
        XCTAssertEqual(review.standings.first?.total, 22)
        XCTAssertEqual(review.standings.first?.perfectPodiums, 4)
        XCTAssertEqual(review.standings.first?.bet, "Dinner is on me")
        XCTAssertTrue(review.recap.contains("18 points ahead of Bob"))
        XCTAssertTrue(review.highlights.contains { $0.id == "perfect" })
    }

    func testManualOrLegacyFinaleDoesNotTriggerArchive() throws {
        var state = state()
        for index in state.results.indices { state.results[index].isOfficial = false }
        XCTAssertTrue(service.updatedArchives(state: state, events: events(), participants: drivers).isEmpty)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(state.results[0])) as? [String: Any])
        payload.removeValue(forKey: "isOfficial")
        let result = try decoder.decode(RaceResult.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertFalse(result.isOfficial)
    }

    func testFirstSeriesClosesWithoutPrematureCombinedWinner() throws {
        var state = state()
        state.results.removeAll { $0.series == .motoGP && $0.eventID.hasSuffix("r2") }
        let archives = service.updatedArchives(state: state, events: events(), participants: drivers)
        XCTAssertEqual(archives.count, 1)
        XCTAssertTrue(archives[0].isComplete)
        XCTAssertFalse(try XCTUnwrap(service.reviews(from: archives).first).isComplete)
    }

    func testMissingEarlierResultsAndChampionKeepReportPendingThenComplete() throws {
        var state = state()
        let complete = state
        state.results.removeAll { $0.series == .formula1 && $0.eventID.hasSuffix("r1") }
        state.championResults = []
        state.seasonArchives = service.updatedArchives(state: state, events: events(), participants: drivers, at: date)
        XCTAssertFalse(service.reviews(from: state.seasonArchives)[0].isComplete)
        XCTAssertTrue(state.seasonArchives.contains { $0.pendingDescription.contains("1 race result") })
        state.results = complete.results
        state.championResults = complete.championResults
        let finished = service.updatedArchives(state: state, events: events(), participants: drivers, at: date.addingTimeInterval(60))
        XCTAssertTrue(service.reviews(from: finished)[0].isComplete)
        XCTAssertEqual(finished.count, 2)
    }

    func testEqualScoresRecognizeSharedWinners() throws {
        var state = state()
        for index in state.picks.indices {
            state.picks[index].podium = state.results.first { $0.eventID == state.picks[index].eventID }!.podium
        }
        for index in state.championPicks.indices {
            state.championPicks[index].driverID = "\(state.championPicks[index].series.rawValue)-a"
        }
        let review = service.reviews(from: service.updatedArchives(state: state, events: events(), participants: drivers))[0]
        XCTAssertEqual(review.winners.count, 2)
        XCTAssertTrue(review.recap.contains("shared"))
    }

    func testRepeatedRefreshIsIdempotentAndNamesAndStakesStayFrozen() throws {
        var state = state()
        state.seasonArchives = service.updatedArchives(state: state, events: events(), participants: drivers, at: date)
        let original = state.seasonArchives
        XCTAssertEqual(service.updatedArchives(state: state, events: events(), participants: drivers, at: date.addingTimeInterval(60)), original)
        state.players[0].name = "Renamed"
        state.settings.playerBetTextByPlayerID[alice.id] = "Different bet"
        XCTAssertEqual(service.updatedArchives(state: state, events: events(), participants: drivers, at: date.addingTimeInterval(120)), original)
    }

    func testOfficialCorrectionUpdatesOneReportAndKeepsHistoricalNames() throws {
        var state = state()
        state.seasonArchives = service.updatedArchives(state: state, events: events(), participants: drivers, at: date)
        state.results[0].podium = Podium(p1: "formula1-b", p2: "formula1-a", p3: "formula1-c")
        state.results[0].updatedAt = date.addingTimeInterval(100)
        let archives = service.updatedArchives(state: state, events: events(), participants: drivers, at: date.addingTimeInterval(120))
        XCTAssertEqual(archives.count, 2)
        XCTAssertEqual(archives.first { $0.series == .formula1 }?.revision, 2)
        XCTAssertLessThan(service.reviews(from: archives)[0].standings[0].total, 22)
    }

    func testPriorYearChampionIsNotAppliedToNewYear() throws {
        var state = state()
        state.championResults = state.championResults.map { value in
            var copy = value
            copy.season = 2025
            return copy
        }
        let archives = service.updatedArchives(state: state, events: events(), participants: drivers)
        XCTAssertTrue(archives.allSatisfy { $0.championResult == nil && !$0.isComplete })
    }

    func testSchemaFiveMigrationAddsEmptyArchiveWithoutChangingActivePicks() throws {
        let original = state()
        let encoder = JSONEncoder()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        payload["schemaVersion"] = 5
        payload.removeValue(forKey: "seasonArchives")
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONSerialization.data(withJSONObject: payload)).normalized()
        XCTAssertEqual(decoded.schemaVersion, 6)
        XCTAssertEqual(decoded.picks, original.picks)
        XCTAssertTrue(decoded.seasonArchives.isEmpty)
    }

    func testResetReloadAndPlayerRemovalPreserveArchive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileStateStore(baseDirectoryURL: directory)
        let repo = LocalSeasonRepository(store: store)
        _ = try await repo.replaceState(state())
        let archived = try await repo.updateSeasonArchives(events: events(), participants: drivers)
        _ = try await repo.savePlayers([bob])
        _ = try await repo.resetSeason()
        let loaded = try await LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: directory)).loadState()
        XCTAssertTrue(loaded.results.isEmpty)
        XCTAssertEqual(loaded.seasonArchives.count, 2)
        XCTAssertEqual(loaded.seasonArchives.map(\.players), archived.seasonArchives.map(\.players))
        XCTAssertTrue(service.reviews(from: loaded.seasonArchives)[0].isComplete)
    }

    func testMergeKeepsDifferentYearsAndBothSeriesAfterStaleReset() throws {
        let archives = service.updatedArchives(state: state(), events: events(), participants: drivers, at: date)
        var previousYear = archives[0]
        // A second group's same year is a separate record, never a combined league.
        previousYear = ArchivedSeason(season: 2025, series: previousYear.series, leagueCode: "OLD123", createdAt: date, updatedAt: date, revision: 1, scoringVersion: 1, players: previousYear.players, bets: previousYear.bets, events: previousYear.events, participants: previousYear.participants, picks: previousYear.picks, results: previousYear.results, championPicks: previousYear.championPicks, championResult: previousYear.championResult)
        let merged = ArchivedSeason.merged([archives[0], previousYear] + archives)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(service.reviews(from: merged).count, 2)
        XCTAssertEqual(service.reviews(from: merged).first?.season, 2026)
    }

    func testCloudArchiveMergeSurvivesResetAndDoesNotShareAnotherLeague() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: directory))
        var seed = state()
        seed.seasonArchives = service.updatedArchives(state: seed, events: events(), participants: drivers, at: date)
        seed.settings.leagueCode = "NEW123"
        _ = try await local.replaceState(seed)
        let cloud = ArchiveTestCloudStore()
        let repo = CloudSyncSeasonRepository(localRepository: local, cloudStore: cloud)
        let saved = try await repo.updateSeasonArchives(events: events(), participants: drivers)
        XCTAssertEqual(saved.seasonArchives.count, 4)
        let shared = await cloud.currentState()
        XCTAssertEqual(shared?.seasonArchives.count, 2)
        XCTAssertTrue(shared?.seasonArchives.allSatisfy { $0.leagueCode == "NEW123" } == true)
        let reset = try await repo.resetSeason()
        XCTAssertEqual(reset.seasonArchives.count, 4)
        let synced = try await repo.refreshState()
        XCTAssertEqual(synced.seasonArchives.count, 4)
    }

    func testArchiveMergeReconcilesBundledAndLiveEventAndParticipantIDs() throws {
        let original = service.updatedArchives(state: state(), events: events(), participants: drivers, at: date).first { $0.series == .formula1 }!
        var live = original
        live.createdAt = date.addingTimeInterval(1)
        live.participants = original.participants.map { Driver(id: "live-\($0.id)", series: $0.series, name: $0.name, team: $0.team, number: $0.number) }
        live.events = original.events.map { RaceEvent(id: "live-\($0.id)", series: $0.series, season: $0.season, round: $0.round, title: $0.title, circuit: $0.circuit, raceDate: $0.raceDate) }
        func podium(_ value: Podium) -> Podium { Podium(p1: "live-\(value.p1)", p2: "live-\(value.p2)", p3: "live-\(value.p3)") }
        live.results = original.results.map { RaceResult(series: $0.series, eventID: "live-\($0.eventID)", podium: podium($0.podium), isLocked: true, updatedAt: date.addingTimeInterval(10), isOfficial: true) }
        live.results[0].podium = Podium(p1: "live-formula1-b", p2: "live-formula1-a", p3: "live-formula1-c")
        live.picks = original.picks.map { RacePick(id: $0.id, series: $0.series, eventID: "live-\($0.eventID)", playerID: $0.playerID, podium: podium($0.podium), updatedAt: $0.updatedAt) }
        live.championPicks = original.championPicks.map { value in var copy = value; copy.driverID = "live-\(copy.driverID)"; return copy }
        live.championResult?.driverID = "live-formula1-a"
        let merged = try XCTUnwrap(ArchivedSeason.merged([original, live]).first)
        XCTAssertEqual(merged.results.count, 2)
        XCTAssertEqual(merged.picks.count, 4)
        XCTAssertEqual(merged.participants.count, 3)
        XCTAssertTrue(merged.isComplete)
        XCTAssertEqual(service.standings(for: [merged]).first?.total, 9)
    }

    func testFiveFullSeasonsRoundTripWithoutOverwritingYears() throws {
        var history = state()
        history.seasonArchives = []
        for year in 2022...2026 {
            var seasonState = state()
            seasonState.seasonArchives = history.seasonArchives
            seasonState.picks = []
            seasonState.results = []
            let calendar = RaceSeries.allCases.flatMap { series in
                (1...25).map { round in RaceEvent(id: "\(series.rawValue)-\(year)-\(round)", series: series, season: year, round: round, title: "Championship Grand Prix \(round)", circuit: "Grand Prix Circuit", raceDate: date.addingTimeInterval(Double(round) * 86_400)) }
            }
            for event in calendar {
                let prefix = event.series.rawValue
                let podium = Podium(p1: "\(prefix)-a", p2: "\(prefix)-b", p3: "\(prefix)-c")
                seasonState.results.append(RaceResult(series: event.series, eventID: event.id, podium: podium, isLocked: true, updatedAt: date, isOfficial: true))
                for player in seasonState.players {
                    seasonState.picks.append(RacePick(id: UUID(), series: event.series, eventID: event.id, playerID: player.id, podium: podium, updatedAt: date))
                }
            }
            for index in seasonState.championPicks.indices { seasonState.championPicks[index].season = year }
            for index in seasonState.championResults.indices { seasonState.championResults[index].season = year }
            history.seasonArchives = service.updatedArchives(state: seasonState, events: calendar, participants: drivers, at: date)
        }
        let data = try JSONEncoder().encode(history)
        let restored = try JSONDecoder().decode(PersistedState.self, from: data)
        let reviews = service.reviews(from: restored.seasonArchives)
        XCTAssertEqual(reviews.map(\.season), [2026, 2025, 2024, 2023, 2022])
        XCTAssertTrue(reviews.allSatisfy(\.isComplete))
        XCTAssertEqual(restored.seasonArchives.count, 10)
        XCTAssertLessThan(data.count, 900_000, "Representative two-player, five-season data must fit the existing shared record")
    }

    func testCloudFailureStillPersistsTheLocalArchive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: directory))
        var seed = state()
        seed.settings.leagueCode = "ABC123"
        _ = try await local.replaceState(seed)
        let repo = CloudSyncSeasonRepository(localRepository: local, cloudStore: ArchiveTestCloudStore(failsWrites: true))
        do {
            _ = try await repo.updateSeasonArchives(events: events(), participants: drivers)
            XCTFail("Expected a visible deferred-sync warning")
        } catch let warning as DeferredCloudSyncWarning {
            XCTAssertEqual(warning.state.seasonArchives.count, 2)
        }
        let loaded = try await local.refreshState()
        XCTAssertEqual(loaded.seasonArchives.count, 2)
    }

    @MainActor
    func testOfficialFinaleFetchAutomaticallyArchivesAndResetKeepsReview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = LocalSeasonRepository(store: FileStateStore(baseDirectoryURL: directory))
        var seed = state()
        let finale = events().first { $0.series == .formula1 && $0.round == 2 }!
        seed.results.removeAll { $0.eventID == finale.id }
        _ = try await local.replaceState(seed)
        let model = AppViewModel(driverRepository: ArchiveTestDrivers(values: drivers), calendarRepository: ArchiveTestCalendar(values: events()), resultRepository: ArchiveTestResults(), seasonRepository: local)
        await model.reload()
        XCTAssertFalse(model.seasonReviews[0].isComplete)
        let warning = try await model.updateResultFromOfficialSource(series: .formula1, eventID: finale.id)
        XCTAssertNil(warning)
        XCTAssertTrue(model.seasonReviews[0].isComplete)
        _ = try await model.resetSeason()
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertTrue(model.seasonReviews[0].isComplete)
    }
}

private actor ArchiveTestCloudStore: LeagueSyncStore {
    private var state: PersistedState?
    private let failsWrites: Bool
    init(failsWrites: Bool = false) { self.failsWrites = failsWrites }
    func currentState() -> PersistedState? { state }
    func createLeague(from state: PersistedState) async throws -> PersistedState { state }
    func joinLeague(code: String) async throws -> PersistedState { state ?? .default }
    func fetchState(for code: String) async throws -> PersistedState? { state }
    func pushState(_ state: PersistedState, for code: String) async throws {
        if failsWrites { throw RepositoryError.cloudSyncUnavailable }
        self.state = state
    }
}

private struct ArchiveTestDrivers: DriverRepository {
    let values: [Driver]
    func drivers(for series: RaceSeries) async throws -> [Driver] { values.filter { $0.series == series } }
}

private struct ArchiveTestCalendar: CalendarRepository {
    let values: [RaceEvent]
    func events(for series: RaceSeries) async throws -> [RaceEvent] { values.filter { $0.series == series } }
    func allEvents() async throws -> [RaceEvent] { values }
}

private struct ArchiveTestResults: ResultRepository {
    func podium(for event: RaceEvent) async throws -> [String] { ["Driver A", "Driver B", "Driver C"] }
}

import XCTest
@testable import Chicane

final class RaceWeekendWidgetScheduleTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private var austin: RaceEvent {
        RaceEvent(id: "f1-live-austin", series: .formula1, season: 2026, round: 18,
                  title: "United States Grand Prix", circuit: "Austin",
                  raceDate: date("2026-10-25T20:00:00Z"))
    }

    private var australia: RaceEvent {
        RaceEvent(id: "motogp-live-australia", series: .motoGP, season: 2026, round: 18,
                  title: "Australian GP", circuit: "Phillip Island",
                  raceDate: date("2026-10-25T01:00:00Z"))
    }

    private var mexico: RaceEvent {
        RaceEvent(id: "f1-live-mexico", series: .formula1, season: 2026, round: 19,
                  title: "Mexico City Grand Prix", circuit: "Mexico City",
                  raceDate: date("2026-11-01T20:00:00Z"))
    }

    private func result(_ event: RaceEvent, locked: Bool = true) -> RaceResult {
        RaceResult(series: event.series, eventID: event.id, podium: Podium(p1: "a", p2: "b", p3: "c"),
                   isLocked: locked, updatedAt: date("2026-10-25T23:00:00Z"))
    }

    func testCanceledMotoGPDoesNotSkipAustinBeforeItsStart() {
        let snapshot = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [australia, austin, mexico], canceledEvents: [australia])
        // 08:12 in Los Angeles, before the app's 13:00 Austin race start.
        let selected = WidgetCalendarStore.nextEvent(at: date("2026-10-25T15:12:00Z"), snapshot: snapshot)
        XCTAssertEqual(selected.id, austin.id)
        XCTAssertEqual(selected.raceDate, austin.raceDate)
        XCTAssertEqual(selected.round, 18)
    }

    func testCanceledLaterRaceDoesNotHideEarlierPendingRaceWithIdenticalBundledStartTimes() {
        let early = RaceEvent(id: austin.id, series: austin.series, season: 2026, round: 18,
                              title: austin.title, circuit: austin.circuit, raceDate: date("2026-10-25T12:00:00Z"))
        let later = RaceEvent(id: australia.id, series: australia.series, season: 2026, round: 18,
                              title: australia.title, circuit: australia.circuit, raceDate: early.raceDate)
        let snapshot = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [early, later, mexico], canceledEvents: [later])
        XCTAssertEqual(WidgetCalendarStore.nextEvent(at: date("2026-10-25T15:12:00Z"), snapshot: snapshot).id, early.id)
    }

    func testResultForAnotherSeriesDoesNotHidePendingAustin() {
        let later = RaceEvent(id: australia.id, series: australia.series, season: 2026, round: 18,
                              title: australia.title, circuit: australia.circuit, raceDate: date("2026-10-25T21:00:00Z"))
        let snapshot = RaceWeekendWidgetSnapshotStore.snapshot(results: [result(later)], events: [austin, later, mexico])
        XCTAssertEqual(WidgetCalendarStore.nextEvent(at: date("2026-10-25T23:00:00Z"), snapshot: snapshot).id, austin.id)
    }

    func testAustinStaysUntilItsResultIsRecordedThenAdvances() {
        let beforeResult = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [austin, mexico])
        XCTAssertEqual(WidgetCalendarStore.nextEvent(at: date("2026-10-25T23:00:00Z"), snapshot: beforeResult).id, austin.id)
        let afterResult = RaceWeekendWidgetSnapshotStore.snapshot(results: [result(austin)], events: [austin, mexico])
        XCTAssertEqual(WidgetCalendarStore.nextEvent(at: date("2026-10-25T23:00:00Z"), snapshot: afterResult).id, mexico.id)
    }

    func testPrematureResultCannotAdvanceBeforeScheduledStart() {
        let snapshot = RaceWeekendWidgetSnapshotStore.snapshot(results: [result(austin)], events: [austin, mexico])
        XCTAssertEqual(WidgetCalendarStore.nextEvent(at: austin.raceDate.addingTimeInterval(-1), snapshot: snapshot).id, austin.id)
    }

    func testFutureCancellationIsSkippedAndUndoRestoresIt() {
        let canceled = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [austin, mexico], canceledEvents: [austin])
        XCTAssertEqual(WidgetCalendarStore.nextEvent(at: austin.raceDate.addingTimeInterval(-1), snapshot: canceled).id, mexico.id)
        let restored = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [austin, mexico])
        XCTAssertEqual(WidgetCalendarStore.nextEvent(at: austin.raceDate.addingTimeInterval(-1), snapshot: restored).id, austin.id)
    }

    func testOldMissingResultDoesNotBlockNextWeekend() {
        let snapshot = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [austin, mexico])
        XCTAssertEqual(WidgetCalendarStore.nextEvent(at: date("2026-10-31T12:00:00Z"), snapshot: snapshot).id, mexico.id)
    }

    func testAtomicSnapshotRetainsLiveCalendarAndUpdatesWhenOnlyStartTimeChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(RaceWeekendWidgetSnapshot.fileName)
        let snapshot = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [australia, austin, mexico], canceledEvents: [australia])
        XCTAssertTrue(try snapshot.write(to: url))
        XCTAssertEqual(try RaceWeekendWidgetSnapshot.read(from: url), snapshot)
        XCTAssertFalse(try snapshot.write(to: url))
        let delayed = RaceEvent(id: austin.id, series: austin.series, season: 2026, round: 18,
                                title: austin.title, circuit: austin.circuit, raceDate: austin.raceDate.addingTimeInterval(3600))
        let updated = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [australia, delayed, mexico], canceledEvents: [australia])
        XCTAssertTrue(try updated.write(to: url))
        let readBack = try RaceWeekendWidgetSnapshot.read(from: url)
        let selected = WidgetCalendarStore.nextEvent(at: date("2026-10-25T15:12:00Z"), snapshot: readBack)
        XCTAssertEqual(selected.raceDate, delayed.raceDate)
        XCTAssertEqual(readBack.canceledEventKeys, ["motoGP|2026|18"])
    }

    func testDelayedWriteCannotOverwriteNewerCancellationSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(RaceWeekendWidgetSnapshot.fileName)
        let older = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [australia, austin, mexico])
        let newer = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [australia, austin, mexico], canceledEvents: [australia])
        let instant = ContinuousClock.now
        let writer = RaceWeekendWidgetSnapshotWriter()
        try await writer.save(newer, to: url, requestedAt: instant.advanced(by: .seconds(1)))
        try await writer.save(older, to: url, requestedAt: instant)
        XCTAssertEqual(try RaceWeekendWidgetSnapshot.read(from: url), newer)
    }

    func testRefreshDoesNotWaitUntilNextDayAtRaceStart() {
        let snapshot = RaceWeekendWidgetSnapshotStore.snapshot(results: [], events: [austin, mexico])
        let now = austin.raceDate.addingTimeInterval(-30)
        let event = WidgetCalendarStore.nextEvent(at: now, snapshot: snapshot)
        XCTAssertEqual(WidgetCalendarStore.nextRefreshDate(for: event, at: now), austin.raceDate.addingTimeInterval(60))
    }
}

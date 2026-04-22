import AppIntents
import Foundation
import SwiftUI

@main
struct ChicaneApp: App {
    @StateObject private var viewModel: AppViewModel

    init() {
        Self.updateSettingsVersionDisplay()

        let viewModel = Self.makeViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
    private static func updateSettingsVersionDisplay() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        let displayValue: String
        if let version, !version.isEmpty {
            if let build, !build.isEmpty {
                displayValue = "\(version) (\(build))"
            } else {
                displayValue = version
            }
        } else {
            displayValue = "--"
        }

        UserDefaults.standard.set(displayValue, forKey: "app_version_display")
    }

    private static func makeViewModel() -> AppViewModel {
        let launchEnvironment = ProcessInfo.processInfo.environment
        if launchEnvironment["CHICANE_UI_TEST_MODE"] == "1" {
            let runID = launchEnvironment["CHICANE_UI_TEST_RUN_ID"] ?? UUID().uuidString
            let scenarioRaw = launchEnvironment["CHICANE_UI_TEST_SCENARIO"] ?? "default"
            let scenario = UITestScenario(rawValue: scenarioRaw) ?? .default
            let localSeasonRepository = makeUITestLocalSeasonRepository(runID: runID, scenario: scenario)
            return AppViewModel(
                driverRepository: UITestDriverRepository(),
                calendarRepository: UITestCalendarRepository(),
                resultRepository: UITestResultRepository(),
                championshipRepository: UITestChampionshipRepository(),
                seasonRepository: CloudSyncSeasonRepository(localRepository: localSeasonRepository)
            )
        }

        let bundledDrivers = BundledDriverRepository()
        let bundledCalendar = BundledCalendarRepository()
        let onlineDrivers = OnlineDriverRepository()
        let onlineCalendar = OnlineCalendarRepository()
        let onlineResults = OnlineResultRepository()
        let onlineChampionships = OnlineChampionshipRepository()
        let localSeasonRepository = LocalSeasonRepository()

        return AppViewModel(
            driverRepository: FallbackDriverRepository(
                primary: onlineDrivers,
                fallback: bundledDrivers
            ),
            calendarRepository: FallbackCalendarRepository(
                primary: onlineCalendar,
                fallback: bundledCalendar
            ),
            resultRepository: onlineResults,
            championshipRepository: onlineChampionships,
            seasonRepository: CloudSyncSeasonRepository(
                localRepository: localSeasonRepository
            )
        )
    }

    private static func makeUITestLocalSeasonRepository(
        runID: String,
        scenario: UITestScenario
    ) -> LocalSeasonRepository {
        let fileManager = FileManager.default
        let baseDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("ChicaneUITests", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        let store = FileStateStore(baseDirectoryURL: baseDirectoryURL)
        let stateFileURL = baseDirectoryURL
            .appendingPathComponent("Chicane", isDirectory: true)
            .appendingPathComponent("season_state_v1.json", isDirectory: false)

        do {
            try fileManager.removeItem(at: baseDirectoryURL)
        } catch {
            // If there is no previous run directory, this is expected.
        }

        do {
            try fileManager.createDirectory(at: stateFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            var state = PersistedState.default
            state.players = [Player(id: UITestFixtures.playerID, name: "UITest Player")]
            switch scenario {
            case .default:
                break
            case .lockedGates:
                state.results = [
                    RaceResult(
                        series: .formula1,
                        eventID: UITestFixtures.eventID,
                        podium: Podium(
                            p1: UITestFixtures.driver1ID,
                            p2: UITestFixtures.driver2ID,
                            p3: UITestFixtures.driver3ID
                        ),
                        isLocked: true,
                        updatedAt: Date()
                    )
                ]
                state.championResults = [
                    SeasonChampionResult(
                        series: .formula1,
                        driverID: UITestFixtures.driver1ID,
                        isLocked: true,
                        updatedAt: Date()
                    )
                ]
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateFileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to prepare UI test seed state: \(error)")
        }

        return LocalSeasonRepository(store: store)
    }
}

private enum UITestScenario: String {
    case `default` = "default"
    case lockedGates = "locked_gates"
}

private enum UITestFixtures {
    static let playerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let eventID = "ui-f1-r1"
    static let driver1ID = "ui-f1-max"
    static let driver2ID = "ui-f1-lando"
    static let driver3ID = "ui-f1-charles"
}

private struct UITestDriverRepository: DriverRepository {
    func drivers(for series: RaceSeries) async throws -> [Driver] {
        switch series {
        case .formula1:
            return [
                Driver(id: UITestFixtures.driver1ID, series: .formula1, name: "Max Verstappen", team: "Red Bull", number: "1"),
                Driver(id: UITestFixtures.driver2ID, series: .formula1, name: "Lando Norris", team: "McLaren", number: "4"),
                Driver(id: UITestFixtures.driver3ID, series: .formula1, name: "Charles Leclerc", team: "Ferrari", number: "16")
            ]
        case .motoGP:
            return [
                Driver(id: "ui-mgp-bagnaia", series: .motoGP, name: "Francesco Bagnaia", team: "Ducati", number: "1"),
                Driver(id: "ui-mgp-martin", series: .motoGP, name: "Jorge Martin", team: "Aprilia", number: "89"),
                Driver(id: "ui-mgp-marquez", series: .motoGP, name: "Marc Marquez", team: "Ducati", number: "93")
            ]
        }
    }
}

private struct UITestCalendarRepository: CalendarRepository {
    func events(for series: RaceSeries) async throws -> [RaceEvent] {
        let now = Date()
        switch series {
        case .formula1:
            return [
                RaceEvent(
                    id: UITestFixtures.eventID,
                    series: .formula1,
                    season: 2026,
                    round: 1,
                    title: "UI Test Grand Prix",
                    circuit: "Test Circuit",
                    raceDate: now.addingTimeInterval(7 * 24 * 3600),
                    trackTimeZoneID: "America/Los_Angeles"
                )
            ]
        case .motoGP:
            return [
                RaceEvent(
                    id: "ui-mgp-r1",
                    series: .motoGP,
                    season: 2026,
                    round: 1,
                    title: "UI Test MotoGP",
                    circuit: "Moto Test Circuit",
                    raceDate: now.addingTimeInterval(10 * 24 * 3600),
                    trackTimeZoneID: "Europe/Rome"
                )
            ]
        }
    }

    func allEvents() async throws -> [RaceEvent] {
        let formula1 = try await events(for: .formula1)
        let motoGP = try await events(for: .motoGP)
        return (formula1 + motoGP).sorted { $0.raceDate < $1.raceDate }
    }
}

private struct UITestResultRepository: ResultRepository {
    func podium(for _: RaceEvent) async throws -> [String] {
        ["Max Verstappen", "Lando Norris", "Charles Leclerc"]
    }
}

private struct UITestChampionshipRepository: ChampionshipRepository {
    func topThree(for _: RaceSeries) async throws -> [ChampionshipLeader] {
        []
    }
}

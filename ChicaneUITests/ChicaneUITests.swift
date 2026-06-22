import AppIntents
import XCTest

final class ChicaneUITests: XCTestCase {
    private enum Timeout {
        static let short: TimeInterval = 5
        static let medium: TimeInterval = 10
    }

    private enum UITestScenario: String {
        case `default` = "default"
        case lockedGates = "locked_gates"
    }

    private enum Tab {
        static let weekend = "Weekend"
        static let standings = "Standings"
        static let results = "Results"
        static let settings = "Settings"
    }

    func testLaunchShowsCoreTabShell() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].exists)
        XCTAssertTrue(app.tabBars.buttons[Tab.standings].exists)
        XCTAssertTrue(app.tabBars.buttons[Tab.results].exists)
        XCTAssertTrue(app.tabBars.buttons[Tab.settings].exists)
    }

    func testAddPlayerInSettingsThenWeekendPicksArePlayable() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.settings].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.settings].tap()

        let addPlayerField = app.textFields["Add Player"]
        XCTAssertTrue(addPlayerField.waitForExistence(timeout: Timeout.medium))
        addPlayerField.tap()

        let playerName = "UITest Player \(UUID().uuidString.prefix(8))"
        addPlayerField.typeText(playerName)
        app.buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts[playerName].waitForExistence(timeout: Timeout.medium))
        dismissKeyboardIfVisible(in: app)

        let weekendTab = app.tabBars.buttons[Tab.weekend]
        XCTAssertTrue(weekendTab.waitForExistence(timeout: Timeout.medium))
        weekendTab.tap()
        XCTAssertTrue(app.staticTexts["Make your picks"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.descendants(matching: .any)["Position 1 selection"].waitForExistence(timeout: Timeout.short))
    }

    func testMainTabJourneyShowsCoreScreens() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["Make your picks"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons[Tab.results].tap()
        XCTAssertTrue(app.staticTexts["Race Results Podium"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons[Tab.standings].tap()
        XCTAssertTrue(app.staticTexts["Season Totals"].waitForExistence(timeout: Timeout.medium))
    }

    func testResultsShowsLockedStateWhenResultIsAlreadyLocked() throws {
        let app = makeApp(scenario: .lockedGates)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.results].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.results].tap()

        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))
        XCTAssertFalse(app.buttons["Fetch Official Results"].exists)
    }

    func testChampionPickShowsLockedMessageWhenSeasonChampionIsLocked() throws {
        let app = makeApp(scenario: .lockedGates)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.results].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.results].tap()

        XCTAssertTrue(
            app.staticTexts["Season champion is locked"]
                .waitForExistence(timeout: Timeout.medium)
        )
    }

    func testResultsStartsSpoilerSafeBeforeAnyOfficialResultIsFetched() throws {
        let app = makeApp(scenario: .default)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.results].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.results].tap()

        XCTAssertTrue(
            app.staticTexts["Fetch the official top three for this event."]
                .waitForExistence(timeout: Timeout.medium)
        )
        XCTAssertFalse(app.staticTexts["Official result is locked"].exists)
    }

    func testAccessibilityCriticalControlsAcrossTabsRemainDiscoverable() throws {
        let app = makeApp(scenario: .default)
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].isHittable)
        XCTAssertTrue(app.tabBars.buttons[Tab.standings].isHittable)
        XCTAssertTrue(app.tabBars.buttons[Tab.results].isHittable)
        XCTAssertTrue(app.tabBars.buttons[Tab.settings].isHittable)

        app.tabBars.buttons[Tab.weekend].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Position 1 selection"]
                .waitForExistence(timeout: Timeout.medium)
        )

        app.tabBars.buttons[Tab.results].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Fetch official results"]
                .waitForExistence(timeout: Timeout.medium)
        )
        XCTAssertTrue(
            app.staticTexts["Fetch the official top three for this event."]
                .waitForExistence(timeout: Timeout.medium)
        )

        app.tabBars.buttons[Tab.standings].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Scoreboard scope"]
                .waitForExistence(timeout: Timeout.medium)
        )

        app.tabBars.buttons[Tab.settings].tap()
        let playerNameField = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Name for ")
        ).firstMatch
        XCTAssertTrue(
            playerNameField.waitForExistence(timeout: Timeout.medium)
        )
        XCTAssertTrue(app.textFields["Add Player"].waitForExistence(timeout: Timeout.medium))
    }

    func testAccessibilityLockedStatusSurfacesRemainDiscoverable() throws {
        let app = makeApp(scenario: .lockedGates)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.results].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.results].tap()

        XCTAssertTrue(app.staticTexts["Race Results Podium"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["Season champion is locked"].waitForExistence(timeout: Timeout.medium))
        XCTAssertFalse(app.descendants(matching: .any)["Fetch official results"].exists)
    }

    private func makeApp(scenario: UITestScenario = .default) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHICANE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CHICANE_UI_TEST_SCENARIO"] = scenario.rawValue
        app.launchEnvironment["CHICANE_UI_TEST_RUN_ID"] = UUID().uuidString
        return app
    }

    private func dismissKeyboardIfVisible(in app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }

        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        } else if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
        }
    }
}

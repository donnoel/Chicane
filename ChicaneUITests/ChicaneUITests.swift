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

    func testLaunchShowsCoreTabShell() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Picks"].exists)
        XCTAssertTrue(app.tabBars.buttons["Results"].exists)
        XCTAssertTrue(app.tabBars.buttons["Scoreboard"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testAddPlayerInSettingsThenPicksIsPlayable() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons["Settings"].tap()

        let addPlayerField = app.textFields["Add Player"]
        XCTAssertTrue(addPlayerField.waitForExistence(timeout: Timeout.medium))
        addPlayerField.tap()

        let playerName = "UITest Player \(UUID().uuidString.prefix(8))"
        addPlayerField.typeText(playerName)
        app.buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts[playerName].waitForExistence(timeout: Timeout.medium))
        dismissKeyboardIfVisible(in: app)

        let picksTab = app.tabBars.buttons["Picks"]
        XCTAssertTrue(picksTab.waitForExistence(timeout: Timeout.medium))
        picksTab.tap()
        XCTAssertTrue(app.staticTexts["Podium Picks"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.descendants(matching: .any)["Position 1 selection"].waitForExistence(timeout: Timeout.short))
    }

    func testMainTabJourneyShowsCoreScreens() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Picks"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons["Picks"].tap()
        XCTAssertTrue(app.staticTexts["Podium Picks"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons["Results"].tap()
        XCTAssertTrue(app.staticTexts["Race Results Podium"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons["Scoreboard"].tap()
        XCTAssertTrue(app.staticTexts["Season Scoreboard"].waitForExistence(timeout: Timeout.medium))
    }

    func testResultsShowsLockedStateWhenResultIsAlreadyLocked() throws {
        let app = makeApp(scenario: .lockedGates)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Results"].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons["Results"].tap()

        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))
        XCTAssertFalse(app.buttons["Fetch Official Results"].exists)
    }

    func testChampionPickShowsLockedMessageWhenSeasonChampionIsLocked() throws {
        let app = makeApp(scenario: .lockedGates)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Results"].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons["Results"].tap()

        XCTAssertTrue(
            app.staticTexts["Season champion is locked"]
                .waitForExistence(timeout: Timeout.medium)
        )
    }

    func testResultsStartsSpoilerSafeBeforeAnyOfficialResultIsFetched() throws {
        let app = makeApp(scenario: .default)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Results"].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons["Results"].tap()

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
        XCTAssertTrue(app.tabBars.buttons["Home"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Picks"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Results"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Scoreboard"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isHittable)

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Standings series"]
                .waitForExistence(timeout: Timeout.medium)
        )

        app.tabBars.buttons["Results"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Fetch official results"]
                .waitForExistence(timeout: Timeout.medium)
        )
        XCTAssertTrue(
            app.staticTexts["Fetch the official top three for this event."]
                .waitForExistence(timeout: Timeout.medium)
        )

        app.tabBars.buttons["Scoreboard"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Scoreboard scope"]
                .waitForExistence(timeout: Timeout.medium)
        )

        app.tabBars.buttons["Settings"].tap()
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

        XCTAssertTrue(app.tabBars.buttons["Results"].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons["Results"].tap()

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

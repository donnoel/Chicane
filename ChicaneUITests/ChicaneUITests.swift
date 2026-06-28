import AppIntents
import XCTest

@MainActor
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

    func testWeekendPickAutosavesAndShowsReadyState() throws {
        let app = makeApp()
        app.launch()

        completeWeekendPick(in: app, playerName: "UITest Player")

        XCTAssertTrue(app.staticTexts["Saved automatically"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: Timeout.medium))
    }

    func testAllRacesChampionPickSavesAndShowsLockedState() throws {
        var app = makeApp()
        app.launch()

        openAllRacesAndManualPicks(in: app)
        selectChampionPick(option: "Max Verstappen (Red Bull)", in: app)

        let saveChampionButton = app.buttons["Save world champion pick for UITest Player"]
        scrollToElementIfNeeded(saveChampionButton, in: app)
        XCTAssertTrue(saveChampionButton.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(saveChampionButton.isEnabled)
        saveChampionButton.tap()

        XCTAssertTrue(
            app.staticTexts["Saved and still editable until the season champion is entered."]
                .waitForExistence(timeout: Timeout.medium)
        )

        app.terminate()

        app = makeApp(scenario: .lockedGates)
        app.launch()

        openAllRacesAndManualPicks(in: app)

        let lockedMessage = app.staticTexts["Locked once the official season champion is entered."]
        scrollToElementIfNeeded(lockedMessage, in: app)
        XCTAssertTrue(lockedMessage.waitForExistence(timeout: Timeout.medium))

        let lockedSaveButton = app.buttons["Save world champion pick for UITest Player"]
        XCTAssertTrue(lockedSaveButton.waitForExistence(timeout: Timeout.medium))
        XCTAssertFalse(lockedSaveButton.isEnabled)
    }

    func testOfficialResultFetchLocksPodiumAndUpdatesStandings() throws {
        let app = makeApp()
        app.launch()

        completeWeekendPick(in: app, playerName: "UITest Player")
        fetchOfficialResult(in: app)

        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["Official Podium"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.descendants(matching: .any)["P1 Max Verstappen (Red Bull)"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["Event Points"].waitForExistence(timeout: Timeout.medium))
        let eventPlayer = app.staticTexts["UITest Player"]
        scrollToElementIfNeeded(eventPlayer, in: app)
        XCTAssertTrue(eventPlayer.waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons[Tab.standings].tap()
        XCTAssertTrue(app.staticTexts["Season Totals"].waitForExistence(timeout: Timeout.medium))
        let leaderSummary = app.staticTexts["UITest Player leads with 3"]
        scrollToElementIfNeeded(leaderSummary, in: app)
        XCTAssertTrue(leaderSummary.waitForExistence(timeout: Timeout.medium))
    }

    func testPlayerPickAndResultPersistAfterRelaunch() throws {
        let runID = UUID().uuidString
        let playerName = "Persistent Player \(UUID().uuidString.prefix(8))"
        var app = makeApp(runID: runID)
        app.launch()

        addPlayer(named: playerName, in: app)
        app.tabBars.buttons[Tab.weekend].tap()
        completeWeekendPick(in: app, playerName: playerName)
        fetchOfficialResult(in: app)
        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))

        app.terminate()

        app = makeApp(runID: runID, preserveState: true)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
        app.descendants(matching: .any)["\(playerName) picks"].tap()
        XCTAssertTrue(app.staticTexts["Saved automatically"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons[Tab.results].tap()
        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.descendants(matching: .any)["P1 Max Verstappen (Red Bull)"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons[Tab.standings].tap()
        XCTAssertTrue(app.staticTexts[playerName].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["\(playerName) leads with 3"].waitForExistence(timeout: Timeout.medium))
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

    func testResultsHidesSeasonChampionStatusWhenSeasonChampionIsLocked() throws {
        let app = makeApp(scenario: .lockedGates)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.results].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.results].tap()

        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))
        XCTAssertFalse(app.staticTexts["Season champion is locked"].exists)
        XCTAssertFalse(app.staticTexts["Season Champion"].exists)
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
        XCTAssertFalse(app.staticTexts["Season champion is locked"].exists)
        XCTAssertFalse(app.staticTexts["Season Champion"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["Fetch official results"].exists)
    }

    private func makeApp(
        scenario: UITestScenario = .default,
        runID: String = UUID().uuidString,
        preserveState: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHICANE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CHICANE_UI_TEST_SCENARIO"] = scenario.rawValue
        app.launchEnvironment["CHICANE_UI_TEST_RUN_ID"] = runID
        if preserveState {
            app.launchEnvironment["CHICANE_UI_TEST_PRESERVE_STATE"] = "1"
        }
        return app
    }

    private func addPlayer(named playerName: String, in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons[Tab.settings].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.settings].tap()

        let addPlayerField = app.textFields["Add Player"]
        XCTAssertTrue(addPlayerField.waitForExistence(timeout: Timeout.medium))
        addPlayerField.tap()
        addPlayerField.typeText(playerName)
        app.buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts[playerName].waitForExistence(timeout: Timeout.medium))
        dismissKeyboardIfVisible(in: app)
    }

    private func completeWeekendPick(in app: XCUIApplication, playerName: String) {
        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.weekend].tap()

        let playerPicker = app.descendants(matching: .any)["\(playerName) picks"]
        if playerPicker.waitForExistence(timeout: Timeout.short), playerPicker.isHittable {
            playerPicker.tap()
        }

        selectPodiumPosition(1, option: "Max Verstappen (Red Bull)", in: app)
        selectPodiumPosition(2, option: "Lando Norris (McLaren)", in: app)
        selectPodiumPosition(3, option: "Charles Leclerc (Ferrari)", in: app)
    }

    private func openAllRacesAndManualPicks(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.weekend].tap()

        let allRacesLink = app.buttons["All races and manual picks"]
        scrollToElementIfNeeded(allRacesLink, in: app)
        XCTAssertTrue(allRacesLink.waitForExistence(timeout: Timeout.medium))
        allRacesLink.tap()

        XCTAssertTrue(app.staticTexts["Podium Picks"].waitForExistence(timeout: Timeout.medium))
    }

    private func selectChampionPick(option: String, in app: XCUIApplication) {
        let picker = app.staticTexts.matching(identifier: "Champion pick").element(boundBy: 1)
        scrollToElementIfNeeded(picker, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: Timeout.medium))
        picker.tap()

        let optionElement = app.descendants(matching: .any)[option]
        XCTAssertTrue(optionElement.waitForExistence(timeout: Timeout.medium))
        optionElement.tap()

        XCTAssertTrue(app.staticTexts["World Champion"].waitForExistence(timeout: Timeout.medium))
    }

    private func selectPodiumPosition(_ position: Int, option: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["Position \(position) selection"]
        XCTAssertTrue(picker.waitForExistence(timeout: Timeout.medium))
        picker.tap()

        let optionElement = app.descendants(matching: .any)[option]
        XCTAssertTrue(optionElement.waitForExistence(timeout: Timeout.medium))
        optionElement.tap()

        if !picker.waitForExistence(timeout: Timeout.short) {
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists {
                backButton.tap()
            }
            XCTAssertTrue(picker.waitForExistence(timeout: Timeout.medium))
        }
    }

    private func fetchOfficialResult(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons[Tab.results].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.results].tap()

        let fetchButton = app.descendants(matching: .any)["Fetch official results"]
        XCTAssertTrue(fetchButton.waitForExistence(timeout: Timeout.medium))
        fetchButton.tap()
    }

    private func dismissKeyboardIfVisible(in app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }

        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        } else if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
        }
    }

    private func scrollToElementIfNeeded(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists && element.isHittable {
                return
            }
            app.swipeUp()
        }
    }
}

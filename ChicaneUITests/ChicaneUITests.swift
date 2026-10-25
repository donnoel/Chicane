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
        case multiRaceWeekend = "multi_race_weekend"
        case singleRaceWeekend = "single_race_weekend"
        case seasonArchive = "season_archive"
        case pendingSeasonArchive = "pending_season_archive"
    }

    private enum Tab {
        static let weekend = "Weekend"
        static let standings = "Standings"
        static let results = "Results"
    }

    func testLaunchShowsCoreTabShell() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].exists)
        XCTAssertTrue(app.tabBars.buttons[Tab.standings].exists)
        XCTAssertTrue(app.tabBars.buttons[Tab.results].exists)
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        openAllRacesAndManualPicks(in: app)
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: Timeout.medium))
    }

    func testSeasonsEmptyStateKeepsLiveResultsAvailable() throws {
        let app = makeApp()
        app.launch()
        openSeasons(in: app)
        XCTAssertTrue(app.otherElements["SeasonArchiveEmptyState"].waitForExistence(timeout: Timeout.medium)
            || app.staticTexts["Your story starts this season"].exists)
        app.buttons["MotoGP"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Official Results"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.descendants(matching: .any)["Fetch official results"].exists)
    }

    func testSeasonReviewShowsWinnerAndPersistsAfterRelaunch() throws {
        let runID = UUID().uuidString
        var app = makeApp(scenario: .seasonArchive, runID: runID)
        app.launch()
        openSeasonReview(in: app)
        let recap = app.staticTexts["SeasonReviewRecap"]
        XCTAssertTrue(recap.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(recap.label.contains("UITest Player won"))
        XCTAssertTrue(recap.label.contains("16 points"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Season review"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()

        app = makeApp(scenario: .seasonArchive, runID: runID, preserveState: true)
        app.launch()
        openSeasonReview(in: app)
        XCTAssertTrue(app.staticTexts["SeasonReviewRecap"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["SeasonReviewRecap"].label.contains("16 points"))
    }

    func testSeasonChampionConfirmationsFinalizePendingReport() throws {
        let app = makeApp(scenario: .pendingSeasonArchive)
        app.launch()
        openSeasonReview(in: app)
        XCTAssertTrue(app.staticTexts["SeasonReviewRecap"].label.contains("being preserved"))
        for (series, champion) in [("F1", "Max Verstappen"), ("MotoGP", "Francesco Bagnaia")] {
            let confirm = app.buttons["Confirm \(series) champion"]
            scrollToElementIfNeeded(confirm, in: app)
            XCTAssertTrue(confirm.isHittable)
            confirm.tap()
            let selection = app.descendants(matching: .any)["ArchiveChampionSelection"]
            XCTAssertTrue(selection.waitForExistence(timeout: Timeout.medium))
            selection.tap()
            app.descendants(matching: .any)[champion].firstMatch.tap()
            app.buttons["Confirm champion"].tap()
            XCTAssertTrue(app.alerts["Confirm season champion?"].waitForExistence(timeout: Timeout.medium))
            app.alerts["Confirm season champion?"].buttons["Confirm"].tap()
            XCTAssertTrue(waitUntilGone(app.navigationBars["\(series) champion"]))
        }
        XCTAssertTrue(app.staticTexts["SeasonReviewRecap"].label.contains("UITest Player won"))
    }

    private func openSeasons(in app: XCUIApplication) {
        let results = app.buttons[Tab.results].firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: Timeout.medium))
        results.tap()
        let seasons = app.buttons["Seasons"].firstMatch
        XCTAssertTrue(seasons.waitForExistence(timeout: Timeout.medium))
        seasons.tap()
    }

    private func openSeasonReview(in app: XCUIApplication) {
        openSeasons(in: app)
        let review = app.buttons["SeasonReview-2026"]
        XCTAssertTrue(review.waitForExistence(timeout: Timeout.medium))
        review.tap()
    }

    func testAddPlayerInSettingsThenWeekendPicksArePlayable() throws {
        let app = makeApp()
        app.launch()

        openSettings(in: app)

        let addPlayerField = app.textFields["Add Player"]
        XCTAssertTrue(addPlayerField.waitForExistence(timeout: Timeout.medium))
        addPlayerField.tap()

        let playerName = "UITest Player \(UUID().uuidString.prefix(8))"
        addPlayerField.typeText(playerName)
        app.buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts[playerName].waitForExistence(timeout: Timeout.medium))
        dismissKeyboardIfVisible(in: app)
        navigateBackIfPossible(in: app)

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

    func testClearingOnePositionPersistsAndImmediatelyRemovesReadyState() throws {
        let runID = UUID().uuidString
        var app = makeApp(runID: runID)
        app.launch()
        completeWeekendPick(in: app, playerName: "UITest Player")
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: Timeout.medium))
        selectPodiumPosition(1, option: "Choose driver", in: app)
        XCTAssertTrue(app.staticTexts["Open"].waitForExistence(timeout: Timeout.medium))
        XCTAssertEqual(app.buttons["Position 1 selection"].value as? String, "Choose driver")
        app.terminate()
        app = makeApp(runID: runID, preserveState: true)
        app.launch()
        let picker = app.descendants(matching: .any)["Position 1 selection"]
        XCTAssertTrue(picker.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(picker.label.contains("Choose driver") || (picker.value as? String)?.contains("Choose driver") == true || app.staticTexts["Choose driver"].exists)
        XCTAssertTrue(app.staticTexts["Open"].exists)
        selectPodiumPosition(1, option: "Max Verstappen (Red Bull)", in: app)
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: Timeout.medium))
    }

    func testCancelRaceSkipsWeekendPersistsAndUndoRestoresIt() throws {
        let runID = UUID().uuidString
        var app = makeApp(scenario: .multiRaceWeekend, runID: runID)
        app.launch()
        XCTAssertTrue(app.staticTexts["WeekendRaceTitle"].waitForExistence(timeout: Timeout.medium))
        XCTAssertEqual(app.staticTexts["WeekendRaceTitle"].label, "UI Test MotoGP")
        app.tabBars.buttons[Tab.results].tap()
        app.buttons["MotoGP"].firstMatch.tap()
        let options = app.buttons["Race options"]
        XCTAssertTrue(options.waitForExistence(timeout: Timeout.medium))
        options.tap()
        app.buttons["Mark race canceled"].tap()
        let alert = app.alerts["Cancel this race?"]
        XCTAssertTrue(alert.waitForExistence(timeout: Timeout.medium))
        alert.buttons["Mark race canceled"].tap()
        XCTAssertTrue(app.staticTexts["Race canceled"].waitForExistence(timeout: Timeout.medium))
        XCTAssertFalse(app.buttons["Fetch official results"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Canceled race"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.tabBars.buttons[Tab.weekend].tap()
        XCTAssertEqual(app.staticTexts["WeekendRaceTitle"].label, "UI Test Grand Prix")
        app.terminate()
        app = makeApp(scenario: .multiRaceWeekend, runID: runID, preserveState: true)
        app.launch()
        XCTAssertTrue(app.staticTexts["WeekendRaceTitle"].waitForExistence(timeout: Timeout.medium))
        XCTAssertEqual(app.staticTexts["WeekendRaceTitle"].label, "UI Test Grand Prix")
        app.tabBars.buttons[Tab.results].tap()
        app.buttons["MotoGP"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Race canceled"].waitForExistence(timeout: Timeout.medium))
        app.buttons["Race options"].tap()
        app.buttons["Undo cancellation"].tap()
        let undo = app.alerts["Undo cancellation?"]
        XCTAssertTrue(undo.waitForExistence(timeout: Timeout.medium))
        undo.buttons["Undo cancellation"].tap()
        XCTAssertTrue(app.buttons["Fetch official results"].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.weekend].tap()
        // Undo restores the race without changing the user's current selection.
        XCTAssertEqual(app.staticTexts["WeekendRaceTitle"].label, "UI Test Grand Prix")
        XCTAssertEqual(app.staticTexts["WeekendRacePosition"].label, "Race 2 of 2")
        app.buttons["WeekendRaceSwitcher"].tap()
        XCTAssertEqual(app.staticTexts["WeekendRaceTitle"].label, "UI Test MotoGP")
        XCTAssertEqual(app.staticTexts["WeekendRacePosition"].label, "Race 1 of 2")
    }

    func testWeekendHeroCyclesRacesInStartOrderAndPreservesSavedPicks() throws {
        let app = makeApp(scenario: .multiRaceWeekend)
        app.launch()

        let title = app.staticTexts["WeekendRaceTitle"]
        let position = app.staticTexts["WeekendRacePosition"]
        let switcher = app.buttons["WeekendRaceSwitcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: Timeout.medium))
        XCTAssertEqual(title.label, "UI Test MotoGP")
        XCTAssertEqual(position.label, "Race 1 of 2")
        XCTAssertTrue((switcher.value as? String)?.contains("0/1 ready") == true)
        XCTAssertFalse(app.staticTexts["Choose a race, then make your picks."].exists)

        switcher.tap()
        XCTAssertEqual(title.label, "UI Test Grand Prix")
        XCTAssertEqual(position.label, "Race 2 of 2")
        completeWeekendPick(in: app, playerName: "UITest Player")
        XCTAssertTrue(app.staticTexts["Saved automatically"].waitForExistence(timeout: Timeout.medium))

        for _ in 0..<5 where !switcher.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(switcher.isHittable)
        XCTAssertTrue((switcher.value as? String)?.contains("1/1 ready") == true)
        switcher.tap()
        XCTAssertEqual(title.label, "UI Test MotoGP")
        XCTAssertEqual(position.label, "Race 1 of 2")
        XCTAssertTrue((switcher.value as? String)?.contains("0/1 ready") == true)

        switcher.tap()
        XCTAssertEqual(title.label, "UI Test Grand Prix")
        XCTAssertTrue((switcher.value as? String)?.contains("1/1 ready") == true)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Combined weekend hero"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSingleRaceWeekendShowsReadinessWithoutRaceSwitcher() throws {
        let app = makeApp(scenario: .singleRaceWeekend)
        app.launch()

        let title = app.staticTexts["WeekendRaceTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: Timeout.medium))
        XCTAssertEqual(title.label, "UI Test Grand Prix")
        XCTAssertEqual(app.staticTexts["WeekendRacePosition"].label, "Next up")
        XCTAssertTrue(app.staticTexts["0/1 ready"].exists)
        XCTAssertFalse(app.buttons["WeekendRaceSwitcher"].exists)
        XCTAssertFalse(app.staticTexts["Choose a race, then make your picks."].exists)
    }

    func testWeekendHeroSwitcherWorksWithLargestAccessibilityText() throws {
        let app = makeApp(scenario: .multiRaceWeekend)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let title = app.staticTexts["WeekendRaceTitle"]
        let switcher = app.buttons["WeekendRaceSwitcher"]
        XCTAssertTrue(title.waitForExistence(timeout: Timeout.medium))
        XCTAssertEqual(title.label, "UI Test MotoGP")
        scrollToElementIfNeeded(switcher, in: app)
        XCTAssertTrue(switcher.isHittable)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Weekend hero with accessibility text"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        switcher.tap()
        XCTAssertEqual(title.label, "UI Test Grand Prix")
        XCTAssertEqual(app.staticTexts["WeekendRacePosition"].label, "Race 2 of 2")
    }

    func testAllRacesChampionPickSavesAndShowsLockedState() throws {
        var app = makeApp()
        app.launch()

        openAllRacesAndManualPicks(in: app)
        selectChampionPick(option: "Max Verstappen (Red Bull)", in: app)

        XCTAssertTrue(
            app.staticTexts["Saved quietly. Lock it in when ready."]
                .waitForExistence(timeout: Timeout.medium)
        )

        let lockChampionButton = app.buttons["Lock world champion pick for UITest Player"]
        scrollToElementIfNeeded(lockChampionButton, in: app)
        XCTAssertTrue(lockChampionButton.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(lockChampionButton.isEnabled)
        lockChampionButton.tap()
        XCTAssertTrue(app.alerts["Lock champion pick?"].waitForExistence(timeout: Timeout.medium))
        app.alerts["Lock champion pick?"].buttons["Lock Pick"].tap()
        XCTAssertTrue(
            app.staticTexts["Locked in as a final champion pick."]
                .waitForExistence(timeout: Timeout.medium)
        )
        XCTAssertFalse(lockChampionButton.exists)

        app.terminate()

        app = makeApp(scenario: .lockedGates)
        app.launch()

        openAllRacesAndManualPicks(in: app)

        let lockedMessage = app.staticTexts["Locked once the official season champion is entered."]
        scrollToElementIfNeeded(lockedMessage, in: app)
        XCTAssertTrue(lockedMessage.waitForExistence(timeout: Timeout.medium))

        XCTAssertFalse(app.buttons["Lock world champion pick for UITest Player"].exists)
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

    func testOfficialResultFetchExplainsIncompletePlayerPicks() throws {
        let app = makeApp()
        app.launch()

        fetchOfficialResult(in: app)

        XCTAssertTrue(
            app.staticTexts["All players must complete all three podium picks before fetching official results."]
                .waitForExistence(timeout: Timeout.medium)
        )
        XCTAssertFalse(app.staticTexts["Official result is locked"].exists)
    }

    func testSelectedPodiumOptionCanBeChosenAgain() throws {
        let app = makeApp()
        app.launch()

        let option = "Charles Leclerc (Ferrari)"
        selectPodiumPosition(3, option: option, in: app)
        selectPodiumPosition(3, option: option, in: app)
        XCTAssertEqual(app.buttons["Position 3 selection"].value as? String, option)
    }

    func testPlayerPickAndResultPersistAfterRelaunch() throws {
        let runID = UUID().uuidString
        let playerName = "Persistent Player \(UUID().uuidString.prefix(8))"
        var app = makeApp(runID: runID)
        app.launch()

        addPlayer(named: playerName, in: app)
        app.tabBars.buttons[Tab.weekend].tap()
        // Official results require complete picks for every player, including the seeded player.
        completeWeekendPick(in: app, playerName: "UITest Player")
        completeWeekendPick(in: app, playerName: playerName)
        fetchOfficialResult(in: app)
        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))

        app.terminate()

        app = makeApp(runID: runID, preserveState: true)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
        app.descendants(matching: .any)["\(playerName) picks"].tap()
        XCTAssertTrue(app.staticTexts["Locked once official results are retrieved."].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons[Tab.results].tap()
        XCTAssertTrue(app.staticTexts["Official result is locked"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.descendants(matching: .any)["P1 Max Verstappen (Red Bull)"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons[Tab.standings].tap()
        XCTAssertTrue(app.staticTexts[playerName].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["It's a tie at 3"].waitForExistence(timeout: Timeout.medium))
    }

    func testMainTabJourneyShowsCoreScreens() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.staticTexts["Make your picks"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons[Tab.results].tap()
        XCTAssertTrue(app.staticTexts["Official Results"].waitForExistence(timeout: Timeout.medium))

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

    func testWeekendPicksAreLockedWhenOfficialResultIsLocked() throws {
        let app = makeApp(scenario: .lockedGates)
        app.launch()

        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.weekend].tap()

        XCTAssertTrue(app.staticTexts["Make your picks"].waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(
            app.staticTexts["Locked once official results are retrieved."]
                .waitForExistence(timeout: Timeout.medium)
        )

        let picker = app.descendants(matching: .any)["Position 1 selection"]
        XCTAssertTrue(picker.waitForExistence(timeout: Timeout.medium))
        XCTAssertFalse(picker.isEnabled)
        XCTAssertTrue(app.staticTexts["Max Verstappen (Red Bull)"].exists)
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
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)

        app.tabBars.buttons[Tab.weekend].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Position 1 selection"]
                .waitForExistence(timeout: Timeout.medium)
        )
        XCTAssertFalse(app.buttons["Open Settings"].exists)
        openAllRacesAndManualPicks(in: app)
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: Timeout.medium))

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

        openSettings(in: app)
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

        XCTAssertTrue(app.staticTexts["Official Results"].waitForExistence(timeout: Timeout.medium))
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
        openSettings(in: app)

        let addPlayerField = app.textFields["Add Player"]
        XCTAssertTrue(addPlayerField.waitForExistence(timeout: Timeout.medium))
        addPlayerField.tap()
        addPlayerField.typeText(playerName)
        app.buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts[playerName].waitForExistence(timeout: Timeout.medium))
        dismissKeyboardIfVisible(in: app)
        navigateBackIfPossible(in: app)
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsButton = app.buttons["Open Settings"]
        if !settingsButton.waitForExistence(timeout: Timeout.short) {
            openAllRacesAndManualPicks(in: app)
        }

        XCTAssertTrue(settingsButton.waitForExistence(timeout: Timeout.medium))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Timeout.medium))
    }

    private func navigateBackIfPossible(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: Timeout.short) {
            backButton.tap()
        }
    }

    private func completeWeekendPick(in app: XCUIApplication, playerName: String) {
        if !app.staticTexts["Make your picks"].exists {
            XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
            app.tabBars.buttons[Tab.weekend].tap()
        }

        let playerPicker = app.buttons["\(playerName) picks"]
        guard playerPicker.waitForExistence(timeout: Timeout.medium) else {
            XCTFail("Missing player picker: \(playerName)")
            return
        }
        // Completing the previous player's taller podium card can leave this strip
        // above the viewport. Never silently keep editing the previous player.
        for _ in 0..<5 {
            if playerPicker.isHittable { break }
            app.swipeDown()
        }
        guard waitUntilHittable(playerPicker) else {
            XCTFail("Player picker was not hittable: \(playerName)")
            return
        }
        playerPicker.tap()
        XCTAssertTrue(
            app.staticTexts[playerName].waitForExistence(timeout: Timeout.medium),
            "The active player card must show the requested player"
        )

        selectPodiumPosition(3, option: "Charles Leclerc (Ferrari)", in: app)
        selectPodiumPosition(2, option: "Lando Norris (McLaren)", in: app)
        selectPodiumPosition(1, option: "Max Verstappen (Red Bull)", in: app)
    }

    private func openAllRacesAndManualPicks(in app: XCUIApplication) {
        let isPicksScreen = {
            app.buttons["Open Settings"].exists && app.buttons["BackButton"].exists
        }

        if app.staticTexts["Podium Picks"].exists || isPicksScreen() {
            return
        }

        XCTAssertTrue(app.tabBars.buttons[Tab.weekend].waitForExistence(timeout: Timeout.medium))
        app.tabBars.buttons[Tab.weekend].tap()
        if app.staticTexts["Podium Picks"].exists || isPicksScreen() {
            return
        }

        let allRacesLink = app.buttons["Manage race and champion picks"]
        scrollToElementIfNeeded(allRacesLink, in: app)
        XCTAssertTrue(allRacesLink.waitForExistence(timeout: Timeout.medium))
        allRacesLink.tap()

        XCTAssertTrue(app.staticTexts["Podium Picks"].waitForExistence(timeout: Timeout.medium))
    }

    private func selectChampionPick(option: String, in app: XCUIApplication) {
        var picker = app.descendants(matching: .any)["ChampionPickSelection"]
        if !picker.exists {
            picker = app.descendants(matching: .any)["Champion pick selection"]
        }
        scrollToElementIfNeeded(picker, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: Timeout.medium))
        picker.tap()

        let optionElement = app.buttons[option]
        XCTAssertTrue(optionElement.waitForExistence(timeout: Timeout.medium))
        optionElement.tap()

        XCTAssertTrue(app.staticTexts["World Champion"].waitForExistence(timeout: Timeout.medium))
    }

    private func selectPodiumPosition(_ position: Int, option: String, in app: XCUIApplication) {
        let picker = app.buttons["Position \(position) selection"]
        let pickerNavigationBar = app.navigationBars["Position \(position) selection"]

        guard openPodiumPicker(picker, navigationBar: pickerNavigationBar, in: app) else {
            XCTFail("Failed to open Position \(position) picker")
            return
        }

        // The covered podium field also exposes the selected driver's text.
        // Target the actionable picker row, not that underlying StaticText.
        let optionElement = app.buttons[option]
        guard optionElement.waitForExistence(timeout: Timeout.medium) else {
            XCTFail("Missing picker option: \(option)")
            return
        }
        guard waitUntilHittable(optionElement) else {
            XCTFail("Picker option was not hittable: \(option)")
            return
        }
        optionElement.tap()

        guard waitUntilGone(pickerNavigationBar) else {
            XCTFail("Position \(position) picker did not dismiss")
            return
        }
        recoverWeekendTabIfNeeded(in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: Timeout.medium))
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
            let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
            // Reveal the complete control instead of accepting a sliver above the tab bar.
            if element.exists && element.isHittable && element.frame.maxY < bottom {
                return
            }
            app.swipeUp()
        }
    }

    private func openPodiumPicker(
        _ picker: XCUIElement,
        navigationBar: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        recoverWeekendTabIfNeeded(in: app)

        for _ in 0..<3 {
            guard picker.waitForExistence(timeout: Timeout.medium) else {
                return false
            }
            scrollToElementIfNeeded(picker, in: app)
            guard picker.isHittable else {
                continue
            }

            picker.tap()
            if navigationBar.waitForExistence(timeout: Timeout.short) {
                return true
            }
            recoverWeekendTabIfNeeded(in: app)
        }
        return navigationBar.exists
    }

    private func recoverWeekendTabIfNeeded(in app: XCUIApplication) {
        guard !app.staticTexts["Make your picks"].exists else { return }
        let weekendTab = app.tabBars.buttons[Tab.weekend]
        guard weekendTab.waitForExistence(timeout: Timeout.short), !weekendTab.isSelected else {
            return
        }

        weekendTab.tap()
        XCTAssertTrue(app.staticTexts["Make your picks"].waitForExistence(timeout: Timeout.medium))
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = Timeout.medium) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = Timeout.medium) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

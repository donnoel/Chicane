import AppIntents
import XCTest

final class ChicaneUITests: XCTestCase {
    private enum Timeout {
        static let short: TimeInterval = 5
        static let medium: TimeInterval = 10
    }

    func testLaunchShowsCoreTabShell() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: Timeout.medium))
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Picks"].exists)
        XCTAssertTrue(app.tabBars.buttons["Results"].exists)
        XCTAssertTrue(app.tabBars.buttons["Scoreboard"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testAddPlayerInSettingsThenPicksIsPlayable() throws {
        let app = XCUIApplication()
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
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Picks"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons["Picks"].tap()
        XCTAssertTrue(app.staticTexts["Podium Picks"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons["Results"].tap()
        XCTAssertTrue(app.staticTexts["Race Results Podium"].waitForExistence(timeout: Timeout.medium))

        app.tabBars.buttons["Scoreboard"].tap()
        XCTAssertTrue(app.staticTexts["Season Scoreboard"].waitForExistence(timeout: Timeout.medium))
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

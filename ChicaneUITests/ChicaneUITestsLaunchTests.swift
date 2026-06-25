import XCTest

final class ChicaneUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }
}

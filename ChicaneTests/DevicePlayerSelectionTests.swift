import XCTest
@testable import Chicane

final class DevicePlayerSelectionTests: XCTestCase {
    func testEditablePlayersUsesStoredDevicePlayerID() {
        let son = Player(id: UUID(), name: "Son")
        let mom = Player(id: UUID(), name: "Mom")

        let editablePlayers = DevicePlayerSelection.editablePlayers(
            in: [son, mom],
            rawValue: DevicePlayerSelection.rawValue(for: mom)
        )

        XCTAssertEqual(editablePlayers, [mom])
    }

    func testEditablePlayersRequiresSelectionWhenMultiplePlayersExist() {
        let son = Player(id: UUID(), name: "Son")
        let mom = Player(id: UUID(), name: "Mom")

        XCTAssertTrue(DevicePlayerSelection.editablePlayers(in: [son, mom], rawValue: "").isEmpty)
        XCTAssertTrue(DevicePlayerSelection.editablePlayers(in: [son, mom], rawValue: UUID().uuidString).isEmpty)
    }

    func testSinglePlayerIsEditableWithoutStoredSelection() {
        let player = Player(id: UUID(), name: "Solo")

        XCTAssertEqual(DevicePlayerSelection.editablePlayers(in: [player], rawValue: ""), [player])
    }
}

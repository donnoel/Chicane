import XCTest
@testable import Chicane

final class AutosaveDecisionTests: XCTestCase {
    func testShouldAutosavePodiumPickMatrix() {
        struct Case {
            let name: String
            let draft: PodiumDraft
            let savedDraft: PodiumDraft
            let expected: Bool
        }

        let completeDraft = PodiumDraft(p1: "a", p2: "b", p3: "c")

        let cases: [Case] = [
            Case(
                name: "saves when complete and changed",
                draft: completeDraft,
                savedDraft: .empty,
                expected: true
            ),
            Case(
                name: "does not save when incomplete and changed",
                draft: PodiumDraft(p1: "a", p2: nil, p3: "c"),
                savedDraft: .empty,
                expected: false
            ),
            Case(
                name: "does not save when complete and unchanged",
                draft: completeDraft,
                savedDraft: completeDraft,
                expected: false
            ),
            Case(
                name: "does not save when incomplete and unchanged",
                draft: .empty,
                savedDraft: .empty,
                expected: false
            )
        ]

        for testCase in cases {
            XCTAssertEqual(
                AutosaveDecision.shouldAutosavePodiumPick(
                    draft: testCase.draft,
                    savedDraft: testCase.savedDraft
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testShouldAutosaveChampionPickMatrix() {
        struct Case {
            let name: String
            let selectedDriverID: String?
            let savedDriverID: String?
            let isLocked: Bool
            let expected: Bool
        }

        let cases: [Case] = [
            Case(
                name: "saves when selected changed and unlocked",
                selectedDriverID: "driver-a",
                savedDriverID: nil,
                isLocked: false,
                expected: true
            ),
            Case(
                name: "does not save when selection is nil",
                selectedDriverID: nil,
                savedDriverID: nil,
                isLocked: false,
                expected: false
            ),
            Case(
                name: "does not save when locked even if changed",
                selectedDriverID: "driver-b",
                savedDriverID: "driver-a",
                isLocked: true,
                expected: false
            ),
            Case(
                name: "does not save when unchanged and unlocked",
                selectedDriverID: "driver-c",
                savedDriverID: "driver-c",
                isLocked: false,
                expected: false
            )
        ]

        for testCase in cases {
            XCTAssertEqual(
                AutosaveDecision.shouldAutosaveChampionPick(
                    selectedDriverID: testCase.selectedDriverID,
                    savedDriverID: testCase.savedDriverID,
                    isLocked: testCase.isLocked
                ),
                testCase.expected,
                testCase.name
            )
        }
    }
}

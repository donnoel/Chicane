import Foundation

struct AutosaveDecision {
    static func shouldAutosavePodiumPick(draft: PodiumDraft, savedDraft: PodiumDraft) -> Bool {
        draft.isComplete && savedDraft != draft
    }

    static func shouldAutosaveChampionPick(
        selectedDriverID: String?,
        savedDriverID: String?,
        isLocked: Bool
    ) -> Bool {
        guard let selectedDriverID else {
            return false
        }
        guard !isLocked else {
            return false
        }
        return savedDriverID != selectedDriverID
    }
}

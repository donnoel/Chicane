import Foundation

struct AutosaveDecision {
    static func shouldAutosavePodiumPick(draft: PodiumDraft, savedDraft: PodiumDraft) -> Bool {
        (draft.isComplete || draft == .empty) && savedDraft != draft
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

struct DraftHydrationDecision {
    static func shouldAdoptSavedDraft<Draft: Equatable>(
        current: Draft,
        previousSaved: Draft,
        saved: Draft,
        empty: Draft
    ) -> Bool {
        current == empty || current == previousSaved || current == saved
    }

    static func shouldAdoptSavedSelection(
        current: String?,
        previousSaved: String?,
        saved: String?
    ) -> Bool {
        current == nil || current == previousSaved || current == saved
    }
}

import Foundation

struct PodiumDraft: Hashable, Sendable {
    var p1: String?
    var p2: String?
    var p3: String?

    static let empty = PodiumDraft(p1: nil, p2: nil, p3: nil)

    init(p1: String?, p2: String?, p3: String?) {
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }

    init(podium: Podium) {
        self.p1 = podium.p1
        self.p2 = podium.p2
        self.p3 = podium.p3
    }

    var selectedIDs: [String] {
        [p1, p2, p3].compactMap { $0 }
    }

    var hasDuplicates: Bool {
        Set(selectedIDs).count != selectedIDs.count
    }

    var isComplete: Bool {
        p1 != nil && p2 != nil && p3 != nil
    }

    func toPodium() -> Podium? {
        guard let p1, let p2, let p3 else {
            return nil
        }

        let podium = Podium(p1: p1, p2: p2, p3: p3)
        return podium.isUnique ? podium : nil
    }

    func isSelectionDisabled(driverID: String, for position: Int) -> Bool {
        switch position {
        case 1:
            return p2 == driverID || p3 == driverID
        case 2:
            return p1 == driverID || p3 == driverID
        case 3:
            return p1 == driverID || p2 == driverID
        default:
            return false
        }
    }
}

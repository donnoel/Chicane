import Foundation

enum DevicePlayerSelection {
    static let storageKey = "selectedDevicePlayerID"

    static func selectedPlayer(in players: [Player], rawValue: String) -> Player? {
        if players.count == 1 {
            return players.first
        }

        guard let selectedID = UUID(uuidString: rawValue) else {
            return nil
        }

        return players.first { $0.id == selectedID }
    }

    static func editablePlayers(in players: [Player], rawValue: String) -> [Player] {
        guard !players.isEmpty else {
            return []
        }

        guard let selectedID = UUID(uuidString: rawValue) else {
            return players
        }

        guard let selectedPlayer = players.first(where: { $0.id == selectedID }) else {
            return players
        }
        return [selectedPlayer]
    }

    static func rawValue(for player: Player) -> String {
        player.id.uuidString
    }
}

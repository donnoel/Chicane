import Foundation

enum RaceSeries: String, Codable, CaseIterable, Identifiable, Sendable {
    case formula1
    case motoGP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula1:
            return "Formula 1"
        case .motoGP:
            return "MotoGP"
        }
    }

    var shortTitle: String {
        switch self {
        case .formula1:
            return "F1"
        case .motoGP:
            return "MotoGP"
        }
    }

    var symbolName: String {
        switch self {
        case .formula1:
            return "car.fill"
        case .motoGP:
            return "figure.outdoor.cycle"
        }
    }
}

struct Driver: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let series: RaceSeries
    let name: String
    let team: String
    let number: String
}

struct RaceEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let series: RaceSeries
    let season: Int
    let round: Int
    let title: String
    let circuit: String
    let raceDate: Date

    var accessibilitySummary: String {
        let formatter = DateFormatter.dayMonthYear
        return "Round \(round), \(title), \(formatter.string(from: raceDate))"
    }
}

struct Player: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
}

struct Podium: Codable, Hashable, Sendable {
    var p1: String
    var p2: String
    var p3: String

    var orderedDriverIDs: [String] {
        [p1, p2, p3]
    }

    var isUnique: Bool {
        Set(orderedDriverIDs).count == 3
    }
}

struct RacePick: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let series: RaceSeries
    let eventID: String
    let playerID: UUID
    var podium: Podium
    var updatedAt: Date
}

struct RaceResult: Codable, Hashable, Sendable {
    let series: RaceSeries
    let eventID: String
    var podium: Podium
    var isLocked: Bool
    var updatedAt: Date

    var id: String {
        "\(series.rawValue)-\(eventID)"
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    var seasonBetText: String
    var spoilerGateEnabled: Bool
    var spoilersDontAskAgain: Bool
    var showSpoilersSection: Bool

    static let `default` = AppSettings(
        seasonBetText: "Winner chooses a chore: wash the other's windows.",
        spoilerGateEnabled: true,
        spoilersDontAskAgain: false,
        showSpoilersSection: false
    )
}

struct PersistedState: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var players: [Player]
    var picks: [RacePick]
    var results: [RaceResult]
    var settings: AppSettings

    static let `default` = PersistedState(
        schemaVersion: PersistedState.currentSchemaVersion,
        players: [
            Player(id: UUID(uuidString: "6B366E1E-2E99-4BEE-B294-D2AE5A26FB6A") ?? UUID(), name: "Mom"),
            Player(id: UUID(uuidString: "0FA60E6D-AB20-4D50-A4B9-B37CFA5F7F58") ?? UUID(), name: "Don")
        ],
        picks: [],
        results: [],
        settings: .default
    )

    func normalized() -> PersistedState {
        var normalized = self
        if normalized.schemaVersion != PersistedState.currentSchemaVersion {
            normalized.schemaVersion = PersistedState.currentSchemaVersion
        }
        normalized.players = normalized.players.map { player in
            var copy = player
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
        .filter { !$0.name.isEmpty }
        return normalized
    }
}

enum ScoreboardScope: String, CaseIterable, Identifiable, Sendable {
    case formula1
    case motoGP
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula1:
            return "F1"
        case .motoGP:
            return "MotoGP"
        case .combined:
            return "Combined"
        }
    }

    var series: RaceSeries? {
        switch self {
        case .formula1:
            return .formula1
        case .motoGP:
            return .motoGP
        case .combined:
            return nil
        }
    }
}

struct EventScoreRow: Identifiable, Hashable, Sendable {
    let id: String
    let event: RaceEvent
    let pointsByPlayerID: [UUID: Int]
    let series: RaceSeries
}

struct PlayerStanding: Identifiable, Hashable, Sendable {
    let id: UUID
    let player: Player
    let points: Int
}

extension DateFormatter {
    static let dayMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

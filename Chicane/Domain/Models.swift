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
        seasonBetText: "Winner determines.",
        spoilerGateEnabled: true,
        spoilersDontAskAgain: false,
        showSpoilersSection: false
    )
}

struct PersistedState: Codable, Sendable {
    // Increment this when the stored data format changes and add a migration
    // case in migratedToCurrentVersion() below.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var players: [Player]
    var picks: [RacePick]
    var results: [RaceResult]
    var settings: AppSettings

    /// Fresh-install default: no hardcoded players so Settings is the canonical
    /// way to add players, rather than shipping personal names in the binary.
    static let `default` = PersistedState(
        schemaVersion: PersistedState.currentSchemaVersion,
        players: [],
        picks: [],
        results: [],
        settings: .default
    )

    // MARK: - Normalisation & Migration

    /// Returns a copy of this state fully migrated to the current schema version
    /// with player names sanitised.
    func normalized() -> PersistedState {
        var state = migratedToCurrentVersion()

        state.players = state.players.map { player in
            var copy = player
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
        .filter { !$0.name.isEmpty }

        return state
    }

    /// Walks the schema version forward one step at a time so no migration is
    /// ever skipped, regardless of how old the on-disk data is.
    ///
    /// How to add a migration when bumping `currentSchemaVersion` to N:
    ///   1. Increment `currentSchemaVersion` to N.
    ///   2. Add `case N - 1:` here, apply the transform, set `state.schemaVersion = N`.
    private func migratedToCurrentVersion() -> PersistedState {
        var state = self

        while state.schemaVersion < PersistedState.currentSchemaVersion {
            switch state.schemaVersion {
            // Template for the next migration — uncomment and fill in:
            // case 1:
            //     // v1 → v2: describe the structural change here.
            //     state.schemaVersion = 2
            default:
                // Unrecognised old version: jump to current to avoid an infinite loop.
                state.schemaVersion = PersistedState.currentSchemaVersion
            }
        }

        return state
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

// MARK: - News

struct NewsArticle: Identifiable, Sendable, Hashable {
    let id: String          // article URL used as stable identity
    let series: RaceSeries
    let title: String
    let description: String
    let url: URL
    let publishedAt: Date
    let imageURL: URL?

    var formattedDate: String {
        DateFormatter.dayMonthYear.string(from: publishedAt)
    }
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

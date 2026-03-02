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
    var leagueCode: String?

    init(
        seasonBetText: String,
        spoilerGateEnabled: Bool,
        spoilersDontAskAgain: Bool,
        showSpoilersSection: Bool,
        leagueCode: String? = nil
    ) {
        self.seasonBetText = seasonBetText
        self.spoilerGateEnabled = spoilerGateEnabled
        self.spoilersDontAskAgain = spoilersDontAskAgain
        self.showSpoilersSection = showSpoilersSection
        self.leagueCode = leagueCode
    }

    static let `default` = AppSettings(
        seasonBetText: "Winner determines.",
        spoilerGateEnabled: true,
        spoilersDontAskAgain: false,
        showSpoilersSection: false,
        leagueCode: nil
    )
}

struct PersistedState: Codable, Hashable, Sendable {
    // Increment this when the stored data format changes and add a migration
    // case in migratedToCurrentVersion() below.
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var updatedAt: Date
    var playersUpdatedAt: Date
    var settingsUpdatedAt: Date
    var seasonResetAt: Date?
    var players: [Player]
    var picks: [RacePick]
    var results: [RaceResult]
    var settings: AppSettings

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case playersUpdatedAt
        case settingsUpdatedAt
        case seasonResetAt
        case players
        case picks
        case results
        case settings
    }

    init(
        schemaVersion: Int,
        updatedAt: Date,
        playersUpdatedAt: Date,
        settingsUpdatedAt: Date,
        seasonResetAt: Date?,
        players: [Player],
        picks: [RacePick],
        results: [RaceResult],
        settings: AppSettings
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.playersUpdatedAt = playersUpdatedAt
        self.settingsUpdatedAt = settingsUpdatedAt
        self.seasonResetAt = seasonResetAt
        self.players = players
        self.picks = picks
        self.results = results
        self.settings = settings
    }

    /// Fresh-install default: no hardcoded players so Settings is the canonical
    /// way to add players, rather than shipping personal names in the binary.
    static let `default` = PersistedState(
        schemaVersion: PersistedState.currentSchemaVersion,
        updatedAt: .distantPast,
        playersUpdatedAt: .distantPast,
        settingsUpdatedAt: .distantPast,
        seasonResetAt: nil,
        players: [],
        picks: [],
        results: [],
        settings: .default
    )

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        playersUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .playersUpdatedAt) ?? .distantPast
        settingsUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .settingsUpdatedAt) ?? .distantPast
        seasonResetAt = try container.decodeIfPresent(Date.self, forKey: .seasonResetAt)
        players = try container.decodeIfPresent([Player].self, forKey: .players) ?? []
        picks = try container.decodeIfPresent([RacePick].self, forKey: .picks) ?? []
        results = try container.decodeIfPresent([RaceResult].self, forKey: .results) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .default
    }

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
            case 1:
                state.updatedAt = state.picks.map(\.updatedAt)
                    .chain(state.results.map(\.updatedAt))
                    .max() ?? .distantPast
                state.schemaVersion = 2
            case 2:
                state.playersUpdatedAt = state.updatedAt
                state.settingsUpdatedAt = state.updatedAt
                state.seasonResetAt = nil
                state.schemaVersion = 3
            default:
                // Unrecognised old version: jump to current to avoid an infinite loop.
                state.schemaVersion = PersistedState.currentSchemaVersion
            }
        }

        return state
    }
}

private extension Sequence where Element == Date {
    func chain(_ other: [Date]) -> [Date] {
        Array(self) + other
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

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

    var artworkName: String {
        switch self {
        case .formula1:
            return "SeriesFormula1"
        case .motoGP:
            return "SeriesMotoGP"
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
    let trackTimeZoneID: String?

    init(
        id: String,
        series: RaceSeries,
        season: Int,
        round: Int,
        title: String,
        circuit: String,
        raceDate: Date,
        trackTimeZoneID: String? = nil
    ) {
        self.id = id
        self.series = series
        self.season = season
        self.round = round
        self.title = title
        self.circuit = circuit
        self.raceDate = raceDate
        self.trackTimeZoneID = trackTimeZoneID
    }

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

struct SeasonChampionPick: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let series: RaceSeries
    let playerID: UUID
    var driverID: String
    var updatedAt: Date
}

struct SeasonChampionResult: Identifiable, Codable, Hashable, Sendable {
    let series: RaceSeries
    var driverID: String
    var isLocked: Bool
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case series
        case driverID
        case isLocked
        case updatedAt
    }

    init(
        series: RaceSeries,
        driverID: String,
        isLocked: Bool = true,
        updatedAt: Date
    ) {
        self.series = series
        self.driverID = driverID
        self.isLocked = isLocked
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        series = try container.decode(RaceSeries.self, forKey: .series)
        driverID = try container.decode(String.self, forKey: .driverID)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? true
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var id: String {
        series.rawValue
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    static let leagueCodeLength = 6

    // Legacy MVP fields are retained for Codable compatibility with existing
    // local and CloudKit payloads until a schema migration intentionally removes them.
    var seasonBetText: String
    var playerBetTextByPlayerID: [UUID: String]
    var spoilerGateEnabled: Bool
    var spoilersDontAskAgain: Bool
    var showSpoilersSection: Bool
    var leagueCode: String?

    private enum CodingKeys: String, CodingKey {
        case seasonBetText
        case playerBetTextByPlayerID
        case spoilerGateEnabled
        case spoilersDontAskAgain
        case showSpoilersSection
        case leagueCode
    }

    init(
        seasonBetText: String,
        playerBetTextByPlayerID: [UUID: String] = [:],
        spoilerGateEnabled: Bool,
        spoilersDontAskAgain: Bool,
        showSpoilersSection: Bool,
        leagueCode: String? = nil
    ) {
        self.seasonBetText = seasonBetText
        self.playerBetTextByPlayerID = playerBetTextByPlayerID
        self.spoilerGateEnabled = spoilerGateEnabled
        self.spoilersDontAskAgain = spoilersDontAskAgain
        self.showSpoilersSection = showSpoilersSection
        self.leagueCode = leagueCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasonBetText = try container.decodeIfPresent(String.self, forKey: .seasonBetText) ?? AppSettings.default.seasonBetText
        playerBetTextByPlayerID = try container.decodeIfPresent([UUID: String].self, forKey: .playerBetTextByPlayerID) ?? [:]
        spoilerGateEnabled = try container.decodeIfPresent(Bool.self, forKey: .spoilerGateEnabled) ?? AppSettings.default.spoilerGateEnabled
        spoilersDontAskAgain = try container.decodeIfPresent(Bool.self, forKey: .spoilersDontAskAgain) ?? AppSettings.default.spoilersDontAskAgain
        showSpoilersSection = try container.decodeIfPresent(Bool.self, forKey: .showSpoilersSection) ?? AppSettings.default.showSpoilersSection
        leagueCode = try container.decodeIfPresent(String.self, forKey: .leagueCode)
    }

    static let `default` = AppSettings(
        seasonBetText: "Winner determines.",
        playerBetTextByPlayerID: [:],
        spoilerGateEnabled: true,
        spoilersDontAskAgain: false,
        showSpoilersSection: false,
        leagueCode: nil
    )

    var normalizedLeagueCode: String? {
        Self.normalizedLeagueCode(leagueCode)
    }

    static func normalizedLeagueCode(_ code: String?) -> String? {
        guard let code else {
            return nil
        }

        let allowed = code.uppercased().filter { $0.isLetter || $0.isNumber }
        let normalized = String(allowed.prefix(leagueCodeLength))
        guard normalized.count == leagueCodeLength else {
            return nil
        }
        return normalized
    }
}

struct PersistedState: Codable, Hashable, Sendable {
    // Increment this when the stored data format changes and add a migration
    // case in migratedToCurrentVersion() below.
    static let currentSchemaVersion = 4

    var schemaVersion: Int
    var updatedAt: Date
    var playersUpdatedAt: Date
    var settingsUpdatedAt: Date
    var seasonResetAt: Date?
    var players: [Player]
    var picks: [RacePick]
    var results: [RaceResult]
    var championPicks: [SeasonChampionPick]
    var championResults: [SeasonChampionResult]
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
        case championPicks
        case championResults
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
        championPicks: [SeasonChampionPick],
        championResults: [SeasonChampionResult],
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
        self.championPicks = championPicks
        self.championResults = championResults
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
        championPicks: [],
        championResults: [],
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
        championPicks = try container.decodeIfPresent([SeasonChampionPick].self, forKey: .championPicks) ?? []
        championResults = try container.decodeIfPresent([SeasonChampionResult].self, forKey: .championResults) ?? []
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

        let validPlayerIDs = Set(state.players.map(\.id))
        state.picks = state.picks.filter { validPlayerIDs.contains($0.playerID) }
        state.championPicks = state.championPicks.filter { validPlayerIDs.contains($0.playerID) }
        state.settings.playerBetTextByPlayerID = state.settings.playerBetTextByPlayerID.reduce(into: [:]) { partialResult, entry in
            guard validPlayerIDs.contains(entry.key) else { return }
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            partialResult[entry.key] = trimmed
        }
        state.settings.leagueCode = state.settings.normalizedLeagueCode

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
            case 3:
                state.championPicks = []
                state.championResults = []
                state.schemaVersion = 4
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

struct ChampionshipLeader: Identifiable, Hashable, Sendable {
    let series: RaceSeries
    let position: Int
    let name: String
    let team: String
    let points: Int

    var id: String {
        "\(series.rawValue)-\(position)-\(name)"
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

extension RaceEvent {
    var trackTimeZone: TimeZone? {
        RaceTrackTimeZoneResolver.timeZone(for: self)
    }

    func trackLocalTimeString(
        at referenceDate: Date = .now,
        relativeTo viewerTimeZone: TimeZone = .current
    ) -> String? {
        guard let trackTimeZone else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = trackTimeZone
        let localTime = formatter.string(from: referenceDate)
        let relativeDay = Self.relativeDayLabel(
            at: referenceDate,
            trackTimeZone: trackTimeZone,
            viewerTimeZone: viewerTimeZone
        )
        return "\(localTime) · \(relativeDay)"
    }

    private static func relativeDayLabel(
        at referenceDate: Date,
        trackTimeZone: TimeZone,
        viewerTimeZone: TimeZone
    ) -> String {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? viewerTimeZone

        let trackDateComponents = utcCalendar.dateComponents(in: trackTimeZone, from: referenceDate)
        let viewerDateComponents = utcCalendar.dateComponents(in: viewerTimeZone, from: referenceDate)

        guard
            let trackDay = utcCalendar.date(
                from: DateComponents(
                    year: trackDateComponents.year,
                    month: trackDateComponents.month,
                    day: trackDateComponents.day
                )
            ),
            let viewerDay = utcCalendar.date(
                from: DateComponents(
                    year: viewerDateComponents.year,
                    month: viewerDateComponents.month,
                    day: viewerDateComponents.day
                )
            )
        else {
            return "Today"
        }

        let dayDelta = utcCalendar.dateComponents([.day], from: viewerDay, to: trackDay).day ?? 0
        switch dayDelta {
        case ..<(-1):
            return "\(abs(dayDelta)) days ago"
        case -1:
            return "Yesterday"
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            return "In \(dayDelta) days"
        }
    }
}

private enum RaceTrackTimeZoneResolver {
    private static let slugToTimeZoneID: [String: String] = [
        "abu-dhabi": "Asia/Dubai",
        "americas": "America/Chicago",
        "aragon": "Europe/Madrid",
        "australia": "Australia/Melbourne",
        "austria": "Europe/Vienna",
        "azerbaijan": "Asia/Baku",
        "bahrain": "Asia/Bahrain",
        "belgium": "Europe/Brussels",
        "brazil": "America/Sao_Paulo",
        "canada": "America/Toronto",
        "catalan": "Europe/Madrid",
        "china": "Asia/Shanghai",
        "czech": "Europe/Prague",
        "france": "Europe/Paris",
        "germany": "Europe/Berlin",
        "great-britain": "Europe/London",
        "hungary": "Europe/Budapest",
        "italy": "Europe/Rome",
        "japan": "Asia/Tokyo",
        "las-vegas": "America/Los_Angeles",
        "mexico-city": "America/Mexico_City",
        "monaco": "Europe/Monaco",
        "netherlands": "Europe/Amsterdam",
        "qatar": "Asia/Qatar",
        "san-marino": "Europe/Rome",
        "sao-paulo": "America/Sao_Paulo",
        "saudi-arabia": "Asia/Riyadh",
        "singapore": "Asia/Singapore",
        "spain": "Europe/Madrid",
        "thailand": "Asia/Bangkok",
        "united-states": "America/Chicago",
        "usa": "America/Chicago",
        "valencia": "Europe/Madrid"
    ]

    private static let circuitToTimeZoneID: [String: String] = [
        "albert-park": "Australia/Melbourne",
        "assen": "Europe/Amsterdam",
        "austin": "America/Chicago",
        "baku": "Asia/Baku",
        "balaton-park": "Europe/Budapest",
        "brno": "Europe/Prague",
        "buriram": "Asia/Bangkok",
        "circuit-de-barcelona-catalunya": "Europe/Madrid",
        "goiania": "America/Sao_Paulo",
        "hungaroring": "Europe/Budapest",
        "interlagos": "America/Sao_Paulo",
        "jeddah": "Asia/Riyadh",
        "jerez": "Europe/Madrid",
        "las-vegas-strip": "America/Los_Angeles",
        "le-mans": "Europe/Paris",
        "lusail": "Asia/Qatar",
        "madrid": "Europe/Madrid",
        "marina-bay": "Asia/Singapore",
        "mexico-city": "America/Mexico_City",
        "miami": "America/New_York",
        "misano": "Europe/Rome",
        "monte-carlo": "Europe/Monaco",
        "montreal": "America/Toronto",
        "monza": "Europe/Rome",
        "motorland-aragon": "Europe/Madrid",
        "mugello": "Europe/Rome",
        "ricardo-tormo": "Europe/Madrid",
        "sachsenring": "Europe/Berlin",
        "sakhir": "Asia/Bahrain",
        "shanghai": "Asia/Shanghai",
        "silverstone": "Europe/London",
        "spa-francorchamps": "Europe/Brussels",
        "spielberg": "Europe/Vienna",
        "suzuka": "Asia/Tokyo",
        "yas-marina": "Asia/Dubai",
        "zandvoort": "Europe/Amsterdam"
    ]

    static func timeZone(for event: RaceEvent) -> TimeZone? {
        if
            let storedID = canonicalTimeZoneID(from: event.trackTimeZoneID),
            let stored = TimeZone(identifier: storedID)
        {
            return stored
        }

        let slug = eventSlug(from: event.id)
        if
            let mappedID = slugToTimeZoneID[slug],
            let mapped = TimeZone(identifier: mappedID)
        {
            return mapped
        }

        let circuitKey = normalizedLookupKey(from: event.circuit)
        if
            let mappedID = circuitToTimeZoneID[circuitKey],
            let mapped = TimeZone(identifier: mappedID)
        {
            return mapped
        }

        return nil
    }

    private static func canonicalTimeZoneID(from rawID: String?) -> String? {
        guard let rawID = rawID?.trimmingCharacters(in: .whitespacesAndNewlines), !rawID.isEmpty else {
            return nil
        }

        if TimeZone(identifier: rawID) != nil {
            return rawID
        }

        let canonical = rawID
            .split(separator: "/")
            .map { pathPart in
                pathPart
                    .split(separator: "_")
                    .map { segment in
                        let lower = segment.lowercased()
                        guard let first = lower.first else {
                            return lower
                        }
                        return first.uppercased() + lower.dropFirst()
                    }
                    .joined(separator: "_")
            }
            .joined(separator: "/")

        return TimeZone(identifier: canonical) == nil ? nil : canonical
    }

    private static func eventSlug(from eventID: String) -> String {
        let parts = eventID.lowercased().split(separator: "-")
        guard let seriesPrefix = parts.first else {
            return normalizedLookupKey(from: eventID)
        }

        guard seriesPrefix == "f1" || seriesPrefix == "mgp" else {
            return normalizedLookupKey(from: eventID)
        }

        if parts.count >= 3, Int(parts[1]) != nil {
            return parts.dropFirst(2).joined(separator: "-")
        }
        if parts.count >= 2 {
            return parts.dropFirst().joined(separator: "-")
        }
        return normalizedLookupKey(from: eventID)
    }

    private static func normalizedLookupKey(from value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

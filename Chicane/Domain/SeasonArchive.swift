import Foundation

/// A self-contained record of one series for one group and year. Active-season
/// resets and player edits never remove or rewrite these historical identities.
struct ArchivedSeason: Codable, Hashable, Identifiable, Sendable {
    let season: Int
    let series: RaceSeries
    let leagueCode: String?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    let scoringVersion: Int
    var players: [Player]
    var bets: [UUID: String]
    var events: [RaceEvent]
    var participants: [Driver]
    var picks: [RacePick]
    var results: [RaceResult]
    var championPicks: [SeasonChampionPick]
    var championResult: SeasonChampionResult?
    var eventStatuses: [RaceEventStatus]? = nil

    func isCanceled(_ event: RaceEvent) -> Bool {
        eventStatuses?.first(where: { $0.matches(event) })?.isCanceled == true
    }

    var groupYearID: String { "\(leagueCode ?? "device")|\(season)" }
    var id: String { "\(groupYearID)|\(series.rawValue)" }
    var isComplete: Bool {
        !players.isEmpty && !events.isEmpty &&
            events.allSatisfy { event in isCanceled(event) || results.contains { $0.eventID == event.id && $0.isLocked } } &&
            championResult?.isLocked == true
    }
    var pendingDescription: String {
        let missing = events.filter { event in !isCanceled(event) && !results.contains { $0.eventID == event.id && $0.isLocked } }.count
        var reasons: [String] = []
        if missing > 0 { reasons.append("\(missing) race result\(missing == 1 ? "" : "s")") }
        if championResult?.isLocked != true { reasons.append("confirmed season champion") }
        if players.isEmpty { reasons.append("players") }
        return reasons.isEmpty ? "Final" : "Awaiting " + reasons.joined(separator: " and ")
    }

    /// Union by identity keeps old years, independently completed series and
    /// results absent from a stale device. Official corrections use timestamps.
    static func merged(_ archives: [ArchivedSeason]) -> [ArchivedSeason] {
        var output: [String: ArchivedSeason] = [:]
        for incoming in archives {
            guard let old = output[incoming.id] else {
                var first = incoming
                first.results = newest(first.results, key: { $0.eventID }, date: { $0.updatedAt })
                first.picks = newest(first.picks, key: { "\($0.eventID)|\($0.playerID)" }, date: { $0.updatedAt })
                first.championPicks = newest(first.championPicks, key: { $0.playerID.uuidString }, date: { $0.updatedAt })
                output[incoming.id] = first
                continue
            }
            var merged = old.createdAt <= incoming.createdAt ? old : incoming
            for event in (old.events + incoming.events) where !merged.events.contains(where: { $0.round == event.round }) {
                merged.events.append(event)
            }
            for participant in (old.participants + incoming.participants) where !merged.participants.contains(where: { ParticipantNameMatcher.normalizedName($0.name) == ParticipantNameMatcher.normalizedName(participant.name) }) {
                merged.participants.append(participant)
            }
            let left = canonicalized(old, using: merged)
            let right = canonicalized(incoming, using: merged)
            merged.results = newest(left.results + right.results, key: { $0.eventID }, date: { $0.updatedAt })
            merged.picks = newest(left.picks + right.picks, key: { "\($0.eventID)|\($0.playerID)" }, date: { $0.updatedAt })
            merged.championPicks = newest(left.championPicks + right.championPicks, key: { $0.playerID.uuidString }, date: { $0.updatedAt })
            merged.championResult = [left.championResult, right.championResult].compactMap { $0 }.max { $0.updatedAt < $1.updatedAt }
            merged.eventStatuses = RaceEventStatus.merged((left.eventStatuses ?? []) + (right.eventStatuses ?? []))
            merged.updatedAt = max(old.updatedAt, incoming.updatedAt)
            merged.createdAt = min(old.createdAt, incoming.createdAt)
            merged.revision = max(old.revision, incoming.revision)
            output[incoming.id] = merged
        }
        return output.values.sorted { $0.id < $1.id }
    }

    private static func canonicalized(_ snapshot: ArchivedSeason, using base: ArchivedSeason) -> ArchivedSeason {
        var copy = snapshot
        func eventID(_ raw: String) -> String {
            guard let source = snapshot.events.first(where: { $0.id == raw }) else { return raw }
            return base.events.first { $0.round == source.round }?.id ?? raw
        }
        func participantID(_ raw: String) -> String {
            guard let source = snapshot.participants.first(where: { $0.id == raw }) else { return raw }
            return base.participants.first { ParticipantNameMatcher.normalizedName($0.name) == ParticipantNameMatcher.normalizedName(source.name) }?.id ?? raw
        }
        func podium(_ value: Podium) -> Podium {
            Podium(p1: participantID(value.p1), p2: participantID(value.p2), p3: participantID(value.p3))
        }
        copy.results = snapshot.results.map {
            RaceResult(series: $0.series, eventID: eventID($0.eventID), podium: podium($0.podium), isLocked: $0.isLocked, updatedAt: $0.updatedAt, isOfficial: $0.isOfficial)
        }
        copy.picks = snapshot.picks.map {
            RacePick(id: $0.id, series: $0.series, eventID: eventID($0.eventID), playerID: $0.playerID, podium: podium($0.podium), isLocked: $0.isLocked, updatedAt: $0.updatedAt, draft: $0.draft.map { PodiumDraft(p1: $0.p1.map(participantID), p2: $0.p2.map(participantID), p3: $0.p3.map(participantID)) })
        }
        copy.championPicks = snapshot.championPicks.map {
            var value = $0
            value.driverID = participantID(value.driverID)
            return value
        }
        if var champion = snapshot.championResult {
            champion.driverID = participantID(champion.driverID)
            copy.championResult = champion
        }
        return copy
    }

    private static func newest<T>(_ values: [T], key: (T) -> String, date: (T) -> Date) -> [T] {
        var output: [String: T] = [:]
        for value in values {
            let id = key(value)
            if let old = output[id], date(old) > date(value) { continue }
            output[id] = value
        }
        return output.keys.sorted().compactMap { output[$0] }
    }
}

struct SeasonPlayerSummary: Identifiable, Sendable {
    let id: UUID
    let name: String
    let racePoints: Int
    let championBonus: Int
    let perfectPodiums: Int
    let picksMade: Int
    let bet: String?
    var total: Int { racePoints + championBonus }
}

struct SeasonHighlight: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
}

struct SeasonReview: Identifiable, Sendable {
    let id: String
    let season: Int
    let leagueCode: String?
    let seriesArchives: [ArchivedSeason]
    let standings: [SeasonPlayerSummary]
    let standingsByScope: [ScoreboardScope: [SeasonPlayerSummary]]
    let highlights: [SeasonHighlight]
    let recap: String
    var isComplete: Bool {
        RaceSeries.allCases.allSatisfy { series in seriesArchives.contains { $0.series == series && $0.isComplete } }
    }
    var winners: [SeasonPlayerSummary] {
        guard let first = standings.first else { return [] }
        return standings.filter { $0.total == first.total }
    }
}

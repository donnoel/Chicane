import Foundation

struct ScoringService: Sendable {
    func points(for pick: Podium, result: Podium) -> Int {
        var score = 0
        if pick.p1 == result.p1 { score += 1 }
        if pick.p2 == result.p2 { score += 1 }
        if pick.p3 == result.p3 { score += 1 }
        return score
    }

    func pointsByPlayer(
        players: [Player],
        picks: [RacePick],
        result: RaceResult,
        series: RaceSeries,
        eventID: String,
        events: [RaceEvent] = [],
        participants: [Driver] = []
    ) -> [UUID: Int] {
        let resolver = StoredIdentityResolver(
            series: series,
            events: events,
            participants: participants
        )
        var output: [UUID: Int] = [:]
        for player in players {
            let pick = resolver.matchingPick(
                for: player.id,
                targetEventID: eventID,
                in: picks
            )
            guard let pick else {
                output[player.id] = 0
                continue
            }
            output[player.id] = resolver.points(for: pick.podium, result: result.podium)
        }
        return output
    }
}

struct ScoreboardCalculator: Sendable {
    private let scoringService = ScoringService()

    func standings(
        players: [Player],
        picks: [RacePick],
        results: [RaceResult],
        events: [RaceEvent],
        scope: ScoreboardScope,
        driversBySeries: [RaceSeries: [Driver]] = [:]
    ) -> [PlayerStanding] {
        let filteredResults = results.filter { result in
            guard let series = scope.series else { return true }
            return result.series == series
        }

        let totalByPlayerID = players.reduce(into: [UUID: Int]()) { totals, player in
            totals[player.id] = 0
        }

        let totals = filteredResults.reduce(into: totalByPlayerID) { totals, result in
            let points = scoringService.pointsByPlayer(
                players: players,
                picks: picks,
                result: result,
                series: result.series,
                eventID: result.eventID,
                events: events.filter { $0.series == result.series },
                participants: driversBySeries[result.series] ?? []
            )
            for (playerID, earned) in points {
                totals[playerID, default: 0] += earned
            }
        }

        return players.map { player in
            PlayerStanding(id: player.id, player: player, points: totals[player.id, default: 0])
        }
        .sorted { lhs, rhs in
            if lhs.points == rhs.points {
                return lhs.player.name.localizedCaseInsensitiveCompare(rhs.player.name) == .orderedAscending
            }
            return lhs.points > rhs.points
        }
    }

    func eventHistory(
        players: [Player],
        picks: [RacePick],
        results: [RaceResult],
        events: [RaceEvent],
        scope: ScoreboardScope,
        driversBySeries: [RaceSeries: [Driver]] = [:]
    ) -> [EventScoreRow] {
        return results.compactMap { result in
            let resolver = StoredIdentityResolver(
                series: result.series,
                events: events.filter { $0.series == result.series },
                participants: driversBySeries[result.series] ?? []
            )
            guard let event = resolver.resolvedEvent(for: result.eventID) else { return nil }

            if let scopedSeries = scope.series, result.series != scopedSeries {
                return nil
            }

            let points = scoringService.pointsByPlayer(
                players: players,
                picks: picks,
                result: result,
                series: result.series,
                eventID: result.eventID,
                events: events.filter { $0.series == result.series },
                participants: driversBySeries[result.series] ?? []
            )

            return EventScoreRow(
                id: result.id,
                event: event,
                pointsByPlayerID: points,
                series: result.series
            )
        }
        .sorted { $0.event.raceDate > $1.event.raceDate }
    }

    func leaderText(for standings: [PlayerStanding]) -> String {
        guard let first = standings.first else {
            return "No scores yet"
        }

        let topPlayers = standings.filter { $0.points == first.points }
        if topPlayers.count > 1 {
            return "It's a tie at \(first.points)"
        }
        return "\(first.player.name) leads with \(first.points)"
    }
}

struct StoredIdentityResolver: Sendable {
    let series: RaceSeries
    let events: [RaceEvent]
    let participants: [Driver]

    private let aliasToParticipantKey: [String: String]

    init(
        series: RaceSeries,
        events: [RaceEvent],
        participants: [Driver]
    ) {
        self.series = series
        self.events = events.filter { $0.series == series }
        self.participants = participants.filter { $0.series == series }
        self.aliasToParticipantKey = StoredIdentityResolver.makeParticipantAliasMap(
            participants: self.participants
        )
    }

    func matchingPick(
        for playerID: UUID,
        targetEventID: String,
        in picks: [RacePick]
    ) -> RacePick? {
        let candidates = picks.filter {
            $0.series == series && $0.playerID == playerID
        }

        if let exact = newestPick(in: candidates, matching: { $0.eventID == targetEventID }) {
            return exact
        }

        return newestPick(in: candidates, matching: { eventIDsMatch($0.eventID, targetEventID) })
    }

    func matchingResult(
        targetEventID: String,
        in results: [RaceResult]
    ) -> RaceResult? {
        let candidates = results.filter { $0.series == series }

        if let exact = newestResult(in: candidates, matching: { $0.eventID == targetEventID }) {
            return exact
        }

        return newestResult(in: candidates, matching: { eventIDsMatch($0.eventID, targetEventID) })
    }

    func resolvedEvent(for eventID: String) -> RaceEvent? {
        if let exact = events.first(where: { $0.id == eventID }) {
            return exact
        }

        let fallback = legacyEventKey(for: eventID)
        guard !fallback.tokens.isEmpty else {
            return nil
        }

        let scored = events.compactMap { event -> (event: RaceEvent, score: Int)? in
            if let season = fallback.season, event.season != season {
                return nil
            }

            let eventTokens = normalizedTokens(
                "\(event.title) \(event.circuit) \(event.id)"
            )
            let matchCount = fallback.tokens.reduce(into: 0) { total, token in
                if eventTokens.contains(where: { tokensMatch($0, token) }) {
                    total += 1
                }
            }

            guard matchCount == fallback.tokens.count else {
                return nil
            }

            let score = fallback.tokens.joined().count
            return (event, score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.event.round < rhs.event.round
            }
            return lhs.score > rhs.score
        }

        guard let best = scored.first else {
            return nil
        }

        if scored.count > 1, scored[1].score == best.score {
            return nil
        }

        return best.event
    }

    func eventIDsMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs {
            return true
        }

        guard
            let leftEvent = resolvedEvent(for: lhs),
            let rightEvent = resolvedEvent(for: rhs)
        else {
            return false
        }

        return leftEvent.id == rightEvent.id
    }

    func points(for pick: Podium, result: Podium) -> Int {
        var score = 0
        if participantKeysMatch(pick.p1, result.p1) { score += 1 }
        if participantKeysMatch(pick.p2, result.p2) { score += 1 }
        if participantKeysMatch(pick.p3, result.p3) { score += 1 }
        return score
    }

    private func newestPick(
        in picks: [RacePick],
        matching predicate: (RacePick) -> Bool
    ) -> RacePick? {
        picks
            .filter(predicate)
            .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
    }

    private func newestResult(
        in results: [RaceResult],
        matching predicate: (RaceResult) -> Bool
    ) -> RaceResult? {
        results
            .filter(predicate)
            .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
    }

    private func participantKeysMatch(_ lhs: String, _ rhs: String) -> Bool {
        canonicalParticipantKey(for: lhs) == canonicalParticipantKey(for: rhs)
    }

    private func canonicalParticipantKey(for rawID: String) -> String {
        if let participant = participants.first(where: { $0.id == rawID }) {
            return canonicalNameKey(for: participant.name)
        }

        let rawAlias = normalizedIdentifierFragment(rawID)
        if let aliasMatch = aliasToParticipantKey[rawAlias] {
            return aliasMatch
        }

        return rawAlias
    }

    private func legacyEventKey(for eventID: String) -> (season: Int?, tokens: [String]) {
        var tokens = normalizedTokens(eventID)
        let prefix = seriesIDPrefix
        if tokens.first == prefix {
            tokens.removeFirst()
        }

        var season: Int?
        if let first = tokens.first, first.count == 4, let parsed = Int(first) {
            season = parsed
            tokens.removeFirst()
        }

        return (season, tokens)
    }

    private var seriesIDPrefix: String {
        switch series {
        case .formula1:
            return "f1"
        case .motoGP:
            return "mgp"
        }
    }

    private static func makeParticipantAliasMap(participants: [Driver]) -> [String: String] {
        let aliasCounts = participants.reduce(into: [String: Int]()) { counts, participant in
            for alias in participantAliases(for: participant) {
                counts[alias, default: 0] += 1
            }
        }

        return participants.reduce(into: [String: String]()) { aliases, participant in
            let canonicalKey = canonicalNameKey(for: participant.name)
            for alias in participantAliases(for: participant) where aliasCounts[alias] == 1 {
                aliases[alias] = canonicalKey
            }
        }
    }

    private static func participantAliases(for participant: Driver) -> Set<String> {
        let tokens = normalizedTokens(participant.name)
        guard !tokens.isEmpty else {
            return []
        }

        var aliases = Set<String>()
        aliases.insert(tokens.joined())

        if let surname = tokens.last {
            aliases.insert(surname)

            if let givenName = tokens.first, let initial = givenName.first {
                aliases.insert("\(initial)\(surname)")
            }
        }

        return aliases
    }
}

private func canonicalNameKey(for value: String) -> String {
    normalizedTokens(value).joined()
}

private func normalizedIdentifierFragment(_ value: String) -> String {
    normalizedTokens(value).joined()
}

private func normalizedTokens(_ value: String) -> [String] {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .replacingOccurrences(
            of: #"[^a-zA-Z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        .split(separator: " ")
        .map { String($0).lowercased() }
}

private func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
    if lhs == rhs {
        return true
    }

    guard lhs.count >= 4, rhs.count >= 4 else {
        return false
    }

    return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
}

import Foundation

struct ScoringService: Sendable {
    func points(for pick: Podium, result: Podium) -> Int {
        var score = 0
        if pick.p1 == result.p1 { score += 1 }
        if pick.p2 == result.p2 { score += 1 }
        if pick.p3 == result.p3 { score += 1 }
        return score
    }

    func seasonChampionBonusByPlayer(
        players: [Player],
        championPicks: [SeasonChampionPick],
        championResult: SeasonChampionResult?,
        series: RaceSeries,
        participants: [Driver] = []
    ) -> [UUID: Int] {
        guard let championResult else {
            return players.reduce(into: [UUID: Int]()) { output, player in
                output[player.id] = 0
            }
        }

        let resolver = StoredIdentityResolver(
            series: series,
            events: [],
            participants: participants
        )

        return players.reduce(into: [UUID: Int]()) { output, player in
            let matchingPick = championPicks
                .filter { $0.series == series && $0.playerID == player.id }
                .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }

            guard let matchingPick else {
                output[player.id] = 0
                return
            }

            output[player.id] = resolver.participantIDsMatch(
                matchingPick.driverID,
                championResult.driverID
            ) ? 5 : 0
        }
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
    private struct PickLookupKey: Hashable, Sendable {
        let series: RaceSeries
        let playerID: UUID
    }

    private struct ChampionPickLookupKey: Hashable, Sendable {
        let series: RaceSeries
        let playerID: UUID
    }

    private struct CalculationInputs: Sendable {
        let players: [Player]
        let eventsBySeries: [RaceSeries: [RaceEvent]]
        let resolversBySeries: [RaceSeries: StoredIdentityResolver]
        let picksBySeriesAndPlayer: [PickLookupKey: [RacePick]]
        let championPickBySeriesAndPlayer: [ChampionPickLookupKey: SeasonChampionPick]
        let championResultBySeries: [RaceSeries: SeasonChampionResult]

        init(
            players: [Player],
            picks: [RacePick],
            championPicks: [SeasonChampionPick],
            championResults: [SeasonChampionResult],
            events: [RaceEvent],
            driversBySeries: [RaceSeries: [Driver]]
        ) {
            self.players = players
            let groupedEvents = Dictionary(grouping: events, by: \.series)
            self.eventsBySeries = groupedEvents

            var resolvers: [RaceSeries: StoredIdentityResolver] = [:]
            for series in RaceSeries.allCases {
                resolvers[series] = StoredIdentityResolver(
                    series: series,
                    events: groupedEvents[series] ?? [],
                    participants: driversBySeries[series] ?? []
                )
            }
            self.resolversBySeries = resolvers

            var pickLookup: [PickLookupKey: [RacePick]] = [:]
            for pick in picks {
                let key = PickLookupKey(series: pick.series, playerID: pick.playerID)
                pickLookup[key, default: []].append(pick)
            }
            self.picksBySeriesAndPlayer = pickLookup.mapValues {
                $0.sorted { $0.updatedAt > $1.updatedAt }
            }

            self.championPickBySeriesAndPlayer = championPicks.reduce(into: [:]) { output, pick in
                let key = ChampionPickLookupKey(series: pick.series, playerID: pick.playerID)
                guard let existing = output[key], existing.updatedAt >= pick.updatedAt else {
                    output[key] = pick
                    return
                }
            }

            self.championResultBySeries = championResults.reduce(into: [:]) { output, result in
                guard let existing = output[result.series], existing.updatedAt >= result.updatedAt else {
                    output[result.series] = result
                    return
                }
            }
        }

        func resolver(for series: RaceSeries) -> StoredIdentityResolver {
            resolversBySeries[series] ?? StoredIdentityResolver(
                series: series,
                events: eventsBySeries[series] ?? [],
                participants: []
            )
        }

        func pointsByPlayer(for result: RaceResult) -> [UUID: Int] {
            let resolver = resolver(for: result.series)
            var output: [UUID: Int] = [:]
            for player in players {
                guard let pick = matchingPick(
                    for: player.id,
                    series: result.series,
                    eventID: result.eventID,
                    resolver: resolver
                ) else {
                    output[player.id] = 0
                    continue
                }
                output[player.id] = resolver.points(for: pick.podium, result: result.podium)
            }
            return output
        }

        func championBonusByPlayer(for series: RaceSeries) -> [UUID: Int] {
            guard let championResult = championResultBySeries[series] else {
                return players.reduce(into: [UUID: Int]()) { output, player in
                    output[player.id] = 0
                }
            }

            let resolver = resolver(for: series)
            return players.reduce(into: [UUID: Int]()) { output, player in
                let key = ChampionPickLookupKey(series: series, playerID: player.id)
                guard let championPick = championPickBySeriesAndPlayer[key] else {
                    output[player.id] = 0
                    return
                }
                output[player.id] = resolver.participantIDsMatch(
                    championPick.driverID,
                    championResult.driverID
                ) ? 5 : 0
            }
        }

        private func matchingPick(
            for playerID: UUID,
            series: RaceSeries,
            eventID: String,
            resolver: StoredIdentityResolver
        ) -> RacePick? {
            let candidates = picksBySeriesAndPlayer[PickLookupKey(series: series, playerID: playerID)] ?? []

            if let exact = candidates.first(where: { $0.eventID == eventID }) {
                return exact
            }

            return candidates.first { resolver.eventIDsMatch($0.eventID, eventID) }
        }
    }

    func standings(
        players: [Player],
        picks: [RacePick],
        results: [RaceResult],
        championPicks: [SeasonChampionPick] = [],
        championResults: [SeasonChampionResult] = [],
        events: [RaceEvent],
        scope: ScoreboardScope,
        driversBySeries: [RaceSeries: [Driver]] = [:]
    ) -> [PlayerStanding] {
        let inputs = CalculationInputs(
            players: players,
            picks: picks,
            championPicks: championPicks,
            championResults: championResults,
            events: events,
            driversBySeries: driversBySeries
        )
        let filteredResults = results.filter { result in
            guard let series = scope.series else { return true }
            return result.series == series
        }

        let totalByPlayerID = players.reduce(into: [UUID: Int]()) { totals, player in
            totals[player.id] = 0
        }

        var totals = filteredResults.reduce(into: totalByPlayerID) { totals, result in
            let points = inputs.pointsByPlayer(for: result)
            for (playerID, earned) in points {
                totals[playerID, default: 0] += earned
            }
        }

        let bonusSeries = scope.series.map { [$0] } ?? RaceSeries.allCases
        for series in bonusSeries {
            let bonus = inputs.championBonusByPlayer(for: series)
            for (playerID, earned) in bonus {
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
        let inputs = CalculationInputs(
            players: players,
            picks: picks,
            championPicks: [],
            championResults: [],
            events: events,
            driversBySeries: driversBySeries
        )
        return results.compactMap { result in
            if let scopedSeries = scope.series, result.series != scopedSeries {
                return nil
            }

            let resolver = inputs.resolver(for: result.series)
            guard let event = resolver.resolvedEvent(for: result.eventID) else { return nil }
            let points = inputs.pointsByPlayer(for: result)

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
    private let aliasToParticipantID: [String: String]

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
        self.aliasToParticipantID = StoredIdentityResolver.makeParticipantIDAliasMap(
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

    func participantIDsMatch(_ lhs: String, _ rhs: String) -> Bool {
        participantKeysMatch(lhs, rhs)
    }

    func resolvedParticipantID(for rawID: String) -> String? {
        if let participant = participants.first(where: { $0.id == rawID }) {
            return participant.id
        }

        for alias in legacyParticipantAliases(for: rawID) {
            if let participantID = aliasToParticipantID[alias] {
                return participantID
            }
        }

        return nil
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

        let aliases = legacyParticipantAliases(for: rawID)
        for alias in aliases {
            if let aliasMatch = aliasToParticipantKey[alias] {
                return aliasMatch
            }
        }

        return aliases.first ?? normalizedIdentifierFragment(rawID)
    }

    private func legacyParticipantAliases(for rawID: String) -> [String] {
        let tokens = normalizedTokens(rawID)
        guard !tokens.isEmpty else {
            return []
        }

        var aliases: [String] = []
        aliases.append(tokens.joined())

        var strippedTokens = tokens
        if strippedTokens.first == seriesIDPrefix {
            strippedTokens.removeFirst()
        }

        if !strippedTokens.isEmpty {
            aliases.append(contentsOf: Self.joinedTokenSuffixes(strippedTokens))
        }

        var uniqueAliases: [String] = []
        for alias in aliases where !uniqueAliases.contains(alias) {
            uniqueAliases.append(alias)
        }
        return uniqueAliases
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

    private static func makeParticipantIDAliasMap(participants: [Driver]) -> [String: String] {
        let aliasCounts = participants.reduce(into: [String: Int]()) { counts, participant in
            for alias in participantAliases(for: participant) {
                counts[alias, default: 0] += 1
            }
        }

        return participants.reduce(into: [String: String]()) { aliases, participant in
            for alias in participantAliases(for: participant) where aliasCounts[alias] == 1 {
                aliases[alias] = participant.id
            }
        }
    }

    private static func participantAliases(for participant: Driver) -> Set<String> {
        let tokens = normalizedTokens(participant.name)
        guard !tokens.isEmpty else {
            return []
        }

        var aliases = Set<String>()
        aliases.formUnion(joinedTokenSuffixes(tokens))

        if let surname = tokens.last {
            aliases.insert(surname)

            if let givenName = tokens.first, let initial = givenName.first {
                aliases.insert("\(initial)\(surname)")
            }
        }

        return aliases
    }

    private static func joinedTokenSuffixes(_ tokens: [String]) -> [String] {
        guard !tokens.isEmpty else { return [] }

        return tokens.indices.map { index in
            tokens[index...].joined()
        }
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

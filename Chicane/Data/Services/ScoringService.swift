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
        eventID: String
    ) -> [UUID: Int] {
        var output: [UUID: Int] = [:]
        for player in players {
            let pick = picks.first {
                $0.series == series && $0.eventID == eventID && $0.playerID == player.id
            }
            guard let pick else {
                output[player.id] = 0
                continue
            }
            output[player.id] = points(for: pick.podium, result: result.podium)
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
        scope: ScoreboardScope
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
                eventID: result.eventID
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
        scope: ScoreboardScope
    ) -> [EventScoreRow] {
        let eventByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })

        return results.compactMap { result in
            guard let event = eventByID[result.eventID] else { return nil }

            if let scopedSeries = scope.series, result.series != scopedSeries {
                return nil
            }

            let points = scoringService.pointsByPlayer(
                players: players,
                picks: picks,
                result: result,
                series: result.series,
                eventID: result.eventID
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

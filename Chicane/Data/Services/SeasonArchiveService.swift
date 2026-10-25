import Foundation

struct SeasonArchiveService: Sendable {
    func updatedArchives(state: PersistedState, events: [RaceEvent], participants: [Driver], at date: Date = .now) -> [ArchivedSeason] {
        var archives = state.seasonArchives
        for series in RaceSeries.allCases {
            guard let year = events.filter({ $0.series == series }).map(\.season).max() else { continue }
            let calendar = events.filter { $0.series == series && $0.season == year }.sorted { $0.raceDate < $1.raceDate }
            let currentDrivers = participants.filter { $0.series == series }
            let resolver = StoredIdentityResolver(series: series, events: calendar, participants: currentDrivers)
            let statuses = state.eventStatuses.filter { $0.series == series && $0.season == year }
            guard let finale = calendar.last else { continue }
            let finaleResult = resolver.matchingResult(targetEventID: finale.id, in: state.results)
            let finaleCanceled = statuses.first(where: { $0.matches(finale) })?.isCanceled == true
            let group = state.settings.normalizedLeagueCode
            let hasArchive = archives.contains { $0.season == year && $0.series == series && $0.leagueCode == group }
            guard hasArchive || finaleCanceled || (finaleResult?.isOfficial == true && finaleResult?.isLocked == true) else { continue }

            let old = archives.first { $0.season == year && $0.series == series && $0.leagueCode == group }
            let players = old?.players ?? state.players
            let frozenEvents = old?.events ?? calendar
            var drivers = old?.participants ?? currentDrivers
            for driver in currentDrivers where !drivers.contains(where: { ParticipantNameMatcher.normalizedName($0.name) == ParticipantNameMatcher.normalizedName(driver.name) }) {
                drivers.append(driver)
            }
            let identity = StoredIdentityResolver(series: series, events: calendar + frozenEvents, participants: currentDrivers)
            func participantID(_ raw: String) -> String {
                let resolved = identity.resolvedParticipantID(for: raw) ?? raw
                guard let current = currentDrivers.first(where: { $0.id == resolved }) else { return raw }
                return drivers.first { ParticipantNameMatcher.normalizedName($0.name) == ParticipantNameMatcher.normalizedName(current.name) }?.id ?? resolved
            }
            func podium(_ value: Podium) -> Podium {
                Podium(p1: participantID(value.p1), p2: participantID(value.p2), p3: participantID(value.p3))
            }
            let results = frozenEvents.compactMap { event -> RaceResult? in
                guard let result = identity.matchingResult(targetEventID: event.id, in: state.results), result.isLocked else { return nil }
                return RaceResult(series: series, eventID: event.id, podium: podium(result.podium), isLocked: true, updatedAt: result.updatedAt, isOfficial: result.isOfficial)
            }
            let picks = frozenEvents.flatMap { event in
                players.compactMap { player -> RacePick? in
                    guard let pick = identity.matchingPick(for: player.id, targetEventID: event.id, in: state.picks) else { return nil }
                    return RacePick(id: pick.id, series: series, eventID: event.id, playerID: player.id, podium: podium(pick.podium), isLocked: pick.isLocked, updatedAt: pick.updatedAt, draft: pick.draft.map { PodiumDraft(p1: $0.p1.map(participantID), p2: $0.p2.map(participantID), p3: $0.p3.map(participantID)) })
                }
            }
            let championPicks = state.championPicks.filter {
                $0.series == series && belongsToSeason($0.season, updatedAt: $0.updatedAt, year: year)
            }.filter { pick in players.contains { $0.id == pick.playerID } }.map { pick in
                var copy = pick
                copy.driverID = participantID(copy.driverID)
                return copy
            }
            var champion = state.championResults.filter {
                $0.series == series && $0.isLocked && belongsToSeason($0.season, updatedAt: $0.updatedAt, year: year)
            }.max { $0.updatedAt < $1.updatedAt }
            if var value = champion {
                value.driverID = participantID(value.driverID)
                champion = value
            }
            var candidate = ArchivedSeason(
                season: year, series: series, leagueCode: group,
                createdAt: old?.createdAt ?? date, updatedAt: old?.updatedAt ?? date,
                revision: old?.revision ?? 1, scoringVersion: 1,
                players: players, bets: old?.bets ?? state.settings.playerBetTextByPlayerID,
                events: frozenEvents, participants: drivers, picks: picks, results: results,
                championPicks: championPicks, championResult: champion, eventStatuses: statuses
            )
            candidate = ArchivedSeason.merged([old, candidate].compactMap { $0 }).first ?? candidate
            if let old, candidate != old {
                candidate.updatedAt = date
                candidate.revision = old.revision + 1
            }
            archives.removeAll { $0.id == candidate.id }
            archives.append(candidate)
        }
        return ArchivedSeason.merged(archives)
    }

    private func belongsToSeason(_ explicitSeason: Int?, updatedAt: Date, year: Int) -> Bool {
        if let explicitSeason { return explicitSeason == year }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.year, from: updatedAt) == year
    }

    func reviews(from archives: [ArchivedSeason]) -> [SeasonReview] {
        Dictionary(grouping: archives, by: \.groupYearID).map { id, snapshots in
            let sorted = snapshots.sorted { $0.series.rawValue < $1.series.rawValue }
            let rows = standings(for: sorted)
            let complete = RaceSeries.allCases.allSatisfy { series in sorted.contains { $0.series == series && $0.isComplete } }
            let season = sorted[0].season
            let recap: String
            if complete, let first = rows.first {
                let winners = rows.filter { $0.total == first.total }
                if winners.count > 1 {
                    recap = "\(winners.map(\.name).joined(separator: " and ")) shared the \(season) title on \(first.total) points."
                } else if let runnerUp = rows.dropFirst().first {
                    let margin = first.total - runnerUp.total
                    recap = "\(first.name) won your \(season) season with \(first.total) points, finishing \(margin) point\(margin == 1 ? "" : "s") ahead of \(runnerUp.name)."
                } else {
                    recap = "\(first.name) completed the \(season) season with \(first.total) points."
                }
            } else {
                recap = "Your \(season) season is being preserved. The combined winner will be confirmed when both series and their champion bonuses are complete."
            }
            let scopes = Dictionary(uniqueKeysWithValues: ScoreboardScope.allCases.map { scope in
                (scope, scope == .combined ? rows : standings(for: sorted.filter { $0.series == scope.series }))
            })
            return SeasonReview(id: id, season: season, leagueCode: sorted[0].leagueCode, seriesArchives: sorted, standings: rows, standingsByScope: scopes, highlights: highlights(for: sorted, rows: rows), recap: recap)
        }.sorted {
            if $0.season != $1.season { return $0.season > $1.season }
            return $0.id < $1.id
        }
    }

    // Version-one archive scoring stays explicit so a future scoring-rule change
    // cannot retrospectively change the record book.
    func standings(for snapshots: [ArchivedSeason]) -> [SeasonPlayerSummary] {
        var players: [UUID: Player] = [:]
        for snapshot in snapshots {
            for player in snapshot.players where players[player.id] == nil { players[player.id] = player }
        }
        return players.values.map { player in
            var racePoints = 0
            var bonus = 0
            var perfect = 0
            var picksMade = 0
            for snapshot in snapshots {
                for event in snapshot.events where !snapshot.isCanceled(event) {
                    guard let pick = snapshot.picks.first(where: { $0.isComplete && $0.eventID == event.id && $0.playerID == player.id }) else { continue }
                    picksMade += 1
                    guard let result = snapshot.results.first(where: { $0.eventID == event.id }) else { continue }
                    let points = points(pick.podium, result.podium)
                    racePoints += points
                    if points == 3 { perfect += 1 }
                }
                if let champion = snapshot.championResult,
                   snapshot.championPicks.contains(where: { $0.playerID == player.id && $0.driverID == champion.driverID }) {
                    bonus += 5
                }
            }
            return SeasonPlayerSummary(id: player.id, name: player.name, racePoints: racePoints, championBonus: bonus, perfectPodiums: perfect, picksMade: picksMade, bet: snapshots.compactMap { $0.bets[player.id] }.first)
        }.sorted {
            if $0.total != $1.total { return $0.total > $1.total }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func points(_ pick: Podium, _ result: Podium) -> Int {
        (pick.p1 == result.p1 ? 1 : 0) + (pick.p2 == result.p2 ? 1 : 0) + (pick.p3 == result.p3 ? 1 : 0)
    }

    private func highlights(for snapshots: [ArchivedSeason], rows: [SeasonPlayerSummary]) -> [SeasonHighlight] {
        var highlights: [SeasonHighlight] = []
        if let most = rows.map(\.perfectPodiums).max(), most > 0 {
            let names = rows.filter { $0.perfectPodiums == most }.map(\.name).joined(separator: " and ")
            highlights.append(SeasonHighlight(id: "perfect", title: "Perfect podiums", detail: "\(names): \(most) exact 3-for-3 prediction\(most == 1 ? "" : "s")."))
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var weekends: [Date: [UUID: Int]] = [:]
        for snapshot in snapshots {
            for event in snapshot.events where !snapshot.isCanceled(event) {
                guard let result = snapshot.results.first(where: { $0.eventID == event.id }),
                      let week = calendar.dateInterval(of: .weekOfYear, for: event.raceDate)?.start else { continue }
                for pick in snapshot.picks where pick.isComplete && pick.eventID == event.id {
                    weekends[week, default: [:]][pick.playerID, default: 0] += points(pick.podium, result.podium)
                }
            }
        }
        if let best = weekends.values.flatMap({ $0.values }).max(), best > 0 {
            let ids = Set(weekends.values.flatMap { values in values.filter { $0.value == best }.map(\.key) })
            let names = rows.filter { ids.contains($0.id) }.map(\.name).joined(separator: " and ")
            highlights.append(SeasonHighlight(id: "weekend", title: "Best scoring weekend", detail: "\(names) earned \(best) race point\(best == 1 ? "" : "s") in a single race week."))
        }
        let correctChampions = rows.filter { $0.championBonus > 0 }
        if !correctChampions.isEmpty {
            highlights.append(SeasonHighlight(id: "champions", title: "Called the champion", detail: correctChampions.map { "\($0.name) (+\($0.championBonus))" }.joined(separator: " · ")))
        }
        if snapshots.count == RaceSeries.allCases.count && snapshots.allSatisfy(\.isComplete), let first = rows.first, rows.count > 1 {
            let winners = rows.filter { $0.total == first.total }
            highlights.append(SeasonHighlight(id: "finish", title: winners.count > 1 ? "A shared title" : "The winning margin", detail: winners.count > 1 ? "The season finished level on \(first.total) points." : "\(first.name) finished \(first.total - rows[1].total) points clear."))
            if let finale = snapshots.flatMap({ snapshot in snapshot.events.filter { !snapshot.isCanceled($0) } }).max(by: { $0.raceDate < $1.raceDate }) {
                var before = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, 0) })
                for snapshot in snapshots {
                    for event in snapshot.events where event.raceDate < finale.raceDate && !snapshot.isCanceled(event) {
                        guard let result = snapshot.results.first(where: { $0.eventID == event.id }) else { continue }
                        for pick in snapshot.picks where pick.isComplete && pick.eventID == event.id {
                            before[pick.playerID, default: 0] += points(pick.podium, result.podium)
                        }
                    }
                }
                if let priorTop = before.values.max(), priorTop > 0, let finalTop = rows.map(\.racePoints).max() {
                    let previousLeaders = Set(before.filter { $0.value == priorTop }.map(\.key))
                    let finalLeaders = Set(rows.filter { $0.racePoints == finalTop }.map(\.id))
                    if previousLeaders != finalLeaders {
                        highlights.append(SeasonHighlight(id: "finale", title: "Final-race shake-up", detail: "The race-points lead changed at \(finale.title), before season champion bonuses."))
                    }
                }
            }
        }
        return highlights
    }
}

import Foundation

struct OnlineCalendarRepository: CalendarRepository {
    private let client: RemoteDataClient
    private let calendar: Calendar

    init(
        client: RemoteDataClient = RemoteDataClient(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.client = client
        self.calendar = calendar
    }

    func events(for series: RaceSeries) async throws -> [RaceEvent] {
        switch series {
        case .formula1:
            return try await formula1Events()
        case .motoGP:
            return try await motoGPEvents()
        }
    }

    func allEvents() async throws -> [RaceEvent] {
        async let f1 = events(for: .formula1)
        async let motoGP = events(for: .motoGP)
        return try await (f1 + motoGP).sorted { $0.raceDate < $1.raceDate }
    }

    private func formula1Events() async throws -> [RaceEvent] {
        let currentYear = calendar.component(.year, from: Date())
        let candidateYears = [currentYear, currentYear + 1, currentYear - 1]
        var lastError: Error?

        for season in candidateYears {
            guard let url = URL(string: "https://www.formula1.com/en/racing/\(season)") else {
                continue
            }

            do {
                let html = try await client.fetchString(from: url)
                let parsed = F1OfficialHTMLParser.parseEvents(from: html, expectedSeason: season)
                if !parsed.isEmpty {
                    return await enrichUpcomingFormula1Event(in: parsed, season: season)
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw RemoteDataError.emptyPayload(source: "Formula 1 calendar")
    }

    private func enrichUpcomingFormula1Event(in events: [RaceEvent], season: Int) async -> [RaceEvent] {
        let now = Date()
        guard let eventIndex = events.firstIndex(where: { calendar.isDateInToday($0.raceDate) || $0.raceDate >= now }) else {
            return events
        }

        let event = events[eventIndex]
        guard
            let slug = formula1Slug(for: event),
            let url = URL(string: "https://www.formula1.com/en/racing/\(season)/\(slug)")
        else {
            return events
        }

        guard
            let html = try? await client.fetchString(from: url),
            let details = F1OfficialHTMLParser.parseRaceSessionDetails(fromRacePageHTML: html)
        else {
            return events
        }

        var updatedEvents = events
        updatedEvents[eventIndex] = RaceEvent(
            id: event.id,
            series: event.series,
            season: event.season,
            round: event.round,
            title: event.title,
            circuit: event.circuit,
            raceDate: details.startDate,
            trackTimeZoneID: details.timeZoneID ?? event.trackTimeZoneID
        )
        return updatedEvents
    }

    private func formula1Slug(for event: RaceEvent) -> String? {
        let prefix = "f1-\(event.season)-"
        guard event.id.hasPrefix(prefix) else {
            return nil
        }

        let slug = String(event.id.dropFirst(prefix.count))
        return slug.isEmpty ? nil : slug
    }

    private func motoGPEvents() async throws -> [RaceEvent] {
        let seasonYear = try await resolvedMotoGPSeasonYear()
        let currentSeasonEvents = try await fetchMotoGPEvents(for: seasonYear)
        if !currentSeasonEvents.isEmpty {
            return await enrichUpcomingMotoGPEvent(in: currentSeasonEvents, seasonYear: seasonYear)
        }

        let fallbackYear = calendar.component(.year, from: Date())
        guard fallbackYear != seasonYear else {
            throw RemoteDataError.emptyPayload(source: "MotoGP calendar")
        }

        let fallbackEvents = try await fetchMotoGPEvents(for: fallbackYear)
        guard !fallbackEvents.isEmpty else {
            throw RemoteDataError.emptyPayload(source: "MotoGP calendar")
        }
        return await enrichUpcomingMotoGPEvent(in: fallbackEvents, seasonYear: fallbackYear)
    }

    private func resolvedMotoGPSeasonYear() async throws -> Int {
        guard let url = URL(string: "https://api.pulselive.motogp.com/motogp/v1/results/seasons") else {
            return calendar.component(.year, from: Date())
        }
        let seasons = try await client.fetchJSON([MotoGPSeasonPayload].self, from: url)
        if let currentSeason = seasons.first(where: { $0.current }) {
            return currentSeason.year
        }
        return seasons.map(\.year).max() ?? calendar.component(.year, from: Date())
    }

    private func fetchMotoGPEvents(for seasonYear: Int) async throws -> [RaceEvent] {
        var components = URLComponents(string: "https://api.pulselive.motogp.com/motogp/v1/events")
        components?.queryItems = [URLQueryItem(name: "seasonYear", value: String(seasonYear))]
        guard let url = components?.url else {
            throw RemoteDataError.emptyPayload(source: "MotoGP calendar")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try await client.fetchJSON([MotoGPEventPayload].self, from: url, decoder: decoder)

        let mapped = payload.compactMap { event -> RaceEvent? in
            guard event.kind.uppercased() == "GP" else {
                return nil
            }

            let round = event.sequence ?? 0
            guard round > 0 else {
                return nil
            }

            let season = event.season?.year ?? seasonYear
            let cleanTitle = event.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .localizedCapitalized
            let title = cleanTitle.isEmpty ? "MotoGP Round \(round)" : cleanTitle
            let circuit = event.circuit?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "MotoGP Circuit"

            return RaceEvent(
                id: "mgp-\(event.id)",
                series: .motoGP,
                season: season,
                round: round,
                title: title,
                circuit: circuit,
                raceDate: event.dateEnd,
                trackTimeZoneID: event.timeZone
            )
        }
        .sorted {
            if $0.round == $1.round {
                return $0.raceDate < $1.raceDate
            }
            return $0.round < $1.round
        }

        return mapped
    }

    private func enrichUpcomingMotoGPEvent(in events: [RaceEvent], seasonYear: Int) async -> [RaceEvent] {
        let now = Date()
        guard let eventIndex = events.firstIndex(where: { calendar.isDateInToday($0.raceDate) || $0.raceDate >= now }) else {
            return events
        }

        let event = events[eventIndex]
        guard
            let toadEventUUID = motoGPEventUUID(from: event.id),
            let seasonUUID = try? await resolvedMotoGPResultsSeasonUUID(for: seasonYear),
            let resultsEvent = try? await resolvedMotoGPResultsEvent(
                seasonUUID: seasonUUID,
                toadEventUUID: toadEventUUID,
                fallbackRound: event.round
            ),
            let categoryUUID = try? await resolvedMotoGPCategoryUUID(eventUUID: resultsEvent.id),
            let sessions = try? await fetchMotoGPResultSessions(
                eventUUID: resultsEvent.id,
                categoryUUID: categoryUUID
            ),
            let raceStartDate = preferredMotoGPRaceSessionDate(from: sessions)
        else {
            return events
        }

        var updated = events
        updated[eventIndex] = RaceEvent(
            id: event.id,
            series: event.series,
            season: event.season,
            round: event.round,
            title: event.title,
            circuit: event.circuit,
            raceDate: raceStartDate,
            trackTimeZoneID: event.trackTimeZoneID
        )
        return updated
    }

    func preferredMotoGPRaceSessionDate(from sessions: [MotoGPRaceSessionPayload]) -> Date? {
        let raceSessions = sessions.filter { $0.type.uppercased() == "RAC" }
        let activeRaceSessions = raceSessions.filter { session in
            let status = session.status?.uppercased() ?? ""
            return status != "CANCELLED"
        }
        return activeRaceSessions.compactMap(\.date).min()
    }

    private func resolvedMotoGPResultsSeasonUUID(for seasonYear: Int) async throws -> String? {
        guard let url = URL(string: "https://api.pulselive.motogp.com/motogp/v1/results/seasons") else {
            return nil
        }

        let seasons = try await client.fetchJSON([MotoGPResultsSeasonPayload].self, from: url)
        if let matched = seasons.first(where: { $0.year == seasonYear }) {
            return matched.id
        }
        if let current = seasons.first(where: { $0.current }) {
            return current.id
        }
        return seasons.max(by: { $0.year < $1.year })?.id
    }

    private func resolvedMotoGPResultsEvent(
        seasonUUID: String,
        toadEventUUID: String,
        fallbackRound: Int
    ) async throws -> CalendarMotoGPResultsEventPayload? {
        guard var components = URLComponents(string: "https://api.pulselive.motogp.com/motogp/v1/results/events") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "seasonUuid", value: seasonUUID)]
        guard let url = components.url else {
            return nil
        }

        let events = try await client.fetchJSON([CalendarMotoGPResultsEventPayload].self, from: url)
        let toadMatches = events.filter { $0.toadAPIUUID == toadEventUUID }
        if let bestToadMatch = preferredMotoGPResultsEvent(from: toadMatches) {
            return bestToadMatch
        }

        let roundMatches = events.filter { $0.sequence == fallbackRound }
        return preferredMotoGPResultsEvent(from: roundMatches)
    }

    private func preferredMotoGPResultsEvent(
        from candidates: [CalendarMotoGPResultsEventPayload]
    ) -> CalendarMotoGPResultsEventPayload? {
        candidates.first(where: { !$0.test }) ?? candidates.first
    }

    private func resolvedMotoGPCategoryUUID(eventUUID: String) async throws -> String? {
        guard var components = URLComponents(string: "https://api.pulselive.motogp.com/motogp/v1/results/categories") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "eventUuid", value: eventUUID)]
        guard let url = components.url else {
            return nil
        }

        let categories = try await client.fetchJSON([MotoGPResultCategoryPayload].self, from: url)
        return categories.first(where: { $0.legacyID == 3 })?.id
            ?? categories.first(where: { $0.name.localizedCaseInsensitiveContains("MotoGP") })?.id
    }

    private func fetchMotoGPResultSessions(
        eventUUID: String,
        categoryUUID: String
    ) async throws -> [MotoGPRaceSessionPayload] {
        guard var components = URLComponents(string: "https://api.pulselive.motogp.com/motogp/v1/results/sessions") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "eventUuid", value: eventUUID),
            URLQueryItem(name: "categoryUuid", value: categoryUUID)
        ]
        guard let url = components.url else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try await client.fetchJSON([MotoGPRaceSessionPayload].self, from: url, decoder: decoder)
    }

    private func motoGPEventUUID(from eventID: String) -> String? {
        guard eventID.hasPrefix("mgp-") else {
            return nil
        }
        let raw = String(eventID.dropFirst(4))
        return raw.isEmpty ? nil : raw
    }
}

private struct MotoGPSeasonPayload: Decodable {
    let year: Int
    let current: Bool
}

private struct MotoGPResultsSeasonPayload: Decodable {
    let id: String
    let year: Int
    let current: Bool
}

private struct CalendarMotoGPResultsEventPayload: Decodable {
    let id: String
    let toadAPIUUID: String?
    let test: Bool
    let sequence: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case toadAPIUUID = "toad_api_uuid"
        case test
        case sequence
    }
}

private struct MotoGPResultCategoryPayload: Decodable {
    let id: String
    let name: String
    let legacyID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case legacyID = "legacy_id"
    }
}

struct MotoGPRaceSessionPayload: Decodable {
    let type: String
    let date: Date?
    let status: String?
}

private struct MotoGPEventPayload: Decodable {
    let id: String
    let season: MotoGPEventSeasonPayload?
    let sequence: Int?
    let name: String
    let kind: String
    let circuit: MotoGPEventCircuitPayload?
    let dateEnd: Date
    let timeZone: String?

    enum CodingKeys: String, CodingKey {
        case id
        case season
        case sequence
        case name
        case kind
        case circuit
        case dateEnd = "date_end"
        case timeZone = "time_zone"
    }
}

private struct MotoGPEventSeasonPayload: Decodable {
    let year: Int
}

private struct MotoGPEventCircuitPayload: Decodable {
    let name: String?
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

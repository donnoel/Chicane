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
            trackTimeZoneID: details.timeZoneID
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
            return currentSeasonEvents
        }

        let fallbackYear = calendar.component(.year, from: Date())
        guard fallbackYear != seasonYear else {
            throw RemoteDataError.emptyPayload(source: "MotoGP calendar")
        }

        let fallbackEvents = try await fetchMotoGPEvents(for: fallbackYear)
        guard !fallbackEvents.isEmpty else {
            throw RemoteDataError.emptyPayload(source: "MotoGP calendar")
        }
        return fallbackEvents
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
}

private struct MotoGPSeasonPayload: Decodable {
    let year: Int
    let current: Bool
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

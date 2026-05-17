import Foundation

struct OnlineResultRepository: ResultRepository {
    private let client: RemoteDataClient

    init(client: RemoteDataClient = RemoteDataClient()) {
        self.client = client
    }

    func podium(for event: RaceEvent) async throws -> [String] {
        switch event.series {
        case .formula1:
            return try await formula1Podium(for: event)
        case .motoGP:
            return try await motoGPPodium(for: event)
        }
    }

    static func parseF1PodiumNames(from html: String) -> [String] {
        guard
            let tableStart = html.range(of: "<table", options: .caseInsensitive),
            let tableEnd = html.range(
                of: "</table>",
                options: .caseInsensitive,
                range: tableStart.lowerBound..<html.endIndex
            )
        else {
            return []
        }

        let tableHTML = String(html[tableStart.lowerBound..<tableEnd.upperBound])
        let rowRange = NSRange(tableHTML.startIndex..<tableHTML.endIndex, in: tableHTML)
        let rowMatches = f1TableRowRegex.matches(in: tableHTML, range: rowRange)

        var namesByPosition: [Int: String] = [:]
        for rowMatch in rowMatches {
            guard let rowHTML = tableHTML.substring(for: rowMatch.range(at: 1)) else {
                continue
            }

            let rowCellRange = NSRange(rowHTML.startIndex..<rowHTML.endIndex, in: rowHTML)
            let cellMatches = f1TableCellRegex.matches(in: rowHTML, range: rowCellRange)
            guard cellMatches.count >= 3 else {
                continue
            }

            guard
                let positionRaw = rowHTML.substring(for: cellMatches[0].range(at: 1)),
                let position = Int(stripHTML(positionRaw).trimmingCharacters(in: .whitespacesAndNewlines)),
                (1...3).contains(position)
            else {
                continue
            }

            guard let driverCell = rowHTML.substring(for: cellMatches[2].range(at: 1)) else {
                continue
            }
            let name = parseF1DriverName(from: driverCell)
            guard !name.isEmpty else {
                continue
            }
            namesByPosition[position] = name
        }

        return [1, 2, 3].compactMap { namesByPosition[$0] }
    }

    private func formula1Podium(for event: RaceEvent) async throws -> [String] {
        guard let seasonResultsURL = URL(string: "https://www.formula1.com/en/results/\(event.season)/races") else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }

        let indexHTML = try await client.fetchString(from: seasonResultsURL)
        let raceLinks = parseF1ResultLinks(from: indexHTML)
        guard let raceLink = selectF1ResultLink(for: event, links: raceLinks) else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }

        guard let raceResultURL = URL(string: "https://www.formula1.com\(raceLink.path)") else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }

        let resultHTML = try await client.fetchString(from: raceResultURL)
        let names = Self.parseF1PodiumNames(from: resultHTML)
        guard names.count == 3 else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }
        return names
    }

    private func motoGPPodium(for event: RaceEvent) async throws -> [String] {
        guard let seasonUUID = try await resolvedMotoGPSeasonUUID(for: event.season) else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }

        guard
            let eventsURL = URL(string: "https://api.pulselive.motogp.com/motogp/v1/results/events"),
            let categoriesURL = URL(string: "https://api.pulselive.motogp.com/motogp/v1/results/categories"),
            let sessionsURL = URL(string: "https://api.pulselive.motogp.com/motogp/v1/results/sessions"),
            let classificationsURL = URL(string: "https://api.pulselive.motogp.com/motogp/v2/results/classifications")
        else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }

        let resultsEvents: [MotoGPResultsEventPayload] = try await fetchMotoGPJSON(
            from: eventsURL,
            queryItems: [
                URLQueryItem(name: "seasonUuid", value: seasonUUID),
                URLQueryItem(name: "isFinished", value: "true")
            ]
        )

        guard let resultsEvent = selectMotoGPResultsEvent(for: event, events: resultsEvents) else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }

        let categories: [MotoGPResultCategoryPayload] = try await fetchMotoGPJSON(
            from: categoriesURL,
            queryItems: [URLQueryItem(name: "eventUuid", value: resultsEvent.id)]
        )
        guard let motoGPCategory = categories.first(where: { $0.legacyID == 3 }) ??
            categories.first(where: { $0.name.localizedCaseInsensitiveContains("MotoGP") })
        else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }

        let sessionDecoder = JSONDecoder()
        sessionDecoder.dateDecodingStrategy = .iso8601
        let sessions: [MotoGPResultSessionPayload] = try await fetchMotoGPJSON(
            from: sessionsURL,
            queryItems: [
                URLQueryItem(name: "eventUuid", value: resultsEvent.id),
                URLQueryItem(name: "categoryUuid", value: motoGPCategory.id)
            ],
            decoder: sessionDecoder
        )
        guard let raceSession = selectedMotoGPRaceSession(from: sessions) else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }

        let classification: MotoGPResultClassificationPayload = try await fetchMotoGPJSON(
            from: classificationsURL,
            queryItems: [
                URLQueryItem(name: "session", value: raceSession.id),
                URLQueryItem(name: "test", value: resultsEvent.test ? "true" : "false")
            ]
        )

        let names = classification.classification
            .filter { ($0.position ?? Int.max) <= 3 }
            .sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }
            .compactMap { row -> String? in
                let direct = row.rider?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let direct, !direct.isEmpty {
                    return direct
                }
                let fallback = "\(row.rider?.name ?? "") \(row.rider?.surname ?? "")"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return fallback.isEmpty ? nil : fallback
            }

        guard names.count == 3 else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }
        return names
    }

    private func resolvedMotoGPSeasonUUID(for seasonYear: Int) async throws -> String? {
        guard let seasonsURL = URL(string: "https://api.pulselive.motogp.com/motogp/v1/results/seasons") else {
            return nil
        }
        let seasons = try await client.fetchJSON([MotoGPSeasonPayload].self, from: seasonsURL)
        if let matched = seasons.first(where: { $0.year == seasonYear }) {
            return matched.id
        }
        if let current = seasons.first(where: { $0.current }) {
            return current.id
        }
        return seasons.max(by: { $0.year < $1.year })?.id
    }

    private func fetchMotoGPJSON<T: Decodable>(
        from baseURL: URL,
        queryItems: [URLQueryItem],
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw OfficialResultRepositoryError.resultsUnavailable
        }
        return try await client.fetchJSON(T.self, from: url, decoder: decoder)
    }

    func selectedMotoGPRaceSession(from sessions: [MotoGPResultSessionPayload]) -> MotoGPResultSessionPayload? {
        let raceSessions = sessions.filter { session in
            guard session.type.uppercased() == "RAC" else {
                return false
            }
            let status = session.status?.uppercased() ?? ""
            return status != "CANCELLED"
        }

        return raceSessions.max { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (lhsDate?, rhsDate?):
                return lhsDate < rhsDate
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            case (nil, nil):
                return lhs.id < rhs.id
            }
        }
    }

    func selectMotoGPResultsEvent(
        for event: RaceEvent,
        events: [MotoGPResultsEventPayload]
    ) -> MotoGPResultsEventPayload? {
        let toadEventUUID = event.id.replacingOccurrences(of: "mgp-", with: "")

        let toadMatches = events.filter { $0.toadAPIUUID == toadEventUUID }
        if let bestMatch = preferredMotoGPResultsEvent(in: toadMatches) {
            return bestMatch
        }

        let roundMatches = events.filter { $0.legacyEventID == event.round }
        if let bestMatch = preferredMotoGPResultsEvent(in: roundMatches) {
            return bestMatch
        }

        let sequenceMatches = events.filter { $0.sequence == event.round }
        return preferredMotoGPResultsEvent(in: sequenceMatches)
    }

    private func preferredMotoGPResultsEvent(
        in candidates: [MotoGPResultsEventPayload]
    ) -> MotoGPResultsEventPayload? {
        candidates.first(where: { !$0.test }) ?? candidates.first
    }

    func parseF1ResultLinks(from html: String) -> [F1ResultLink] {
        let normalizedHTML = html.replacingOccurrences(of: "\\/", with: "/")
        let range = NSRange(normalizedHTML.startIndex..<normalizedHTML.endIndex, in: normalizedHTML)
        let matches = f1ResultLinkRegexes.flatMap { $0.matches(in: normalizedHTML, range: range) }

        var links: [F1ResultLink] = []
        var seenPaths = Set<String>()
        for match in matches {
            guard
                let seasonRaw = normalizedHTML.substring(for: match.range(at: 1)),
                let meetingRaw = normalizedHTML.substring(for: match.range(at: 2)),
                let slug = normalizedHTML.substring(for: match.range(at: 3)),
                let fullPath = normalizedHTML.substring(for: match.range(at: 0)),
                let season = Int(seasonRaw),
                let meetingID = Int(meetingRaw),
                seenPaths.insert(fullPath).inserted
            else {
                continue
            }
            links.append(F1ResultLink(season: season, meetingID: meetingID, slug: slug, path: fullPath))
        }
        return links
    }

    func selectF1ResultLink(for event: RaceEvent, links: [F1ResultLink]) -> F1ResultLink? {
        let seasonLinks = links
            .filter { $0.season == event.season }
            .sorted { lhs, rhs in
                if lhs.meetingID == rhs.meetingID {
                    return lhs.path < rhs.path
                }
                return lhs.meetingID < rhs.meetingID
            }
        guard !seasonLinks.isEmpty else {
            return nil
        }

        if
            let slug = f1Slug(for: event),
            let exactSlugMatch = seasonLinks.first(where: { $0.slug == slug })
        {
            return exactSlugMatch
        }

        let roundIndex = max(0, event.round - 1)
        if seasonLinks.indices.contains(roundIndex) {
            return seasonLinks[roundIndex]
        }

        return seasonLinks.first
    }

    private func f1Slug(for event: RaceEvent) -> String? {
        let prefix = "f1-\(event.season)-"
        guard event.id.hasPrefix(prefix) else {
            return nil
        }
        return String(event.id.dropFirst(prefix.count))
    }
}

enum OfficialResultRepositoryError: LocalizedError {
    case resultsUnavailable

    var errorDescription: String? {
        switch self {
        case .resultsUnavailable:
            return "Official top-3 results are not available for this event yet."
        }
    }
}

struct F1ResultLink: Hashable {
    let season: Int
    let meetingID: Int
    let slug: String
    let path: String
}

private struct MotoGPSeasonPayload: Decodable {
    let id: String
    let year: Int
    let current: Bool
}

struct MotoGPResultsEventPayload: Decodable {
    let id: String
    let toadAPIUUID: String?
    let test: Bool
    let sequence: Int?
    let legacyIDs: [MotoGPResultsEventLegacyIDPayload]

    var legacyEventID: Int? {
        legacyIDs.first(where: { $0.categoryID == 3 })?.eventID
            ?? legacyIDs.first?.eventID
    }

    init(
        id: String,
        toadAPIUUID: String?,
        test: Bool,
        sequence: Int?,
        legacyIDs: [MotoGPResultsEventLegacyIDPayload]
    ) {
        self.id = id
        self.toadAPIUUID = toadAPIUUID
        self.test = test
        self.sequence = sequence
        self.legacyIDs = legacyIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        toadAPIUUID = try container.decodeIfPresent(String.self, forKey: .toadAPIUUID)
        test = try container.decodeIfPresent(Bool.self, forKey: .test) ?? false
        sequence = try container.decodeIfPresent(Int.self, forKey: .sequence)
        legacyIDs = try container.decodeIfPresent([MotoGPResultsEventLegacyIDPayload].self, forKey: .legacyIDs) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case toadAPIUUID = "toad_api_uuid"
        case test
        case sequence
        case legacyIDs = "legacy_id"
    }
}

struct MotoGPResultsEventLegacyIDPayload: Decodable {
    let categoryID: Int?
    let eventID: Int?

    init(categoryID: Int?, eventID: Int?) {
        self.categoryID = categoryID
        self.eventID = eventID
    }

    enum CodingKeys: String, CodingKey {
        case categoryID = "categoryId"
        case eventID = "eventId"
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

struct MotoGPResultSessionPayload: Decodable {
    let id: String
    let type: String
    let date: Date?
    let status: String?
}

private struct MotoGPResultClassificationPayload: Decodable {
    let classification: [MotoGPResultClassificationRow]
}

private struct MotoGPResultClassificationRow: Decodable {
    let position: Int?
    let rider: MotoGPResultRider?
}

private struct MotoGPResultRider: Decodable {
    let fullName: String?
    let name: String?
    let surname: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
        case surname
    }
}

private let f1ResultLinkRegexes: [NSRegularExpression] = {
    // Formula1.com markup varies; keep multiple patterns.
    let patterns: [String] = [
        #"/en/results/(\d{4})/races/(\d+)/([a-z0-9-]+)/race-result"#,
        // Sometimes the path omits the leading /en or includes an extra suffix.
        #"/results/(\d{4})/races/(\d+)/([a-z0-9-]+)/race-result"#
    ]

    return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
}()

private let f1TableRowRegex: NSRegularExpression = {
    (try? NSRegularExpression(
        pattern: #"<tr[^>]*>(.*?)</tr>"#,
        options: [.dotMatchesLineSeparators, .caseInsensitive]
    )) ?? fallbackNeverMatchRegex
}()

private let f1TableCellRegex: NSRegularExpression = {
    (try? NSRegularExpression(
        pattern: #"<td[^>]*>(.*?)</td>"#,
        options: [.dotMatchesLineSeparators, .caseInsensitive]
    )) ?? fallbackNeverMatchRegex
}()

private let fallbackNeverMatchRegex: NSRegularExpression = {
    // Guaranteed non-matching regex used as a safe fallback.
    (try? NSRegularExpression(pattern: "(?!x)x"))
    ?? (try! NSRegularExpression(pattern: "(?!x)x"))
}()

private func parseF1DriverName(from driverCellHTML: String) -> String {
    let stripped = stripHTML(driverCellHTML)
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !stripped.isEmpty else {
        return ""
    }

    var tokens = stripped.split(separator: " ").map(String.init)
    if let last = tokens.last, last.count == 3, last.uppercased() == last {
        tokens.removeLast()
    }
    tokens.removeAll { Int($0) != nil }
    return tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func stripHTML(_ html: String) -> String {
    html.replacingOccurrences(
        of: #"<[^>]+>"#,
        with: " ",
        options: .regularExpression
    )
}

private extension String {
    func substring(for range: NSRange) -> String? {
        guard let swiftRange = Range(range, in: self) else {
            return nil
        }
        return String(self[swiftRange])
    }
}

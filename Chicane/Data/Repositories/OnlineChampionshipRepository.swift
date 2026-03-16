import Foundation

struct OnlineChampionshipRepository: ChampionshipRepository {
    private let client: RemoteDataClient

    init(client: RemoteDataClient = RemoteDataClient()) {
        self.client = client
    }

    func topThree(for series: RaceSeries) async throws -> [ChampionshipLeader] {
        switch series {
        case .formula1:
            return try await formula1TopThree()
        case .motoGP:
            return try await motoGPTopThree()
        }
    }

    private func formula1TopThree() async throws -> [ChampionshipLeader] {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: .now)
        guard let url = URL(string: "https://www.formula1.com/en/results/\(currentYear)/drivers") else {
            throw RemoteDataError.emptyPayload(source: "Formula 1 standings")
        }

        let html = try await client.fetchString(from: url)
        let leaders = F1OfficialHTMLParser.parseTopThreeDriverStandings(from: html)
        guard leaders.count == 3 else {
            throw RemoteDataError.emptyPayload(source: "Formula 1 standings")
        }
        return leaders
    }

    private func motoGPTopThree() async throws -> [ChampionshipLeader] {
        guard
            let seasonsURL = URL(string: "https://api.pulselive.motogp.com/motogp/v1/results/seasons"),
            let categoriesURL = URL(string: "https://api.pulselive.motogp.com/motogp/v1/results/categories"),
            let standingsURL = URL(string: "https://api.pulselive.motogp.com/motogp/v2/results/world-standings")
        else {
            throw RemoteDataError.emptyPayload(source: "MotoGP standings")
        }

        let seasons = try await client.fetchJSON([MotoGPSeasonPayload].self, from: seasonsURL)
        guard let season = seasons.first(where: { $0.current }) ?? seasons.max(by: { $0.year < $1.year }) else {
            throw RemoteDataError.emptyPayload(source: "MotoGP standings")
        }

        let categories: [MotoGPStandingCategoryPayload] = try await client.fetchJSON(
            [MotoGPStandingCategoryPayload].self,
            from: try motoGPURL(
                from: categoriesURL,
                queryItems: [URLQueryItem(name: "seasonUuid", value: season.id)]
            )
        )

        guard let motoGPCategory = categories.first(where: { $0.legacyID == 3 })
            ?? categories.first(where: { $0.name.localizedCaseInsensitiveContains("MotoGP") })
        else {
            throw RemoteDataError.emptyPayload(source: "MotoGP standings")
        }

        let standings: MotoGPWorldStandingsPayload = try await client.fetchJSON(
            MotoGPWorldStandingsPayload.self,
            from: try motoGPURL(
                from: standingsURL,
                queryItems: [
                    URLQueryItem(name: "type", value: "rider"),
                    URLQueryItem(name: "season", value: season.id),
                    URLQueryItem(name: "category", value: motoGPCategory.id)
                ]
            )
        )

        let leaders = standings.classification
            .compactMap { row -> ChampionshipLeader? in
                guard let position = row.position, (1...3).contains(position) else {
                    return nil
                }

                let directName = row.rider?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackName = "\(row.rider?.name ?? "") \(row.rider?.surname ?? "")"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let name = (directName?.isEmpty == false ? directName : fallbackName) ?? ""

                guard !name.isEmpty else {
                    return nil
                }

                let team = row.teamName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedTeam = (team?.isEmpty == false) ? team ?? "MotoGP" : "MotoGP"
                return ChampionshipLeader(
                    series: .motoGP,
                    position: position,
                    name: name,
                    team: resolvedTeam,
                    points: row.points ?? 0
                )
            }
            .sorted { $0.position < $1.position }

        guard leaders.count == 3 else {
            throw RemoteDataError.emptyPayload(source: "MotoGP standings")
        }

        return leaders
    }

    private func motoGPURL(from baseURL: URL, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteDataError.emptyPayload(source: "MotoGP standings")
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw RemoteDataError.emptyPayload(source: "MotoGP standings")
        }
        return url
    }
}

private struct MotoGPSeasonPayload: Decodable {
    let id: String
    let year: Int
    let current: Bool
}

private struct MotoGPStandingCategoryPayload: Decodable {
    let id: String
    let name: String
    let legacyID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case legacyID = "legacy_id"
    }
}

struct MotoGPWorldStandingsPayload: Decodable {
    let classification: [MotoGPWorldStandingRow]

    private enum CodingKeys: String, CodingKey {
        case classification
    }

    private struct ClassificationContainer: Decodable {
        let rider: [MotoGPWorldStandingRow]?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let directRows = try? container.decode([MotoGPWorldStandingRow].self, forKey: .classification) {
            classification = directRows
            return
        }

        if
            let wrapped = try? container.decode(ClassificationContainer.self, forKey: .classification),
            let riderRows = wrapped.rider
        {
            classification = riderRows
            return
        }

        classification = []
    }
}

struct MotoGPWorldStandingRow: Decodable {
    let position: Int?
    let points: Int?
    let teamName: String?
    let rider: MotoGPStandingRider?

    enum CodingKeys: String, CodingKey {
        case position
        case points
        case teamName = "team_name"
        case rider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decodeLossyIntIfPresent(forKey: .position)
        points = try container.decodeLossyIntIfPresent(forKey: .points)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName)
        rider = try container.decodeIfPresent(MotoGPStandingRider.self, forKey: .rider)
    }
}

struct MotoGPStandingRider: Decodable {
    let fullName: String?
    let name: String?
    let surname: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
        case surname
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        }

        return nil
    }
}

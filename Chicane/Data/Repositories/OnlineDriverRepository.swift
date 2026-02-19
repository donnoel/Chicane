import Foundation

struct OnlineDriverRepository: DriverRepository {
    private let client: RemoteDataClient

    init(client: RemoteDataClient = RemoteDataClient()) {
        self.client = client
    }

    func drivers(for series: RaceSeries) async throws -> [Driver] {
        switch series {
        case .formula1:
            return try await formula1Drivers()
        case .motoGP:
            return try await motoGPDrivers()
        }
    }

    private func formula1Drivers() async throws -> [Driver] {
        guard let url = URL(string: "https://www.formula1.com/en/drivers") else {
            throw RemoteDataError.emptyPayload(source: "Formula 1 drivers")
        }

        let html = try await client.fetchString(from: url)
        let parsed = F1OfficialHTMLParser.parseDrivers(from: html)
        guard !parsed.isEmpty else {
            throw RemoteDataError.emptyPayload(source: "Formula 1 drivers")
        }
        return parsed
    }

    private func motoGPDrivers() async throws -> [Driver] {
        guard let url = URL(string: "https://api.pulselive.motogp.com/motogp/v1/riders") else {
            throw RemoteDataError.emptyPayload(source: "MotoGP riders")
        }

        let riders = try await client.fetchJSON(
            [MotoGPRiderPayload].self,
            from: url
        )

        let mapped = riders.compactMap { rider -> Driver? in
            guard
                let step = rider.currentCareerStep,
                step.current,
                step.category?.name == "MotoGP"
            else {
                return nil
            }

            let fullName = "\(rider.name) \(rider.surname)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fullName.isEmpty else {
                return nil
            }

            let teamName = step.sponsoredTeam?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTeam = step.team?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let team = teamName?.isEmpty == false ? teamName! : (fallbackTeam?.isEmpty == false ? fallbackTeam! : "MotoGP")
            let number = step.number.map(String.init) ?? ""

            return Driver(
                id: "mgp-\(rider.id)",
                series: .motoGP,
                name: fullName,
                team: team,
                number: number
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !mapped.isEmpty else {
            throw RemoteDataError.emptyPayload(source: "MotoGP riders")
        }
        return mapped
    }
}

private struct MotoGPRiderPayload: Decodable {
    let id: String
    let name: String
    let surname: String
    let currentCareerStep: MotoGPCareerStep?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case surname
        case currentCareerStep = "current_career_step"
    }
}

private struct MotoGPCareerStep: Decodable {
    let number: Int?
    let sponsoredTeam: String?
    let current: Bool
    let team: MotoGPTeamPayload?
    let category: MotoGPCategoryPayload?

    enum CodingKeys: String, CodingKey {
        case number
        case sponsoredTeam = "sponsored_team"
        case current
        case team
        case category
    }
}

private struct MotoGPTeamPayload: Decodable {
    let name: String?
}

private struct MotoGPCategoryPayload: Decodable {
    let name: String?
}

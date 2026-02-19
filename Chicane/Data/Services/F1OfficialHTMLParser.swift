import Foundation

enum F1OfficialHTMLParser {
    private static let driverCardRegex = try! NSRegularExpression(
        pattern: #"<a[^>]*data-f1rd-a7s-click="driver_card_click"[^>]*data-f1rd-a7s-context="([^"]+)"[^>]*href="(/en/drivers/[^"]+)"[^>]*>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let eventCardRegex = try! NSRegularExpression(
        pattern: #"<a class="group"[^>]*data-f1rd-a7s-context="([^"]+)"[^>]*href="(/en/racing/(\d{4})/[^"]+)"[^>]*>(.*?)</a>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let roundRegex = try! NSRegularExpression(pattern: #">ROUND\s*(\d+)<"#)
    private static let dateRangeRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})(?:\s+[A-Za-z]{3})?\s*-\s*(\d{1,2})\s+([A-Za-z]{3})"#
    )
    private static let singleDateRegex = try! NSRegularExpression(pattern: #"(\d{1,2})\s+([A-Za-z]{3})"#)

    private static let monthMap: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    static func parseDrivers(from html: String) -> [Driver] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = driverCardRegex.matches(in: html, range: range)

        var driversByID: [String: Driver] = [:]
        for match in matches {
            guard
                let contextRaw = html.substring(for: match.range(at: 1)),
                let href = html.substring(for: match.range(at: 2)),
                let context: F1DriverContext = decodeContext(contextRaw),
                let name = context.driverName?.trimmingCharacters(in: .whitespacesAndNewlines),
                let team = context.driverTeam?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                !team.isEmpty
            else {
                continue
            }

            let slug = href.split(separator: "/").last.map(String.init) ?? UUID().uuidString
            let id = "f1-\(slug)"
            driversByID[id] = Driver(
                id: id,
                series: .formula1,
                name: name,
                team: team,
                number: ""
            )
        }

        return driversByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func parseEvents(from html: String, expectedSeason: Int) -> [RaceEvent] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = eventCardRegex.matches(in: html, range: range)

        var eventsByID: [String: RaceEvent] = [:]
        for match in matches {
            guard
                let contextRaw = html.substring(for: match.range(at: 1)),
                let href = html.substring(for: match.range(at: 2)),
                let seasonRaw = html.substring(for: match.range(at: 3)),
                let cardHTML = html.substring(for: match.range(at: 4)),
                let season = Int(seasonRaw),
                let round = parseRound(from: cardHTML),
                let raceDate = parseRaceDate(from: cardHTML, season: season),
                let context: F1RaceContext = decodeContext(contextRaw)
            else {
                continue
            }

            let slug = href.split(separator: "/").last.map(String.init) ?? "event-\(round)"
            let title = normalizedRaceTitle(
                from: context.raceName,
                season: season,
                fallbackSlug: slug
            )
            let circuit = context.trackName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? slug
                .replacingOccurrences(of: "-", with: " ")
                .localizedCapitalized

            let id = "f1-\(season)-\(slug)"
            eventsByID[id] = RaceEvent(
                id: id,
                series: .formula1,
                season: season,
                round: round,
                title: title,
                circuit: circuit,
                raceDate: raceDate
            )
        }

        let parsed = eventsByID.values.sorted {
            if $0.round == $1.round {
                return $0.raceDate < $1.raceDate
            }
            return $0.round < $1.round
        }
        return parsed.filter { $0.season == expectedSeason }
    }

    private static func parseRound(from cardHTML: String) -> Int? {
        guard
            let value = roundRegex.firstCapture(in: cardHTML),
            let round = Int(value)
        else {
            return nil
        }
        return round
    }

    private static func parseRaceDate(from cardHTML: String, season: Int) -> Date? {
        if let match = dateRangeRegex.firstMatch(in: cardHTML, range: NSRange(cardHTML.startIndex..<cardHTML.endIndex, in: cardHTML)) {
            guard
                let endDayRaw = cardHTML.substring(for: match.range(at: 2)),
                let monthRaw = cardHTML.substring(for: match.range(at: 3)),
                let day = Int(endDayRaw),
                let month = monthMap[monthRaw.lowercased()]
            else {
                return nil
            }
            return makeDate(year: season, month: month, day: day)
        }

        if let match = singleDateRegex.firstMatch(in: cardHTML, range: NSRange(cardHTML.startIndex..<cardHTML.endIndex, in: cardHTML)) {
            guard
                let dayRaw = cardHTML.substring(for: match.range(at: 1)),
                let monthRaw = cardHTML.substring(for: match.range(at: 2)),
                let day = Int(dayRaw),
                let month = monthMap[monthRaw.lowercased()]
            else {
                return nil
            }
            return makeDate(year: season, month: month, day: day)
        }

        return nil
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date
    }

    private static func normalizedRaceTitle(
        from rawValue: String?,
        season: Int,
        fallbackSlug: String
    ) -> String {
        guard let rawValue = rawValue?.nonEmpty else {
            return fallbackSlug
                .replacingOccurrences(of: "-", with: " ")
                .localizedCapitalized + " Grand Prix"
        }

        var cleaned = rawValue.replacingOccurrences(of: "FORMULA 1 ", with: "")
        cleaned = cleaned.replacingOccurrences(of: " \(season)", with: "")
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).localizedCapitalized
    }

    private static func decodeContext<T: Decodable>(_ encoded: String) -> T? {
        let normalized = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - normalized.count % 4) % 4
        let padded = normalized + String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: padded) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private struct F1DriverContext: Decodable {
    let driverName: String?
    let driverTeam: String?
}

private struct F1RaceContext: Decodable {
    let raceName: String?
    let trackName: String?
}

private extension NSRegularExpression {
    func firstCapture(in string: String, captureIndex: Int = 1) -> String? {
        guard
            let match = firstMatch(
                in: string,
                range: NSRange(string.startIndex..<string.endIndex, in: string)
            ),
            let range = Range(match.range(at: captureIndex), in: string)
        else {
            return nil
        }
        return String(string[range])
    }
}

private extension String {
    func substring(for range: NSRange) -> String? {
        guard let swiftRange = Range(range, in: self) else {
            return nil
        }
        return String(self[swiftRange])
    }

    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

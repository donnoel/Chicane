import Foundation

enum F1OfficialHTMLParser {
    // NOTE: F1 markup changes periodically. Use multiple patterns and fail soft (empty results)
    // rather than crashing or throwing from a static initializer.
    private static let driverCardRegexes: [NSRegularExpression] = {
        let patterns: [String] = [
            // Current-ish: analytics attributes + base64url context
            #"<a[^>]*data-f1rd-a7s-click=\"driver_card_click\"[^>]*data-f1rd-a7s-context=\"([^\"]+)\"[^>]*href=\"(/en/drivers/[^\"]+)\"[^>]*>"#,
            // Fallback: some pages omit the click attr
            #"<a[^>]*data-f1rd-a7s-context=\"([^\"]+)\"[^>]*href=\"(/en/drivers/[^\"]+)\"[^>]*>"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators]) }
    }()

    private static let eventCardRegexes: [NSRegularExpression] = {
        let patterns: [String] = [
            // Current-ish: group card anchor with context
            #"<a class=\"group\"[^>]*data-f1rd-a7s-context=\"([^\"]+)\"[^>]*href=\"(/en/racing/(\d{4})/[^\"]+)\"[^>]*>(.*?)</a>"#,
            // Fallback: class may not be exactly "group"
            #"<a[^>]*data-f1rd-a7s-context=\"([^\"]+)\"[^>]*href=\"(/en/racing/(\d{4})/[^\"]+)\"[^>]*>(.*?)</a>"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators]) }
    }()

    private static let roundRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #">ROUND\s*(\d+)<"#))
        ?? fallbackNeverMatchRegex
    }()

    // Captures: (1) optional start-day, (3) optional start-month abbreviation,
    //           (2) end-day, (4) end-month abbreviation.
    // Examples: "27 - 29 Mar"  →  start=nil, end=29, endMonth="Mar"
    //           "30 Dec - 1 Jan" → startDay=30, startMonth="Dec", endDay=1, endMonth="Jan"
    private static let dateRangeRegex: NSRegularExpression = {
        (try? NSRegularExpression(
            pattern: #"(\d{1,2})(?:\s+([A-Za-z]{3,4}))?\s*-\s*(\d{1,2})\s+([A-Za-z]{3,4})"#
        )) ?? fallbackNeverMatchRegex
    }()

    private static let singleDateRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #"(\d{1,2})\s+([A-Za-z]{3,4})"#))
        ?? fallbackNeverMatchRegex
    }()

    private static let raceSessionRegex: NSRegularExpression = {
        (try? NSRegularExpression(
            pattern: #"\\"session\\":\\"r\\",.*?\\"startTime\\":\\"([^\\"]+)\\",.*?\\"gmtOffset\\":\\"([+-]\d{2}:\d{2})\\",.*?\\"timezone\\":\\"([^\\"]+)\\""#,
            options: [.dotMatchesLineSeparators]
        )) ?? fallbackNeverMatchRegex
    }()

    private static let fallbackNeverMatchRegex: NSRegularExpression = {
        // A guaranteed non-matching regex used as a safe fallback when compilation fails.
        // Using an explicit pattern avoids defining an `init()` that would conflict with Obj-C.
        (try? NSRegularExpression(pattern: "(?!x)x"))
        ?? (try! NSRegularExpression(pattern: "(?!x)x"))
    }()

    private static let raceSessionDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let monthMap: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    static func parseDrivers(from html: String) -> [Driver] {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = driverCardRegexes.flatMap { $0.matches(in: html, range: range) }

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
        let matches = eventCardRegexes.flatMap { $0.matches(in: html, range: range) }

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

    /// Parses the race date from a card's inner HTML.
    ///
    /// **Year-boundary handling:**
    /// F1 seasons occasionally end with a late-December race whose weekend card shows
    /// a date range that spans New Year's Eve into January of the following year
    /// (e.g. "30 Dec – 1 Jan").  In that case the end date (race day) belongs to
    /// `season + 1`, not `season`.  We detect this by checking whether the range
    /// start-month is December while the end-month is January.
    private static func parseRaceDate(from cardHTML: String, season: Int) -> Date? {
        let cardRange = NSRange(cardHTML.startIndex..<cardHTML.endIndex, in: cardHTML)

        if let match = dateRangeRegex.firstMatch(in: cardHTML, range: cardRange) {
            // Group indices for the updated regex:
            // 1 = start day, 2 = start month (optional), 3 = end day, 4 = end month
            guard
                let endDayRaw   = cardHTML.substring(for: match.range(at: 3)),
                let endMonthRaw = cardHTML.substring(for: match.range(at: 4)),
                let endDay      = Int(endDayRaw),
                let endMonth    = monthMap[endMonthRaw.lowercased()]
            else {
                return nil
            }

            // Detect year-boundary: start is December, end rolls into January.
            var year = season
            if endMonth == 1,
               let startMonthRaw = cardHTML.substring(for: match.range(at: 2)),
               monthMap[startMonthRaw.lowercased()] == 12 {
                year = season + 1
            }

            return makeDate(year: year, month: endMonth, day: endDay)
        }

        if let match = singleDateRegex.firstMatch(in: cardHTML, range: cardRange) {
            guard
                let dayRaw   = cardHTML.substring(for: match.range(at: 1)),
                let monthRaw = cardHTML.substring(for: match.range(at: 2)),
                let day      = Int(dayRaw),
                let month    = monthMap[monthRaw.lowercased()]
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

    static func parseRaceSessionDetails(fromRacePageHTML html: String) -> (startDate: Date, timeZoneID: String)? {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard
            let match = raceSessionRegex.firstMatch(in: html, range: range),
            let startTime = html.substring(for: match.range(at: 1)),
            let gmtOffset = html.substring(for: match.range(at: 2)),
            let timeZoneID = html.substring(for: match.range(at: 3)),
            let startDate = raceSessionDateFormatter.date(from: "\(startTime)\(gmtOffset)")
        else {
            return nil
        }

        return (startDate, timeZoneID)
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
        let encoded = encoded
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&#47;", with: "/")

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

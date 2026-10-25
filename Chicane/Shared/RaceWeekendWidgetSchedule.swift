import Foundation
import OSLog

/// One atomic snapshot keeps live event identities, start times and settlement
/// state together; bundled round numbers/times can differ from the live season.
struct RaceWeekendWidgetSnapshot: Codable, Equatable, Sendable {
    static let fileName = "race-weekend-widget-snapshot-v3.json"
    static let appGroupID = "group.dn.thepodium"
    let events: [WidgetRaceEvent]
    let completedEventKeys: [String]
    let canceledEventKeys: [String]

    static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func readShared() -> Self? {
        guard let url = sharedURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try read(from: url) }
        catch {
            Logger(subsystem: "dn.thepodium", category: "WidgetCalendar").error("Could not read widget calendar: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func read(from url: URL) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: Data(contentsOf: url))
    }

    @discardableResult
    func write(to url: URL) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        if (try? Data(contentsOf: url)) == data { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return true
    }
}

enum WidgetCalendarStore {
    private static let appGroupID = "group.dn.thepodium"
    private static let completedEventKeysKey = "race_weekend_widget_completed_event_keys_v2"
    private static let currentRaceResultHoldWindow: TimeInterval = 5 * 24 * 60 * 60

    static func nextEvent(at date: Date) -> WidgetRaceEvent {
        if let snapshot = RaceWeekendWidgetSnapshot.readShared() {
            return nextEvent(at: date, snapshot: snapshot)
        }
        // Before the app has supplied its calendar, retain the bundled fallback.
        return nextEvent(at: date, snapshot: RaceWeekendWidgetSnapshot(
            events: loadEvents(), completedEventKeys: [], canceledEventKeys: Array(loadCompletedEventKeys())
        ))
    }

    static func nextEvent(at date: Date, snapshot: RaceWeekendWidgetSnapshot) -> WidgetRaceEvent {
        let completed = Set(snapshot.completedEventKeys)
        let canceled = Set(snapshot.canceledEventKeys)
        let sortedEvents = snapshot.events.sorted { $0.raceDate < $1.raceDate }
        let eligible = sortedEvents.filter { event in
            !canceled.contains(completedEventKey(for: event)) &&
                !(event.raceDate <= date && completed.contains(completedEventKey(for: event)))
        }

        // Remove settled races first: a canceled/finished later race must not
        // hide another series' still-pending race on the same weekend.
        if let latestStarted = eligible.last(where: { $0.raceDate <= date }),
           date.timeIntervalSince(latestStarted.raceDate) <= currentRaceResultHoldWindow {
            return latestStarted
        }
        return eligible.first { $0.raceDate > date } ?? eligible.last ?? sortedEvents.last ?? .placeholder
    }

    static func nextRefreshDate(for event: WidgetRaceEvent, at date: Date) -> Date {
        if event.raceDate > date {
            let afterRaceStart = event.raceDate.addingTimeInterval(60)
            let nextRoutineRefresh = date.addingTimeInterval(6 * 60 * 60)
            return min(afterRaceStart, nextRoutineRefresh)
        }

        return date.addingTimeInterval(6 * 60 * 60)
    }

    private static func loadEvents() -> [WidgetRaceEvent] {
        guard let url = calendarURL() else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WidgetCalendar.self, from: data).events
        } catch {
            return []
        }
    }

    private static func loadCompletedEventKeys() -> Set<String> {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return []
        }

        return Set(defaults.stringArray(forKey: completedEventKeysKey) ?? [])
    }

    private static func completedEventKey(for event: WidgetRaceEvent) -> String {
        "\(event.series.rawValue)|\(event.season)|\(event.round)"
    }

    private static func calendarURL() -> URL? {
        Bundle.main.url(forResource: "calendar", withExtension: "json")
            ?? Bundle.main.url(forResource: "calendar", withExtension: "json", subdirectory: "Seed")
            ?? Bundle.main.url(forResource: "calendar", withExtension: "json", subdirectory: "Resources/Seed")
    }
}

private struct WidgetCalendar: Decodable {
    let events: [WidgetRaceEvent]
}

enum WidgetRaceSeries: String, Codable, Sendable {
    case formula1
    case motoGP

    var shortTitle: String {
        switch self {
        case .formula1:
            return "F1"
        case .motoGP:
            return "MotoGP"
        }
    }

    var artworkName: String {
        switch self {
        case .formula1:
            return "SeriesFormula1"
        case .motoGP:
            return "SeriesMotoGP"
        }
    }

    var artworkWidth: CGFloat {
        switch self {
        case .formula1:
            return 52
        case .motoGP:
            return 42
        }
    }
}

struct WidgetRaceEvent: Codable, Equatable, Sendable {
    let id: String
    let series: WidgetRaceSeries
    let season: Int
    let round: Int
    let title: String
    let circuit: String
    let raceDate: Date

    var widgetDateText: String {
        WidgetDateFormatter.shared.string(from: raceDate)
    }

    var compactWidgetDateText: String {
        WidgetDateFormatter.compact.string(from: raceDate)
    }

    var smallWidgetTitle: String {
        let sponsorPrefixes = [
            "Pirelli ",
            "Qatar Airways ",
            "Lenovo ",
            "Tissot ",
            "Crypto.com ",
            "MSC Cruises ",
            "Gulf Air ",
            "Heineken ",
            "Rolex "
        ]
        let sponsorlessTitle = sponsorPrefixes.reduce(title) { currentTitle, prefix in
            currentTitle.hasPrefix(prefix) ? String(currentTitle.dropFirst(prefix.count)) : currentTitle
        }

        return sponsorlessTitle.replacingOccurrences(of: "Grand Prix", with: "GP")
    }

    static let placeholder = WidgetRaceEvent(
        id: "placeholder",
        series: .formula1,
        season: 2026,
        round: 9,
        title: "Pirelli British Grand Prix",
        circuit: "Silverstone",
        raceDate: Date(timeIntervalSince1970: 1_783_253_600)
    )
}

private enum WidgetDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let compact: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d HH:mm")
        return formatter
    }()
}

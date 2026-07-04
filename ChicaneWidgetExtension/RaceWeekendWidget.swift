import SwiftUI
import WidgetKit

struct RaceWeekendEntry: TimelineEntry {
    let date: Date
    let event: WidgetRaceEvent
}

struct RaceWeekendProvider: TimelineProvider {
    func placeholder(in context: Context) -> RaceWeekendEntry {
        RaceWeekendEntry(date: .now, event: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RaceWeekendEntry) -> Void) {
        completion(RaceWeekendEntry(date: .now, event: WidgetCalendarStore.nextEvent(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RaceWeekendEntry>) -> Void) {
        let now = Date()
        let event = WidgetCalendarStore.nextEvent(at: now)
        let refreshDate = WidgetCalendarStore.nextRefreshDate(for: event, at: now)
        completion(Timeline(entries: [RaceWeekendEntry(date: now, event: event)], policy: .after(refreshDate)))
    }
}

struct RaceWeekendWidget: Widget {
    let kind = "RaceWeekendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RaceWeekendProvider()) { entry in
            RaceWeekendWidgetView(entry: entry)
        }
        .configurationDisplayName("Race Weekend")
        .description("See the next race weekend from The Podium.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RaceWeekendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var widgetContentMargins
    let entry: RaceWeekendEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallCard
            default:
                mediumCard
            }
        }
        .containerBackground(for: .widget) {
            WidgetStyle.gradient(for: entry.event.series)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var mediumCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(iconSize: 36, titleSize: .caption, subtitleSize: .headline)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.event.title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)

                Text(entry.event.circuit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            HStack(spacing: 8) {
                timePill
                Spacer(minLength: 0)
                roundPill
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .padding(.horizontal, -mediumContentHorizontalOutset)
    }

    private var smallCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                flagBadge(size: 28, iconSize: 13)

                Spacer(minLength: 8)

                seriesArtwork
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.event.smallWidgetTitle)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                        .layoutPriority(1)

                    compactRoundText
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.event.circuit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            compactTimePill
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .padding(.horizontal, -smallContentHorizontalOutset)
        .padding(.vertical, -smallContentVerticalOutset)
    }

    private var smallContentHorizontalOutset: CGFloat {
        min(10, min(widgetContentMargins.leading, widgetContentMargins.trailing))
    }

    private var smallContentVerticalOutset: CGFloat {
        min(5, min(widgetContentMargins.top, widgetContentMargins.bottom))
    }

    private var mediumContentHorizontalOutset: CGFloat {
        min(10, min(widgetContentMargins.leading, widgetContentMargins.trailing))
    }

    private func header(iconSize: CGFloat, titleSize: Font, subtitleSize: Font) -> some View {
        HStack(alignment: .center, spacing: 8) {
            flagBadge(size: iconSize, iconSize: iconSize * 0.48)

            VStack(alignment: .leading, spacing: 1) {
                Text("Race Weekend")
                    .font(titleSize.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("Next up")
                    .font(subtitleSize.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Spacer(minLength: 4)

            seriesArtwork
        }
    }

    private var timePill: some View {
        Label(entry.event.widgetDateText, systemImage: "clock")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private var compactTimePill: some View {
        Label(entry.event.compactWidgetDateText, systemImage: "clock")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private var roundPill: some View {
        Text("R\(entry.event.round)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private var compactRoundText: some View {
        Text("R\(entry.event.round)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var seriesArtwork: some View {
        Image(entry.event.series.artworkName)
            .resizable()
            .scaledToFit()
            .frame(width: entry.event.series.artworkWidth, height: 27)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private func flagBadge(size: CGFloat, iconSize: CGFloat) -> some View {
        Image(systemName: "flag.checkered.2.crossed")
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.white.opacity(0.18), in: Circle())
            .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        "Race weekend. Next up, \(entry.event.title) at \(entry.event.circuit), \(entry.event.widgetDateText)."
    }
}

private enum WidgetStyle {
    static let f1Red = Color(red: 0.89, green: 0.08, blue: 0.13)
    static let motoBlue = Color(red: 0.15, green: 0.45, blue: 0.99)
    static let deepNavy = Color(red: 0.04, green: 0.08, blue: 0.18)
    static let glowAmber = Color(red: 0.99, green: 0.61, blue: 0.28)

    static func gradient(for series: WidgetRaceSeries) -> LinearGradient {
        LinearGradient(
            colors: [
                seriesColor(series).opacity(0.96),
                deepNavy.opacity(0.96),
                glowAmber.opacity(series == .formula1 ? 0.82 : 0.64)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func seriesColor(_ series: WidgetRaceSeries) -> Color {
        switch series {
        case .formula1:
            return f1Red
        case .motoGP:
            return motoBlue
        }
    }
}

private enum WidgetCalendarStore {
    private static let appGroupID = "group.dn.thepodium"
    private static let resultKeysKey = "race_weekend_widget_result_keys_v1"
    private static let currentRaceResultHoldWindow: TimeInterval = 5 * 24 * 60 * 60

    static func nextEvent(at date: Date) -> WidgetRaceEvent {
        let events = loadEvents()
        guard !events.isEmpty else { return .placeholder }

        let sortedEvents = events.sorted { $0.raceDate < $1.raceDate }
        let resultKeys = loadResultKeys()

        if
            let latestStartedEvent = sortedEvents.last(where: { $0.raceDate <= date }),
            date.timeIntervalSince(latestStartedEvent.raceDate) <= currentRaceResultHoldWindow,
            !resultKeys.contains(resultKey(for: latestStartedEvent))
        {
            return latestStartedEvent
        }

        return sortedEvents.first { $0.raceDate > date } ?? sortedEvents.last ?? .placeholder
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

    private static func loadResultKeys() -> Set<String> {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return []
        }

        return Set(defaults.stringArray(forKey: resultKeysKey) ?? [])
    }

    private static func resultKey(for event: WidgetRaceEvent) -> String {
        "\(event.series.rawValue)|\(event.id)"
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

enum WidgetRaceSeries: String, Codable {
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

struct WidgetRaceEvent: Decodable {
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
        round: 12,
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

#Preview(as: .systemMedium) {
    RaceWeekendWidget()
} timeline: {
    RaceWeekendEntry(date: .now, event: .placeholder)
}

#Preview(as: .systemSmall) {
    RaceWeekendWidget()
} timeline: {
    RaceWeekendEntry(date: .now, event: .placeholder)
}

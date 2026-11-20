import Foundation

struct FallbackDriverRepository: DriverRepository {
    private let primary: DriverRepository
    private let fallback: DriverRepository

    init(primary: DriverRepository, fallback: DriverRepository) {
        self.primary = primary
        self.fallback = fallback
    }

    func drivers(for series: RaceSeries) async throws -> [Driver] {
        if let online = try? await primary.drivers(for: series), !online.isEmpty {
            return online
        }
        return try await fallback.drivers(for: series)
    }
}

actor FallbackCalendarRepository: CalendarRepository {
    private struct SavedCalendar: Codable {
        let fetchedAt: Date
        let events: [RaceEvent]
    }

    static var defaultCacheDirectoryURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Chicane/CalendarCache", isDirectory: true)
    }

    private let primary: CalendarRepository
    private let fallback: CalendarRepository
    private let cacheDirectoryURL: URL?
    private var warnings: [RaceSeries: String] = [:]

    init(primary: CalendarRepository, fallback: CalendarRepository, cacheDirectoryURL: URL? = nil) {
        self.primary = primary
        self.fallback = fallback
        self.cacheDirectoryURL = cacheDirectoryURL
    }

    func events(for series: RaceSeries) async throws -> [RaceEvent] {
        if let online = try? await primary.events(for: series), !online.isEmpty {
            warnings[series] = nil
            if let url = cacheURL(for: series) {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(SavedCalendar(fetchedAt: .now, events: online))
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                } catch {
                    warnings[series] = "Live \(series.title) calendar loaded, but its offline copy could not be saved."
                }
            }
            return online
        }

        if let url = cacheURL(for: series),
           let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let saved = try? decoder.decode(SavedCalendar.self, from: data),
               !saved.events.isEmpty, saved.events.allSatisfy({ $0.series == series }) {
                warnings[series] = "Using saved \(series.title) calendar from \(saved.fetchedAt.formatted(date: .abbreviated, time: .omitted)); live update unavailable."
                return saved.events
            }
        }
        warnings[series] = "Using bundled \(series.title) calendar; live update unavailable."
        return try await fallback.events(for: series)
    }

    func allEvents() async throws -> [RaceEvent] {
        async let formula1 = events(for: .formula1)
        async let motoGP = events(for: .motoGP)
        return try await (formula1 + motoGP).sorted { $0.raceDate < $1.raceDate }
    }

    func freshnessWarning() async -> String? {
        let messages = RaceSeries.allCases.compactMap { warnings[$0] }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private func cacheURL(for series: RaceSeries) -> URL? {
        cacheDirectoryURL?.appendingPathComponent("\(series.rawValue)-v1.json")
    }
}

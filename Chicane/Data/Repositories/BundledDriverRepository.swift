import Foundation

struct BundledDriverRepository: DriverRepository {
    private struct DriverPayload: Codable {
        let drivers: [Driver]
    }

    private let loader: BundleJSONLoader

    init(loader: BundleJSONLoader = BundleJSONLoader()) {
        self.loader = loader
    }

    func drivers(for series: RaceSeries) async throws -> [Driver] {
        let payload = try loader.decode(DriverPayload.self, fileName: "drivers")
        return payload.drivers
            .filter { $0.series == series }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

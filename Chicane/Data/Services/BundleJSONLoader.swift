import Foundation

struct BundleJSONLoader: Sendable {
    var bundle: Bundle = .main

    func decode<T: Decodable>(_ type: T.Type, fileName: String) throws -> T {
        guard let url = bundle.url(forResource: fileName, withExtension: "json") else {
            throw RepositoryError.missingBundleResource(name: fileName + ".json")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

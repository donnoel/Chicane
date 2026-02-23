import Foundation

// MARK: - Protocol

protocol NewsRepository: Sendable {
    func articles(for series: RaceSeries) async throws -> [NewsArticle]
}

// MARK: - RSS implementation

/// Fetches the most recent articles from Motorsport.com's public RSS feeds.
/// Falls back gracefully — a fetch failure for one series never blocks the other.
struct RSSNewsRepository: NewsRepository, Sendable {
    private let client: RemoteDataClient

    init(client: RemoteDataClient = RemoteDataClient()) {
        self.client = client
    }

    private func feedURL(for series: RaceSeries) -> URL {
        switch series {
        case .formula1:
            // Motorsport.com F1 news RSS — public, no auth required
            return URL(string: "https://www.motorsport.com/rss/f1/news/")!
        case .motoGP:
            return URL(string: "https://www.motorsport.com/rss/motogp/news/")!
        }
    }

    func articles(for series: RaceSeries) async throws -> [NewsArticle] {
        let url  = feedURL(for: series)
        let data = try await client.fetchData(from: url)
        let raw  = RSSParser.parse(data: data)

        return raw.compactMap { item -> NewsArticle? in
            guard
                let articleURL = URL(string: item.link),
                !item.title.isEmpty
            else { return nil }

            let imageURL = item.imageURL.flatMap { URL(string: $0) }

            return NewsArticle(
                id: item.link,
                series: series,
                title: item.title,
                description: item.description,
                url: articleURL,
                publishedAt: RSSParser.parseDate(item.pubDate),
                imageURL: imageURL
            )
        }
        // Most-recent first
        .sorted { $0.publishedAt > $1.publishedAt }
    }
}

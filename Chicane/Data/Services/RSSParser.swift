import Foundation

/// Parses a standard RSS 2.0 feed into `RawRSSItem` values.
/// Each item maps to a potential `NewsArticle` — filtering and enrichment
/// happen in the repository layer.
struct RawRSSItem {
    let title: String
    let description: String
    let link: String
    let pubDate: String
    let imageURL: String?
}

final class RSSParser: NSObject, XMLParserDelegate {

    // MARK: - Public API

    static func parse(data: Data) -> [RawRSSItem] {
        let parser = RSSParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.items
    }

    // MARK: - Private state

    private var items: [RawRSSItem] = []

    // Current item being built
    private var currentTitle       = ""
    private var currentDescription = ""
    private var currentLink        = ""
    private var currentPubDate     = ""
    private var currentImageURL: String?
    private var currentElement     = ""
    private var insideItem         = false
    private var buffer             = ""

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        buffer = ""

        if elementName == "item" {
            insideItem = true
            currentTitle       = ""
            currentDescription = ""
            currentLink        = ""
            currentPubDate     = ""
            currentImageURL    = nil
        }

        // <enclosure url="..." type="image/jpeg"/>  or  <media:content url="..."/>
        if insideItem {
            let url = attributeDict["url"] ?? attributeDict["URL"]
            if elementName == "enclosure", let url, attributeDict["type"]?.hasPrefix("image") == true {
                currentImageURL = url
            }
            if elementName == "media:content" || elementName == "media:thumbnail",
               let url, currentImageURL == nil {
                currentImageURL = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser,
                foundCDATA CDATABlock: Data) {
        guard insideItem, let text = String(data: CDATABlock, encoding: .utf8) else { return }
        buffer += text
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        guard insideItem else {
            if elementName == "item" { insideItem = false }
            return
        }

        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "title":
            currentTitle = value
        case "description":
            // Strip basic HTML tags from the description snippet
            currentDescription = value
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case "link":
            if currentLink.isEmpty { currentLink = value }
        case "pubDate", "dc:date", "published":
            currentPubDate = value
        case "item":
            let item = RawRSSItem(
                title: currentTitle,
                description: currentDescription,
                link: currentLink,
                pubDate: currentPubDate,
                imageURL: currentImageURL
            )
            if !item.link.isEmpty, !item.title.isEmpty {
                items.append(item)
            }
            insideItem = false
        default:
            break
        }

        buffer = ""
    }
}

// MARK: - Date parsing helpers

extension RSSParser {
    /// RFC 822 dates used by RSS 2.0, e.g. "Mon, 10 Jun 2024 12:00:00 +0000"
    static let rfc822Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    static let rfc822ShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    /// ISO 8601 dates used by Atom feeds
    static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601BasicFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String) -> Date {
        if let d = rfc822Formatter.date(from: string) { return d }
        if let d = rfc822ShortFormatter.date(from: string) { return d }
        if let d = iso8601Formatter.date(from: string) { return d }
        if let d = iso8601BasicFormatter.date(from: string) { return d }
        return Date()
    }
}

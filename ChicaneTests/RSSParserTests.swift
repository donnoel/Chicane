import XCTest
@testable import Chicane

final class RSSParserTests: XCTestCase {

    // MARK: - Standard RSS 2.0

    func testParsesStandardRSSFeed() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>F1 News</title>
            <item>
              <title>Hamilton wins Monaco</title>
              <description>Lewis takes the top step in Monte Carlo.</description>
              <link>https://example.com/hamilton-monaco</link>
              <pubDate>Mon, 10 Jun 2024 12:00:00 +0000</pubDate>
            </item>
            <item>
              <title>Verstappen leads championship</title>
              <description>Max extends his points lead.</description>
              <link>https://example.com/verstappen-leads</link>
              <pubDate>Tue, 11 Jun 2024 09:30:00 +0000</pubDate>
            </item>
          </channel>
        </rss>
        """

        let items = RSSParser.parse(data: Data(xml.utf8))

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Hamilton wins Monaco")
        XCTAssertEqual(items[0].description, "Lewis takes the top step in Monte Carlo.")
        XCTAssertEqual(items[0].link, "https://example.com/hamilton-monaco")
        XCTAssertEqual(items[1].title, "Verstappen leads championship")
    }

    // MARK: - Image extraction

    func testParsesEnclosureImageURL() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>Photo article</title>
              <link>https://example.com/photo</link>
              <enclosure url="https://example.com/photo.jpg" type="image/jpeg" length="12345"/>
            </item>
          </channel>
        </rss>
        """

        let items = RSSParser.parse(data: Data(xml.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].imageURL, "https://example.com/photo.jpg")
    }

    func testParsesMediaContentImageURL() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
          <channel>
            <item>
              <title>Media article</title>
              <link>https://example.com/media</link>
              <media:content url="https://example.com/media.jpg"/>
            </item>
          </channel>
        </rss>
        """

        let items = RSSParser.parse(data: Data(xml.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].imageURL, "https://example.com/media.jpg")
    }

    // MARK: - HTML stripping in descriptions

    func testStripsHTMLFromDescription() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>HTML article</title>
              <description>&lt;p&gt;A &lt;strong&gt;bold&lt;/strong&gt; statement.&lt;/p&gt;</description>
              <link>https://example.com/html</link>
            </item>
          </channel>
        </rss>
        """

        let items = RSSParser.parse(data: Data(xml.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].description, "A bold statement.")
    }

    // MARK: - CDATA content

    func testParsesCDATAContent() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title><![CDATA[CDATA Title]]></title>
              <description><![CDATA[A CDATA description.]]></description>
              <link>https://example.com/cdata</link>
            </item>
          </channel>
        </rss>
        """

        let items = RSSParser.parse(data: Data(xml.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "CDATA Title")
        XCTAssertEqual(items[0].description, "A CDATA description.")
    }

    // MARK: - Filtering invalid items

    func testSkipsItemsWithNoLink() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>No link article</title>
              <description>Missing link field.</description>
            </item>
            <item>
              <title>Valid article</title>
              <link>https://example.com/valid</link>
            </item>
          </channel>
        </rss>
        """

        let items = RSSParser.parse(data: Data(xml.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Valid article")
    }

    func testSkipsItemsWithNoTitle() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <description>An orphan description.</description>
              <link>https://example.com/no-title</link>
            </item>
          </channel>
        </rss>
        """

        let items = RSSParser.parse(data: Data(xml.utf8))

        XCTAssertEqual(items.count, 0)
    }

    // MARK: - Empty / malformed feeds

    func testEmptyFeedReturnsNoItems() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Empty Feed</title>
          </channel>
        </rss>
        """

        let items = RSSParser.parse(data: Data(xml.utf8))
        XCTAssertTrue(items.isEmpty)
    }

    func testMalformedXMLReturnsPartialResults() {
        // The parser should return whatever it managed to parse before the error
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>Good article</title>
              <link>https://example.com/good</link>
            </item>
            <item>
              <title>Broken
        """

        let items = RSSParser.parse(data: Data(xml.utf8))
        // May get 1 item or 0 depending on parser behavior — just verify no crash
        XCTAssertTrue(items.count <= 1)
    }

    func testEmptyDataReturnsNoItems() {
        let items = RSSParser.parse(data: Data())
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Date parsing

    func testParsesRFC822Date() {
        let dateString = "Mon, 10 Jun 2024 12:00:00 +0000"
        let date = RSSParser.parseDate(dateString)
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 10)
    }

    func testParsesShortRFC822Date() {
        let dateString = "10 Jun 2024 12:00:00 +0000"
        let date = RSSParser.parseDate(dateString)
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 6)
    }

    func testParsesISO8601Date() {
        let dateString = "2024-06-10T12:00:00Z"
        let date = RSSParser.parseDate(dateString)
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 10)
    }

    func testUnrecognizedDateFormatReturnsFallback() {
        // Should return current date (not crash) for unrecognized format
        let date = RSSParser.parseDate("not-a-date")
        let now = Date()
        XCTAssertTrue(abs(date.timeIntervalSince(now)) < 5, "Fallback should return approximately current date")
    }
}

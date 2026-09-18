import Foundation

enum FeedParseError: Error, Equatable {
    /// Well-formed XML (or HTML) that isn't a podcast feed — usually a show's
    /// web page, pasted instead of its feed.
    case notAFeed
    case malformedXML(line: Int, column: Int)
}

/// Reads an RSS podcast feed with Foundation's `XMLParser`.
///
/// Takes `Data`, never `String`: `XMLParser` honours the encoding declared in
/// the XML prolog, and feeds in the wild are not all UTF-8. Decoding to a
/// `String` first would guess, and guess wrong.
enum FeedParser {

    /// Parses a feed, keeping the `maxEpisodes` newest episodes.
    ///
    /// Synchronous and CPU-bound; callers on the main actor should hand it off
    /// (see `FeedLoader`). Nothing is shared — the delegate is created, used and
    /// destroyed inside this call — so only Sendable values cross the boundary.
    static func parse(_ data: Data, maxEpisodes: Int = 300) throws -> ParsedFeed {
        let delegate = FeedParserDelegate()
        let parser = XMLParser(data: data)
        // Feeds routinely use the `itunes:` prefix without declaring it, which
        // makes a namespace-aware parse fail outright rather than degrade. So
        // namespaces stay off and elements are matched by qualified name.
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate

        let finished = parser.parse()
        guard delegate.sawChannel else { throw FeedParseError.notAFeed }
        guard finished else {
            throw FeedParseError.malformedXML(
                line: parser.lineNumber,
                column: parser.columnNumber
            )
        }

        var feed = delegate.feed
        // Feeds are usually newest-first but nothing guarantees it, so sort
        // before truncating or we'd keep the wrong end of a long archive.
        feed.episodes = Array(
            delegate.episodes
                .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
                .prefix(maxEpisodes)
        )
        return feed
    }
}

/// Collects channel and item values as the parser streams past them.
///
/// The element stack is kept as lowercased qualified names ("itunes:image"),
/// which is what lets `<image><url>` be told apart from an item's `<url>`.
private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    private(set) var feed = ParsedFeed()
    private(set) var episodes: [ParsedEpisode] = []
    private(set) var sawChannel = false

    private var path: [String] = []
    private var text = ""

    // Channel-level candidates, resolved at the end of `</channel>` so that
    // precedence doesn't depend on the order elements happen to appear in.
    private var channelDescription = ""
    private var channelITunesSummary = ""
    private var channelContentEncoded = ""
    private var channelITunesAuthor = ""
    private var channelManagingEditor = ""
    private var channelAuthor = ""
    private var channelITunesImage: String?
    private var channelRSSImage: String?

    private var item: ItemDraft?

    private struct ItemDraft {
        var guid = ""
        var title = ""
        var description = ""
        var itunesSummary = ""
        var contentEncoded = ""
        var rawPubDate = ""
        var rawDuration = ""
        var audioURL = ""
        var audioMIMEType: String?
        var audioByteCount: Int?
        var artworkURL: String?
        var pageURL: String?
    }

    private var inItem: Bool { item != nil }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let name = (qualifiedName ?? elementName).lowercased()
        path.append(name)
        text = ""

        switch name {
        case "channel":
            sawChannel = true
        case "item":
            if !inItem { item = ItemDraft() }
        case "enclosure":
            guard var draft = item, let url = attributes["url"], !url.isEmpty else { break }
            draft.audioURL = url
            draft.audioMIMEType = attributes["type"]
            draft.audioByteCount = attributes["length"].flatMap(Int.init)
            item = draft
        case "itunes:image":
            guard let href = attributes["href"] ?? attributes["url"], !href.isEmpty else { break }
            if var draft = item {
                draft.artworkURL = href
                item = draft
            } else {
                channelITunesImage = href
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    /// Descriptions are almost always CDATA, and `XMLParser` delivers those
    /// here and nowhere else. Without this every summary would come out empty.
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = (qualifiedName ?? elementName).lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            if !path.isEmpty { path.removeLast() }
            text = ""
        }

        if inItem {
            endItemElement(name, value)
        } else {
            endChannelElement(name, value)
        }
    }

    private func endItemElement(_ name: String, _ value: String) {
        guard var draft = item else { return }
        switch name {
        case "item":
            finish(draft)
            item = nil
            return
        case "title": draft.title = value
        case "description": draft.description = value
        case "itunes:summary": draft.itunesSummary = value
        case "content:encoded": draft.contentEncoded = value
        case "pubdate": draft.rawPubDate = value
        case "itunes:duration": draft.rawDuration = value
        case "guid": draft.guid = value
        case "link": if draft.pageURL == nil { draft.pageURL = value.isEmpty ? nil : value }
        default: break
        }
        item = draft
    }

    private func endChannelElement(_ name: String, _ value: String) {
        switch name {
        case "title":
            // Only the channel's own title; `<image><title>` repeats it.
            if path.suffix(2).first == "channel", feed.title.isEmpty { feed.title = value }
        case "description": channelDescription = value
        case "itunes:summary": channelITunesSummary = value
        case "content:encoded": channelContentEncoded = value
        case "itunes:author": channelITunesAuthor = value
        case "managingeditor": channelManagingEditor = value
        case "author": channelAuthor = value
        case "language": feed.language = value.isEmpty ? nil : value
        case "itunes:new-feed-url": feed.newFeedURL = value.isEmpty ? nil : value
        case "link":
            if path.suffix(2).first == "channel", feed.websiteURL == nil, !value.isEmpty {
                feed.websiteURL = value
            }
        case "url":
            // `<image><url>` — the RSS-native artwork, used only as a fallback.
            if path.suffix(2).first == "image", channelRSSImage == nil, !value.isEmpty {
                channelRSSImage = value
            }
        case "channel":
            resolveChannel()
        default:
            break
        }
    }

    private func resolveChannel() {
        feed.summary = [channelDescription, channelITunesSummary, channelContentEncoded]
            .first { !$0.isEmpty } ?? ""
        feed.author = [channelITunesAuthor, channelManagingEditor, channelAuthor]
            .first { !$0.isEmpty } ?? ""
        // `itunes:image` is the square 1400–3000px artwork; `<image>` is the
        // older, smaller one, so it only fills in when iTunes art is absent.
        feed.artworkURL = channelITunesImage ?? channelRSSImage
    }

    private func finish(_ draft: ItemDraft) {
        // An item with no enclosure can never be played, so it is not an
        // episode. `media:content` is not read; such items are dropped too.
        guard !draft.audioURL.isEmpty else { return }

        var episode = ParsedEpisode()
        episode.title = draft.title
        episode.summary = [draft.description, draft.itunesSummary, draft.contentEncoded]
            .first { !$0.isEmpty } ?? ""
        episode.publishedAt = draft.rawPubDate.isEmpty ? nil : RSSDate.parse(draft.rawPubDate)
        episode.audioURL = draft.audioURL
        episode.audioMIMEType = draft.audioMIMEType
        episode.audioByteCount = draft.audioByteCount
        episode.duration = draft.rawDuration.isEmpty
            ? nil
            : EpisodeDuration.seconds(from: draft.rawDuration)
        episode.artworkURL = draft.artworkURL
        episode.pageURL = draft.pageURL
        // Identity must survive a refresh, so fall back until something sticks.
        episode.guid = [draft.guid, draft.audioURL, draft.pageURL ?? ""]
            .first { !$0.isEmpty } ?? "\(draft.title)|\(draft.rawPubDate)"

        episodes.append(episode)
    }
}

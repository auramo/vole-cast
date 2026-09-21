import Foundation

/// Show notes are HTML. Rendering them properly is a later job; for now they
/// are flattened to readable plain text.
///
/// Hand-rolled rather than `NSAttributedString(html:)`, which must run on the
/// main thread and is far too slow to call per row in a list.
enum HTMLText {

    static func plain(from html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return html }

        var text = ""
        let characters = Array(html)
        var index = 0

        while index < characters.count {
            guard let tag = tag(in: characters, startingAt: index) else {
                text.append(characters[index])
                index += 1
                continue
            }
            // Block-level tags are where line breaks belong.
            if ["br", "br/", "/p", "/div", "/li", "/h1", "/h2", "/h3"].contains(tag.name) {
                text += "\n"
            }
            index = tag.end + 1
        }

        return decodeEntities(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The tag starting at `index`, or nil when that `<` is ordinary text.
    ///
    /// `5 < 10`, `<3` and `a <- b` are all common in show notes, so a `<` only
    /// opens a tag when what follows could begin one. An opener that never
    /// closes swallows the rest, as a browser does — but a second `<` before
    /// any `>` means the first was text after all.
    private static func tag(
        in characters: [Character],
        startingAt index: Int
    ) -> (end: Int, name: String)? {
        guard characters[index] == "<", index + 1 < characters.count else { return nil }
        let first = characters[index + 1]
        guard first.isLetter || first == "/" || first == "!" || first == "?" else { return nil }

        var name = ""
        var scan = index + 1
        while scan < characters.count, characters[scan] != ">" {
            guard characters[scan] != "<" else { return nil }
            if !characters[scan].isWhitespace { name.append(characters[scan]) }
            scan += 1
        }
        return (end: scan, name: name.lowercased())
    }

    /// Ordered, not a `Dictionary`: replacements feed each other, and Swift
    /// randomises dictionary order per process, so the same notes decoded
    /// differently from launch to launch. `&amp;` has to resolve last — ahead of
    /// the others it manufactures entities for them to decode a second time,
    /// turning `&amp;nbsp;` into a space instead of the literal `&nbsp;`.
    private static let entities: [(String, String)] = [
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&hellip;", "…"),
        ("&mdash;", "—"), ("&ndash;", "–"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
        ("&ldquo;", "“"), ("&rdquo;", "”"),
        ("&amp;", "&"),
    ]

    private static func decodeEntities(_ text: String) -> String {
        entities.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

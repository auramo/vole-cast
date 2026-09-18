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
        var insideTag = false
        var tagName = ""

        for character in html {
            switch character {
            case "<":
                insideTag = true
                tagName = ""
            case ">":
                insideTag = false
                // Block-level tags are where line breaks belong.
                if ["br", "br/", "/p", "/div", "/li", "/h1", "/h2", "/h3"].contains(tagName.lowercased()) {
                    text += "\n"
                }
            default:
                if insideTag {
                    if !character.isWhitespace { tagName.append(character) }
                } else {
                    text.append(character)
                }
            }
        }

        return decodeEntities(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        var text = text
        let named = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&hellip;": "…",
            "&mdash;": "—", "&ndash;": "–", "&rsquo;": "’", "&lsquo;": "‘",
            "&ldquo;": "“", "&rdquo;": "”",
        ]
        for (entity, replacement) in named {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
    }
}

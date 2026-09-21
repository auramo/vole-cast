import Testing
@testable import VoleCast

struct HTMLTextTests {

    @Test func stripsTags() {
        #expect(HTMLText.plain(from: "<p>Hello <strong>there</strong></p>") == "Hello there")
    }

    @Test func turnsBlockTagsIntoLineBreaks() {
        let notes = "<p>First paragraph</p><p>Second paragraph</p>"
        #expect(HTMLText.plain(from: notes) == "First paragraph\nSecond paragraph")
    }

    @Test func decodesEntities() {
        #expect(HTMLText.plain(from: "Tom &amp; Jerry &#39;n&#39; friends") == "Tom & Jerry 'n' friends")
        #expect(HTMLText.plain(from: "a&nbsp;b") == "a b")
    }

    @Test func dropsLinkMarkupButKeepsItsText() {
        #expect(HTMLText.plain(from: #"See <a href="https://x.example">the site</a>."#) == "See the site.")
    }

    @Test func leavesPlainTextAlone() {
        #expect(HTMLText.plain(from: "Just a sentence.") == "Just a sentence.")
        #expect(HTMLText.plain(from: "") == "")
    }

    /// An unescaped `<` is ordinary in show notes, and treating it as the start
    /// of a tag swallowed everything after it.
    @Test func keepsTextAfterABareLessThan() {
        #expect(
            HTMLText.plain(from: "Is 5 < 10? Yes, and here is the rest.")
                == "Is 5 < 10? Yes, and here is the rest."
        )
        #expect(HTMLText.plain(from: "Hearts <3 and <- arrows") == "Hearts <3 and <- arrows")
    }

    /// A tag that never closes is dropped, as a browser would, but it must not
    /// take the text in front of it along.
    @Test func keepsTextBeforeAnUnclosedTag() {
        #expect(HTMLText.plain(from: "Real notes <b unterminated") == "Real notes")
    }

    /// The decoder ran over a `Dictionary`, whose order Swift randomises per
    /// process, so a doubly-encoded entity decoded differently run to run.
    /// `&amp;` has to resolve last or it manufactures entities for later passes.
    @Test func decodesEachEntityExactlyOnce() {
        #expect(HTMLText.plain(from: "&amp;nbsp;") == "&nbsp;")
        #expect(HTMLText.plain(from: "&amp;lt;b&amp;gt;") == "&lt;b&gt;")
        #expect(HTMLText.plain(from: "Tom &amp;amp; Jerry") == "Tom &amp; Jerry")
    }
}

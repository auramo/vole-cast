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
}

import Foundation
import SwiftUI

/// Search-field state: what was typed, what came back, and what went wrong.
@MainActor
@Observable
final class SearchModel {
    enum State: Equatable {
        case idle
        case searching
        case results([PodcastSearchResult])
        case empty
        case failed(NetworkError)
    }

    var query: String = ""
    private(set) var state: State = .idle

    private let directory: any PodcastDirectory
    /// Long enough that a fast typist makes one request, short enough not to
    /// feel laggy. Injected so tests don't wait on wall-clock time.
    private let debounce: Duration

    init(directory: any PodcastDirectory, debounce: Duration = .milliseconds(350)) {
        self.directory = directory
        self.debounce = debounce
    }

    /// A feed URL typed or pasted into the search field, if that's what it is.
    var typedFeedURL: URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(".") || trimmed.contains("://") else { return nil }
        return FeedURL.normalize(trimmed)
    }

    /// Runs a search. Intended to be driven by `.task(id:)`, which cancels and
    /// restarts this on every keystroke — that's what makes the sleep below a
    /// debounce rather than a delay.
    /// Whether the text is plainly a URL rather than something that merely
    /// parses as one.
    ///
    /// A scheme or a path says so; a bare dotted word does not. "ev.news" is a
    /// real show name and normalises to a perfectly good host, so looking like
    /// a URL cannot be the test — only looking like nothing else.
    private static func isPlainlyAURL(_ text: String) -> Bool {
        guard FeedURL.normalize(text) != nil else { return false }
        return text.contains("://") || text.contains("/")
    }

    func search(_ raw: String) async {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            state = .idle
            return
        }

        // A feed URL is not a show name. Asking the directory to find a show
        // called "https://feeds.npr.org/510289/podcast.xml" can only come back
        // empty, and that emptiness replaced the one row that could actually
        // open it. Idle is what the view draws the Open feed row in.
        //
        // It must not be sent at all, either: a private feed from Patreon or
        // Supercast carries a per-user token in its query string, and a search
        // would hand that to Apple.
        guard !Self.isPlainlyAURL(term) else {
            state = .idle
            return
        }

        do {
            try await Task.sleep(for: debounce)
        } catch {
            return // Superseded by a newer keystroke.
        }

        state = .searching
        do {
            let results = try await directory.search(term: term, limit: 25)
            try Task.checkCancellation()
            state = results.isEmpty ? .empty : .results(results)
        } catch is CancellationError {
            // A newer search is already running; leave its state alone.
        } catch {
            state = .failed(NetworkError(from: error))
        }
    }
}

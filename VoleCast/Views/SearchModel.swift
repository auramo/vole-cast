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
    func search(_ raw: String) async {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
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

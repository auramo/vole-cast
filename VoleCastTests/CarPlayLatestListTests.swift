import Testing
import Foundation
import SwiftData
@testable import VoleCast

/// The rules behind the car's list, tested without the CarPlay framework —
/// the rows are values, so none of this needs a car or a template.
@Suite(.serialized)
@MainActor
struct CarPlayLatestListTests {

    /// Its own container per test, like `PlayerRestoreTests`.
    private func makeEpisode(
        _ context: ModelContext,
        guid: String,
        title: String,
        duration: Double? = 2520
    ) -> Episode {
        let show = Podcast(feedURL: "https://c.example.com/feed", feedIdentity: "c", title: "Show")
        context.insert(show)
        let episode = Episode(guid: guid, title: title, audioURL: "https://c.example.com/\(guid).mp3")
        // Left nil deliberately: a relative date ("3 days ago") is not a
        // deterministic string to assert on.
        episode.publishedAt = nil
        episode.duration = duration
        episode.podcast = show
        context.insert(episode)
        return episode
    }

    @Test func aRowCarriesTheTitleAndTheSharedSubtitle() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "c1", title: "Episode One")

        let rows = CarPlayLatestList.rows(for: [episode], current: nil)

        #expect(rows.count == 1)
        #expect(rows.first?.title == "Episode One")
        // The show, then the same line the phone shows from `EpisodeSubtitle`.
        // Asserted by shape rather than by the exact duration: how "42m" is
        // written is that type's business, and it is written differently in
        // every language. `EpisodeSubtitleTests` pins the wording.
        #expect(rows.first?.subtitle.hasPrefix("Show · ") == true)
    }

    /// Two lines is all a `CPListItem` has, where the phone's row has three.
    /// The show name has to share the second one, or the car lists a column of
    /// episode titles with no clue which show any of them belongs to.
    @Test func aRowNamesTheShowItBelongsTo() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "c1", title: "Episode One")

        let rows = CarPlayLatestList.rows(for: [episode], current: nil)

        #expect(rows.first?.subtitle.hasPrefix("Show · ") == true)
    }

    /// An orphan has no show to name, and must not be given a stray separator.
    @Test func aRowWithoutAShowSaysOnlyWhatItKnows() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = Episode(guid: "c9", title: "Orphan", audioURL: "https://c.example.com/c9.mp3")
        episode.duration = 2520
        context.insert(episode)

        let rows = CarPlayLatestList.rows(for: [episode], current: nil)

        // One part and no separator: nothing was named that it does not know.
        #expect(rows.first?.subtitle.contains("·") == false)
        #expect(rows.first?.subtitle.isEmpty == false)
    }

    @Test func marksTheLoadedEpisodeAndNoOther() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let first = makeEpisode(context, guid: "c1", title: "One")
        let second = makeEpisode(context, guid: "c2", title: "Two")

        let rows = CarPlayLatestList.rows(
            for: [first, second],
            current: second.persistentModelID
        )

        #expect(rows.map(\.isPlaying) == [false, true])
    }

    @Test func marksNothingWhenThePlayerIsEmpty() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "c1", title: "One")

        let rows = CarPlayLatestList.rows(for: [episode], current: nil)

        #expect(rows.allSatisfy { !$0.isPlaying })
    }

    @Test func anEmptyStoreMakesAnEmptyList() {
        #expect(CarPlayLatestList.rows(for: [], current: nil).isEmpty)
    }

    @Test func selectingAnotherEpisodePlaysIt() {
        #expect(
            CarPlayLatestList.selection(isCurrent: false, isPlaying: false) == .playThenShowPlayer
        )
    }

    /// The one that would be easy to get wrong. Tapping the episode already
    /// playing must take the driver to the player — not restart it from zero,
    /// and not pause it, which is what reusing `toggle` would do.
    @Test func selectingTheEpisodeAlreadyPlayingOnlyOpensThePlayer() {
        #expect(CarPlayLatestList.selection(isCurrent: true, isPlaying: true) == .showPlayer)
    }

    /// The Continue row's whole purpose. The episode is loaded but paused —
    /// carried over from the phone — and tapping it means carry on, from where
    /// it was left.
    @Test func selectingTheLoadedButPausedEpisodeResumesIt() {
        #expect(
            CarPlayLatestList.selection(isCurrent: true, isPlaying: false) == .resumeThenShowPlayer
        )
    }

    // MARK: - Sections

    /// CarPlay offers no route to the player from a list, and the system's own
    /// now-playing screen stays empty until the app owns the audio session —
    /// which a restored episode never has. So the episode has to appear in the
    /// one place the app controls: a row of its own, above the rest.
    @Test func theCurrentEpisodeGetsASectionOfItsOwn() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let playing = makeEpisode(context, guid: "c1", title: "Carried Over")
        let other = makeEpisode(context, guid: "c2", title: "Something Else")

        let sections = CarPlayLatestList.sections(
            current: playing,
            at: 842,
            latest: [other]
        )

        #expect(sections.count == 2)
        #expect(sections.first?.title == "Continue")
        #expect(sections.first?.rows.map(\.title) == ["Carried Over"])
        #expect(sections.first?.rows.first?.isPlaying == true)
        #expect(sections.last?.title == "Latest")
        #expect(sections.last?.rows.map(\.title) == ["Something Else"])
    }

    /// Where it was left, so the driver knows what they are returning to.
    @Test func theContinueRowSaysWhereTheEpisodeWasLeft() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let playing = makeEpisode(context, guid: "c1", title: "Carried Over")

        let sections = CarPlayLatestList.sections(current: playing, at: 842, latest: [])

        #expect(sections.first?.rows.first?.subtitle.hasPrefix("Show · ") == true)
        #expect(sections.first?.rows.first?.subtitle.hasSuffix(" · 14:02") == true)
    }

    /// Barely started is not worth a reading, and "0:00" would be noise.
    @Test func theContinueRowOmitsAPositionAtTheVeryStart() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let playing = makeEpisode(context, guid: "c1", title: "Carried Over")

        let sections = CarPlayLatestList.sections(current: playing, at: 0, latest: [])

        // A clock is the only part with a colon in it, in any language.
        #expect(sections.first?.rows.first?.subtitle.contains(":") == false)
    }

    /// One episode, one row. The same episode in both sections would be two
    /// things to read and two places to tap for one outcome.
    @Test func theCurrentEpisodeIsNotListedTwice() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let playing = makeEpisode(context, guid: "c1", title: "Carried Over")
        let other = makeEpisode(context, guid: "c2", title: "Something Else")

        let sections = CarPlayLatestList.sections(
            current: playing,
            at: 842,
            latest: [playing, other]
        )

        #expect(sections.last?.rows.map(\.title) == ["Something Else"])
    }

    /// Nothing played yet: one section, with no Continue heading announcing a
    /// player that does not exist. It keeps its own title — the template above
    /// it has none, so this is the only thing naming the list.
    @Test func withNothingPlayingThereIsJustTheList() {
        let context = ModelContext(VoleCastModelContainer.makeInMemory())
        let episode = makeEpisode(context, guid: "c1", title: "One")

        let sections = CarPlayLatestList.sections(current: nil, at: 0, latest: [episode])

        #expect(sections.count == 1)
        #expect(sections.first?.title == "Latest")
        #expect(sections.first?.rows.map(\.title) == ["One"])
    }
}

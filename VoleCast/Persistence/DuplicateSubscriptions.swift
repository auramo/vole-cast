import Foundation
import SwiftData

/// Folding away two copies of one show.
///
/// Sync can leave them. `Subscriptions.subscribe` refuses a second
/// subscription by looking for the feed identity first, which is airtight on
/// one device and not at all airtight across two: both can look, both can find
/// nothing, and both can insert. It needs two subscriptions to the same show
/// before either device syncs, so it is rare — but a show listed twice, with
/// its episodes doubled and its progress split between the copies, is the kind
/// of wrong that makes someone distrust everything else the app says.
///
/// Run at launch rather than on every remote change: the window that creates a
/// duplicate is narrow, and a pass over the subscriptions is cheap next to
/// opening the store at all.
@MainActor
enum DuplicateSubscriptions {

    /// One episode's playback state, apart from the store so the rule for
    /// combining two of them can be checked on its own.
    struct PlaybackState: Equatable {
        var position: Double
        var isPlayed: Bool
        var lastPlayedAt: Date?
    }

    /// The two copies, reconciled.
    ///
    /// Finished wins over part-played, and takes the position to zero with it.
    /// That is not arbitrary: `PlaybackProgress.markPlayed` zeroes them
    /// together so the two fields cannot contradict each other, and keeping
    /// the furthest position here would produce exactly the contradiction it
    /// avoids — an episode both finished and fourteen minutes in.
    ///
    /// Otherwise the furthest position wins, because the alternative is
    /// telling someone to listen again to something they have already heard.
    static func merging(_ a: PlaybackState, _ b: PlaybackState) -> PlaybackState {
        let played = a.isPlayed || b.isPlayed
        return PlaybackState(
            position: played ? 0 : max(a.position, b.position),
            isPlayed: played,
            // The later stamp, so the show keeps its place in History rather
            // than sinking to where the staler copy had it.
            lastPlayedAt: [a.lastPlayedAt, b.lastPlayedAt].compactMap { $0 }.max()
        )
    }

    /// Folds every duplicated subscription into one.
    ///
    /// Returns how many copies were removed, which is nothing the app shows —
    /// it is there so a test can say "and nothing happened" about the ordinary
    /// case rather than inferring it.
    @discardableResult
    static func merge(in context: ModelContext) -> Int {
        let podcasts = (try? context.fetch(FetchDescriptor<Podcast>())) ?? []
        let byIdentity = Dictionary(grouping: podcasts, by: \.feedIdentity)

        var removed = 0
        for (_, copies) in byIdentity where copies.count > 1 {
            // The oldest subscription keeps the show: it is the one whose
            // identifier other devices have most likely already seen, and
            // `subscribedAt` is the only ordering here that is stable.
            let sorted = copies.sorted { $0.subscribedAt < $1.subscribedAt }
            guard let keeper = sorted.first else { continue }

            for loser in sorted.dropFirst() {
                absorb(loser, into: keeper, in: context)
                context.delete(loser)
                removed += 1
            }
        }

        // Saved here rather than left to autosave: this runs at launch, and
        // folding two shows into one is the kind of structural change that
        // should not be lost if the app is closed in the next second. Only
        // when something changed, so the ordinary launch writes nothing.
        if removed > 0 { try? context.save() }
        return removed
    }

    /// Moves what the loser knows into the keeper.
    ///
    /// An episode the keeper already has is reconciled and left behind, to be
    /// swept away by the cascade when the loser goes. One it does not have is
    /// moved across — the two copies can have refreshed at different times, so
    /// the loser may hold episodes that are genuinely missing from the keeper.
    private static func absorb(_ loser: Podcast, into keeper: Podcast, in context: ModelContext) {
        let existing = Dictionary(
            (keeper.episodes ?? []).map { ($0.guid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for episode in loser.episodes ?? [] {
            guard let twin = existing[episode.guid] else {
                episode.podcast = keeper
                continue
            }
            let merged = merging(
                PlaybackState(
                    position: twin.playbackPosition,
                    isPlayed: twin.isPlayed,
                    lastPlayedAt: twin.lastPlayedAt
                ),
                PlaybackState(
                    position: episode.playbackPosition,
                    isPlayed: episode.isPlayed,
                    lastPlayedAt: episode.lastPlayedAt
                )
            )
            twin.playbackPosition = merged.position
            twin.isPlayed = merged.isPlayed
            twin.lastPlayedAt = merged.lastPlayedAt
        }

        // The keeper should look as refreshed as the better-refreshed copy.
        if let theirs = loser.lastEpisodeAt,
           keeper.lastEpisodeAt == nil || theirs > keeper.lastEpisodeAt! {
            keeper.lastEpisodeAt = theirs
        }
        if keeper.itunesCollectionID == nil {
            keeper.itunesCollectionID = loser.itunesCollectionID
        }
    }
}

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

    /// Folds every episode the show holds more than once into one copy.
    ///
    /// Sync delivers these on its own, no double subscription needed: a device
    /// that receives a show and refreshes it before the show's episodes have
    /// finished arriving finds none to match against, makes its own copy of
    /// every one, and sends them all back. One phone ended up with 5,693
    /// episodes twice over and the Latest list showing each one twice.
    ///
    /// The oldest copy is kept, and an unstamped one counts as oldest. That has
    /// to be a rule every device reaches by itself: each folds the same pair
    /// independently, and two devices keeping different copies would each
    /// delete the other's keeper and lose the episode everywhere.
    ///
    /// Takes one show because the caller is a refresh, which has its episodes
    /// in hand already. Returns how many copies were removed.
    @discardableResult
    static func foldEpisodes(of podcast: Podcast, in context: ModelContext) -> Int {
        let byGUID = Dictionary(grouping: podcast.episodes ?? [], by: \.guid)

        var removed = 0
        for (_, copies) in byGUID where copies.count > 1 {
            let sorted = copies.sorted {
                ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            guard let keeper = sorted.first else { continue }

            for loser in sorted.dropFirst() {
                reconcile(keeper, with: loser)

                // Detached first, so the show stops listing it now rather than
                // at the next save.
                loser.podcast = nil
                context.delete(loser)
                removed += 1
            }
        }
        return removed
    }

    /// Folds an episode that has lost its show into the copy that still has
    /// one.
    ///
    /// Turning sync on left these: another device's import deleted shows on
    /// this one without their episodes, the shows came back with fresh
    /// copies, and the old episodes stayed behind with no show. History only
    /// lists episodes with a show, so plays made on the old copies vanished
    /// from it.
    ///
    /// Only with exactly one twin. With none there is no show to put it back
    /// in, and an episode can be without its show for a moment while sync is
    /// still delivering both — deleting it then would delete it on every
    /// device. With twins in two shows there is no telling which it was.
    @discardableResult
    static func foldOrphans(in context: ModelContext) -> Int {
        let orphans = (try? context.fetch(
            FetchDescriptor<Episode>(predicate: #Predicate { $0.podcast == nil })
        )) ?? []
        guard !orphans.isEmpty else { return 0 }

        // One query for every twin rather than one per orphan: the phone this
        // was written for had two thousand of them.
        let guids = Set(orphans.map(\.guid))
        let twins = (try? context.fetch(
            FetchDescriptor<Episode>(predicate: #Predicate {
                $0.podcast != nil && guids.contains($0.guid)
            })
        )) ?? []
        let twinsByGUID = Dictionary(grouping: twins, by: \.guid)

        var removed = 0
        for orphan in orphans {
            guard let found = twinsByGUID[orphan.guid], found.count == 1,
                  let twin = found.first else { continue }
            reconcile(twin, with: orphan)
            context.delete(orphan)
            removed += 1
        }

        // Saved for the same reason `merge` saves: it runs at launch.
        if removed > 0 { try? context.save() }
        return removed
    }

    /// Writes the two copies' combined playback state onto the keeper.
    ///
    /// Only what moved, for the same reason `Subscriptions.merge` does it:
    /// every write re-runs the queries watching episodes.
    private static func reconcile(_ keeper: Episode, with other: Episode) {
        let merged = merging(
            PlaybackState(
                position: keeper.playbackPosition,
                isPlayed: keeper.isPlayed,
                lastPlayedAt: keeper.lastPlayedAt
            ),
            PlaybackState(
                position: other.playbackPosition,
                isPlayed: other.isPlayed,
                lastPlayedAt: other.lastPlayedAt
            )
        )
        if keeper.playbackPosition != merged.position { keeper.playbackPosition = merged.position }
        if keeper.isPlayed != merged.isPlayed { keeper.isPlayed = merged.isPlayed }
        if keeper.lastPlayedAt != merged.lastPlayedAt { keeper.lastPlayedAt = merged.lastPlayedAt }
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
            reconcile(twin, with: episode)
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

import CarPlay
import SwiftData
import UIKit

/// The car's scene.
///
/// UIKit instantiates this and cannot be handed anything, which is the whole
/// reason `PlaybackHost` owns the store and the player rather than a screen.
/// Touching `PlaybackHost.shared` here is also what brings the app up when the
/// car is the only scene — the window scene may never exist, and the host's
/// initialiser is what puts the last played episode back in the player.
///
/// Deliberately thin. What the rows say and what a selection means live in
/// `CarPlayLatestList`, where they are tested; this turns those values into
/// templates and back.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    /// Titled "Episodes" rather than "Latest", which the section below already
    /// says, or nothing, which costs more than it looks like it should.
    ///
    /// The title *is* the navigation bar — drop it and CarPlay has nothing to
    /// draw there, so the bar collapses, taking the system's now-playing
    /// button with it and leaving the list pressed against the top of the
    /// screen. That button is the only route back to the player once
    /// something is playing, so the bar has to stay.
    private let listTemplate = CPListTemplate(title: "Episodes", sections: [])

    /// The episodes the rows on screen stand for, kept for as long as those
    /// rows are.
    ///
    /// A row carries only a `PersistentIdentifier`, and a `ModelContext`
    /// registers its models weakly — so once the fetch that built the list
    /// returns, nothing holds the episodes and resolving a tap finds nothing.
    /// A screen's `@Query` hides this on the phone by holding its results;
    /// here the list is the only thing that can. Left undone, taps do nothing
    /// at all, and intermittently so: whether the phone happens to have a
    /// screen alive holding the same episodes decides it.
    private var shown: [PersistentIdentifier: Episode] = [:]

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        refreshRows()
        trackPlayer()
        interfaceController.setRootTemplate(listTemplate, animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: - The list

    /// Built on connect, after a selection, and whenever the player changes
    /// what it is holding — including from the phone, which is the case the
    /// first version missed. Choosing an episode in History while the car
    /// screen was up left the Continue row naming the previous one, even as
    /// the right audio played and the system's own Now Playing screen was
    /// correct, because that screen is fed by `MPNowPlayingInfoCenter` and
    /// this list is not.
    ///
    /// It still does not track the store, so a show subscribed to mid-drive
    /// brings no new rows until the next connect. Rarer by far than reaching
    /// for the phone, and it needs watching something other than the player.
    private func refreshRows() {
        let host = PlaybackHost.shared
        let latest = (try? host.container.mainContext.fetch(LatestEpisodes.descriptor())) ?? []
        let current = host.player.currentEpisode
        let sections = CarPlayLatestList.sections(
            current: current,
            at: host.player.position,
            latest: latest
        )
        // Rebuilt wholesale alongside the rows, so it holds exactly what is on
        // screen and an episode that has left the list is let go with its row.
        // The current episode is usually in `latest` as well, so the keys
        // collide by design — last one wins rather than trapping.
        shown = (latest + [current].compactMap { $0 })
            .reduce(into: [:]) { $0[$1.persistentModelID] = $1 }
        listTemplate.updateSections(sections.map(section(for:)))
    }

    private func section(for section: CarPlaySection) -> CPListSection {
        let items = section.rows.map(item(for:))
        guard let title = section.title else { return CPListSection(items: items) }
        return CPListSection(items: items, header: title, sectionIndexTitle: nil)
    }

    private func item(for row: CarPlayRow) -> CPListItem {
        let item = CPListItem(text: row.title, detailText: row.subtitle)
        item.isPlaying = row.isPlaying
        // Set before the real picture is asked for, so the row is its final
        // size from the first frame. `ArtworkView` keeps a placeholder for the
        // same reason on the phone, and a list reflowing under a glance
        // matters more in a car than it does there.
        item.setImage(Self.placeholder)
        loadArtwork(row.artworkURL, into: item)
        item.handler = { [weak self] _, completion in
            // Answered first. CarPlay holds the row in a selected state until
            // this is called, and everything `select` does happens to the
            // template that row belongs to — rebuilding its sections, pushing
            // on top of it. Doing that with the selection still in flight is
            // how a tap ends up looking like nothing happened.
            completion()
            self?.select(row.id)
        }
        return item
    }

    /// Watches the player so the list follows what the phone does.
    ///
    /// Two things about `withObservationTracking` shape this. It reports a
    /// change *before* the new value is in place, so the rebuild waits a turn
    /// of the main actor rather than reading the old one back; and it fires
    /// once, so it re-arms itself afterwards.
    private func trackPlayer() {
        let player = PlaybackHost.shared.player
        withObservationTracking {
            // Only what a row is drawn from. Not `position`, which ticks every
            // second and would rebuild the list under the driver's hand — the
            // Continue row's own "left at" detail is read at rebuild time, so
            // it stays current anyway.
            _ = player.current
            _ = player.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                // Disconnected: stop here rather than re-arming. `didConnect`
                // starts a fresh chain, so this cannot leave the car without
                // one.
                guard let self, interfaceController != nil else { return }
                refreshRows()
                trackPlayer()
            }
        }
    }

    // MARK: - Artwork

    /// CarPlay draws the row's image at `maximumImageSize`; anything larger is
    /// scaled down for nothing. Asked for in pixels because that is what the
    /// decoder works in, and fetched on the car's own screen scale rather than
    /// the phone's.
    private func loadArtwork(_ url: String?, into item: CPListItem) {
        guard let url, let resolved = URL(string: url) else { return }

        let points = CPListItem.maximumImageSize
        let scale = interfaceController?.carTraitCollection.displayScale ?? 2
        let pixels = Int(max(points.width, points.height) * max(scale, 1))

        // Already drawn on the phone, most of the time: the car's scene shares
        // this process, so the cache is the same one. That path sets the image
        // without a hop through the network or another decode.
        if let hit = ArtworkCache.shared.cached(resolved, maxPixels: pixels) {
            item.setImage(hit)
            return
        }

        // The item is captured, not the row: `updateSections` replaces every
        // item wholesale, so one left over from a list that has moved on just
        // sets an image on an object nothing is showing, and then goes away
        // with it.
        Task {
            guard let image = await ArtworkCache.shared.image(for: resolved, maxPixels: pixels)
            else { return }
            item.setImage(image)
        }
    }

    /// The same glyph the phone draws while it waits, rendered once.
    private static let placeholder: UIImage? = UIImage(
        systemName: "waveform",
        withConfiguration: UIImage.SymbolConfiguration(scale: .large)
    )

    // MARK: - Selecting

    /// The identifier is carried rather than the `Episode`, and resolved again
    /// here from what the list is holding: a row can outlive the episode it
    /// describes, and reading a deleted `@Model` traps.
    private func select(_ id: PersistentIdentifier) {
        let host = PlaybackHost.shared
        guard let episode = shown[id], !episode.isDeleted else { return }

        switch CarPlayLatestList.selection(
            isCurrent: host.player.isCurrent(episode),
            isPlaying: host.player.isPlaying
        ) {
        case .playThenShowPlayer:
            host.player.play(episode)
        case .resumeThenShowPlayer:
            // Carries on from the stored position, and hands the episode to
            // the engine if launching restored it without ever loading it.
            host.player.resume()
        case .showPlayer:
            break
        }

        // Player first, list second. Rebuilding the list replaces every row in
        // it, including the one just tapped, so it happens once that row has
        // finished being the thing the driver is interacting with.
        showPlayer()
        refreshRows()
    }

    /// Pushing a template that is already on top is an error rather than a
    /// no-op, and a second tap on the row already playing leads here.
    private func showPlayer() {
        guard interfaceController?.topTemplate !== CPNowPlayingTemplate.shared else { return }
        interfaceController?.pushTemplate(
            CPNowPlayingTemplate.shared,
            animated: true,
            completion: nil
        )
    }
}

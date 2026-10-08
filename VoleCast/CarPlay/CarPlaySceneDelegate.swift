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
    /// Untitled on purpose. The sections name themselves — Continue, then
    /// Latest — and a template title above them put "Latest" on screen twice,
    /// once as a heading for a list that is only partly Latest.
    private let listTemplate = CPListTemplate(title: nil, sections: [])

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
        interfaceController.setRootTemplate(listTemplate, animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: - The list

    /// Built on connect and again after a selection, so the playing indicator
    /// moves. It deliberately does not track the store: an episode finished on
    /// the phone mid-drive will not redraw here until the next connect, which
    /// is a trade this first version makes on purpose.
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

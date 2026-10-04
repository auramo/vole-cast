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
    private let listTemplate = CPListTemplate(title: "Latest", sections: [])

    /// The car's answer to the mini-player bar. CarPlay puts no route to the
    /// player on a list of its own, so without this the only way to reach one
    /// is to start something — and an episode carried over from the phone,
    /// which is the thing you most want in a car, would be unreachable.
    ///
    /// Shown only while an episode is loaded, which is exactly when the phone
    /// shows its bar.
    private lazy var nowPlayingButton = CPBarButton(title: "Now Playing") { [weak self] _ in
        self?.showPlayer()
    }

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
        let sections = CarPlayLatestList.sections(
            current: host.player.currentEpisode,
            at: host.player.position,
            latest: latest
        )
        listTemplate.updateSections(sections.map(section(for:)))
        listTemplate.trailingNavigationBarButtons =
            host.player.current == nil ? [] : [nowPlayingButton]
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
            self?.select(row.id)
            completion()
        }
        return item
    }

    // MARK: - Selecting

    /// The identifier is carried rather than the `Episode`, and resolved again
    /// here: a row can outlive the episode it describes, and reading a deleted
    /// `@Model` traps. `registeredModel` and not `model(for:)` for the reason
    /// `PlayerModel` gives — the latter hands back a fault for a row that is
    /// gone, so a deleted episode would come back looking alive.
    private func select(_ id: PersistentIdentifier) {
        let host = PlaybackHost.shared
        guard let episode = host.container.mainContext.registeredModel(for: id) as Episode?,
              !episode.isDeleted
        else { return }

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

        refreshRows()
        showPlayer()
    }

    /// Pushing a template that is already on top is an error rather than a
    /// no-op, and both the button and a row selection lead here.
    private func showPlayer() {
        guard interfaceController?.topTemplate !== CPNowPlayingTemplate.shared else { return }
        interfaceController?.pushTemplate(
            CPNowPlayingTemplate.shared,
            animated: true,
            completion: nil
        )
    }
}

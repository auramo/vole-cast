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
        let episodes = (try? host.container.mainContext.fetch(LatestEpisodes.descriptor())) ?? []
        // Asked through the player's own predicate rather than reading an
        // identifier off it, so this cannot disagree with what the player
        // thinks it is holding.
        let current = episodes.first(where: host.player.isCurrent)?.persistentModelID
        let rows = CarPlayLatestList.rows(for: episodes, current: current)
        listTemplate.updateSections([CPListSection(items: rows.map(item(for:)))])
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

        switch CarPlayLatestList.selection(isCurrent: host.player.isCurrent(episode)) {
        case .playThenShowPlayer:
            host.player.play(episode)
        case .showPlayer:
            break
        }

        refreshRows()
        interfaceController?.pushTemplate(
            CPNowPlayingTemplate.shared,
            animated: true,
            completion: nil
        )
    }
}

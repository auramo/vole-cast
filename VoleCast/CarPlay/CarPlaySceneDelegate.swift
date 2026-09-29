import CarPlay
import UIKit

/// The car's scene.
///
/// UIKit instantiates this and cannot be handed anything, which is the whole
/// reason `PlaybackHost` owns the store and the player rather than a screen.
/// Touching `PlaybackHost.shared` here is also what brings the app up when the
/// car is the only scene — the window scene may never exist.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(
            CPListTemplate(title: "Latest", sections: []),
            animated: false,
            completion: nil
        )
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }
}

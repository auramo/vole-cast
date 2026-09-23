import SwiftUI

/// Services reach the views through the environment, so previews and tests can
/// swap in fakes and no view ever names a concrete implementation.
extension EnvironmentValues {
    @Entry var podcastDirectory: any PodcastDirectory = ITunesPodcastDirectory()
    @Entry var feedLoader: any FeedLoading = FeedLoader()

    /// A factory, unlike its neighbours above, for two reasons. `@Entry`
    /// synthesises a *computed* default, so every view that read a plain
    /// existential here would build its own `AVPlayer` — one engine per screen,
    /// all fighting over the audio session. And the engine is `@MainActor`,
    /// which a nonisolated default cannot construct. `RootView` calls this once.
    @Entry var makeAudioPlayback: @MainActor @Sendable () -> any AudioPlayback = {
        AVPlayerAudioEngine()
    }
}

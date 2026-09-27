import SwiftUI

/// Services reach the views through the environment, so previews and tests can
/// swap in fakes and no view ever names a concrete implementation.
extension EnvironmentValues {
    @Entry var podcastDirectory: any PodcastDirectory = ITunesPodcastDirectory()
    @Entry var feedLoader: any FeedLoading = FeedLoader()
}

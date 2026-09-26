# VoleCast

An open-source podcast app for iOS.

Early days. You can find a show by name, or paste an RSS feed URL, subscribe to
it, browse its episodes and play them — streaming, with the lock-screen
controls and resume-where-you-left-off you'd expect. A History tab lists what
you've been listening to; finishing an episode takes it out of Latest.
Downloads come next.

Built with SwiftUI and SwiftData, with no third-party dependencies — feeds are
parsed with Foundation's `XMLParser`.

## How shows are found

Search goes to Apple's [iTunes Search
API](https://performance-partners.apple.com/search-api), which needs no API key
or signup, so a fresh clone searches with nothing to configure. Its rate limit
applies per device rather than per app, and its results carry the feed URL,
which is all a subscription needs.

Two things follow from that, and are worth knowing before changing the search
code:

- It never reports "no matches". An unrecognised name comes back as a handful
  of loosely related shows, so results are offered as suggestions and pasting a
  feed URL stays a first-class path.
- Throttling arrives as HTTP 403 rather than 429, so 403 is treated as
  "try again shortly", not as a permanent failure.

A show only appears if it publishes a public RSS feed. Shows exclusive to Supla,
Podme or Spotify have no feed, so no podcast app can reach them.

`PodcastDirectory` is a protocol, so another directory (Podcast Index, say) can
be added without the UI knowing. That one needs an API key; if it is ever added,
the key belongs in a git-ignored xcconfig with a committed template, the same
way `Config/Local.xcconfig` works.

## How playback works

Episodes stream. Nothing is stored on the device beyond the session, and that
is a property of the design rather than a policy anyone has to enforce:
`AVURLAsset` uses CoreMedia's own HTTP stack, which neither consults nor
populates the `URLCache` in `AppURLSession`, and the one API that writes audio
durably — `AVAssetDownloadURLSession` — is not used. There is no downloads
directory, nothing to enumerate and nothing to delete when you unsubscribe.

What that does *not* mean is a bounded memory footprint. While an episode
plays, AVFoundation buffers into its own scratch storage, and for a plain
progressive MP3 it fetches front-to-back and may hold a large fraction of the
item for the session — a two-hour show at 128 kbps is around 115 MB.
`preferredForwardBufferDuration` is a hint, and constrains HLS far more tightly
than it constrains a progressive download. Capping it for real would mean a
caching layer, which is the thing streaming was chosen to avoid.

Three things guard against stalls, none of them a cache. The forward buffer
starts automatic and is raised to sixty seconds only once audio is flowing,
because asking for a large read-ahead up front buys stall resistance at the
cost of time-to-first-sound — the delay people actually notice. Seeks carry a
one-second tolerance and coalesce, so dragging the scrubber cannot queue a
burst of byte-range requests. And a watchdog nudges the player if it sits
waiting to play for twenty seconds, which AVPlayer occasionally does even after
the network has returned; it gives up after two attempts so a dead stream
cannot become a retry loop.

`Playback/` imports neither SwiftUI nor SwiftData. Episodes reach it as a
`PlayableEpisode` snapshot, which keeps the engine testable without a store and
means it cannot trap by reading an `Episode` that unsubscribing has already
deleted. `PlayerModel` is the only place that sees both.

Background audio is declared in `Config/Info.plist` rather than through a
build setting. `INFOPLIST_KEY_UIBackgroundModes` is not a real setting —
`xcodebuild` accepts it and then silently drops it — so that one key lives in a
partial plist which `GENERATE_INFOPLIST_FILE` merges the generated keys into.

## Code layout

Each folder is defined by what it is allowed to touch, so the dependencies only
ever point one way — parsing knows nothing about the network, and nothing below
`Views/` knows about SwiftUI.

| Folder | Holds | May use |
| --- | --- | --- |
| `Models/` | `Podcast`, `Episode` | SwiftData |
| `Persistence/` | the container, the `LatestEpisodes` and `ListeningHistory` queries, plus `Subscriptions` and `PlaybackProgress` — the only writers to the store | SwiftData |
| `FeedParsing/` | `FeedParser` and the pure helpers it needs (`RSSDate`, `EpisodeDuration`, `FeedURL`, `ParsedFeed`) | nothing but Foundation |
| `Networking/` | `HTTPClient`, `AppURLSession`, `NetworkError` — transport, no podcast knowledge | URLSession |
| `Catalog/` | where shows come from: `PodcastDirectory`, its iTunes implementation, and `FeedLoader` | Networking + FeedParsing |
| `Formatting/` | turning stored values into display strings | Foundation |
| `Playback/` | `AudioPlayback` and its AVPlayer engine, the audio session, now-playing and remote commands. Speaks in `PlayableEpisode` values, never `Episode` | AVFoundation, MediaPlayer, UIKit |
| `Views/` | SwiftUI screens, `SearchModel` and `PlayerModel` | everything above |

Services reach the views through the environment (`Views/Environment+Services.swift`),
so no view names a concrete implementation and previews and tests can substitute
fakes.

## Requirements

- Xcode 26.3 or newer
- iOS 26.1+ (iPhone and iPad)
- Swift 6

## Getting started

```sh
git clone git@github.com:auramo/vole-cast.git
cd vole-cast
cp Config/Local.xcconfig.template Config/Local.xcconfig
git config core.hooksPath .githooks
```

Then open `VoleCast.xcodeproj` and fill in `Config/Local.xcconfig` with your own
`ORG_IDENTIFIER` (a reverse-DNS prefix, e.g. `com.yourname`) and
`DEVELOPMENT_TEAM` (your Apple Developer Team ID, from Xcode > Settings >
Accounts). That file is git-ignored; it is the only place personal signing
values belong.

The project builds without it — the placeholders in `Config/Shared.xcconfig`
take over — but code signing needs a team of your own.

The `core.hooksPath` line enables a pre-commit hook that keeps those values out
of commits. Xcode writes them back into `project.pbxproj` whenever you touch
the Signing & Capabilities pane; the hook strips them and re-stages the file,
so you never have to do it by hand. Nothing is lost, since the build reads them
from the xcconfig.

## Tests

`Cmd-U` in Xcode, or from the command line against any installed iPhone
simulator:

```sh
xcrun simctl list devices available | grep iPhone   # pick one you have
xcodebuild -project VoleCast.xcodeproj -scheme VoleCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Simulator names change with each Xcode release, so substitute a name from the
first command rather than trusting the one above. CI resolves it at run time
and runs the same suite on every push and pull request.

## License

MIT — see [LICENSE](LICENSE).

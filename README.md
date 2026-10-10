# VoleCast

An open-source podcast app for iOS.

The main idea is to give you the latest episodes of your subscribed
podcasts via streaming, no downloaded garbage left behind to fill your
phone.

There is no "continuing the next episode"-feature, which in some
podcast applications just means the end jingles or ads of previously
listened episodes appear endlessly :(
In fact: no concept of next episode at all. You pick one form the
latest view, and when it's done and nothing plays after you select
something else.

If you want to pick up an unfinished episode, you can find it in the
history view which shows the last 100 listened episodes whether they
are fully played or not.

There is also a possibility to jump to the episode in the podcast's
feed to find the next episode in case you want to continue to the next
episode. It doesn't matter how far past the episode is in the
podcast's feed. This way you can play related episodes which could
have been originally released years ago.

You can find a show by name, or paste an RSS feed URL, subscribe to it, browse
its episodes and play them, with the lock-screen controls and
resume-where-you-left-off you'd expect. Alongside the search there is a
Discover list: Apple's top podcasts for a country you choose, overall or by
genre. Search and pasting a URL are the paths that matter, and they are built
so that Discover failing cannot touch them.

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

## CarPlay

The car gets the Latest list and the system Now Playing screen, and nothing
else for now. No Subscriptions, no History, and no search — search needs a
keyboard the car locks out while moving. The list shows what is already in the
store; feeds are not refreshed from the car.

Connecting puts a part-listened episode back in the player at its stored
position without making a sound. Plugging in for maps should not start a
podcast, so audio waits until it is asked for, from the car screen or the
wheel.

The car and the phone drive one player and one store, which is what
`PlaybackHost` is for: CarPlay is a second scene, created by UIKit, which
cannot be handed anything at construction. Two players would mean two claims on
one audio session and a car that does not know what the phone is playing.

The scene is declared in `Config/Info.plist`, and
`INFOPLIST_KEY_UIApplicationSceneManifest_Generation` has to stay `NO`. Left at
`YES`, Xcode generates a scene manifest of its own and the generated one wins:
the CarPlay role is dropped from the built app without a word, and the car
simply never offers it.

`Config/VoleCast.entitlements` carries `com.apple.developer.carplay-audio`.
That is a capability flag with nothing personal in it, but the entitlement
itself is granted per Apple developer account, so **a device build will not
sign without CarPlay Audio approved on your own account.** Simulator builds and
the test suite are unaffected, since neither provisions. Apple grants it on
request, through the CarPlay entitlement form in the developer portal.

Seeing it work means a real car. The CarPlay display that older Xcodes offered
under *I/O → External Displays* has no equivalent in Xcode 27's DeviceHub, so
a head unit is the only place the scene can be checked. A development build is
enough — no App Store or TestFlight — once the entitlement is on the
provisioning profile.

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
| `Catalog/` | where shows come from: `PodcastDirectory` and `PodcastCharts` with their Apple implementations, `PodcastLookup`, `PodcastGenre`, `Storefront`, and `FeedLoader` | Networking + FeedParsing |
| `Formatting/` | turning stored values into display strings | Foundation |
| `Playback/` | `AudioPlayback` and its AVPlayer engine, the audio session, now-playing and remote commands. Speaks in `PlayableEpisode` values, never `Episode` | AVFoundation, MediaPlayer, UIKit |
| `Player/` | `PlayerModel` — the one thing that sees both an `Episode` and the engine, and the only code both UIs share | SwiftData, `Playback/` |
| `Views/` | SwiftUI screens, `SearchModel` and `DiscoverModel` | everything above |

Services reach the views through the environment (`Views/Environment+Services.swift`),
so no view names a concrete implementation and previews and tests can substitute
fakes.

### Browsing the charts

Discover is a second way in for people who don't already have a show in mind.
It asks Apple for a chart of up to a hundred shows, for the device's own
country by default and any other you pick.

It takes two endpoints to do that, and the reason is worth writing down because
all of it was found by trying them rather than by reading documentation that
does not exist:

- `rss.itunes.apple.com/api/v1/…`, the URL usually suggested for this, is dead.
  It answers 503 with a DNS failure.
- `rss.marketingtools.apple.com/api/v2/…` replaced it and is the one Apple
  documents. It serves the overall chart, and it *silently ignores* any genre
  you ask it for — request Comedy and it returns the same shows as the
  unfiltered chart, with no error to notice.
- The legacy `itunes.apple.com/{country}/rss/toppodcasts/limit={n}/genre={id}/json`
  endpoint genuinely filters. It is undocumented and its sibling host has
  already been retired, so it is the fragile half.

So the overall chart comes from the supported endpoint and genre charts from
the fragile one. If the legacy endpoint goes the way of its sibling, genre
browsing fails on its own: the overall chart, the search and pasting a feed URL
all keep working. `ApplePodcastCharts` is the only place that would need
changing.

Neither chart carries a feed URL — only an iTunes collection id — so tapping a
row looks the show up through `itunes.apple.com/lookup` before its feed can be
loaded. Some shows are exclusive to Apple Podcasts and have no public feed at
all; those say so rather than offering a retry that could never succeed.

The country list is every region the device can name, not Apple's own roughly
175 storefronts, which are published nowhere stable. Picking one Apple does not
serve is recoverable; a country missing from a hardcoded table is not.

## Languages

English and Finnish. Strings live in one catalog, `VoleCast/Localizable.xcstrings`,
with the English text itself as the key — so a string with no translation yet
falls back to something readable rather than to an identifier.

The catalog sits at the top of the synchronized `VoleCast/` folder, which is the
whole of its wiring: nothing lists it as a resource, and `knownRegions` naming
`fi` is the only project change localization needed.

Two things are deliberately left in English: the app's own name, which is not a
word in either language, and anything only a developer reads — log messages and
the `fatalError` text in `VoleCastModelContainer` among them.

Finnish cannot inflect an interpolated proper noun, so strings that would need
to are punctuated around it: "Charts from %@" is `Listat maasta: %@`, where the
colon lets the country name stay in its basic form rather than being asked to
become *Suomesta*.

Not every term wants translating. "True Crime" is the genre's name in Finnish
too, and the catalog says so explicitly rather than leaving the entry empty, so
it reads as a decision rather than as an omission.

To see it: run with the scheme's language set to Finnish, or from the command
line

```sh
xcrun simctl launch <udid> <bundle-id> -AppleLanguages "(fi)" -AppleLocale fi_FI
```

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

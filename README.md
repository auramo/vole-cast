# VoleCast

An open-source podcast app for iOS.

Early days. You can find a show by name, or paste an RSS feed URL, subscribe to
it, and browse its episodes. Playing them comes next.

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

## Requirements

- Xcode 26.3 or newer
- iOS 18.0+ (iPhone and iPad)
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

```sh
xcodebuild -project VoleCast.xcodeproj -scheme VoleCast \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## License

MIT — see [LICENSE](LICENSE).

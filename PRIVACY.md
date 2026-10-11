# Privacy

VoleCast has no account, no analytics, no advertising identifier and no server
of its own. Nothing is sent anywhere to be counted.

## What stays on your device

Your subscriptions, which episodes you have played, where you stopped in each
one, and your listening history. Episodes are streamed and nothing is written
to the device beyond the session, so there is no library of audio files either.

## What is mirrored to iCloud

That same data is mirrored to **your own private iCloud database**, so your
shows and your place in them follow you between your devices. It is stored
under your Apple Account, in the private part of the app's CloudKit container:

- The developer cannot read it. A private CloudKit database is not visible to
  the app's developer — only to you, on your devices.
- It counts against your iCloud storage, not against anything the app controls.
- There is nothing to switch on. iOS mirrors the store when the device is
  signed into an Apple Account and keeps it local when it isn't.

If you would rather it didn't, turn VoleCast off under **Settings → your name →
iCloud**. The app keeps working; it simply stops following you around.

Deleting the app does not delete what has already synced. That lives under
**Settings → your name → iCloud → Manage Account Storage**.

## Who else your device talks to

- **Podcast publishers.** Feeds and audio are fetched straight from whoever
  hosts them, so they see your IP address and what you asked for, as any
  podcast app or web browser would.
- **Apple's iTunes Search API**, when you search for a show by name, and
  **Apple's podcast charts**, when you browse Discover. Those requests carry
  what you typed or which chart you asked for.

A feed URL you paste is never sent to Apple's search — private feeds from
Patreon and similar carry a token in their address, and handing that to a
search engine would be handing out the subscription.

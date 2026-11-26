# TeleBase — Usage Guide

How developers actually use TeleBase, end to end: what it is good for,
how to add it to a project, and complete walkthroughs for both modes.

## What can you use it for?

| Use case | Mode | What happens |
|---|---|---|
| **Remote config** — change app behaviour without an update | Broadcast | Post one config message in your channel; every app copy reads it on launch. |
| **Feature flags** — turn a feature on/off for everyone instantly | Broadcast | Flip a flag in the config message; apps pick it up on next launch. |
| **Announcements** — maintenance notices, news, welcome messages | Broadcast | The config carries an `announcement` string your app displays. |
| **Forced update** — retire a broken old version | Broadcast | Set `minVersion`; older builds prompt (or force) an update. |
| **Profile cards** — rich public profiles (banner, bio, links) | Registry | Each user publishes a card into the group; other users' apps render it. This is the use TeleBase was invented for (Urgram). |
| **Leaderboards** — small public score tables | Registry | Players publish their score record; apps fetch and rank them. |
| **Shared settings / presence** — small per-user public state | Registry | Any small `Codable` payload, keyed per user. |

Broadcast mode works in **any** app today. Registry mode needs an app
that embeds a Telegram user client (see the prerequisites below).

## Installation

**Xcode:** File → Add Package Dependencies… → paste the repository URL:

```
https://github.com/O87l/TeleBase
```

**Or in `Package.swift`:**

```swift
dependencies: [
    .package(url: "https://github.com/O87l/TeleBase", from: "0.1.0")
]
```

Then import it where you need it:

```swift
import TeleBase
```

## Broadcast mode — remote config in 5 minutes

### 1. Create a public channel

Any public Telegram channel works. Its username is your config address
(e.g. `@myappconfig`). Only you post there; the whole world can read —
that is exactly what config needs.

### 2. Post the config message

Post one message that starts with the line `TBCFG`, followed by a JSON
object:

```
TBCFG
{"announcement":"Scheduled maintenance on Friday.",
 "minVersion":"1.2.0",
 "latestVersion":"1.4.0",
 "featureFlags":{"snow":true,"newOnboarding":false},
 "links":{"support":"https://t.me/example"}}
```

All fields are optional except `featureFlags`. To change the config,
just post a **newer** message — the newest one wins. Repost it every so
often: the public web feed only shows recent history.

### 3. Read it in your app

```swift
import TeleBase

let client = TeleBase.broadcastClient()

// On launch — falls back to the last cached config when offline.
if let config = try? await client.fetchConfig(channel: "myappconfig") {
    if let news = config.announcement {
        showBanner(news)
    }
    if config.flag("snow") {
        enableSnowEffect()
    }
    if needsUpdate(below: config.minVersion) {
        showUpdatePrompt()
    }
}
```

`fetchConfig` caches every success on disk; on any failure it returns
the cached copy and only throws when nothing was ever cached. You can
also read the raw feed yourself for custom message formats:

```swift
let messages = try await client.fetchMessages(channel: "myappconfig")
```

## Registry mode — user-owned records in a group

### Prerequisites

Registry mode moves data through a Telegram **user account**, so your
app must embed a Telegram client (MTProto — e.g. a Telegram fork), or
you must supply an equivalent transport. TeleBase defines the small
`GroupTransport` protocol (join / leave / search / post); the mapping to
a TDLib-style client is documented in
[TransportGuide.md](TransportGuide.md). A `MockGroupTransport` is
included so you can build and test your whole flow with no Telegram
account at all.

Setup on the Telegram side: create a **public supergroup** with visible
history — that group is your database. Users' clients join it briefly
to read or write, then leave, so it never clutters their chat list.

### Publish a profile card

```swift
import TeleBase

let client = TeleBase.registryClient(transport: myTransport)

let card = TBProfile(
    displayName: "Abd",
    bio: "iOS developer",
    links: ["telegram": "https://t.me/example"]
)

// Owned by the signed-in user; stored under "profile:<userId>".
try await client.publish(card, key: TBProfile.recordKey(ownerId: myUserId))
```

### Read someone's card

```swift
let theirCard = try await client.fetch(
    key: TBProfile.recordKey(ownerId: theirUserId),
    as: TBProfile.self
)
```

Reads are cache-first (24h). Behind the scenes the client joins the
group, searches for the record, keeps only copies whose poster matches
the record's owner — impostor copies are discarded — and returns the
newest genuine one, then leaves the group.

### Your own payloads

Any `Codable` type works the same way:

```swift
struct Score: Codable {
    var points: Int
    var level: Int
}

try await client.publish(Score(points: 1200, level: 7),
                         key: "score:\(myUserId)")

let best = try await client.fetch(key: "score:\(theirUserId)", as: Score.self)
```

Key conventions are yours; `profile:<id>` and `score:<id>` are just the
examples used here. Call `client.invalidate(key:)` to force the next
read to search the group again.

## Rules of the road

- **Public data only.** Everything in the group/channel is world-readable.
  Never store secrets, tokens, or private user data.
- **Small data.** Records are messages — keep payloads to a few KB.
- **Ownership is verified by poster.** In Registry mode a record counts
  only when the account that posted it matches the record's `ownerId`.
- **Best effort.** Telegram rate limits apply; the caches exist so your
  app degrades gracefully instead of failing.

See the [README](../README.md) for the record format spec, the security
model, and the full list of limits.

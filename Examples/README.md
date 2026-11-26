# TeleBase Demo

A minimal SwiftUI example showing both TeleBase modes:

- **Broadcast tab** — fetches remote config (`TBCFG`) from a public
  Telegram channel over HTTPS using `TBBroadcastClient`. Works as-is,
  no Telegram account involved.
- **Registry tab** — publishes a `TBProfile` card and reads it back
  through `TBRegistryClient` running on `MockGroupTransport`, so the
  whole record flow (chunking, verification, newest-wins) is visible
  without an MTProto client.

## Running it

The example is intentionally just source files, not a full Xcode project:

1. In Xcode, create a new iOS App project (SwiftUI, iOS 16+).
2. Add the TeleBase package: **File → Add Package Dependencies → Add
   Local…** and select the repository root.
3. Replace the generated `App` and `ContentView` files with
   `TeleBaseDemoApp.swift` and `ContentView.swift` from this folder.
4. Run. In the Broadcast tab, point the channel field at a public channel
   you control, post a `TBCFG` message there (format in
   `TBRemoteConfig`), and fetch.

import Foundation

/// TeleBase — a free backend for your app, powered by a Telegram group.
///
/// No server. No bill. A Telegram group (or channel) *is* the database.
///
/// TeleBase has two modes:
///
/// - **Registry mode** (`TBRegistryClient`) — read/write records stored as
///   messages in a Telegram group, for apps that embed a Telegram user
///   client. Records are ownership-verified and resolved newest-first.
///   See `GroupTransport` for the small protocol your client must conform
///   to, and `Docs/TransportGuide.md` for a walkthrough.
///
/// - **Broadcast mode** (`TBBroadcastClient`) — read-only remote config,
///   announcements and feature flags from a public channel's web feed.
///   Works in *any* app today over plain HTTPS — no Telegram account,
///   no SDK, no server.
///
/// Start with Broadcast mode for config, and reach for Registry mode when
/// your app already speaks MTProto and needs user-owned data (profile
/// cards, leaderboards, shared settings) with zero infrastructure.
public enum TeleBase {

    /// The TeleBase format version implemented by this release.
    public static let version = "0.1.0"

    /// Creates a broadcast client (remote config from a public channel).
    public static func broadcastClient() -> TBBroadcastClient {
        TBBroadcastClient()
    }

    /// Creates a registry client over a Telegram transport you provide.
    public static func registryClient(transport: GroupTransport) -> TBRegistryClient {
        TBRegistryClient(transport: transport)
    }
}

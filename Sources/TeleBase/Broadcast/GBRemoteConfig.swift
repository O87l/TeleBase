import Foundation

/// Remote configuration delivered through Broadcast mode.
///
/// To publish a config, post one message in your public channel that starts
/// with the line `TBCFG`, followed by a JSON object:
///
/// ```
/// TBCFG
/// {"announcement":"Scheduled maintenance on Friday.",
///  "minVersion":"1.2.0",
///  "featureFlags":{"snow":true,"newOnboarding":false}}
/// ```
///
/// Every field except `featureFlags` is optional. Unknown JSON keys are
/// ignored, so you can extend your config format over time — decode the raw
/// messages yourself (see `TBBroadcastClient.fetchMessages`) when you need
/// custom fields.
public struct TBRemoteConfig: Codable, Equatable, Sendable {

    /// A user-facing announcement to show in the app.
    public var announcement: String?

    /// Oldest app version that may keep running; older builds should be
    /// told to update. Compared as a string by the app — TeleBase does
    /// not interpret it.
    public var minVersion: String?

    /// Newest available app version, for "update available" prompts.
    public var latestVersion: String?

    /// Feature flags by name.
    public var featureFlags: [String: Bool]

    /// Named links, e.g. `["support": "https://t.me/example"]`.
    public var links: [String: String]?

    public init(announcement: String? = nil,
                minVersion: String? = nil,
                latestVersion: String? = nil,
                featureFlags: [String: Bool] = [:],
                links: [String: String]? = nil) {
        self.announcement = announcement
        self.minVersion = minVersion
        self.latestVersion = latestVersion
        self.featureFlags = featureFlags
        self.links = links
    }

    /// Convenience accessor for a flag, defaulting to `false`.
    public func flag(_ name: String) -> Bool {
        featureFlags[name] ?? false
    }
}

/// One message parsed out of a public channel's web feed.
public struct TBBroadcastMessage: Equatable, Sendable {

    /// The message's public id, e.g. `"mychannel/123"`.
    public var id: String

    /// Plain text of the message (HTML stripped, entities decoded).
    public var text: String

    /// Publication time, when the feed exposed it.
    public var date: Date?

    public init(id: String, text: String, date: Date?) {
        self.id = id
        self.text = text
        self.date = date
    }
}

import Foundation

/// Broadcast mode: read-only remote config, announcements and feature
/// flags from a **public** Telegram channel — in any app, today, with no
/// Telegram account at all.
///
/// Telegram serves a public web preview of every public channel at
/// `https://t.me/s/<channel>`. This client fetches that page over plain
/// HTTPS, extracts the channel's recent messages, and interprets the
/// newest `TBCFG` message as a `TBRemoteConfig` (see `TBRemoteConfig` for
/// the format).
///
/// The last good config is cached on disk; when a fetch fails, the cached
/// copy is served instead of failing your app's launch.
///
/// Honest limits: the web preview shows only the channel's recent history
/// (keep your config message recent — repost it when it ages out), page
/// markup is Telegram's and may change, and delivery is best-effort —
/// treat broadcast config as a convenience, never as a security boundary.
public final class TBBroadcastClient {

    /// Marker line that introduces a config message.
    public static let configMarker = "TBCFG"

    private let session: URLSession
    private let cache: TBDiskCache

    public init(session: URLSession = .shared, cache: TBDiskCache = .defaultCache()) {
        self.session = session
        self.cache = cache
    }

    // MARK: - Messages

    /// Fetches and parses the recent messages of a public channel,
    /// oldest first. Throws `TBError.broadcastUnavailable` on network or
    /// HTTP failure and `TBError.emptyFeed` when no messages are found.
    public func fetchMessages(channel: String) async throws -> [TBBroadcastMessage] {
        guard let url = URL(string: "https://t.me/s/\(channel)") else {
            throw TBError.broadcastUnavailable
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw TBError.broadcastUnavailable
        }
        let messages = Self.parseFeed(html)
        guard !messages.isEmpty else { throw TBError.emptyFeed }
        return messages
    }

    // MARK: - Remote config

    /// Fetches the channel's newest config message.
    ///
    /// On success the config is cached and returned. On any failure the
    /// last cached config is returned instead; only when there is no cache
    /// at all does this throw.
    public func fetchConfig(channel: String) async throws -> TBRemoteConfig {
        do {
            let messages = try await fetchMessages(channel: channel)
            guard let config = Self.config(from: messages) else {
                if let cached = cachedConfig(channel: channel) { return cached }
                throw TBError.emptyFeed
            }
            if let encoded = try? JSONEncoder().encode(config),
               let json = String(data: encoded, encoding: .utf8) {
                cache.set(json, forKey: cacheKey(channel))
            }
            return config
        } catch {
            if let cached = cachedConfig(channel: channel) { return cached }
            throw error
        }
    }

    /// The last successfully fetched config for `channel`, if any.
    /// Works offline and never throws.
    public func cachedConfig(channel: String) -> TBRemoteConfig? {
        guard let json = cache.string(forKey: cacheKey(channel)),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TBRemoteConfig.self, from: data)
    }

    /// Finds the newest `TBCFG` message in `messages` and decodes it.
    public static func config(from messages: [TBBroadcastMessage]) -> TBRemoteConfig? {
        for message in messages.reversed() {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.hasPrefix(configMarker) else { continue }
            let json = text.dropFirst(configMarker.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = json.data(using: .utf8),
                  let config = try? JSONDecoder().decode(TBRemoteConfig.self, from: data) else {
                continue
            }
            return config
        }
        return nil
    }

    private func cacheKey(_ channel: String) -> String {
        "config:" + channel
    }

    // MARK: - Feed parsing

    /// Parses the `https://t.me/s/<channel>` HTML into messages.
    ///
    /// The parser is intentionally small: it locates each message block by
    /// its `data-post` attribute, then extracts the text div inside the
    /// block. It does not build a DOM and tolerates missing pieces.
    public static func parseFeed(_ html: String) -> [TBBroadcastMessage] {
        var messages: [TBBroadcastMessage] = []
        let blocks = html.components(separatedBy: "tgme_widget_message_wrap")
        for block in blocks.dropFirst() {
            guard let id = firstMatch(in: block, pattern: "data-post=\"([^\"]+)\"") else { continue }
            guard let rawText = firstMatch(in: block,
                                           pattern: "tgme_widget_message_text[^>]*>(.*?)</div>",
                                           dotMatchesLineSeparators: true) else { continue }
            let text = plainText(fromHTML: rawText)
            let dateString = firstMatch(in: block, pattern: "datetime=\"([^\"]+)\"")
            let date = dateString.flatMap { ISO8601DateFormatter().date(from: $0) }
            messages.append(TBBroadcastMessage(id: id, text: text, date: date))
        }
        return messages
    }

    /// Converts a message's inner HTML to plain text.
    static func plainText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        // Strip remaining tags.
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = regex.stringByReplacingMatches(in: text,
                                                  range: NSRange(text.startIndex..., in: text),
                                                  withTemplate: "")
        }
        // Decode the entities Telegram emits.
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'")
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in string: String,
                                   pattern: String,
                                   dotMatchesLineSeparators: Bool = false) -> String? {
        var options: NSRegularExpression.Options = []
        if dotMatchesLineSeparators { options.insert(.dotMatchesLineSeparators) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[capture])
    }
}

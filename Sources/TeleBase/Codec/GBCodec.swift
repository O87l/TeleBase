import Foundation

/// The wire format of TeleBase records.
///
/// A record on the wire looks like this:
///
/// ```
/// TB1|profile:35022025
/// {"ownerId":35022025,"payload":"{...}","updatedAt":1764110400}
/// ```
///
/// The first line is the **header**: the literal `TB1|`, followed by the
/// record key. Everything after the first newline is the **envelope**: a
/// JSON object with `ownerId`, `updatedAt` (unix time) and `payload`
/// (the payload itself, as raw JSON text inside a JSON string).
///
/// ## Chunked publishing
///
/// Telegram limits a photo caption to 1024 characters and a text message
/// to 4096. TeleBase therefore publishes a record the way the original
/// Urgram registry did:
///
/// 1. One message containing **only the header** — short enough to ride as
///    a photo caption (e.g. attached to a profile banner image).
/// 2. The envelope split into body chunks, each prefixed with
///    `TB1|<key>|#<index>/<count>` so readers can reassemble them in order.
///
/// `messages(for:)` produces that sequence; `assemble(messages:)`
/// reconstructs a record from messages found by a transport search.
public enum TBCodec {

    /// Prefix of every TeleBase header line.
    public static let headerPrefix = "TB1|"

    /// Telegram's photo-caption limit. The header-only message always fits.
    public static let maxCaptionLength = 1024

    /// Telegram's text-message limit.
    public static let maxMessageLength = 4096

    /// Body size of one chunk, leaving room for the chunk prefix line.
    static let chunkBodyLimit = 3800

    // MARK: - Envelope

    /// The JSON envelope that follows the header line.
    struct Envelope: Codable {
        var ownerId: Int64
        var updatedAt: TimeInterval
        var payload: String
    }

    // MARK: - Header

    /// The header line for a record key, e.g. `TB1|profile:35022025`.
    public static func header(forKey key: String) -> String {
        headerPrefix + key
    }

    /// Extracts the record key from a message that starts with a header,
    /// or returns `nil` when the message is not a TeleBase message.
    public static func key(fromMessage text: String) -> String? {
        guard text.hasPrefix(headerPrefix) else { return nil }
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        var rest = firstLine.dropFirst(headerPrefix.count)
        // Strip a chunk suffix "|#i/n" if present.
        if let hashRange = rest.range(of: "|#") {
            rest = rest[..<hashRange.lowerBound]
        }
        return rest.isEmpty ? nil : String(rest)
    }

    // MARK: - Single-message form

    /// Encodes a record as one message: header line + envelope JSON.
    /// Used for caching and for transports without size pressure.
    public static func encode(_ record: TBRecord) throws -> String {
        let envelope = Envelope(ownerId: record.ownerId,
                                updatedAt: record.updatedAt.timeIntervalSince1970,
                                payload: record.payloadJSON)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TBError.invalidPayload
        }
        return header(forKey: record.key) + "\n" + json
    }

    /// Decodes a record from its single-message form.
    /// Returns `nil` for messages that are not TeleBase records.
    public static func decode(_ text: String) -> TBRecord? {
        guard let key = key(fromMessage: text) else { return nil }
        guard let newline = text.firstIndex(of: "\n") else { return nil }
        let json = String(text[text.index(after: newline)...])
        return decodeEnvelope(json, key: key)
    }

    static func decodeEnvelope(_ json: String, key: String) -> TBRecord? {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
        }
        return TBRecord(key: key,
                        ownerId: envelope.ownerId,
                        updatedAt: Date(timeIntervalSince1970: envelope.updatedAt),
                        payloadJSON: envelope.payload)
    }

    // MARK: - Chunked form

    /// Splits a record into the publish sequence: a header-only message
    /// (caption-safe) followed by one or more body-chunk messages.
    public static func messages(for record: TBRecord) throws -> [String] {
        let envelope = Envelope(ownerId: record.ownerId,
                                updatedAt: record.updatedAt.timeIntervalSince1970,
                                payload: record.payloadJSON)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TBError.invalidPayload
        }

        let chunks = split(json, size: chunkBodyLimit)
        var result: [String] = [header(forKey: record.key)]
        for (index, chunk) in chunks.enumerated() {
            result.append("\(header(forKey: record.key))|#\(index + 1)/\(chunks.count)\n\(chunk)")
        }
        return result
    }

    /// Reassembles a record from messages found in the group.
    ///
    /// Accepts both the chunked form (header-only message + `#i/n` chunks)
    /// and the single-message form. Returns `nil` when the chunks are
    /// incomplete or the envelope does not decode. When several complete
    /// copies exist (an owner re-published), the newest one wins.
    public static func assemble(messages: [String]) -> TBRecord? {
        // Single-message copies, if any.
        var candidates: [TBRecord] = messages.compactMap { decode($0) }

        // Chunked copies: group chunk bodies by (key, total count, envelope
        // identity). Chunks of one publication share the same envelope, so
        // we group by key and try assembling in arrival order; publications
        // are separated by the header-only message that precedes them.
        var currentKey: String?
        var currentChunks: [Int: String] = [:]
        var currentTotal = 0

        func flush() {
            guard let key = currentKey, currentTotal > 0,
                  currentChunks.count == currentTotal else { return }
            let json = (1...currentTotal).compactMap { currentChunks[$0] }.joined()
            if let record = decodeEnvelope(json, key: key) {
                candidates.append(record)
            }
        }

        for message in messages {
            guard let key = key(fromMessage: message) else { continue }
            let firstLine = message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message
            if firstLine == header(forKey: key) && !message.contains("\n") {
                // Header-only message: a new publication starts here.
                flush()
                currentKey = key
                currentChunks = [:]
                currentTotal = 0
                continue
            }
            if let marker = chunkMarker(in: firstLine) {
                if currentKey != key {
                    flush()
                    currentKey = key
                    currentChunks = [:]
                }
                currentTotal = marker.total
                let body = message.split(separator: "\n", maxSplits: 1).last.map(String.init) ?? ""
                currentChunks[marker.index] = body
            }
        }
        flush()

        guard let key = candidates.first?.key else { return nil }
        return candidates
            .filter { $0.key == key }
            .max(by: { $0.updatedAt < $1.updatedAt })
    }

    /// Parses the `#i/n` suffix of a chunk header line.
    static func chunkMarker(in headerLine: String) -> (index: Int, total: Int)? {
        guard let hash = headerLine.range(of: "|#") else { return nil }
        let suffix = headerLine[hash.upperBound...]
        let parts = suffix.split(separator: "/")
        guard parts.count == 2,
              let index = Int(parts[0]),
              let total = Int(parts[1]) else { return nil }
        return (index, total)
    }

    static func split(_ string: String, size: Int) -> [String] {
        guard string.count > size else { return [string] }
        var chunks: [String] = []
        var start = string.startIndex
        while start < string.endIndex {
            let end = string.index(start, offsetBy: size, limitedBy: string.endIndex) ?? string.endIndex
            chunks.append(String(string[start..<end]))
            start = end
        }
        return chunks
    }
}

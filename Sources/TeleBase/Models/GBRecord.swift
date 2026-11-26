import Foundation

/// A single record stored in a TeleBase registry group.
///
/// A record is the unit of data in TeleBase. On the wire it is a header line
/// (`TB1|<key>`) followed by a small JSON envelope that carries `ownerId`,
/// `updatedAt` and the payload as raw JSON text. See `TBCodec` for the exact
/// format and `Docs/TransportGuide.md` for how transports move records around.
///
/// Ownership rule: a record is only trustworthy when the transport reports
/// that the message(s) carrying it were posted by `ownerId`. Anyone can type
/// a header line — only the real owner can post *as* the owner.
/// `TBRegistryClient` enforces this on every read.
public struct TBRecord: Equatable, Sendable {

    /// Unique key of the record inside the group, e.g. `"profile:35022025"`.
    /// Convention: `"<type>:<ownerId>"`, so all records of one owner and type
    /// share exactly one key, and the newest one wins.
    public var key: String

    /// Telegram user id of the record's owner.
    public var ownerId: Int64

    /// Last modification time. When several records share a key, the one
    /// with the greatest `updatedAt` wins.
    public var updatedAt: Date

    /// The payload, stored as raw JSON text.
    public var payloadJSON: String

    public init(key: String, ownerId: Int64, updatedAt: Date = Date(), payloadJSON: String) {
        self.key = key
        self.ownerId = ownerId
        self.updatedAt = updatedAt
        self.payloadJSON = payloadJSON
    }

    /// Creates a record by JSON-encoding a typed payload.
    public init<Payload: Encodable>(key: String, ownerId: Int64, updatedAt: Date = Date(), payload: Payload) throws {
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TBError.invalidPayload
        }
        self.init(key: key, ownerId: ownerId, updatedAt: updatedAt, payloadJSON: json)
    }

    /// Decodes the payload as a typed value.
    public func payload<Payload: Decodable>(as type: Payload.Type) throws -> Payload {
        try JSONDecoder().decode(Payload.self, from: Data(payloadJSON.utf8))
    }
}

/// Errors thrown by TeleBase.
public enum TBError: Error, Equatable {
    /// A payload could not be encoded as UTF-8 JSON.
    case invalidPayload
    /// A fetched record failed ownership verification (poster != owner).
    case ownershipVerificationFailed(key: String)
    /// The broadcast feed could not be fetched or parsed.
    case broadcastUnavailable
    /// The channel HTML did not contain any messages.
    case emptyFeed
}

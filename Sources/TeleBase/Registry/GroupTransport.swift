import Foundation

/// One message in the registry group, as reported by a transport.
///
/// `posterId` is the heart of TeleBase's security model: it must be the
/// Telegram user id of the account that actually sent the message, as
/// reported by the Telegram client itself — never a value parsed out of
/// the message text.
public struct TBTransportMessage: Equatable, Sendable {
    public var id: Int64
    public var posterId: Int64
    public var text: String
    public var date: Date

    public init(id: Int64, posterId: Int64, text: String, date: Date = Date()) {
        self.id = id
        self.posterId = posterId
        self.text = text
        self.date = date
    }
}

/// The transport TeleBase needs from a Telegram user client (MTProto).
///
/// TeleBase deliberately does **not** ship an MTProto implementation —
/// embedding a full Telegram client is a project of its own (the original
/// registry lives inside a Telegram fork). Instead, any client that can
/// join a group, search its messages and post to it can conform to this
/// protocol in a few dozen lines. `Docs/TransportGuide.md` walks through a
/// TDLib-style conformance step by step, and `MockGroupTransport` provides
/// an in-memory implementation for tests and demos.
///
/// The expected usage pattern is **join → operate → leave**: the client
/// joins the registry group, does its searches/posts, and leaves again, so
/// the group does not sit in the user's chat list. (Reading a group you are
/// not a member of returns nothing on Telegram — the join is not optional.)
public protocol GroupTransport: AnyObject {

    /// The Telegram user id of the signed-in account. Records published
    /// through this transport are owned by this id.
    var currentUserId: Int64 { get }

    /// Joins the registry group. Safe to call when already joined.
    func join() async throws

    /// Leaves the registry group. Safe to call when not joined.
    func leave() async throws

    /// Searches the group's message history for `query` and returns the
    /// matching messages in chronological order (oldest first).
    func search(query: String) async throws -> [TBTransportMessage]

    /// Posts a text message to the group and returns it as sent.
    @discardableResult
    func post(text: String) async throws -> TBTransportMessage

    /// Posts a message that carries the record header on its own — in a
    /// real client this is typically a photo (e.g. a profile banner) whose
    /// caption is the header. The default implementation posts the header
    /// as a plain text message, which is equally valid for readers.
    @discardableResult
    func postHeader(_ header: String) async throws -> TBTransportMessage
}

public extension GroupTransport {
    func postHeader(_ header: String) async throws -> TBTransportMessage {
        try await post(text: header)
    }
}

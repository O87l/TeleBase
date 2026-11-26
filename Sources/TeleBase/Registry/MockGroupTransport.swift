import Foundation

/// An in-memory `GroupTransport` for tests, demos and previews.
///
/// It behaves like a tiny group: messages are stored in an array, `search`
/// matches substrings, and everything the "current user" posts is stamped
/// with `currentUserId`. Use `inject(text:posterId:)` to simulate messages
/// posted by other accounts — including impostors — and watch the registry
/// client reject them.
public final class MockGroupTransport: GroupTransport {

    public let currentUserId: Int64

    /// All messages currently in the fake group, oldest first.
    public private(set) var messages: [TBTransportMessage] = []

    /// Whether the fake client is currently a member of the group.
    public private(set) var isJoined = false

    private var nextId: Int64 = 1

    public init(currentUserId: Int64) {
        self.currentUserId = currentUserId
    }

    public func join() async throws {
        isJoined = true
    }

    public func leave() async throws {
        isJoined = false
    }

    public func search(query: String) async throws -> [TBTransportMessage] {
        guard isJoined else { return [] }
        return messages.filter { $0.text.contains(query) }
    }

    @discardableResult
    public func post(text: String) async throws -> TBTransportMessage {
        let message = TBTransportMessage(id: nextId, posterId: currentUserId, text: text)
        nextId += 1
        messages.append(message)
        return message
    }

    // MARK: - Test/demo helpers (not part of the protocol)

    /// Adds a message as if posted by another account.
    @discardableResult
    public func inject(text: String, posterId: Int64, date: Date = Date()) -> TBTransportMessage {
        let message = TBTransportMessage(id: nextId, posterId: posterId, text: text, date: date)
        nextId += 1
        messages.append(message)
        return message
    }

    /// Removes all messages, simulating a fresh group.
    public func removeAllMessages() {
        messages.removeAll()
    }
}

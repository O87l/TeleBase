import Foundation

/// Record resolution rules: verification and newest-wins.
///
/// These are pure functions so they can be tested without any transport.
public enum TBResolver {

    /// Keeps only the messages whose transport-reported poster matches the
    /// owner of the record they belong to.
    ///
    /// Verification is per message: a publication consists of several
    /// messages (header + chunks), and *every* one of them must come from
    /// the owner. A single foreign chunk poisons the copy it belongs to —
    /// but `TBCodec.assemble` only ever builds a record out of a complete
    /// run of chunks, so callers should verify the messages first and then
    /// assemble from the survivors, which is what `TBRegistryClient` does.
    public static func verifiedMessages(_ messages: [TBTransportMessage],
                                        ownerId: Int64) -> [TBTransportMessage] {
        messages.filter { $0.posterId == ownerId }
    }

    /// Picks the newest record for `key` out of `records`.
    /// Returns `nil` when no record carries that key.
    public static func newest(_ records: [TBRecord], forKey key: String) -> TBRecord? {
        records
            .filter { $0.key == key }
            .max(by: { $0.updatedAt < $1.updatedAt })
    }
}

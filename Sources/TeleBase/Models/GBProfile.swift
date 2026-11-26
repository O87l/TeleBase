import Foundation

/// An example payload: a public profile card.
///
/// This is the payload shape TeleBase was invented for — in the Urgram app,
/// users publish a profile card (banner, bio, links) into a registry group,
/// and other copies of the app render it on the owner's profile. It is kept
/// in the library as a ready-made example; your app can define any
/// `Codable` payload it likes.
public struct TBProfile: Codable, Equatable, Sendable {

    public var displayName: String
    public var bio: String

    /// Optional banner image URL shown at the top of the profile.
    /// (In the original Urgram design the banner image itself travels as the
    /// photo message whose caption carries the record header.)
    public var bannerURL: String?

    /// Optional avatar image URL.
    public var avatarURL: String?

    /// Free-form social links, e.g. `["telegram": "https://t.me/example"]`.
    public var links: [String: String]

    public init(displayName: String,
                bio: String,
                bannerURL: String? = nil,
                avatarURL: String? = nil,
                links: [String: String] = [:]) {
        self.displayName = displayName
        self.bio = bio
        self.bannerURL = bannerURL
        self.avatarURL = avatarURL
        self.links = links
    }

    /// The registry key under which a user's profile card is stored.
    public static func recordKey(ownerId: Int64) -> String {
        "profile:\(ownerId)"
    }
}

import SwiftUI
import TeleBase

/// Demo root: two tabs, one per TeleBase mode.
///
/// - **Broadcast** talks to a real public channel over HTTPS — no account,
///   works as-is.
/// - **Registry** runs the full publish/read flow against
///   `MockGroupTransport`, so you can see records, chunking and ownership
///   verification without a Telegram client.
struct ContentView: View {
    var body: some View {
        TabView {
            BroadcastDemoView()
                .tabItem { Label("Broadcast", systemImage: "megaphone") }
            RegistryDemoView()
                .tabItem { Label("Registry", systemImage: "person.crop.rectangle") }
        }
    }
}

// MARK: - Broadcast demo (remote config from a public channel)

struct BroadcastDemoView: View {
    @State private var channel = "telegram"
    @State private var config: TBRemoteConfig?
    @State private var status = "Not loaded yet."

    private let client = TeleBase.broadcastClient()

    var body: some View {
        NavigationStack {
            Form {
                Section("Public channel") {
                    TextField("Channel username", text: $channel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Fetch remote config") {
                        Task { await load() }
                    }
                }
                Section("Result") {
                    Text(status)
                    if let config {
                        if let announcement = config.announcement {
                            LabeledContent("Announcement", value: announcement)
                        }
                        if let minVersion = config.minVersion {
                            LabeledContent("Min version", value: minVersion)
                        }
                        ForEach(config.featureFlags.sorted(by: { $0.key < $1.key }), id: \.key) { flag in
                            LabeledContent(flag.key, value: flag.value ? "ON" : "OFF")
                        }
                    }
                }
                Section {
                    Text("Post a message starting with TBCFG followed by a JSON object in the channel, then fetch again. See TBRemoteConfig for the format.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Broadcast mode")
        }
    }

    private func load() async {
        do {
            let fetched = try await client.fetchConfig(channel: channel)
            config = fetched
            status = "Loaded from t.me/\(channel)"
        } catch {
            status = "Failed: \(error.localizedDescription). (The demo channel has no TBCFG message — config falls back to cache, and there is none yet.)"
        }
    }
}

// MARK: - Registry demo (profile card over the mock transport)

struct RegistryDemoView: View {
    @State private var name = "AbdDev"
    @State private var bio = "iOS Developer & Content Creator from Iraq"
    @State private var fetched: TBProfile?
    @State private var status = "Nothing published yet."

    private let myId: Int64 = 42
    @State private var transport: MockGroupTransport?
    @State private var client: TBRegistryClient?

    var body: some View {
        NavigationStack {
            Form {
                Section("My profile card") {
                    TextField("Display name", text: $name)
                    TextField("Bio", text: $bio)
                    Button("Publish to group") {
                        Task { await publish() }
                    }
                }
                Section("Read back") {
                    Button("Fetch newest verified copy") {
                        Task { await fetch() }
                    }
                    if let fetched {
                        LabeledContent("Name", value: fetched.displayName)
                        LabeledContent("Bio", value: fetched.bio)
                    }
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("Publishing writes a header message plus body chunks into the (mock) group. Fetching reassembles them, verifies the poster is the owner, and resolves newest-first — exactly what a real MTProto transport would do.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Registry mode")
            .onAppear(perform: setUp)
        }
    }

    private func setUp() {
        if transport == nil {
            let mock = MockGroupTransport(currentUserId: myId)
            transport = mock
            client = TeleBase.registryClient(transport: mock)
        }
    }

    private func publish() async {
        guard let client else { return }
        do {
            let profile = TBProfile(displayName: name, bio: bio)
            try await client.publish(profile, key: TBProfile.recordKey(ownerId: myId))
            status = "Published. The group now holds the header + chunk messages."
        } catch {
            status = "Publish failed: \(error.localizedDescription)"
        }
    }

    private func fetch() async {
        guard let client else { return }
        do {
            client.invalidate(key: TBProfile.recordKey(ownerId: myId))
            fetched = try await client.fetch(key: TBProfile.recordKey(ownerId: myId), as: TBProfile.self)
            status = fetched == nil ? "No verified record found." : "Fetched and ownership-verified."
        } catch {
            status = "Fetch failed: \(error.localizedDescription)"
        }
    }
}

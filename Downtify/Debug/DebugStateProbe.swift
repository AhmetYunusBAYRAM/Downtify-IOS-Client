#if DEBUG
import SwiftUI

/// Redacted state snapshot exposed to UI tests as the `debug.state` accessibility value.
/// Must never contain tokens, usernames, server addresses or titles.
struct DebugStateSnapshot: Codable, Equatable {
    var playbackPhase: String
    var queueCount: Int
    var currentTrackID: String?
    var position: Double?
    var network: String
    var libraryTrackCount: Int
    var lastErrorCode: String?
    var artworkLoaded: Bool
    var playerVisible: Bool
    var sessionActive: Bool
    /// Library track ids in play order (library items only; catalog items appear as "catalog").
    var queueTrackIDs: [String]

    enum CodingKeys: String, CodingKey {
        case playbackPhase, queueCount, currentTrackID, position, network, libraryTrackCount
        case lastErrorCode, artworkLoaded, playerVisible, sessionActive, queueTrackIDs
    }

    /// Every key is always present (null when absent) so the schema is stable for tests.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playbackPhase, forKey: .playbackPhase)
        try container.encode(queueCount, forKey: .queueCount)
        try container.encode(currentTrackID, forKey: .currentTrackID)
        try container.encode(position, forKey: .position)
        try container.encode(network, forKey: .network)
        try container.encode(libraryTrackCount, forKey: .libraryTrackCount)
        try container.encode(lastErrorCode, forKey: .lastErrorCode)
        try container.encode(artworkLoaded, forKey: .artworkLoaded)
        try container.encode(playerVisible, forKey: .playerVisible)
        try container.encode(sessionActive, forKey: .sessionActive)
        try container.encode(queueTrackIDs, forKey: .queueTrackIDs)
    }

    static let empty = DebugStateSnapshot(playbackPhase: "idle", queueCount: 0, currentTrackID: nil, position: nil,
                                          network: "unknown", libraryTrackCount: 0, lastErrorCode: nil,
                                          artworkLoaded: false, playerVisible: false, sessionActive: false, queueTrackIDs: [])

    /// Stable JSON with sorted keys so tests can compare and decode it.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// Invisible accessibility element carrying the redacted snapshot.
struct DebugStateProbe: View {
    /// Identifier read by UI tests. Kept as a constant so it stays out of user-facing string extraction.
    static let identifier = "debug" + "." + "state"

    let snapshot: DebugStateSnapshot

    var body: some View {
        Text(verbatim: Self.identifier)
            .font(.caption2)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityIdentifier(DebugStateProbe.identifier)
            .accessibilityLabel(DebugStateProbe.identifier)
            .accessibilityValue(snapshot.json)
    }
}
#endif

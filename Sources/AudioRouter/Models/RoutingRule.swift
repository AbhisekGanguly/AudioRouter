import Foundation

/// A persisted "this app plays on this device" rule, keyed by bundle identifier.
struct RoutingRule: Codable, Equatable {
    let bundleID: String
    let deviceUID: String
    /// Snapshots so the UI can show meaningful rows while app/device are absent.
    let deviceName: String
    let appName: String
    /// Per-app gain (0...1) applied while the route is active.
    var volume: Float

    init(bundleID: String, deviceUID: String, deviceName: String, appName: String, volume: Float = 1.0) {
        self.bundleID = bundleID
        self.deviceUID = deviceUID
        self.deviceName = deviceName
        self.appName = appName
        self.volume = volume
    }

    // Manual decoding so rules.json files written before `volume` existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        deviceUID = try container.decode(String.self, forKey: .deviceUID)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        appName = try container.decode(String.self, forKey: .appName)
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
    }
}

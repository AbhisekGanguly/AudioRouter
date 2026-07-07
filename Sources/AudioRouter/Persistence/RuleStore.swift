import Foundation
import os.log

/// Loads/saves routing rules as JSON in Application Support, keyed by bundle ID.
final class RuleStore {
    private(set) var rules: [String: RoutingRule] = [:]

    private let fileURL: URL
    private static let log = Logger(subsystem: "com.abhisekganguly.AudioRouter", category: "RuleStore")

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("AudioRouter", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("rules.json")
        load()
    }

    func rule(for bundleID: String) -> RoutingRule? {
        rules[bundleID]
    }

    func set(_ rule: RoutingRule) {
        rules[rule.bundleID] = rule
        save()
    }

    func removeRule(for bundleID: String) {
        rules.removeValue(forKey: bundleID)
        save()
    }

    /// Volume updates arrive continuously while a slider drags, so the disk
    /// write is debounced; `flush()` forces any pending write out.
    func updateVolume(bundleID: String, volume: Float) {
        guard var rule = rules[bundleID] else { return }
        rule.volume = volume
        rules[bundleID] = rule
        scheduleSave()
    }

    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        save()
    }

    private var saveWorkItem: DispatchWorkItem?

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([RoutingRule].self, from: data)
            rules = Dictionary(uniqueKeysWithValues: decoded.map { ($0.bundleID, $0) })
        } catch {
            Self.log.error("Failed to decode rules.json: \(error, privacy: .public)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rules.values.sorted { $0.bundleID < $1.bundleID })
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.log.error("Failed to save rules.json: \(error, privacy: .public)")
        }
    }
}

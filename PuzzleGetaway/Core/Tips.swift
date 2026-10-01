import Foundation

/// A first-time tutorial tip card.
struct TipCard: Equatable, Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let body: String
}

private struct TipEntry: Codable {
    var title: String
    var body: String
}

private struct TipsFile: Codable {
    var tips: [String: TipEntry]
}

/// Reads `Resources/Tips/<mode>.json` (`{ "tips": { "<key>": { "title", "body" } } }`) through the content store.
enum TipLibrary {
    private static var cache: [String: [String: TipEntry]] = [:]

    private static func tips(forMode mode: String, content: ContentStore) -> [String: TipEntry] {
        if let hit = cache[mode] { return hit }
        let url = content.root.appendingPathComponent("Tips/\(mode).json")
        var result: [String: TipEntry] = [:]
        if let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(TipsFile.self, from: data) {
            result = file.tips
        }
        cache[mode] = result
        return result
    }

    /// Looks a key up in the level's own mode file, then in the file named by the key's prefix ("liquid.pour" -> liquid).
    static func tip(key: String, mode: String, content: ContentStore) -> TipCard? {
        var candidates = [mode]
        if let prefix = key.split(separator: ".").first, String(prefix) != "twist", String(prefix) != mode {
            candidates.append(String(prefix))
        }
        for m in candidates {
            if let entry = tips(forMode: m, content: content)[key] {
                return TipCard(key: key, title: entry.title, body: entry.body)
            }
        }
        return nil
    }

    /// The first tip for this level the player has not seen yet: the tutorial key, then each twist.
    static func pending(for level: LevelEnvelope, seen: Set<String>, content: ContentStore) -> TipCard? {
        var keys: [String] = []
        if let t = level.tutorial { keys.append(t) }
        for twist in level.twists { keys.append("twist.\(twist)") }
        for key in keys where !seen.contains(key) {
            if let card = tip(key: key, mode: level.mode, content: content) { return card }
        }
        return nil
    }
}

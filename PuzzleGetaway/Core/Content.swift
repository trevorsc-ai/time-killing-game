import Foundation

// MARK: - JSONValue

/// Free-form JSON. Level payloads and solution moves are kept as JSONValue in the shared envelope;
/// each mode decodes its own typed payload/moves with `decoded(as:)`.
enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// Re-encodes this value and decodes it as `T`. Use for payloads and moves.
    func decoded<T: Decodable>(as type: T.Type = T.self) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

// MARK: - Levels

/// Shared level envelope. See docs/level-format.md. `payload` and `solution` are mode-specific.
struct LevelEnvelope: Codable, Hashable, Identifiable {
    var id: String
    var mode: String
    var destination: String
    var order: Int
    var title: String
    var difficulty: Int
    var tutorial: String?
    var twists: [String]
    var par: Int
    var solution: [JSONValue]
    var payload: JSONValue

    /// Decode the mode-specific payload.
    func decodePayload<P: Decodable>(_ type: P.Type = P.self) throws -> P {
        try payload.decoded(as: type)
    }

    /// Decode the stored solution as typed moves.
    func decodeSolution<M: Decodable>(_ type: M.Type = M.self) throws -> [M] {
        try solution.map { try $0.decoded(as: type) }
    }
}

struct LevelFile: Codable {
    var destination: String
    var mode: String
    var levels: [LevelEnvelope]
}

struct PoolFile: Codable {
    var pool: String
    var entries: [LevelEnvelope]
}

// MARK: - Destinations

struct DestinationTheme: Codable, Hashable {
    var primary: String
    var secondary: String
    var accent: String
    var background: String
}

struct RestorationStage: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var starsRequired: Int
    var scrapbookArtId: String
}

struct Destination: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var tagline: String
    var intro: String
    var theme: DestinationTheme
    var comingSoon: Bool
    var restorationTitle: String
    var restorationStages: [RestorationStage]
}

struct DestinationsFile: Codable {
    var unlockPercent: Int
    var destinations: [Destination]
}

// MARK: - Palette

struct PaletteColor: Codable, Hashable, Identifiable {
    /// Single-character key used by level payloads and pixel art.
    var id: String
    var name: String
    var hex: String
    var highContrastHex: String
    /// SF Symbol name used as the accessibility pattern.
    var symbol: String
}

struct Palette: Codable, Hashable {
    var colors: [PaletteColor]

    func color(_ id: String) -> PaletteColor? {
        colors.first { $0.id == id }
    }
}

// MARK: - Resource lookup

/// Finds the bundled `Resources` folder reference (see project.yml).
///
/// The app bundle contains `Content/Resources/Levels/*.json`, `.../Pools/*.json`, `.../Art/*.json`
/// and `.../Destinations.json` (a folder reference copied into `Content/`; a `Resources` directory at the
/// bundle root breaks app installation, see project.yml). In hosted unit tests `Bundle.main` is the app bundle, and
/// `Bundle(for:)` of an app class resolves to the same bundle, so this works for both.
enum ResourceLocator {
    private final class BundleToken {}

    static func resourcesRoot(bundles: [Bundle] = [Bundle.main, Bundle(for: BundleToken.self)]) -> URL? {
        let fm = FileManager.default
        for bundle in bundles {
            guard let base = bundle.resourceURL else { continue }
            let nestedPaths = ["Content/Resources", "Resources"]
            for rel in nestedPaths {
                let nested = base.appendingPathComponent(rel, isDirectory: true)
                if fm.fileExists(atPath: nested.appendingPathComponent("Levels").path) { return nested }
            }
            if fm.fileExists(atPath: base.appendingPathComponent("Levels").path) { return base }
        }
        return nil
    }

    /// All `.json` files directly inside `Resources/<subdirectory>`, sorted by file name.
    static func jsonFiles(in subdirectory: String, root: URL) -> [URL] {
        let dir = root.appendingPathComponent(subdirectory, isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

// MARK: - ContentStore

enum ContentError: Error, CustomStringConvertible {
    case resourcesNotFound
    case missingFile(String)
    case decoding(file: String, underlying: Error)
    case duplicateLevelId(String)

    var description: String {
        switch self {
        case .resourcesNotFound: return "Bundled Resources folder not found"
        case .missingFile(let f): return "Missing resource file: \(f)"
        case .decoding(let f, let e): return "Cannot decode \(f): \(e)"
        case .duplicateLevelId(let id): return "Duplicate level id: \(id)"
        }
    }
}

/// Immutable, fully loaded bundled content. Load once at launch via `ContentStore.load()`.
final class ContentStore {
    let destinations: [Destination]
    let unlockPercent: Int
    let palette: Palette
    /// All level-file levels merged and sorted by (destination id, order). Includes the "demo" destination.
    let allLevels: [LevelEnvelope]
    /// Pools by name: relax-liquid, relax-pixel, relax-pipe, daily.
    let pools: [String: [LevelEnvelope]]
    let root: URL

    static func load(bundles: [Bundle] = [Bundle.main, Bundle(for: ContentStore.self)]) throws -> ContentStore {
        guard let root = ResourceLocator.resourcesRoot(bundles: bundles) else { throw ContentError.resourcesNotFound }
        return try ContentStore(root: root)
    }

    init(root: URL) throws {
        self.root = root
        let decoder = JSONDecoder()

        func read<T: Decodable>(_ url: URL, as type: T.Type) throws -> T {
            guard let data = try? Data(contentsOf: url) else { throw ContentError.missingFile(url.lastPathComponent) }
            do { return try decoder.decode(T.self, from: data) } catch {
                throw ContentError.decoding(file: url.lastPathComponent, underlying: error)
            }
        }

        let dest = try read(root.appendingPathComponent("Destinations.json"), as: DestinationsFile.self)
        destinations = dest.destinations
        unlockPercent = dest.unlockPercent
        palette = try read(root.appendingPathComponent("Art/palette.json"), as: Palette.self)

        var levels: [LevelEnvelope] = []
        var seen = Set<String>()
        for url in ResourceLocator.jsonFiles(in: "Levels", root: root) {
            let file = try read(url, as: LevelFile.self)
            for level in file.levels {
                if !seen.insert(level.id).inserted { throw ContentError.duplicateLevelId(level.id) }
                levels.append(level)
            }
        }
        levels.sort { a, b in
            a.destination == b.destination ? a.order < b.order : a.destination < b.destination
        }
        allLevels = levels

        var pools: [String: [LevelEnvelope]] = [:]
        for url in ResourceLocator.jsonFiles(in: "Pools", root: root) {
            let file = try read(url, as: PoolFile.self)
            for entry in file.entries where !seen.insert(entry.id).inserted {
                throw ContentError.duplicateLevelId(entry.id)
            }
            pools[file.pool] = file.entries.sorted { $0.order < $1.order }
        }
        self.pools = pools
    }

    /// Levels of one destination sorted by `order`.
    func levels(in destinationId: String) -> [LevelEnvelope] {
        allLevels.filter { $0.destination == destinationId }
    }

    func level(id: String) -> LevelEnvelope? {
        allLevels.first { $0.id == id } ?? pools.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    func destination(id: String) -> Destination? {
        destinations.first { $0.id == id }
    }

    func pool(_ name: String) -> [LevelEnvelope] {
        pools[name] ?? []
    }

    /// Raw bytes of `Resources/Art/<name>.json` (pixel scenes, scrapbook art, ...), if present.
    func artData(named name: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent("Art/\(name).json"))
    }

    /// Every level and pool entry in the bundle (for replay tests).
    var everyLevel: [LevelEnvelope] {
        allLevels + pools.values.flatMap { $0 }
    }
}

import Foundation
import CryptoKit

// MARK: - Model

struct LevelResult: Codable, Hashable {
    var stars: Int
    var bestMoves: Int
    var completedAt: Date
}

/// Everything persisted for the player. Bump `SaveData.currentVersion` when the shape changes incompatibly.
struct SaveData: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = SaveData.currentVersion
    /// Best result per level id (levels and Daily/Relax ids are all just level ids).
    var progress: [String: LevelResult] = [:]
    /// Resume snapshots (opaque, produced by `AnyGameController.snapshot()`), keyed by level/pool id.
    var inProgress: [String: Data] = [:]
    var settings: SettingsValues = SettingsValues()
    var scrapbookUnlocked: Set<String> = []
    var restorationStagesSeen: Set<String> = []
    /// Daily journeys the player has taken, keyed "yyyy-MM-dd" (local date). No streaks.
    var dailyJourneysTaken: Set<String> = []
    var tutorialsSeen: Set<String> = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? SaveData.currentVersion
        progress = try c.decodeIfPresent([String: LevelResult].self, forKey: .progress) ?? [:]
        inProgress = try c.decodeIfPresent([String: Data].self, forKey: .inProgress) ?? [:]
        settings = try c.decodeIfPresent(SettingsValues.self, forKey: .settings) ?? SettingsValues()
        scrapbookUnlocked = try c.decodeIfPresent(Set<String>.self, forKey: .scrapbookUnlocked) ?? []
        restorationStagesSeen = try c.decodeIfPresent(Set<String>.self, forKey: .restorationStagesSeen) ?? []
        dailyJourneysTaken = try c.decodeIfPresent(Set<String>.self, forKey: .dailyJourneysTaken) ?? []
        tutorialsSeen = try c.decodeIfPresent(Set<String>.self, forKey: .tutorialsSeen) ?? []
    }

    var totalStars: Int { progress.values.reduce(0) { $0 + $1.stars } }

    /// Records a completion, keeping the best stars and fewest moves. Clears the resume snapshot.
    mutating func recordCompletion(levelId: String, stars: Int, moves: Int, at date: Date = Date()) {
        if var existing = progress[levelId] {
            existing.stars = max(existing.stars, stars)
            existing.bestMoves = min(existing.bestMoves, moves)
            existing.completedAt = date
            progress[levelId] = existing
        } else {
            progress[levelId] = LevelResult(stars: stars, bestMoves: moves, completedAt: date)
        }
        inProgress[levelId] = nil
    }
}

// MARK: - File envelope

/// On-disk / `.pgsave` representation: the JSON of SaveData plus a SHA-256 checksum over exactly those bytes.
struct SaveFile: Codable {
    var version: Int
    var checksum: String
    var data: Data
}

enum SaveError: Error, Equatable {
    case notASaveFile
    case checksumMismatch
    case unsupportedVersion(Int)
    case corruptPayload
}

// MARK: - Store

/// Atomic, checksummed, backup-rotating persistence in Application Support.
///
/// Files: `save.json` (main) and `save.bak.json` (last known-good main, rotated before each write).
/// Threading: call from the main thread. `requestSave` debounces; `saveNow` flushes immediately.
final class SaveStore {
    enum Source: Equatable {
        case fresh      // nothing on disk
        case main       // loaded from save.json
        case backup     // main missing/corrupt; recovered from save.bak.json
    }

    struct LoadResult {
        var data: SaveData
        var source: Source
        /// True when save.json existed but failed validation.
        var mainWasCorrupt: Bool
    }

    let directory: URL
    var mainURL: URL { directory.appendingPathComponent("save.json") }
    var backupURL: URL { directory.appendingPathComponent("save.bak.json") }

    private let fm = FileManager.default
    private var pendingProvider: (() -> SaveData)?
    private var pendingWork: DispatchWorkItem?

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PuzzleGetaway", isDirectory: true)
    }

    init(directory: URL = SaveStore.defaultDirectory) {
        self.directory = directory
    }

    // MARK: Encoding

    static func encode(_ save: SaveData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(save)
        let file = SaveFile(version: save.version, checksum: checksum(of: payload), data: payload)
        return try encoder.encode(file)
    }

    /// Validates and decodes a save file (also used for `.pgsave` import).
    static func decode(_ bytes: Data) throws -> SaveData {
        let decoder = JSONDecoder()
        guard let file = try? decoder.decode(SaveFile.self, from: bytes) else { throw SaveError.notASaveFile }
        guard file.checksum == checksum(of: file.data) else { throw SaveError.checksumMismatch }
        guard file.version <= SaveData.currentVersion else { throw SaveError.unsupportedVersion(file.version) }
        guard let save = try? decoder.decode(SaveData.self, from: file.data) else { throw SaveError.corruptPayload }
        return save
    }

    static func checksum(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Load / save

    func load() -> LoadResult {
        var mainCorrupt = false
        if let bytes = try? Data(contentsOf: mainURL) {
            if let save = try? SaveStore.decode(bytes) {
                return LoadResult(data: save, source: .main, mainWasCorrupt: false)
            }
            mainCorrupt = true
        }
        if let bytes = try? Data(contentsOf: backupURL), let save = try? SaveStore.decode(bytes) {
            return LoadResult(data: save, source: .backup, mainWasCorrupt: mainCorrupt)
        }
        return LoadResult(data: SaveData(), source: .fresh, mainWasCorrupt: mainCorrupt)
    }

    /// Writes immediately. Rotates the current main to save.bak.json first, but only if that main is valid.
    func save(_ save: SaveData) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = try SaveStore.encode(save)
        if let existing = try? Data(contentsOf: mainURL), (try? SaveStore.decode(existing)) != nil {
            try existing.write(to: backupURL, options: .atomic)
        }
        try bytes.write(to: mainURL, options: .atomic)
    }

    // MARK: Debounced saving

    /// Schedules a save `delay` seconds from now, coalescing repeated calls. The provider is evaluated at write time.
    func requestSave(delay: TimeInterval = 0.5, provider: @escaping () -> SaveData) {
        pendingProvider = provider
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Flushes any pending debounced save right now (call on scenePhase .inactive/.background).
    /// Returns true if something was written.
    @discardableResult
    func saveNow() -> Bool {
        pendingWork?.cancel()
        pendingWork = nil
        guard let provider = pendingProvider else { return false }
        pendingProvider = nil
        do {
            try save(provider())
            return true
        } catch {
            return false
        }
    }

    var hasPendingSave: Bool { pendingProvider != nil }

    // MARK: Export / import

    /// Bytes for a `.pgsave` file.
    func exportData(_ save: SaveData) throws -> Data {
        try SaveStore.encode(save)
    }

    /// Validates `.pgsave` bytes; throws SaveError if invalid. Does not touch disk.
    static func validateImport(_ bytes: Data) throws -> SaveData {
        try decode(bytes)
    }

    /// Deletes both save files (used by "reset progress" and UI-test launch).
    func wipe() {
        try? fm.removeItem(at: mainURL)
        try? fm.removeItem(at: backupURL)
    }
}

import Foundation

/// An item of the scrapbook: one pixel illustration unlocked by one restoration stage.
struct ScrapbookEntry: Hashable, Identifiable {
    var id: String { artId }
    let artId: String
    let destinationId: String
    let destinationName: String
    let stage: RestorationStage
    /// 1-based index of the stage inside its destination.
    let stageNumber: Int
}

/// Pure progression rules (unlocks, stars to restoration stages, Continue / Quick Play targets, Daily and Relax
/// selection). It holds no state of its own: every query takes the current `SaveData`.
///
/// Rules (see docs/rules.md "Progression constants"):
/// - Levels inside a destination unlock in `order`: a level opens once the previous level has a recorded result.
/// - A destination opens when the previous one has at least `ceil(unlockPercent% of its levels)` recorded results.
///   The first destination is always open; "coming soon" destinations and ones with no levels never open.
/// - A restoration stage unlocks when the destination's total stars reach `starsRequired`.
struct Progression {
    static let relaxPools = ["relax-liquid", "relax-pixel", "relax-pipe"]
    static let dailyPool = "daily"

    let destinations: [Destination]
    /// Every level-file level (campaign destinations plus the development "demo" destination).
    let levels: [LevelEnvelope]
    let pools: [String: [LevelEnvelope]]
    let unlockPercent: Int
    private let isPlayable: (String) -> Bool
    private let rank: [String: Int]

    init(destinations: [Destination],
         levels: [LevelEnvelope],
         pools: [String: [LevelEnvelope]] = [:],
         unlockPercent: Int = 60,
         isPlayable: @escaping (String) -> Bool = { ModeRegistry.plugin(for: $0) != nil }) {
        self.destinations = destinations
        self.pools = pools
        self.unlockPercent = unlockPercent
        self.isPlayable = isPlayable
        var rank: [String: Int] = [:]
        for (i, d) in destinations.enumerated() { rank[d.id] = i }
        self.rank = rank
        self.levels = levels.sorted { a, b in
            let ra = rank[a.destination] ?? 1000
            let rb = rank[b.destination] ?? 1000
            if ra != rb { return ra < rb }
            if a.destination != b.destination { return a.destination < b.destination }
            return a.order < b.order
        }
    }

    /// - Parameter demoOnly: UI-test hook (`-PGDemoOnly`): the only playable levels are the demo-mode levels,
    ///   mapped into destination d1 (so the map, level list and restoration flows can be exercised with any content).
    init(content: ContentStore, demoOnly: Bool = false) {
        if demoOnly {
            let demo: [LevelEnvelope] = content.allLevels.filter { $0.destination == "demo" }.map { level in
                var mapped = level
                mapped.destination = "d1"
                return mapped
            }
            self.init(destinations: content.destinations,
                      levels: demo,
                      pools: [:],
                      unlockPercent: content.unlockPercent)
        } else {
            self.init(destinations: content.destinations,
                      levels: content.allLevels,
                      pools: content.pools,
                      unlockPercent: content.unlockPercent)
        }
    }

    // MARK: Lookup

    func destination(_ id: String) -> Destination? { destinations.first { $0.id == id } }

    func levels(in destinationId: String) -> [LevelEnvelope] {
        levels.filter { $0.destination == destinationId }
    }

    func level(id: String) -> LevelEnvelope? {
        if let l = levels.first(where: { $0.id == id }) { return l }
        for entries in pools.values {
            if let l = entries.first(where: { $0.id == id }) { return l }
        }
        return nil
    }

    func nextDestination(after id: String) -> Destination? {
        guard let i = destinations.firstIndex(where: { $0.id == id }), i + 1 < destinations.count else { return nil }
        return destinations[i + 1]
    }

    func previousDestination(before id: String) -> Destination? {
        guard let i = destinations.firstIndex(where: { $0.id == id }), i > 0 else { return nil }
        return destinations[i - 1]
    }

    // MARK: Completion

    func completedCount(in destinationId: String, save: SaveData) -> Int {
        levels(in: destinationId).filter { save.progress[$0.id] != nil }.count
    }

    func completionFraction(in destinationId: String, save: SaveData) -> Double {
        let n = levels(in: destinationId).count
        return n == 0 ? 0 : Double(completedCount(in: destinationId, save: save)) / Double(n)
    }

    func completionPercent(in destinationId: String, save: SaveData) -> Int {
        let n = levels(in: destinationId).count
        return n == 0 ? 0 : completedCount(in: destinationId, save: save) * 100 / n
    }

    func isDestinationComplete(_ destinationId: String, save: SaveData) -> Bool {
        let n = levels(in: destinationId).count
        return n > 0 && completedCount(in: destinationId, save: save) >= n
    }

    /// How many results the destination needs before the next one opens: ceil(unlockPercent% of the level count).
    func requiredToOpenNext(after destinationId: String) -> Int {
        let n = levels(in: destinationId).count
        return (n * unlockPercent + 99) / 100
    }

    /// True when the destination has any levels laid (otherwise the map shows "Track being laid...").
    func hasLevels(_ destinationId: String) -> Bool {
        !levels(in: destinationId).isEmpty
    }

    func isDestinationUnlocked(_ destinationId: String, save: SaveData) -> Bool {
        guard let dest = destination(destinationId), !dest.comingSoon else { return false }
        guard let prev = previousDestination(before: destinationId) else { return true }
        guard hasLevels(prev.id) else { return false }
        return isDestinationUnlocked(prev.id, save: save)
            && completedCount(in: prev.id, save: save) >= requiredToOpenNext(after: prev.id)
    }

    func isLevelUnlocked(_ level: LevelEnvelope, save: SaveData) -> Bool {
        if destination(level.destination) != nil, !isDestinationUnlocked(level.destination, save: save) { return false }
        // Levels of modes that are not available are skipped in the sequence.
        let siblings = levels(in: level.destination).filter { isPlayable($0.mode) || $0.id == level.id }
        guard let idx = siblings.firstIndex(where: { $0.id == level.id }) else { return false }
        if idx == 0 { return true }
        return save.progress[siblings[idx - 1].id] != nil
    }

    // MARK: Stars and restoration

    func stars(in destinationId: String, save: SaveData) -> Int {
        levels(in: destinationId).reduce(0) { $0 + (save.progress[$1.id]?.stars ?? 0) }
    }

    func maxStars(in destinationId: String) -> Int { levels(in: destinationId).count * 3 }

    func totalStars(save: SaveData) -> Int { save.totalStars }

    func unlockedStageCount(in destinationId: String, stars: Int) -> Int {
        guard let dest = destination(destinationId) else { return 0 }
        return dest.restorationStages.filter { $0.starsRequired <= stars }.count
    }

    func unlockedStageCount(in destinationId: String, save: SaveData) -> Int {
        unlockedStageCount(in: destinationId, stars: stars(in: destinationId, save: save))
    }

    /// Stages whose threshold lies in `(fromStars, toStars]`.
    func newlyUnlockedStages(in destinationId: String, fromStars: Int, toStars: Int) -> [RestorationStage] {
        guard let dest = destination(destinationId) else { return [] }
        return dest.restorationStages.filter { $0.starsRequired > fromStars && $0.starsRequired <= toStars }
    }

    /// The first locked stage, if any.
    func nextStage(in destinationId: String, save: SaveData) -> RestorationStage? {
        guard let dest = destination(destinationId) else { return nil }
        let s = stars(in: destinationId, save: save)
        return dest.restorationStages.first { $0.starsRequired > s }
    }

    /// Restoration tier of the whole train, 0...3, from total stars (drives the main-menu illustration).
    static func trainTier(totalStars: Int) -> Int {
        switch totalStars {
        case ..<3: return 0
        case 3..<15: return 1
        case 15..<40: return 2
        default: return 3
        }
    }

    // MARK: Scrapbook

    func scrapbookEntries() -> [ScrapbookEntry] {
        var out: [ScrapbookEntry] = []
        for dest in destinations {
            for (i, stage) in dest.restorationStages.enumerated() {
                out.append(ScrapbookEntry(artId: stage.scrapbookArtId, destinationId: dest.id,
                                          destinationName: dest.name, stage: stage, stageNumber: i + 1))
            }
        }
        return out
    }

    /// Art ids unlocked by the current stars, plus anything stored in the save (e.g. imported).
    func unlockedArtIds(save: SaveData) -> Set<String> {
        var ids = save.scrapbookUnlocked
        for dest in destinations {
            let s = stars(in: dest.id, save: save)
            for stage in dest.restorationStages where stage.starsRequired <= s { ids.insert(stage.scrapbookArtId) }
        }
        return ids
    }

    // MARK: Level navigation

    /// The next playable level after `level` in its destination, if any.
    func nextLevel(after level: LevelEnvelope) -> LevelEnvelope? {
        let siblings = levels(in: level.destination)
        guard let idx = siblings.firstIndex(where: { $0.id == level.id }) else { return nil }
        return siblings[(idx + 1)...].first { isPlayable($0.mode) }
    }

    /// First unsolved, unlocked, playable level in map order (real destinations before "demo").
    func nextUnsolvedLevel(save: SaveData) -> LevelEnvelope? {
        levels.first { isPlayable($0.mode) && save.progress[$0.id] == nil && isLevelUnlocked($0, save: save) }
    }

    /// Quick Play: first unsolved unlocked level; when everything unlocked is solved, a Relax puzzle.
    func quickPlayLevel(save: SaveData) -> LevelEnvelope? {
        if let l = nextUnsolvedLevel(save: save) { return l }
        if let l = anyRelaxLevel(save: save) { return l }
        return levels.first { isPlayable($0.mode) }
    }

    /// Continue: the exact in-progress level (last touched first), else the next unsolved level, else Quick Play.
    func continueLevel(save: SaveData) -> LevelEnvelope? {
        if let id = save.lastPlayedLevelId, save.inProgress[id] != nil, let l = level(id: id), isPlayable(l.mode) {
            return l
        }
        if let l = levels.first(where: { save.inProgress[$0.id] != nil && isPlayable($0.mode) }) { return l }
        for id in save.inProgress.keys.sorted() {
            if let l = level(id: id), isPlayable(l.mode) { return l }
        }
        return quickPlayLevel(save: save)
    }

    /// True when `continueLevel` would resume a puzzle that is already under way.
    func hasInProgress(save: SaveData) -> Bool {
        save.inProgress.keys.contains { id in
            if let l = level(id: id) { return isPlayable(l.mode) }
            return false
        }
    }

    // MARK: Relax

    static func relaxTitle(pool: String) -> String {
        switch pool {
        case "relax-liquid": return "Liquid"
        case "relax-pixel": return "Pixel Picnic"
        case "relax-pipe": return "Flow Fix"
        default: return pool
        }
    }

    /// The puzzle at `position` in a pool (wrapping around), or nil when the pool is empty or unplayable.
    func relaxEntry(pool: String, position: Int) -> LevelEnvelope? {
        let entries = (pools[pool] ?? []).filter { isPlayable($0.mode) }
        guard !entries.isEmpty else { return nil }
        let n = entries.count
        return entries[((position % n) + n) % n]
    }

    func relaxCount(pool: String) -> Int {
        (pools[pool] ?? []).filter { isPlayable($0.mode) }.count
    }

    /// The puzzle the player is up to in a Relax pool.
    func currentRelaxEntry(pool: String, save: SaveData) -> LevelEnvelope? {
        relaxEntry(pool: pool, position: save.relaxPositions[pool] ?? 0)
    }

    func anyRelaxLevel(save: SaveData) -> LevelEnvelope? {
        for pool in Progression.relaxPools {
            if let l = currentRelaxEntry(pool: pool, save: save) { return l }
        }
        return nil
    }

    // MARK: Daily Journey

    /// FNV-1a, 32 bit, over the UTF-8 bytes (docs/rules.md).
    static func fnv1a32(_ text: String) -> UInt32 {
        var hash: UInt32 = 0x811c9dc5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return hash
    }

    /// Local date as zero-padded "YYYY-MM-DD".
    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func dailyIndex(forKey key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(fnv1a32(key) % UInt32(count))
    }

    /// Today's Daily Journey puzzle, or nil while the pool has no playable entries.
    func dailyEntry(for date: Date, calendar: Calendar = .current) -> LevelEnvelope? {
        let entries = (pools[Progression.dailyPool] ?? []).filter { isPlayable($0.mode) }
        guard !entries.isEmpty else { return nil }
        let key = Progression.dateKey(date, calendar: calendar)
        return entries[Progression.dailyIndex(forKey: key, count: entries.count)]
    }
}

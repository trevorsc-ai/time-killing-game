import XCTest
@testable import PuzzleGetaway

final class ProgressionTests: XCTestCase {
    // MARK: Fixtures

    private func stage(_ id: String, _ title: String, _ stars: Int) -> RestorationStage {
        RestorationStage(id: id, title: title, starsRequired: stars, scrapbookArtId: "\(id)-art")
    }

    private func destination(_ id: String, comingSoon: Bool = false, stages: [RestorationStage] = []) -> Destination {
        Destination(id: id, name: "Stop \(id)", tagline: "t", intro: "i",
                    theme: DestinationTheme(primary: "#000000", secondary: "#000000", accent: "#000000", background: "#FFFFFF"),
                    comingSoon: comingSoon, restorationTitle: "Restore \(id)", restorationStages: stages)
    }

    private func level(_ dest: String, _ order: Int, mode: String = "demo", destinationOverride: String? = nil) -> LevelEnvelope {
        LevelEnvelope(id: "\(dest)-\(mode)-\(String(format: "%02d", order))", mode: mode, destination: destinationOverride ?? dest,
                      order: order, title: "Level \(order)", difficulty: 1, tutorial: nil, twists: [], par: 3,
                      solution: [], payload: .object([:]))
    }

    /// d1: 5 levels, stages at 3/6/9 stars. d2: 2 levels. d3: coming soon.
    private func makeProgression(pools: [String: [LevelEnvelope]] = [:]) -> Progression {
        let dests = [
            destination("d1", stages: [stage("d1-s1", "One", 3), stage("d1-s2", "Two", 6), stage("d1-s3", "Three", 9)]),
            destination("d2", stages: [stage("d2-s1", "Uno", 2)]),
            destination("d3", comingSoon: true)
        ]
        var levels: [LevelEnvelope] = []
        for i in 1...5 { levels.append(level("d1", i)) }
        for i in 1...2 { levels.append(level("d2", i)) }
        levels.append(level("demo", 1))
        return Progression(destinations: dests, levels: levels, pools: pools, unlockPercent: 60, isPlayable: { _ in true })
    }

    private func solved(_ save: inout SaveData, _ id: String, stars: Int = 3) {
        save.recordCompletion(levelId: id, stars: stars, moves: 5)
    }

    // MARK: Unlock rules

    func testFirstDestinationOpenComingSoonNeverOpens() {
        let p = makeProgression()
        let save = SaveData()
        XCTAssertTrue(p.isDestinationUnlocked("d1", save: save))
        XCTAssertFalse(p.isDestinationUnlocked("d2", save: save))
        XCTAssertFalse(p.isDestinationUnlocked("d3", save: save))
    }

    func testNextDestinationOpensAtSixtyPercentRoundedUp() {
        let p = makeProgression()
        XCTAssertEqual(p.requiredToOpenNext(after: "d1"), 3) // ceil(0.6 * 5)
        var save = SaveData()
        solved(&save, "d1-demo-01")
        solved(&save, "d1-demo-02")
        XCTAssertFalse(p.isDestinationUnlocked("d2", save: save))
        solved(&save, "d1-demo-03")
        XCTAssertTrue(p.isDestinationUnlocked("d2", save: save))
        XCTAssertEqual(p.completionPercent(in: "d1", save: save), 60)
        // d3 stays closed: it is coming soon even though d2 could unlock it.
        solved(&save, "d2-demo-01")
        solved(&save, "d2-demo-02")
        XCTAssertFalse(p.isDestinationUnlocked("d3", save: save))
    }

    func testDestinationWithNoLevelsDoesNotOpenTheNext() {
        let dests = [destination("d1"), destination("d2")]
        let p = Progression(destinations: dests, levels: [level("d2", 1)], isPlayable: { _ in true })
        XCTAssertTrue(p.isDestinationUnlocked("d1", save: SaveData()))
        XCTAssertFalse(p.hasLevels("d1"))
        XCTAssertFalse(p.isDestinationUnlocked("d2", save: SaveData()))
    }

    func testLevelsUnlockSequentiallyWithinADestination() {
        let p = makeProgression()
        var save = SaveData()
        let l1 = level("d1", 1), l2 = level("d1", 2), l3 = level("d1", 3)
        XCTAssertTrue(p.isLevelUnlocked(l1, save: save))
        XCTAssertFalse(p.isLevelUnlocked(l2, save: save))
        solved(&save, l1.id)
        XCTAssertTrue(p.isLevelUnlocked(l2, save: save))
        XCTAssertFalse(p.isLevelUnlocked(l3, save: save))
        // A level in a locked destination is locked even though it is first in its list.
        XCTAssertFalse(p.isLevelUnlocked(level("d2", 1), save: save))
    }

    func testNextLevelStaysInsideTheDestination() {
        let p = makeProgression()
        XCTAssertEqual(p.nextLevel(after: level("d1", 2))?.order, 3)
        XCTAssertNil(p.nextLevel(after: level("d1", 5)))
    }

    // MARK: Stars and restoration

    func testStarsMapToRestorationStages() {
        let p = makeProgression()
        XCTAssertEqual(p.unlockedStageCount(in: "d1", stars: 0), 0)
        XCTAssertEqual(p.unlockedStageCount(in: "d1", stars: 2), 0)
        XCTAssertEqual(p.unlockedStageCount(in: "d1", stars: 3), 1)
        XCTAssertEqual(p.unlockedStageCount(in: "d1", stars: 8), 2)
        XCTAssertEqual(p.unlockedStageCount(in: "d1", stars: 9), 3)
        XCTAssertEqual(p.unlockedStageCount(in: "d1", stars: 99), 3)
        XCTAssertEqual(p.unlockedStageCount(in: "d3", stars: 99), 0)
    }

    func testCrossingThresholdsReportsNewStages() {
        let p = makeProgression()
        XCTAssertEqual(p.newlyUnlockedStages(in: "d1", fromStars: 2, toStars: 7).map { $0.id }, ["d1-s1", "d1-s2"])
        XCTAssertTrue(p.newlyUnlockedStages(in: "d1", fromStars: 3, toStars: 5).isEmpty)
        XCTAssertEqual(p.newlyUnlockedStages(in: "d1", fromStars: 8, toStars: 9).map { $0.id }, ["d1-s3"])
    }

    func testDestinationStarsCountOnlyThatDestination() {
        let p = makeProgression()
        var save = SaveData()
        solved(&save, "d1-demo-01", stars: 2)
        solved(&save, "d1-demo-02", stars: 3)
        solved(&save, "d2-demo-01", stars: 1)
        XCTAssertEqual(p.stars(in: "d1", save: save), 5)
        XCTAssertEqual(p.stars(in: "d2", save: save), 1)
        XCTAssertEqual(p.maxStars(in: "d1"), 15)
        XCTAssertEqual(p.nextStage(in: "d1", save: save)?.id, "d1-s2")
    }

    func testScrapbookUnlocksFollowStages() {
        let p = makeProgression()
        var save = SaveData()
        XCTAssertTrue(p.unlockedArtIds(save: save).isEmpty)
        solved(&save, "d1-demo-01")
        let ids = p.unlockedArtIds(save: save)
        XCTAssertEqual(ids, ["d1-s1-art"])
        XCTAssertEqual(p.scrapbookEntries().count, 4)
        save.scrapbookUnlocked.insert("d2-s1-art")
        XCTAssertTrue(p.unlockedArtIds(save: save).contains("d2-s1-art"))
    }

    func testTrainTiersRiseWithStars() {
        XCTAssertEqual(Progression.trainTier(totalStars: 0), 0)
        XCTAssertEqual(Progression.trainTier(totalStars: 3), 1)
        XCTAssertEqual(Progression.trainTier(totalStars: 15), 2)
        XCTAssertEqual(Progression.trainTier(totalStars: 40), 3)
    }

    // MARK: Quick Play and Continue

    func testQuickPlayPicksFirstUnsolvedUnlockedLevel() {
        let p = makeProgression()
        var save = SaveData()
        XCTAssertEqual(p.quickPlayLevel(save: save)?.id, "d1-demo-01")
        solved(&save, "d1-demo-01")
        XCTAssertEqual(p.quickPlayLevel(save: save)?.id, "d1-demo-02")
    }

    func testQuickPlayFallsBackToRelaxWhenEverythingIsSolved() {
        let relax = [level("relax-liquid", 1, destinationOverride: "relax-liquid"), level("relax-liquid", 2, destinationOverride: "relax-liquid")]
        let p = makeProgression(pools: ["relax-liquid": relax])
        var save = SaveData()
        for l in p.levels { solved(&save, l.id) }
        XCTAssertEqual(p.quickPlayLevel(save: save)?.destination, "relax-liquid")
        save.relaxPositions["relax-liquid"] = 1
        XCTAssertEqual(p.quickPlayLevel(save: save)?.order, 2)
    }

    func testQuickPlayWithNoRelaxReplaysTheFirstLevel() {
        let p = makeProgression()
        var save = SaveData()
        for l in p.levels { solved(&save, l.id) }
        XCTAssertEqual(p.quickPlayLevel(save: save)?.id, "d1-demo-01")
    }

    func testContinueResumesTheInProgressLevel() {
        let p = makeProgression()
        var save = SaveData()
        XCTAssertEqual(p.continueLevel(save: save)?.id, "d1-demo-01")
        XCTAssertFalse(p.hasInProgress(save: save))
        solved(&save, "d1-demo-01")
        XCTAssertEqual(p.continueLevel(save: save)?.id, "d1-demo-02")
        save.inProgress["d1-demo-02"] = Data([1])
        XCTAssertTrue(p.hasInProgress(save: save))
        XCTAssertEqual(p.continueLevel(save: save)?.id, "d1-demo-02")
    }

    func testContinuePrefersTheLastPlayedLevel() {
        let p = makeProgression()
        var save = SaveData()
        solved(&save, "d1-demo-01")
        solved(&save, "d1-demo-02")
        save.inProgress["d1-demo-02"] = Data([1])
        save.inProgress["d1-demo-03"] = Data([2])
        save.lastPlayedLevelId = "d1-demo-03"
        XCTAssertEqual(p.continueLevel(save: save)?.id, "d1-demo-03")
        save.lastPlayedLevelId = "d1-demo-99"
        XCTAssertEqual(p.continueLevel(save: save)?.id, "d1-demo-02")
    }

    func testUnplayableModesAreSkipped() {
        let dests = [destination("d1")]
        let levels = [level("d1", 1, mode: "ghost"), level("d1", 2, mode: "demo")]
        let p = Progression(destinations: dests, levels: levels, isPlayable: { $0 == "demo" })
        XCTAssertEqual(p.quickPlayLevel(save: SaveData())?.mode, "demo")
        XCTAssertEqual(p.nextLevel(after: levels[0])?.id, levels[1].id)
    }

    // MARK: Daily Journey

    func testFNV1aVectors() {
        XCTAssertEqual(Progression.fnv1a32(""), 0x811c9dc5)
        XCTAssertEqual(Progression.fnv1a32("a"), 0xe40c292c)
        XCTAssertEqual(Progression.fnv1a32("foobar"), 0xbf9cf968)
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = hour
        return utc.date(from: comps)!
    }

    func testDateKeyIsZeroPaddedLocalDate() {
        XCTAssertEqual(Progression.dateKey(date(2026, 1, 2), calendar: utc), "2026-01-02")
        XCTAssertEqual(Progression.dateKey(date(2026, 12, 31, hour: 23), calendar: utc), "2026-12-31")
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 20:00 UTC on Jan 1 is already Jan 2 in Tokyo: the player's local date decides.
        XCTAssertEqual(Progression.dateKey(date(2026, 1, 1, hour: 20), calendar: tokyo), "2026-01-02")
    }

    func testDailyPickIsDeterministicAndMatchesTheHashRule() {
        var entries: [LevelEnvelope] = []
        for i in 1...10 { entries.append(level("daily", i, destinationOverride: "daily")) }
        let p = makeProgression(pools: ["daily": entries])
        let day = date(2026, 3, 14)
        let first = p.dailyEntry(for: day, calendar: utc)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.id, p.dailyEntry(for: day, calendar: utc)?.id)
        // Same date, different time of day: same puzzle.
        XCTAssertEqual(first?.id, p.dailyEntry(for: date(2026, 3, 14, hour: 1), calendar: utc)?.id)
        let expectedIndex = Int(Progression.fnv1a32("2026-03-14") % 10)
        XCTAssertEqual(first?.order, expectedIndex + 1)
        XCTAssertEqual(Progression.dailyIndex(forKey: "2026-03-14", count: 10), expectedIndex)
    }

    func testDailySpreadsAcrossDays() {
        var entries: [LevelEnvelope] = []
        for i in 1...10 { entries.append(level("daily", i, destinationOverride: "daily")) }
        let p = makeProgression(pools: ["daily": entries])
        var seen = Set<String>()
        for d in 1...28 {
            if let e = p.dailyEntry(for: date(2026, 2, d), calendar: utc) { seen.insert(e.id) }
        }
        XCTAssertGreaterThan(seen.count, 4)
    }

    func testEmptyDailyPoolGivesNoEntry() {
        XCTAssertNil(makeProgression().dailyEntry(for: date(2026, 3, 14), calendar: utc))
        XCTAssertEqual(Progression.dailyIndex(forKey: "2026-03-14", count: 0), 0)
    }

    // MARK: Relax

    func testRelaxEntryWrapsAround() {
        let relax = (1...3).map { level("relax-pipe", $0, destinationOverride: "relax-pipe") }
        let p = makeProgression(pools: ["relax-pipe": relax])
        XCTAssertEqual(p.relaxEntry(pool: "relax-pipe", position: 0)?.order, 1)
        XCTAssertEqual(p.relaxEntry(pool: "relax-pipe", position: 4)?.order, 2)
        XCTAssertEqual(p.relaxEntry(pool: "relax-pipe", position: -1)?.order, 3)
        XCTAssertNil(p.relaxEntry(pool: "relax-liquid", position: 0))
        XCTAssertEqual(p.relaxCount(pool: "relax-pipe"), 3)
    }

    // MARK: Persistence through AppModel (temporary content + save directory)

    private var tempDirs: [URL] = []

    override func tearDown() {
        for d in tempDirs { try? FileManager.default.removeItem(at: d) }
        tempDirs = []
        super.tearDown()
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func demoLevelJSON(id: String, destination: String, order: Int) -> String {
        """
        {"id":"\(id)","mode":"demo","destination":"\(destination)","order":\(order),"title":"T\(order)","difficulty":1,
         "twists":[],"par":2,"solution":[{"delta":1},{"delta":1}],"payload":{"start":0,"target":2,"deltas":[1]}}
        """
    }

    /// A tiny bundle on disk: destination d1 with 3 demo levels and stages at 2 and 4 stars, plus a 3-entry relax pool.
    private func makeContent() throws -> ContentStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pg-content-\(UUID().uuidString)")
        tempDirs.append(root)
        let stagesJSON = """
        [{"id":"d1-s1","title":"One","starsRequired":2,"scrapbookArtId":"d1-stage1"},
         {"id":"d1-s2","title":"Two","starsRequired":4,"scrapbookArtId":"d1-stage2"}]
        """
        let dest = """
        {"unlockPercent":60,"destinations":[{"id":"d1","name":"Stop","tagline":"t","intro":"i",
        "theme":{"primary":"#000000","secondary":"#000000","accent":"#000000","background":"#FFFFFF"},
        "comingSoon":false,"restorationTitle":"R","restorationStages":\(stagesJSON)}]}
        """
        try write(dest, to: root.appendingPathComponent("Destinations.json"))
        try write(#"{"colors":[{"id":"r","name":"Red","hex":"#FF0000","highContrastHex":"#AA0000","symbol":"circle.fill"}]}"#,
                  to: root.appendingPathComponent("Art/palette.json"))
        let levels = (1...3).map { demoLevelJSON(id: "d1-demo-0\($0)", destination: "d1", order: $0) }.joined(separator: ",")
        try write(#"{"destination":"d1","mode":"demo","levels":["# + levels + "]}", to: root.appendingPathComponent("Levels/d1-demo.json"))
        let relax = (1...3).map { demoLevelJSON(id: "relax-liquid-00\($0)", destination: "relax-liquid", order: $0) }.joined(separator: ",")
        try write(#"{"pool":"relax-liquid","entries":["# + relax + "]}", to: root.appendingPathComponent("Pools/relax-liquid.json"))
        return try ContentStore(root: root)
    }

    @MainActor
    func testRelaxPositionPersistsAcrossLaunches() throws {
        let content = try makeContent()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pg-save-\(UUID().uuidString)")
        tempDirs.append(dir)
        let store = SaveStore(directory: dir)
        let model = AppModel(saveStore: store, content: content)
        let first = try XCTUnwrap(model.progression.currentRelaxEntry(pool: "relax-liquid", save: model.save))
        XCTAssertEqual(first.id, "relax-liquid-001")
        model.completeRelax(level: first)
        XCTAssertEqual(model.save.relaxPositions["relax-liquid"], 1)
        // Re-solving an old puzzle that is not the current one does not move the position.
        model.completeRelax(level: first)
        XCTAssertEqual(model.save.relaxPositions["relax-liquid"], 1)
        // Relax never awards stars.
        XCTAssertEqual(model.save.totalStars, 0)

        let relaunched = AppModel(saveStore: SaveStore(directory: dir), content: content)
        XCTAssertEqual(relaunched.save.relaxPositions["relax-liquid"], 1)
        XCTAssertEqual(relaunched.progression.currentRelaxEntry(pool: "relax-liquid", save: relaunched.save)?.id, "relax-liquid-002")
    }

    @MainActor
    func testRecordCompletionReportsNewStagesAndUnlocksScrapbook() throws {
        let content = try makeContent()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pg-save-\(UUID().uuidString)")
        tempDirs.append(dir)
        let model = AppModel(saveStore: SaveStore(directory: dir), content: content)
        let a = model.recordCompletion(levelId: "d1-demo-01", stars: 1, moves: 2)
        XCTAssertTrue(a.newStages.isEmpty)
        XCTAssertTrue(a.isFirstCompletion)
        let b = model.recordCompletion(levelId: "d1-demo-02", stars: 2, moves: 2)
        XCTAssertEqual(b.newStages.map { $0.id }, ["d1-s1"])
        XCTAssertTrue(model.save.scrapbookUnlocked.contains("d1-stage1"))
        // Replaying with the same stars adds nothing new.
        let c = model.recordCompletion(levelId: "d1-demo-02", stars: 2, moves: 2)
        XCTAssertTrue(c.newStages.isEmpty)
        XCTAssertFalse(c.isFirstCompletion)
        let d = model.recordCompletion(levelId: "d1-demo-03", stars: 3, moves: 2)
        XCTAssertEqual(d.newStages.map { $0.id }, ["d1-s2"])
        XCTAssertEqual(model.progression.unlockedStageCount(in: "d1", save: model.save), 2)
        XCTAssertTrue(model.progression.isDestinationComplete("d1", save: model.save))
    }

    @MainActor
    func testDailyCompletionCountsJourneysWithoutStreaks() throws {
        let content = try makeContent()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pg-save-\(UUID().uuidString)")
        tempDirs.append(dir)
        let model = AppModel(saveStore: SaveStore(directory: dir), content: content)
        let level = try XCTUnwrap(content.level(id: "d1-demo-01"))
        model.completeDaily(level: level, on: date(2026, 5, 1))
        model.completeDaily(level: level, on: date(2026, 5, 1))
        model.completeDaily(level: level, on: date(2026, 5, 9))
        XCTAssertEqual(model.save.dailyJourneysTaken.count, 2)
    }

    func testSettingsAndNewFieldsSurviveAnExportImportRoundTrip() throws {
        var save = SaveData()
        save.relaxPositions["relax-pixel"] = 7
        save.lastPlayedLevelId = "d1-demo-02"
        save.settings.showTips = false
        let data = try SaveStore(directory: FileManager.default.temporaryDirectory).exportData(save)
        let back = try SaveStore.validateImport(data)
        XCTAssertEqual(back, save)
        XCTAssertFalse(back.settings.showTips)
    }
}

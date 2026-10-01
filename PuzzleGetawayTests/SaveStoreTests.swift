import XCTest
@testable import PuzzleGetaway

final class SaveStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pg-save-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func sample() -> SaveData {
        var s = SaveData()
        s.recordCompletion(levelId: "d1-liquid-01", stars: 3, moves: 12, at: Date(timeIntervalSince1970: 1_700_000_000))
        s.inProgress["d1-pixel-02"] = Data([1, 2, 3])
        s.dailyJourneysTaken.insert("2026-01-02")
        s.tutorialsSeen.insert("liquid.basic")
        s.scrapbookUnlocked.insert("d1-stage1")
        s.restorationStagesSeen.insert("d1-s1")
        s.settings.highContrast = true
        s.settings.animationSpeed = 2
        return s
    }

    func testRoundTrip() throws {
        let store = SaveStore(directory: dir)
        XCTAssertEqual(store.load().source, .fresh)
        let original = sample()
        try store.save(original)
        let loaded = store.load()
        XCTAssertEqual(loaded.source, .main)
        XCTAssertEqual(loaded.data, original)
    }

    func testCorruptMainFallsBackToBackup() throws {
        let store = SaveStore(directory: dir)
        var first = sample()
        try store.save(first)
        first.recordCompletion(levelId: "d1-liquid-03", stars: 2, moves: 9)
        try store.save(first) // rotates the previous good file to save.bak.json
        try Data("not json at all".utf8).write(to: store.mainURL)
        let loaded = store.load()
        XCTAssertEqual(loaded.source, .backup)
        XCTAssertTrue(loaded.mainWasCorrupt)
        XCTAssertNotNil(loaded.data.progress["d1-liquid-01"])
        XCTAssertNil(loaded.data.progress["d1-liquid-03"], "backup holds the previous good save")
    }

    func testTamperedChecksumIsRejected() throws {
        let store = SaveStore(directory: dir)
        try store.save(sample())
        var bytes = try Data(contentsOf: store.mainURL)
        let text = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"checksum\":\"", with: "\"checksum\":\"00")
        bytes = Data(text.utf8)
        XCTAssertThrowsError(try SaveStore.decode(bytes))
    }

    func testCorruptMainDoesNotOverwriteGoodBackup() throws {
        let store = SaveStore(directory: dir)
        try store.save(sample())
        try store.save(sample())
        try Data("garbage".utf8).write(to: store.mainURL)
        try store.save(SaveData()) // main is corrupt: must not clobber the backup
        let backup = try SaveStore.decode(Data(contentsOf: store.backupURL))
        XCTAssertNotNil(backup.progress["d1-liquid-01"])
    }

    func testExportImport() throws {
        let store = SaveStore(directory: dir)
        let original = sample()
        let bytes = try store.exportData(original)
        XCTAssertEqual(try SaveStore.validateImport(bytes), original)
        XCTAssertThrowsError(try SaveStore.validateImport(Data("{}".utf8)))
        XCTAssertThrowsError(try SaveStore.validateImport(Data()))
    }

    func testRecordCompletionKeepsBest() {
        var s = SaveData()
        s.recordCompletion(levelId: "a", stars: 2, moves: 10)
        s.recordCompletion(levelId: "a", stars: 1, moves: 7)
        XCTAssertEqual(s.progress["a"]?.stars, 2)
        XCTAssertEqual(s.progress["a"]?.bestMoves, 7)
        XCTAssertEqual(s.totalStars, 2)
    }

    func testDebouncedSaveAndSaveNow() throws {
        let store = SaveStore(directory: dir)
        var value = SaveData()
        value.tutorialsSeen.insert("x")
        store.requestSave(delay: 30) { value }
        XCTAssertTrue(store.hasPendingSave)
        XCTAssertEqual(store.load().source, .fresh)
        XCTAssertTrue(store.saveNow())
        XCTAssertFalse(store.hasPendingSave)
        XCTAssertEqual(store.load().data.tutorialsSeen, ["x"])
    }
}

import XCTest
@testable import PuzzleGetaway

/// Replays the stored solution of EVERY bundled level and pool entry through its mode plugin.
/// New modes get covered automatically once registered in ModeRegistry.
///
/// Every campaign level is replayed. Pools (about 1,200 entries) are sampled deterministically (every `poolStride`th
/// entry of each pool, starting with the first) to keep CI fast; the forge (`npm run validate`) replays all of them.
final class SolutionReplayTests: XCTestCase {
    static let poolStride = 6

    private func sampled(_ content: ContentStore) -> [LevelEnvelope] {
        var out = content.allLevels
        for name in content.pools.keys.sorted() {
            for (i, entry) in (content.pools[name] ?? []).enumerated() where i % Self.poolStride == 0 { out.append(entry) }
        }
        return out
    }

    func testEveryStoredSolutionSolvesItsLevel() throws {
        let content = try ContentStore.load()
        var failures: [String] = []
        for level in sampled(content) {
            guard let plugin = ModeRegistry.plugin(for: level.mode) else {
                failures.append("\(level.id): mode \(level.mode) not registered")
                continue
            }
            do {
                if try !plugin.replay(level: level) { failures.append("\(level.id): solution does not solve") }
            } catch {
                failures.append("\(level.id): replay threw \(error)")
            }
            XCTAssertGreaterThanOrEqual(level.solution.count, level.par, level.id)
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    @MainActor
    func testDailyPoolIsFullAndRotatesModes() throws {
        let content = try ContentStore.load()
        let daily = content.pool("daily")
        XCTAssertGreaterThanOrEqual(daily.count, 700)
        XCTAssertEqual(Set(daily.map { $0.mode }), ["liquid", "bolt", "pixel", "parking", "pipe"])
    }

    @MainActor
    func testEveryLevelBuildsAController() throws {
        let content = try ContentStore.load()
        let context = GameContext.standalone(palette: content.palette)
        for level in sampled(content) {
            let plugin = try XCTUnwrap(ModeRegistry.plugin(for: level.mode))
            let controller = plugin.makeController(level: level, snapshot: nil, context: context)
            XCTAssertEqual(controller.levelId, level.id)
            XCTAssertFalse(controller.isSolved, "\(level.id) must not start solved")
            XCTAssertFalse(controller.title.isEmpty)
            // Snapshot round trip must be accepted by the same mode.
            let again = plugin.makeController(level: level, snapshot: controller.snapshot(), context: context)
            XCTAssertEqual(again.moveCount, controller.moveCount)
        }
    }
}

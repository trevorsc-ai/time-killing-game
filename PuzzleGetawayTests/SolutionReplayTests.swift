import XCTest
@testable import PuzzleGetaway

/// Replays the stored solution of EVERY bundled level and pool entry through its mode plugin.
/// New modes get covered automatically once registered in ModeRegistry.
final class SolutionReplayTests: XCTestCase {
    func testEveryStoredSolutionSolvesItsLevel() throws {
        let content = try ContentStore.load()
        var failures: [String] = []
        for level in content.everyLevel {
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
    func testEveryLevelBuildsAController() throws {
        let content = try ContentStore.load()
        let context = GameContext.standalone(palette: content.palette)
        for level in content.everyLevel {
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

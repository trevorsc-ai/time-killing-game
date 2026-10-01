import XCTest
@testable import PuzzleGetaway

final class PipeRulesTests: XCTestCase {
    private func rules(_ grid: [[String]], fixed: [[Int]]? = nil) -> PipeRules {
        PipeRules(payload: PipePayload(grid: grid, fixed: fixed))
    }

    func testMasksRotateClockwise() {
        XCTAssertEqual(PipeRules.rotate(PipeDir.north), PipeDir.east)
        XCTAssertEqual(PipeRules.rotate(PipeDir.west), PipeDir.north)
        XCTAssertEqual(PipeRules.mask("l", rot: 1), PipeDir.east | PipeDir.south)
        XCTAssertEqual(PipeRules.mask("i", rot: 1), PipeDir.east | PipeDir.west)
        XCTAssertEqual(PipeRules.mask("i", rot: 2), PipeDir.north | PipeDir.south)
        XCTAssertEqual(PipeRules.mask("t", rot: 0), 14)
        XCTAssertEqual(PipeRules.mask("t", rot: 2), 11)
        XCTAssertEqual(PipeRules.mask("x", rot: 3), 15)
        XCTAssertEqual(PipeRules.mask(".", rot: 1), 0)
    }

    func testTapRotatesOneStepAndRejectsEmptyAndFixed() {
        let r = rules([["S1", "i0", "D0"], ["l0", ".0", "t0"]], fixed: [[0, 0]])
        let s = r.initialState
        XCTAssertNil(r.apply(PipeMove(r: 1, c: 1), to: s), "empty tile")
        XCTAssertNil(r.apply(PipeMove(r: 0, c: 0), to: s), "fixed tile")
        XCTAssertNil(r.apply(PipeMove(r: 5, c: 0), to: s), "out of range")
        XCTAssertEqual(r.apply(PipeMove(r: 0, c: 1), to: s)?.rots[1], 1)
        XCTAssertEqual(s.rots[1], 0, "value semantics")
        var wrap = s
        wrap.rots[1] = 3
        XCTAssertEqual(r.apply(PipeMove(r: 0, c: 1), to: wrap)?.rots[1], 0)
    }

    func testConnectivityRequiresMatchingOpeningsAndAllowsLeaks() {
        let r = rules([["S1", "i0", "D0"], ["l0", ".0", "t0"]], fixed: [[0, 0]])
        var s = r.initialState
        XCTAssertFalse(r.flow(s).reached[1], "i0 opens north/south, not toward the source")
        s = r.apply(PipeMove(r: 0, c: 1), to: s)!
        XCTAssertTrue(r.flow(s).reached[1])
        XCTAssertFalse(r.isSolved(s), "destination still opens north")
        for _ in 0..<3 { s = r.apply(PipeMove(r: 0, c: 2), to: s)! }
        XCTAssertTrue(r.isSolved(s))
        XCTAssertFalse(r.flow(s).reached[3], "unrelated tiles stay dry")
        XCTAssertEqual(r.flow(s).parent[2], 3, "water enters the destination from the west")
    }

    func testTeeSplitsFlowToTwoDestinations() {
        let r = rules([["D1", "t2", "D3"], [".0", "S0", ".0"]], fixed: [[0, 0], [0, 2], [1, 1]])
        var s = r.initialState
        XCTAssertFalse(r.isSolved(s))
        s = r.apply(PipeMove(r: 0, c: 1), to: s)!
        XCTAssertEqual(PipeRules.mask("t", rot: 3), 7)
        XCTAssertFalse(r.isSolved(s), "north/east/south reaches only the right destination")
        XCTAssertTrue(r.flow(s).reached[2])
        XCTAssertFalse(r.flow(s).reached[0])
        s = r.apply(PipeMove(r: 0, c: 1), to: s)!
        XCTAssertTrue(r.isSolved(s))
    }

    func testNotSolvedWithoutDestinationsOrSource() {
        XCTAssertFalse(rules([["i0", "i0"]]).isSolved(PipeState(rots: [0, 0])))
    }

    func testHintMovesTowardStoredConfiguration() {
        let r = rules([["S1", "i0", "D0"]], fixed: [[0, 0]])
        var target = r.initialState
        target.rots[1] = 1
        target.rots[2] = 3
        let hint = r.hintMove(toward: target, from: r.initialState)
        XCTAssertEqual(hint, PipeMove(r: 0, c: 1), "nearest mismatched tile to the source")
        XCTAssertNil(r.hintMove(toward: target, from: target))
    }

    func testBundledLevelsReplayStartUnsolvedAndRamp() throws {
        let content = try ContentStore.load()
        let levels = content.allLevels.filter { $0.mode == "pipe" }.sorted { $0.order < $1.order }
        XCTAssertEqual(levels.count, 6)
        for (index, level) in levels.enumerated() {
            XCTAssertTrue(try PipeMode.replay(level: level), level.id)
            let payload = try level.decodePayload(PipePayload.self)
            let r = PipeRules(payload: payload)
            XCTAssertFalse(r.isSolved(r.initialState), "\(level.id) must not start solved")
            XCTAssertEqual(payload.grid.count, [3, 4, 5, 5, 6, 6][index], "\(level.id) size ramp")
            let tees = r.kinds.filter { $0 == "t" }.count
            if index >= 3 {
                XCTAssertGreaterThanOrEqual(r.destinationIndices.count, 2, level.id)
                XCTAssertGreaterThanOrEqual(tees, 1, level.id)
            } else {
                XCTAssertEqual(r.destinationIndices.count, 1, level.id)
            }
        }
    }

    func testRelaxPoolEntriesReplayAndStartUnsolved() throws {
        let content = try ContentStore.load()
        let pool = content.pool("relax-pipe")
        XCTAssertGreaterThanOrEqual(pool.count, 140)
        for entry in pool {
            XCTAssertTrue(try PipeMode.replay(level: entry), entry.id)
            let r = PipeRules(payload: try entry.decodePayload(PipePayload.self))
            XCTAssertFalse(r.isSolved(r.initialState), "\(entry.id) must not start solved")
        }
    }

    @MainActor
    func testControllerHintDrivesTowardASolvedBoard() throws {
        let content = try ContentStore.load()
        let level = try XCTUnwrap(content.allLevels.first { $0.id == "d4-pipe-03" })
        let context = GameContext.standalone(palette: content.palette)
        let controller = try XCTUnwrap(PipeMode.makeController(level: level, snapshot: nil, context: context) as? PipeController)
        var guardCount = 0
        while !controller.isSolved && guardCount < 200 {
            guardCount += 1
            let move = try XCTUnwrap(controller.session.hint(), "a hint must exist while unsolved")
            XCTAssertTrue(controller.rotate(row: move.r, col: move.c))
        }
        XCTAssertTrue(controller.isSolved)
        XCTAssertLessThanOrEqual(controller.moveCount, 200)
    }
}

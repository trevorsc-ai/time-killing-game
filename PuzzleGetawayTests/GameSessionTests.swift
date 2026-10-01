import XCTest
@testable import PuzzleGetaway

final class GameSessionTests: XCTestCase {
    private let rules = DemoRules(target: 7, deltas: [1, 3])

    private func makeSession() -> GameSession<DemoRules> {
        GameSession(rules: rules, initial: DemoState(value: 0), solution: [DemoMove(delta: 3), DemoMove(delta: 3), DemoMove(delta: 1)])
    }

    func testPerformUndoRestart() {
        let s = makeSession()
        XCTAssertTrue(s.perform(DemoMove(delta: 3)))
        XCTAssertTrue(s.perform(DemoMove(delta: 3)))
        XCTAssertEqual(s.moveCount, 2)
        XCTAssertFalse(s.perform(DemoMove(delta: 3)), "6 + 3 overshoots")
        XCTAssertFalse(s.perform(DemoMove(delta: 2)), "delta not allowed")
        XCTAssertEqual(s.moveCount, 2)
        XCTAssertTrue(s.undo())
        XCTAssertTrue(s.undo())
        XCTAssertFalse(s.undo())
        XCTAssertEqual(s.state.value, 0)
        XCTAssertEqual(s.undoCount, 2)
        s.perform(DemoMove(delta: 1))
        s.restart()
        XCTAssertEqual(s.state.value, 0)
        XCTAssertEqual(s.moveCount, 0)
        XCTAssertFalse(s.canUndo)
    }

    func testStars() {
        let s = makeSession()
        XCTAssertEqual(s.stars, 0)
        for d in [3, 3, 1] { s.perform(DemoMove(delta: d)) }
        XCTAssertTrue(s.isSolved)
        XCTAssertEqual(s.stars, 3)
        XCTAssertFalse(s.perform(DemoMove(delta: 1)), "no moves after solved")

        let hinted = makeSession()
        _ = hinted.hint()
        for d in [3, 3, 1] { hinted.perform(DemoMove(delta: d)) }
        XCTAssertEqual(hinted.stars, 2)

        let undoer = makeSession()
        for _ in 0..<4 { undoer.perform(DemoMove(delta: 1)); undoer.undo() }
        for d in [3, 3, 1] { undoer.perform(DemoMove(delta: d)) }
        XCTAssertEqual(undoer.undoCount, 4)
        XCTAssertEqual(undoer.stars, 2)
    }

    func testStuckAndHint() {
        let stuckRules = DemoRules(target: 5, deltas: [2])
        let s = GameSession(rules: stuckRules, initial: DemoState(value: 0))
        s.perform(DemoMove(delta: 2))
        s.perform(DemoMove(delta: 2))
        XCTAssertTrue(s.isStuck)
        XCTAssertNil(s.hint())

        let h = makeSession()
        let hint = h.hint()
        XCTAssertNotNil(hint)
        XCTAssertEqual(h.hintsUsed, 1)
        XCTAssertEqual(h.hint(), hint)
        XCTAssertEqual(h.hintsUsed, 1, "re-asking for the same hint is free")
    }

    func testHintSolverFindsShortest() {
        let path = HintSolver.solve(rules: rules, from: DemoState(value: 0))
        XCTAssertEqual(path?.count, 3)
        XCTAssertNil(HintSolver.solve(rules: rules, from: DemoState(value: 0), nodeBudget: 1))
        let fallback = HintSolver.solutionPathHint(
            rules: rules, initial: DemoState(value: 0),
            solution: [DemoMove(delta: 3), DemoMove(delta: 3), DemoMove(delta: 1)], current: DemoState(value: 3))
        XCTAssertEqual(fallback, DemoMove(delta: 3))
    }

    func testSnapshotRestore() {
        let a = makeSession()
        a.perform(DemoMove(delta: 3))
        a.perform(DemoMove(delta: 1))
        a.undo()
        _ = a.hint()
        let data = a.snapshot()
        let b = makeSession()
        XCTAssertTrue(b.restore(from: data))
        XCTAssertEqual(b.state, a.state)
        XCTAssertEqual(b.moveCount, a.moveCount)
        XCTAssertEqual(b.undoCount, 1)
        XCTAssertEqual(b.hintsUsed, 1)
        XCTAssertFalse(b.restore(from: Data("nope".utf8)))
    }
}

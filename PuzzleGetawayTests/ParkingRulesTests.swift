import XCTest
@testable import PuzzleGetaway

final class ParkingRulesTests: XCTestCase {
    private func makeRules() -> ParkingRules {
        ParkingRules(payload: ParkingPayload(
            size: 6,
            vehicles: [
                ParkingVehicle(id: "T", r: 2, c: 0, len: 2, axis: "h", target: true),
                ParkingVehicle(id: "A", r: 0, c: 3, len: 3, axis: "v", target: nil),
                ParkingVehicle(id: "B", r: 4, c: 1, len: 2, axis: "h", target: nil),
            ],
            gates: [ParkingGate(target: "T", edge: "right", index: 2)]))
    }

    func testSlideRangesStopAtWallsAndVehicles() {
        let rules = makeRules()
        let s = rules.initialState
        XCTAssertEqual(rules.slideRange(s, vehicle: 0).min, 0)
        XCTAssertEqual(rules.slideRange(s, vehicle: 0).max, 1, "T is stopped by A in column 3")
        XCTAssertEqual(rules.slideRange(s, vehicle: 1).max, 3)
        XCTAssertEqual(rules.slideRange(s, vehicle: 1).min, 0)
    }

    func testIllegalMovesAreRejected() {
        let rules = makeRules()
        let s = rules.initialState
        XCTAssertNil(rules.apply(ParkingMove(id: "T", delta: 2), to: s), "collision")
        XCTAssertNil(rules.apply(ParkingMove(id: "T", delta: -1), to: s), "off the board")
        XCTAssertNil(rules.apply(ParkingMove(id: "T", delta: 0), to: s))
        XCTAssertNil(rules.apply(ParkingMove(id: "Z", delta: 1), to: s), "unknown vehicle")
        XCTAssertNil(rules.apply(ParkingMove(id: "A", delta: 4), to: s))
    }

    func testBlockedByPerpendicularVehicle() {
        let rules = makeRules()
        var s = rules.initialState
        s = rules.apply(ParkingMove(id: "B", delta: 2), to: s)!   // B now covers columns 3 and 4 of row 4
        XCTAssertEqual(rules.slideRange(s, vehicle: 1).max, 1, "A can only drop one row before reaching B")
    }

    func testLegalMovesAreAllApplicableAndOrdered() {
        let rules = makeRules()
        let s = rules.initialState
        let moves = rules.legalMoves(s)
        XCTAssertEqual(moves.first, ParkingMove(id: "T", delta: 1))
        XCTAssertEqual(moves[1], ParkingMove(id: "A", delta: 1))
        for m in moves { XCTAssertNotNil(rules.apply(m, to: s)) }
    }

    func testExitSolvesAndLongSlideIsOneMove() {
        let rules = makeRules()
        let session = GameSession(rules: rules, initial: rules.initialState)
        XCTAssertFalse(session.isSolved)
        XCTAssertTrue(session.perform(ParkingMove(id: "A", delta: 3)))
        XCTAssertFalse(session.isSolved)
        XCTAssertTrue(session.perform(ParkingMove(id: "T", delta: 4)))
        XCTAssertTrue(session.isSolved)
        XCTAssertEqual(session.moveCount, 2, "each slide counts once regardless of distance")
        XCTAssertFalse(session.isStuck)
    }

    func testTwoTargetsBothMustExit() {
        let rules = ParkingRules(payload: ParkingPayload(
            size: 6,
            vehicles: [
                ParkingVehicle(id: "T", r: 0, c: 0, len: 2, axis: "h", target: true),
                ParkingVehicle(id: "U", r: 2, c: 5, len: 2, axis: "v", target: true),
            ],
            gates: [ParkingGate(target: "T", edge: "right", index: 0), ParkingGate(target: "U", edge: "bottom", index: 5)]))
        var s = rules.initialState
        s = rules.apply(ParkingMove(id: "T", delta: 4), to: s)!
        XCTAssertFalse(rules.isSolved(s))
        XCTAssertTrue(rules.isAtGate(s, vehicle: 0))
        s = rules.apply(ParkingMove(id: "U", delta: 2), to: s)!
        XCTAssertTrue(rules.isSolved(s))
    }

    func testLeftAndTopGates() {
        let rules = ParkingRules(payload: ParkingPayload(
            size: 6,
            vehicles: [
                ParkingVehicle(id: "T", r: 1, c: 3, len: 2, axis: "h", target: true),
                ParkingVehicle(id: "U", r: 3, c: 2, len: 3, axis: "v", target: true),
            ],
            gates: [ParkingGate(target: "T", edge: "left", index: 1), ParkingGate(target: "U", edge: "top", index: 2)]))
        var s = rules.initialState
        s = rules.apply(ParkingMove(id: "T", delta: -3), to: s)!
        s = rules.apply(ParkingMove(id: "U", delta: -3), to: s)!
        XCTAssertTrue(rules.isSolved(s))
    }

    func testHintSolverFindsShortestSolution() {
        let rules = makeRules()
        let solution = HintSolver.solve(rules: rules, from: rules.initialState)
        XCTAssertEqual(solution?.count, 2)
    }

    func testBundledLevelsReplayAndStartUnsolved() throws {
        let content = try ContentStore.load()
        let levels = content.allLevels.filter { $0.mode == "parking" }
        XCTAssertEqual(levels.count, 6)
        var previousPar = 0
        for level in levels.sorted(by: { $0.order < $1.order }) {
            XCTAssertTrue(try ParkingMode.replay(level: level), level.id)
            let payload = try level.decodePayload(ParkingPayload.self)
            let rules = ParkingRules(payload: payload)
            XCTAssertFalse(rules.isSolved(rules.initialState), "\(level.id) starts unsolved")
            let optimal = HintSolver.solve(rules: rules, from: rules.initialState, nodeBudget: 2_000_000)
            XCTAssertEqual(optimal?.count, level.par, "\(level.id) par is optimal")
            XCTAssertGreaterThanOrEqual(level.par, previousPar)
            previousPar = level.par
        }
    }
}

import XCTest
@testable import PuzzleGetaway

final class SortRulesTests: XCTestCase {
    private func state(_ p: SortPayload) -> SortState { SortRules.initialState(p) }

    private func rules(_ p: SortPayload, _ v: SortVariant = .liquid) -> SortRules { SortRules(payload: p, variant: v) }

    func testPourMovesTopRunLimitedBySpace() throws {
        let p = SortPayload(capacity: 4, tubes: [["r", "b", "b"], ["r", "b"], []])
        let r = rules(p)
        let a = try XCTUnwrap(r.apply(SortMove(from: 0, to: 1), to: state(p)))
        XCTAssertEqual(a.fingerprint, "r|rbbb|#,,")
        let b = try XCTUnwrap(r.apply(SortMove(from: 1, to: 0), to: state(p)))
        XCTAssertEqual(b.fingerprint, "rbbb|r|#,,")
        XCTAssertNil(r.apply(SortMove(from: 2, to: 0), to: state(p)))
        XCTAssertNil(r.apply(SortMove(from: 0, to: 0), to: state(p)))
        XCTAssertNil(r.apply(SortMove(from: 0, to: 9), to: state(p)))
    }

    func testMismatchedTopIsIllegalButEmptyTargetIsLegal() {
        let p = SortPayload(capacity: 4, tubes: [["r", "b"], ["b", "r"], []])
        let r = rules(p)
        XCTAssertNil(r.apply(SortMove(from: 0, to: 1), to: state(p)))
        XCTAssertNotNil(r.apply(SortMove(from: 0, to: 2), to: state(p)))
        XCTAssertEqual(r.legalMoves(state(p)).count, 2)
    }

    func testSolvedNeedsOneTubePerColor() {
        let solved = SortPayload(capacity: 2, tubes: [["r", "r"], ["b", "b"], []])
        XCTAssertTrue(rules(solved).isSolved(state(solved)))
        let split = SortPayload(capacity: 2, tubes: [["r"], ["r"], ["b", "b"]])
        XCTAssertFalse(rules(split).isSolved(state(split)))
        let mixed = SortPayload(capacity: 2, tubes: [["r", "b"], ["b", "r"], []])
        XCTAssertFalse(rules(mixed).isSolved(state(mixed)))
    }

    func testStuckMeansNoLegalMove() {
        let p = SortPayload(capacity: 2, tubes: [["r", "b"], ["b", "r"]])
        let r = rules(p)
        XCTAssertTrue(r.isStuck(state(p)))
        let free = SortPayload(capacity: 2, tubes: [["r", "b"], ["b", "r"], []])
        XCTAssertFalse(rules(free).isStuck(state(free)))
    }

    func testHiddenLayersAreNotPartOfARunAndRevealOnTop() throws {
        let p = SortPayload(capacity: 4, tubes: [["r", "r", "r"], ["b", "b"], []], hidden: [[0, 0], [0, 1]])
        let r = rules(p)
        var s = state(p)
        XCTAssertEqual(s.fingerprint, "r?r?r|bb|#,,")
        s = try XCTUnwrap(r.apply(SortMove(from: 0, to: 2), to: s))
        XCTAssertEqual(s.fingerprint, "r?r|bb|r#,,")
        s = try XCTUnwrap(r.apply(SortMove(from: 0, to: 2), to: s))
        XCTAssertEqual(s.fingerprint, "r|bb|rr#,,")
        s = try XCTUnwrap(r.apply(SortMove(from: 0, to: 2), to: s))
        XCTAssertEqual(s.fingerprint, "|bb|rrr#,,")
    }

    func testLockedTubeOpensWhenItsColorIsCompleted() throws {
        let p = SortPayload(capacity: 2, tubes: [["b", "r"], ["r", "b"], [], ["g", "g"]], locks: [SortLock(tube: 3, color: "r")])
        let r = rules(p)
        var s = state(p)
        XCTAssertEqual(s.locks[3], "r")
        XCTAssertNil(r.apply(SortMove(from: 3, to: 2), to: s))
        XCTAssertNil(r.apply(SortMove(from: 0, to: 3), to: s))
        XCTAssertFalse(r.canSource(s, from: 3))
        s = try XCTUnwrap(r.apply(SortMove(from: 0, to: 2), to: s))
        s = try XCTUnwrap(r.apply(SortMove(from: 1, to: 0), to: s))
        XCTAssertEqual(s.locks[3], "r")
        s = try XCTUnwrap(r.apply(SortMove(from: 1, to: 2), to: s))
        XCTAssertEqual(s.fingerprint, "bb||rr|gg#,,,")
        XCTAssertEqual(s.locks[3], "")
        XCTAssertTrue(r.canSource(s, from: 3))
    }

    func testCappedBoltsAndRustyNuts() throws {
        let p = SortPayload(capacity: 3, capacities: [3, 3, 2, 3], tubes: [["b", "g", "g"], ["g", "b"], [], ["y"]],
                            rusty: [SortRustSpec(bolt: 1, index: 0, color: "b")])
        let r = rules(p, .bolt)
        var s = state(p)
        XCTAssertEqual(s.fingerprint, "bgg|g~bb||y#,,,")
        XCTAssertTrue(r.canSource(s, from: 1))
        s = try XCTUnwrap(r.apply(SortMove(from: 0, to: 2), to: s))
        XCTAssertEqual(s.fingerprint, "b|g~bb|gg|y#,,,")
        XCTAssertNil(r.apply(SortMove(from: 3, to: 2), to: s))
        XCTAssertNil(r.apply(SortMove(from: 1, to: 2), to: s))
        s = try XCTUnwrap(r.apply(SortMove(from: 1, to: 0), to: s))
        XCTAssertEqual(s.fingerprint, "bb|g|gg|y#,,,")
        XCTAssertNil(r.apply(SortMove(from: 1, to: 2), to: s), "bolt 2 is capped at two nuts")
    }

    func testRustyTopNutBlocksMovingButNotCovering() throws {
        let p = SortPayload(capacity: 3, tubes: [["y", "g"], ["b", "y"], ["g"], []], rusty: [SortRustSpec(bolt: 0, index: 1, color: "y")])
        let r = rules(p, .bolt)
        var s = state(p)
        XCTAssertEqual(s.fingerprint, "yg~y|by|g|#,,,")
        XCTAssertFalse(r.canSource(s, from: 0))
        XCTAssertTrue(r.legalMoves(s).filter { $0.from == 0 }.isEmpty)
        XCTAssertNotNil(r.apply(SortMove(from: 2, to: 0), to: s))
        s = try XCTUnwrap(r.apply(SortMove(from: 1, to: 3), to: s))
        s = try XCTUnwrap(r.apply(SortMove(from: 2, to: 0), to: s))
        XCTAssertEqual(s.fingerprint, "yg~yg|b||y#,,,")
    }

    func testRustClearsWhenTaggedColorIsCompleted() throws {
        let p = SortPayload(capacity: 2, tubes: [["g", "y"], ["y", "b"], ["g", "b"], []], rusty: [SortRustSpec(bolt: 0, index: 0, color: "b")])
        let r = rules(p, .bolt)
        var s = state(p)
        XCTAssertEqual(s.tubes[0][0].rust, "b")
        s = try XCTUnwrap(r.apply(SortMove(from: 1, to: 3), to: s))
        XCTAssertEqual(s.tubes[0][0].rust, "b")
        s = try XCTUnwrap(r.apply(SortMove(from: 2, to: 3), to: s))
        XCTAssertEqual(s.tubes[0][0].rust, "")
    }

    func testSolutionReplayRejectsMovesAfterSolved() throws {
        let p = SortPayload(capacity: 2, tubes: [["r", "b"], ["b", "r"], []])
        let level = LevelEnvelope(
            id: "d1-liquid-01", mode: "liquid", destination: "d1", order: 1, title: "t", difficulty: 1, tutorial: nil, twists: [], par: 3,
            solution: [JSONValue.object(["from": .int(0), "to": .int(2)]), .object(["from": .int(1), "to": .int(0)]), .object(["from": .int(1), "to": .int(2)])],
            payload: try JSONValue.object(["capacity": .int(2), "tubes": JSONValue(encoding: p.tubes)]))
        XCTAssertTrue(try LiquidMode.replay(level: level))
        var longer = level
        longer.solution.append(.object(["from": .int(0), "to": .int(2)]))
        XCTAssertFalse(try LiquidMode.replay(level: longer))
    }

    // MARK: Solver and hints

    private func bundledLevel(_ id: String) throws -> LevelEnvelope {
        let content = try ContentStore.load()
        return try XCTUnwrap(content.level(id: id), "missing \(id)")
    }

    func testSolverMatchesForgeParOnEarlyLevels() throws {
        for id in ["d1-liquid-01", "d1-liquid-03", "d1-liquid-05", "d1-liquid-07", "d1-bolt-16", "d1-bolt-19"] {
            let level = try bundledLevel(id)
            let payload: SortPayload = try level.decodePayload()
            let r = SortRules(payload: payload, variant: level.mode == "bolt" ? .bolt : .liquid)
            let result = SortSolver.solve(rules: r, from: SortRules.initialState(payload), weight: 1, budget: 200_000)
            XCTAssertEqual(result.solution?.count, level.par, "\(id): optimal length should equal the forge par")
        }
    }

    func testHintSolverFindsAWinningLineOnMidLevels() throws {
        for id in ["d1-liquid-07", "d2-bolt-04"] {
            let level = try bundledLevel(id)
            let payload: SortPayload = try level.decodePayload()
            let r = SortRules(payload: payload, variant: level.mode == "bolt" ? .bolt : .liquid)
            var s = SortRules.initialState(payload)
            var steps = 0
            while !r.isSolved(s) && steps < 80 {
                let move = try XCTUnwrap(HintSolver.hint(rules: r, from: s, nodeBudget: 50_000), "\(id): no hint at step \(steps)")
                s = try XCTUnwrap(r.apply(move, to: s), "\(id): hint must be legal")
                steps += 1
            }
            XCTAssertTrue(r.isSolved(s), id)
            XCTAssertLessThanOrEqual(steps, level.par + 4, id)
        }
    }

    func testHintOnHardLevelsIsLegal() throws {
        for id in ["d1-liquid-13", "d1-liquid-18"] {
            let level = try bundledLevel(id)
            let payload: SortPayload = try level.decodePayload()
            let r = SortRules(payload: payload, variant: .liquid)
            let s = SortRules.initialState(payload)
            let move = try XCTUnwrap(HintSolver.hint(rules: r, from: s, nodeBudget: 50_000), id)
            XCTAssertNotNil(r.apply(move, to: s), id)
        }
    }

    func testEveryBundledSortLevelStartsUnsolvedWithLegalMoves() throws {
        let content = try ContentStore.load()
        for level in content.everyLevel where level.mode == "liquid" || level.mode == "bolt" {
            let payload: SortPayload = try level.decodePayload()
            let r = SortRules(payload: payload, variant: level.mode == "bolt" ? .bolt : .liquid)
            let s = SortRules.initialState(payload)
            XCTAssertFalse(r.isSolved(s), level.id)
            XCTAssertFalse(r.legalMoves(s).isEmpty, level.id)
        }
    }

    // MARK: Golden traces generated by the forge

    private struct GoldenStep: Decodable {
        var move: [Int]
        var fp: String
        var legal: Int
        var solved: Bool
    }

    private struct Golden: Decodable {
        var name: String
        var payload: SortPayload
        var initialFp: String
        var initialLegal: Int
        var optimal: Int
        var steps: [GoldenStep]
    }

    func testGoldenTracesFromForge() throws {
        let goldens = try JSONDecoder().decode([Golden].self, from: Data(SortGoldenData.json.utf8))
        XCTAssertGreaterThanOrEqual(goldens.count, 8)
        var totalSteps = 0
        for g in goldens {
            let variant: SortVariant = g.name.contains("bolt") ? .bolt : .liquid
            let r = SortRules(payload: g.payload, variant: variant)
            var s = SortRules.initialState(g.payload)
            XCTAssertEqual(s.fingerprint, g.initialFp, "\(g.name) initial")
            XCTAssertEqual(r.legalMoves(s).count, g.initialLegal, "\(g.name) initial legal count")
            for (i, step) in g.steps.enumerated() {
                let move = SortMove(from: step.move[0], to: step.move[1])
                s = try XCTUnwrap(r.apply(move, to: s), "\(g.name) step \(i) must be legal")
                XCTAssertEqual(s.fingerprint, step.fp, "\(g.name) step \(i)")
                XCTAssertEqual(r.legalMoves(s).count, step.legal, "\(g.name) step \(i) legal count")
                XCTAssertEqual(r.isSolved(s), step.solved, "\(g.name) step \(i) solved")
                totalSteps += 1
            }
            if g.optimal > 0 && g.optimal <= 15 {
                let result = SortSolver.solve(rules: r, from: SortRules.initialState(g.payload), weight: 1, budget: 200_000)
                XCTAssertEqual(result.solution?.count, g.optimal, "\(g.name) optimal length")
            }
        }
        XCTAssertGreaterThan(totalSteps, 100)
    }

    // MARK: Controller

    @MainActor
    func testControllerTapFlowAndAccessibilityLabels() throws {
        let content = try ContentStore.load()
        let level = try XCTUnwrap(content.level(id: "d1-liquid-01"))
        let context = GameContext.standalone(palette: content.palette)
        let controller = try XCTUnwrap(LiquidMode.makeController(level: level, snapshot: nil, context: context) as? SortController)
        XCTAssertEqual(controller.moveCount, 0)
        XCTAssertTrue(controller.tutorialActive)
        let label = controller.accessibilityLabel(forTube: 0)
        XCTAssertTrue(label.hasPrefix("Tube 1: "), label)
        XCTAssertTrue(label.contains("on top"), label)
        XCTAssertTrue(label.hasSuffix("0 spaces"), label)
        XCTAssertTrue(controller.accessibilityLabel(forTube: 3).hasPrefix("Tube 4: empty, 4 spaces"))

        // Tapping an empty tube first does nothing; the first stored move works as tap-source then tap-target.
        controller.tap(3)
        XCTAssertNil(controller.selected)
        let move = try XCTUnwrap(try level.decodeSolution(SortMove.self).first)
        controller.tap(move.from)
        XCTAssertEqual(controller.selected, move.from)
        controller.tap(move.to)
        XCTAssertEqual(controller.moveCount, 1)
        XCTAssertNil(controller.selected)
        XCTAssertFalse(controller.tutorialActive)
        controller.undo()
        XCTAssertEqual(controller.moveCount, 0)
    }

    @MainActor
    func testControllerRejectsIllegalTargetAndKeepsSelection() throws {
        let content = try ContentStore.load()
        let level = try XCTUnwrap(content.level(id: "d1-liquid-01"))
        let context = GameContext.standalone(palette: content.palette)
        let controller = try XCTUnwrap(LiquidMode.makeController(level: level, snapshot: nil, context: context) as? SortController)
        // Tube 0 = w w w b, tube 1 = b b w r: pouring tube 0 (top b) onto tube 1 (top r) is illegal.
        controller.tap(0)
        controller.tap(1)
        XCTAssertEqual(controller.moveCount, 0)
        XCTAssertEqual(controller.selected, 0)
        controller.tap(0)
        XCTAssertNil(controller.selected)
    }

    @MainActor
    func testBoltControllerLabelsMentionNutsAndCaps() throws {
        let content = try ContentStore.load()
        let level = try XCTUnwrap(content.level(id: "d2-bolt-02"))
        let context = GameContext.standalone(palette: content.palette)
        let controller = try XCTUnwrap(BoltMode.makeController(level: level, snapshot: nil, context: context) as? SortController)
        let labels = (0..<controller.session.state.tubes.count).map { controller.accessibilityLabel(forTube: $0) }
        XCTAssertTrue(labels.allSatisfy { $0.hasPrefix("Bolt ") })
        XCTAssertTrue(labels.contains { $0.contains("capped at") })
        XCTAssertTrue(labels.contains { $0.contains(" nut") })
    }

    @MainActor
    func testSnapshotRoundTripKeepsHiddenAndRustState() throws {
        let content = try ContentStore.load()
        let context = GameContext.standalone(palette: content.palette)
        for id in ["d1-liquid-13", "d2-bolt-04"] {
            let level = try XCTUnwrap(content.level(id: id))
            let plugin = try XCTUnwrap(ModeRegistry.plugin(for: level.mode))
            let controller = try XCTUnwrap(plugin.makeController(level: level, snapshot: nil, context: context) as? SortController)
            let move = try XCTUnwrap(try level.decodeSolution(SortMove.self).first)
            controller.tap(move.from)
            controller.tap(move.to)
            XCTAssertEqual(controller.moveCount, 1)
            let restored = try XCTUnwrap(plugin.makeController(level: level, snapshot: controller.snapshot(), context: context) as? SortController)
            XCTAssertEqual(restored.session.state, controller.session.state)
            XCTAssertEqual(restored.moveCount, 1)
        }
    }
}

private extension JSONValue {
    /// Encodes any Encodable into a JSONValue.
    init<T: Encodable>(encoding value: T) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

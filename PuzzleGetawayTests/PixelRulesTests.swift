import XCTest
import SpriteKit
@testable import PuzzleGetaway

// MARK: - Golden fixture models (produced by tools/forge: `npm run build:pixel golden`)

private struct GoldenFile: Decodable {
    var version: Int
    var cases: [GoldenCase]
}

private struct GoldenCase: Decodable {
    var name: String
    var levelId: String
    var payload: PixelPayload
    var steps: [GoldenStep]
}

private struct GoldenStep: Decodable {
    var lane: Int
    var legal: Bool
    var grid: [String]
    var slots: [String]
    var laneNext: [Int]
    var events: [GoldenEvent]
    var solved: Bool
    var stuck: Bool
}

private struct GoldenEvent: Decodable {
    var slot: Int
    var color: String
    var cells: [Int]
    var crumbled: [Int]
    var departed: Bool
}

final class PixelRulesTests: XCTestCase {
    // MARK: Helpers

    private func payload(_ grid: [String], slots: Int, lanes: [[(String, Int)]]) -> PixelPayload {
        PixelPayload(grid: grid, slots: slots, lanes: lanes.map { $0.map { PixelCrate(color: $0.0, count: $0.1) } })
    }

    private func loadGolden() throws -> GoldenFile {
        let bundle = Bundle(for: PixelRulesTests.self)
        let url = bundle.url(forResource: "pixel-golden", withExtension: "json")
            ?? bundle.url(forResource: "pixel-golden", withExtension: "json", subdirectory: "Fixtures")
        let file = try XCTUnwrap(url, "pixel-golden.json is not bundled with the test target")
        return try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: file))
    }

    // MARK: Rules

    func testExposureEdgeAndTransparentNeighbors() {
        let p = payload(["rrr", "rgr", "rrr"], slots: 2, lanes: [[("g", 1)], [("r", 8)]])
        let rules = PixelRules(payload: p)
        let s = rules.initialState()
        XCTAssertTrue(rules.isExposed(s, 0))
        XCTAssertFalse(rules.isExposed(s, 4), "centre pixel is buried")
        let p2 = payload(["rrrr", "r.gr", "rrrr"], slots: 2, lanes: [[("g", 1)], [("r", 10)]])
        let r2 = PixelRules(payload: p2)
        XCTAssertTrue(r2.isExposed(r2.initialState(), 6), "a pixel next to a '.' cell is exposed from the start")
    }

    func testChainingBFSOrderAndDeparture() throws {
        let p = payload(["rrrrr", "rrgrr", "rrrrr"], slots: 3, lanes: [[("r", 3)], [("r", 11)], [("g", 1)]])
        let rules = PixelRules(payload: p)
        let t = try XCTUnwrap(rules.applyDetailed(PixelMove(lane: 0), to: rules.initialState()))
        XCTAssertEqual(t.events.first?.cells, [0, 1, 2])
        XCTAssertEqual(t.events.first?.departed, true)
        XCTAssertEqual(t.after.rows(), ["...rr", "rrgrr", "rrrrr"])
        XCTAssertEqual(t.after.slotStrings(), ["", "", ""])
    }

    func testChainingReachesBuriedSameColorPixels() throws {
        // One exposed r seed opens the buried r behind it.
        let p = payload(["gggg", "grrg", "gggg"], slots: 2, lanes: [[("r", 2)], [("g", 10)]])
        let rules = PixelRules(payload: p)
        // r pixels are buried under g; tap g first (10), exposing r, then the r crate packs both.
        var s = rules.initialState()
        s = try XCTUnwrap(rules.apply(PixelMove(lane: 0), to: s)) // r crate waits
        XCTAssertEqual(s.slotStrings(), ["r:2", ""])
        s = try XCTUnwrap(rules.apply(PixelMove(lane: 1), to: s)) // g clears -> r auto-resumes
        XCTAssertTrue(rules.isSolved(s))
        XCTAssertEqual(s.slotStrings(), ["", ""])
    }

    func testCrateWaitsAndAutoResumes() throws {
        let p = payload(["rrr", "rgr", "rrr"], slots: 2, lanes: [[("g", 1)], [("r", 8)]])
        let rules = PixelRules(payload: p)
        var s = rules.initialState()
        s = try XCTUnwrap(rules.apply(PixelMove(lane: 0), to: s))
        XCTAssertEqual(s.slotStrings(), ["g:1", ""])
        XCTAssertFalse(rules.isSolved(s))
        s = try XCTUnwrap(rules.apply(PixelMove(lane: 1), to: s))
        XCTAssertEqual(s.slotStrings(), ["", ""])
        XCTAssertTrue(rules.isSolved(s))
    }

    func testStuckDetectionAndIllegalMoves() {
        let p = payload(["rrr", "rgr", "rrr"], slots: 1, lanes: [[("g", 1)], [("r", 8)]])
        let rules = PixelRules(payload: p)
        var s = rules.initialState()
        XCTAssertEqual(rules.legalMoves(s), [PixelMove(lane: 0), PixelMove(lane: 1)])
        s = rules.apply(PixelMove(lane: 0), to: s)!
        XCTAssertTrue(rules.legalMoves(s).isEmpty)
        XCTAssertTrue(rules.isStuck(s))
        XCTAssertNil(rules.apply(PixelMove(lane: 1), to: s), "tray is full")
        XCTAssertNil(rules.apply(PixelMove(lane: 7), to: rules.initialState()), "no such lane")
        XCTAssertFalse(rules.isStuck(rules.initialState()))
    }

    func testStoneCrumblesWhenANeighborIsPacked() throws {
        let p = payload(["rrrr", "r#gr", "rrrr"], slots: 3, lanes: [[("r", 1)], [("g", 1)], [("r", 9)]])
        let rules = PixelRules(payload: p)
        var s = rules.initialState()
        s = try XCTUnwrap(rules.apply(PixelMove(lane: 0), to: s))
        XCTAssertEqual(s.cells[5], PixelCell.stone, "the single r packed cell 0, which does not touch the stone")
        s = try XCTUnwrap(rules.apply(PixelMove(lane: 1), to: s))
        XCTAssertEqual(s.slotStrings(), ["g:1", "", ""], "g is buried behind the stone")
        let t = try XCTUnwrap(rules.applyDetailed(PixelMove(lane: 2), to: s))
        XCTAssertTrue(t.events.contains { !$0.crumbled.isEmpty }, "a stone crumbled")
        XCTAssertTrue(rules.isSolved(t.after))
        XCTAssertFalse(t.after.cells.contains(PixelCell.stone))
    }

    func testPreviewMatchesWhatTheTapPacks() throws {
        let p = payload(["rrr", "rgr", "rrr"], slots: 2, lanes: [[("g", 1)], [("r", 4)]])
        let rules = PixelRules(payload: p)
        let s = rules.initialState()
        XCTAssertEqual(rules.previewCells(lane: 0, in: s), [], "g is buried")
        XCTAssertEqual(rules.previewCells(lane: 1, in: s), [0, 1, 2, 3])
    }

    func testNoMovesAfterSolvedInReplay() throws {
        let content = try ContentStore.load()
        var level = try XCTUnwrap(content.level(id: "d1-pixel-02"))
        XCTAssertTrue(try PixelMode.replay(level: level))
        level.solution.append(.object(["lane": .int(0)]))
        XCTAssertFalse(try PixelMode.replay(level: level), "a tap after the board is clear is rejected")
    }

    // MARK: Bundled levels

    func testBundledPixelLevelsFollowTheDesign() throws {
        let content = try ContentStore.load()
        let levels = content.levels(in: "d1").filter { $0.mode == "pixel" }
        XCTAssertEqual(levels.map { $0.order }, [2, 4, 6, 8, 10, 12, 14, 17, 20, 23])
        XCTAssertEqual(levels.first?.tutorial, "pixel.tap")
        XCTAssertEqual(content.pool("relax-pixel").count, 150)
        for level in levels + content.pool("relax-pixel") {
            let payload = try level.decodePayload(PixelPayload.self)
            // Invariant: crate counts per color equal the pixel counts.
            var pixels: [String: Int] = [:]
            for row in payload.grid { for ch in row where ch != "." && ch != "#" { pixels[String(ch), default: 0] += 1 } }
            var crates: [String: Int] = [:]
            for lane in payload.lanes { for c in lane { crates[c.color, default: 0] += c.count } }
            XCTAssertEqual(pixels, crates, level.id)
            XCTAssertTrue((2...4).contains(payload.lanes.count), level.id)
        }
    }

    // MARK: Golden parity with the forge

    func testGoldenParityWithForge() throws {
        let golden = try loadGolden()
        XCTAssertEqual(golden.version, 1)
        XCTAssertGreaterThanOrEqual(golden.cases.count, 20)
        var sawStuck = false
        var sawCrumble = false
        for c in golden.cases {
            let rules = PixelRules(payload: c.payload)
            var state = rules.initialState()
            for (i, step) in c.steps.enumerated() {
                let label = "\(c.name) step \(i)"
                if let t = rules.applyDetailed(PixelMove(lane: step.lane), to: state) {
                    XCTAssertTrue(step.legal, label)
                    state = t.after
                    XCTAssertEqual(t.events.count, step.events.count, label)
                    for (a, b) in zip(t.events, step.events) {
                        XCTAssertEqual(a.slot, b.slot, label)
                        XCTAssertEqual(String(Character(UnicodeScalar(a.color))), b.color, label)
                        XCTAssertEqual(a.cells, b.cells, label)
                        XCTAssertEqual(a.crumbled, b.crumbled, label)
                        XCTAssertEqual(a.departed, b.departed, label)
                        if !a.crumbled.isEmpty { sawCrumble = true }
                    }
                } else {
                    XCTAssertFalse(step.legal, label)
                }
                XCTAssertEqual(state.rows(), step.grid, label)
                XCTAssertEqual(state.slotStrings(), step.slots, label)
                XCTAssertEqual(state.laneNext, step.laneNext, label)
                XCTAssertEqual(rules.isSolved(state), step.solved, label)
                XCTAssertEqual(rules.isStuck(state), step.stuck, label)
                if step.stuck { sawStuck = true }
            }
        }
        XCTAssertTrue(sawStuck, "fixtures include a jam")
        XCTAssertTrue(sawCrumble, "fixtures include a stone crumble")
    }

    // MARK: Controller and layout

    @MainActor
    func testControllerLabelsPreviewAndSnapshot() throws {
        let content = try ContentStore.load()
        let context = GameContext.standalone(palette: content.palette)
        let level = try XCTUnwrap(content.level(id: "d1-pixel-02"))
        let controller = try XCTUnwrap(PixelMode.makeController(level: level, snapshot: nil, context: context) as? PixelController)
        XCTAssertTrue(controller.laneLabel(0).hasPrefix("Lane 1: "))
        XCTAssertTrue(controller.laneLabel(0).contains("crate"))
        XCTAssertTrue(controller.laneLabel(0).contains("would"), controller.laneLabel(0))
        XCTAssertNotNil(controller.tutorialLane)
        controller.tapLane(controller.tutorialLane ?? 0)
        XCTAssertEqual(controller.moveCount, 1)
        XCTAssertNil(controller.tutorialLane, "the arrow goes away after the first move")
        let snap = controller.snapshot()
        let again = try XCTUnwrap(PixelMode.makeController(level: level, snapshot: snap, context: context) as? PixelController)
        XCTAssertEqual(again.session.state, controller.session.state)
        controller.undo()
        XCTAssertEqual(controller.moveCount, 0)
        XCTAssertEqual(controller.session.state, controller.session.initial)
    }

    func testLayoutKeepsEverythingInsideTheBoard() {
        let sizes = [CGSize(width: 390, height: 560), CGSize(width: 320, height: 420), CGSize(width: 700, height: 700), CGSize(width: 820, height: 1000)]
        for size in sizes {
            for (cols, rows, slots, lanes) in [(10, 10, 5, 2), (20, 20, 3, 4), (14, 12, 4, 3)] {
                let l = PixelLayout(size: size, columns: cols, rows: rows, slotCount: slots, laneCount: lanes)
                let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)
                XCTAssertTrue(bounds.contains(l.gridRect), "\(size) \(cols)x\(rows) grid")
                XCTAssertTrue(bounds.contains(l.trayRect), "\(size) tray")
                for r in l.laneFrontRects { XCTAssertTrue(bounds.contains(r), "\(size) lane") }
                for r in l.laneFrontRects { XCTAssertGreaterThanOrEqual(r.width, 44) }
                XCTAssertLessThanOrEqual(l.gridRect.maxY, l.trayRect.minY)
                XCTAssertLessThanOrEqual(l.trayRect.maxY, l.laneFrontRects[0].minY)
            }
        }
    }

    // MARK: Scene (headless): the animation must always land on the exact final state.

    @MainActor
    private func runScene(levelId: String, reduceMotion: Bool, taps: Int) throws {
        let content = try ContentStore.load()
        let level = try XCTUnwrap(content.level(id: levelId))
        let payload = try level.decodePayload(PixelPayload.self)
        let rules = PixelRules(payload: payload)
        let art = PixelArt(palette: content.palette, highContrast: false, showPatterns: true)
        let hooks = PixelSceneHooks(
            tapLane: { _ in }, reduceMotion: { reduceMotion }, speed: { 2 }, selectionHaptic: {}, softHaptic: {}, successHaptic: {},
            hintLane: { nil }, tutorialLane: { nil }, isStuck: { false }
        )
        var state = rules.initialState()
        let scene = PixelScene(rules: rules, art: art, hooks: hooks, initial: state, appearance: .init(dark: false, highContrast: false, showPatterns: true))
        scene.size = CGSize(width: 390, height: 600)
        var clock: TimeInterval = 1
        scene.update(clock)
        let solution = try level.decodeSolution(PixelMove.self)
        for move in solution.prefix(taps) {
            let t = try XCTUnwrap(rules.applyDetailed(move, to: state))
            state = t.after
            scene.play(t, solved: rules.isSolved(state))
            for _ in 0..<160 {
                clock += 0.05
                scene.update(clock)
            }
            XCTAssertEqual(scene.displayState, state, "\(levelId): scene state after tap")
        }
        scene.jump(to: rules.initialState())
        XCTAssertEqual(scene.displayState, rules.initialState())
    }

    @MainActor
    func testSceneAnimationLandsOnExactState() throws {
        try runScene(levelId: "d1-pixel-02", reduceMotion: false, taps: 20)
        try runScene(levelId: "d1-pixel-14", reduceMotion: false, taps: 20) // stones
        try runScene(levelId: "d1-pixel-23", reduceMotion: false, taps: 20)
    }

    @MainActor
    func testSceneReducedMotionLandsOnExactState() throws {
        try runScene(levelId: "d1-pixel-14", reduceMotion: true, taps: 20)
        try runScene(levelId: "d1-pixel-08", reduceMotion: true, taps: 20)
    }
}

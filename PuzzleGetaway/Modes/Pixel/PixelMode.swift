import SwiftUI
import SpriteKit

/// Pixel Picnic ("Critter Clear"): tap crates into the tray; the Parcel Pals pack the matching blocks.
/// Rules: docs/rules.md. Payload: docs/level-format.md (pixel).
enum PixelMode: PuzzleModePlugin {
    static let mode = "pixel"
    static let displayName = "Pixel Picnic"

    @MainActor
    static func makeController(level: LevelEnvelope, snapshot: Data?, context: GameContext) -> AnyGameController {
        let payload = (try? level.decodePayload(PixelPayload.self)) ?? PixelPayload(
            grid: ["rr", "rr"], slots: 3, lanes: [[PixelCrate(color: "r", count: 2)], [PixelCrate(color: "r", count: 2)]]
        )
        let rules = PixelRules(payload: payload)
        let solution = (try? level.decodeSolution(PixelMove.self)) ?? []
        let initial = rules.initialState()
        let session = GameSession(rules: rules, initial: initial, solution: solution)
        if let snapshot = snapshot, session.restore(from: snapshot) {
            // Guard against a snapshot from a different shape of the same level id.
            let s = session.state
            if s.width != initial.width || s.height != initial.height || s.slotColor.count != initial.slotColor.count || s.laneNext.count != initial.laneNext.count {
                session.restart()
            }
        }
        return PixelController(
            levelId: level.id, title: level.title, session: session, context: context,
            payload: payload, tutorial: level.tutorial == "pixel.tap"
        )
    }

    static func replay(level: LevelEnvelope) throws -> Bool {
        let payload = try level.decodePayload(PixelPayload.self)
        let rules = PixelRules(payload: payload)
        var state = rules.initialState()
        for move in try level.decodeSolution(PixelMove.self) {
            // No taps after the board is clear; every tap must be legal.
            if rules.isSolved(state) { return false }
            guard let next = rules.apply(move, to: state) else { return false }
            state = next
        }
        return rules.isSolved(state) && !state.cells.contains(PixelCell.stone)
    }
}

@MainActor
final class PixelController: SessionController<PixelRules> {
    let payload: PixelPayload
    let art: PixelArt
    private let showTutorialArrow: Bool
    private var sceneStorage: PixelScene?

    init(levelId: String, title: String, session: GameSession<PixelRules>, context: GameContext, payload: PixelPayload, tutorial: Bool) {
        self.payload = payload
        self.showTutorialArrow = tutorial
        self.art = PixelArt(palette: context.palette, highContrast: context.settings.highContrast, showPatterns: context.settings.showPatterns)
        super.init(levelId: levelId, title: title, session: session, context: context)
    }

    /// Fraction of picture blocks cleared so far.
    override var progress: Double? {
        let total = payload.grid.reduce(0) { n, row in n + row.utf8.filter { PixelCell.isPixel($0) }.count }
        guard total > 0 else { return nil }
        return 1 - Double(session.state.pixelsLeft) / Double(total)
    }

    // MARK: Scene

    /// The SpriteKit scene, created on first use so that building a controller (tests, level lists) stays cheap.
    var scene: PixelScene {
        if let s = sceneStorage { return s }
        let hooks = PixelSceneHooks(
            tapLane: { [weak self] lane in self?.tapLane(lane) },
            reduceMotion: { [weak self] in self?.context.settings.effectiveReduceMotion ?? false },
            speed: { [weak self] in Double(self?.context.settings.animationSpeed ?? 1) },
            selectionHaptic: { [weak self] in self?.context.haptics.selection() },
            softHaptic: { [weak self] in self?.context.haptics.legalMove() },
            successHaptic: { [weak self] in self?.context.haptics.success() },
            hintLane: { [weak self] in self?.session.activeHint?.lane },
            tutorialLane: { [weak self] in self?.tutorialLane },
            isStuck: { [weak self] in self?.session.isStuck ?? false }
        )
        let appearance = PixelScene.Appearance(
            dark: UITraitCollection.current.userInterfaceStyle == .dark,
            highContrast: context.settings.highContrast,
            showPatterns: context.settings.showPatterns
        )
        let s = PixelScene(rules: session.rules, art: art, hooks: hooks, initial: session.state, appearance: appearance)
        sceneStorage = s
        return s
    }

    /// First-level tutorial: point at the first lane of the stored solution until the first move is made.
    var tutorialLane: Int? {
        guard showTutorialArrow, session.moveCount == 0, !session.isSolved else { return nil }
        return session.storedSolution.first?.lane ?? 0
    }

#if DEBUG
    override func debugSolveStep() {
        let solution = session.storedSolution
        guard !session.isSolved, session.moveCount < solution.count else { return }
        tapLane(solution[session.moveCount].lane)
    }
#endif

    // MARK: Moves

    /// Tap the front crate of `lane`. The rules update instantly; the scene replays the diff as an animation.
    func tapLane(_ lane: Int) {
        let before = session.state
        guard !session.isSolved, let transition = session.rules.applyDetailed(PixelMove(lane: lane), to: before), session.perform(PixelMove(lane: lane)) else {
            context.haptics.invalid()
            sceneStorage?.rejectTap(lane: lane)
            return
        }
        context.onProgress()
        sceneStorage?.play(transition, solved: session.isSolved)
    }

    override func undo() {
        super.undo()
        sceneStorage?.jump(to: session.state)
    }

    override func restart() {
        super.restart()
        sceneStorage?.jump(to: session.state)
    }

    override func requestHint() {
        super.requestHint()
        sceneStorage?.refreshOverlays()
    }

    // MARK: Accessibility

    private func colorName(_ id: String) -> String {
        (context.palette.color(id)?.name ?? id).lowercased()
    }

    func laneLabel(_ lane: Int) -> String {
        let state = session.state
        guard let crate = session.rules.frontCrate(lane: lane, in: state) else {
            return "Lane \(lane + 1): empty"
        }
        var text = "Lane \(lane + 1): \(colorName(crate.color)) crate, \(crate.count) blocks"
        if state.hasFreeSlot {
            let n = session.rules.previewCells(lane: lane, in: state).count
            text += n > 0 ? ", would pack \(n) now" : ", would wait for blocks"
        } else {
            text += ", tray is full"
        }
        let behind = payload.lanes[lane].count - state.laneNext[lane] - 1
        if behind > 0 { text += ", \(behind) more behind" }
        return text
    }

    func slotLabel(_ slot: Int) -> String {
        let state = session.state
        guard state.slotColor.indices.contains(slot), state.slotColor[slot] != 0 else { return "Tray slot \(slot + 1): empty" }
        let id = String(Character(UnicodeScalar(state.slotColor[slot])))
        return "Tray slot \(slot + 1): \(colorName(id)) crate, \(state.slotRemaining[slot]) blocks left"
    }

    var pictureLabel: String {
        let n = session.state.pixelsLeft
        return n == 0 ? "Picture cleared" : "Picture: \(n) blocks left"
    }

    override var accessibilitySummary: String {
        let state = session.state
        return "\(pictureLabel). Tray: \(state.occupiedSlots) of \(state.slotColor.count) slots in use."
    }

    override var boardView: AnyView {
        AnyView(PixelBoardView(controller: self))
    }
}

struct PixelBoardView: View {
    @ObservedObject var controller: PixelController
    @ObservedObject private var settings: Settings
    @Environment(\.colorScheme) private var colorScheme

    init(controller: PixelController) {
        self.controller = controller
        self._settings = ObservedObject(wrappedValue: controller.context.settings)
    }

    private var appearance: PixelScene.Appearance {
        PixelScene.Appearance(dark: colorScheme == .dark, highContrast: settings.highContrast, showPatterns: settings.showPatterns)
    }

    @State private var zoomed = false

    var body: some View {
        GeometryReader { geo in
            let state = controller.session.state
            let fit = PixelLayout(
                size: geo.size, columns: state.width, rows: state.height,
                slotCount: state.slotColor.count, laneCount: controller.payload.lanes.count
            )
            let tall = PixelLayout.tallHeight(
                width: geo.size.width, base: geo.size.height, columns: state.width, rows: state.height,
                slotCount: state.slotColor.count, laneCount: controller.payload.lanes.count
            )
            let boardSize = zoomed ? CGSize(width: geo.size.width, height: tall) : geo.size
            ZStack(alignment: .topTrailing) {
                ScrollView(.vertical, showsIndicators: zoomed) {
                    boardContent(size: boardSize, state: state)
                }
                .scrollDisabled(!zoomed)
                .frame(width: geo.size.width, height: geo.size.height)
                if fit.isCramped {
                    Button {
                        zoomed.toggle()
                    } label: {
                        Image(systemName: zoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(zoomed ? "Fit picture to screen" : "Zoom in on picture")
                    .accessibilityIdentifier("pixelZoomToggle")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                controller.scene.applyAppearance(appearance)
            }
            .onChange(of: appearance) { newValue in
                controller.scene.applyAppearance(newValue)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pixel Picnic board")
    }

    private func boardContent(size: CGSize, state: PixelState) -> some View {
        let layout = PixelLayout(
            size: size, columns: state.width, rows: state.height,
            slotCount: state.slotColor.count, laneCount: controller.payload.lanes.count
        )
        return ZStack(alignment: .topLeading) {
            SpriteView(scene: controller.scene, options: [.allowsTransparency])
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
            // VoiceOver proxies. Touches fall through to the SpriteKit scene.
            Color.clear
                .frame(width: layout.gridRect.width, height: layout.gridRect.height)
                .position(x: layout.gridRect.midX, y: layout.gridRect.midY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(controller.pictureLabel)
                .allowsHitTesting(false)
            ForEach(0..<layout.slotCount, id: \.self) { i in
                Color.clear
                    .frame(width: layout.slotRects[i].width, height: layout.slotRects[i].height)
                    .position(x: layout.slotRects[i].midX, y: layout.slotRects[i].midY)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(controller.slotLabel(i))
                    .allowsHitTesting(false)
            }
            ForEach(0..<layout.laneCount, id: \.self) { l in
                let r = layout.laneHitRects[l]
                Color.clear
                    .frame(width: max(r.width, Theme.minTapTarget), height: max(r.height, Theme.minTapTarget))
                    .position(x: r.midX, y: r.midY)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(controller.laneLabel(l))
                    .accessibilityHint("Double tap to send this crate to the tray.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default) { controller.tapLane(l) }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

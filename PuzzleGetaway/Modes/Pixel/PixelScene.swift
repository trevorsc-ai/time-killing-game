import SpriteKit
import UIKit

/// Callbacks from the scene into the game controller. The scene never reads or writes game state directly: it is told
/// what to show and reports taps. Everything it draws is purely presentational, replayed from `PixelTransition`s.
struct PixelSceneHooks {
    var tapLane: (Int) -> Void
    var reduceMotion: () -> Bool
    /// 1 or 2 (Settings.animationSpeed).
    var speed: () -> Double
    var selectionHaptic: () -> Void
    var softHaptic: () -> Void
    var successHaptic: () -> Void
    /// Lane whose front crate the hint points at, if any.
    var hintLane: () -> Int?
    /// Lane the first-level tutorial arrow points at, if any.
    var tutorialLane: () -> Int?
    var isStuck: () -> Bool
}

/// SpriteKit board for Pixel Picnic: the pixel scene, the tray and the crate lanes.
final class PixelScene: SKScene {
    struct Appearance: Equatable {
        var dark: Bool
        var highContrast: Bool
        var showPatterns: Bool
    }

    // Inputs
    private let rules: PixelRules
    private let art: PixelArt
    private var hooks: PixelSceneHooks
    private(set) var appearance: Appearance

    // State mirrored on screen
    private(set) var displayState: PixelState
    private(set) var layout: PixelLayout
    private var animating = false

    // Layers
    private let boardLayer = SKNode()
    private let blockLayer = SKNode()
    private let trayLayer = SKNode()
    private let laneLayer = SKNode()
    private let uiLayer = SKNode()
    private let fxLayer = SKNode()

    // Nodes
    private var blockNodes: [Int: SKSpriteNode] = [:]
    private var slotNodes: [Int: SKSpriteNode] = [:]
    private var slotRemaining: [Int: Int] = [:]
    private var slotBays: [SKShapeNode] = []
    private var trayShape: SKShapeNode?
    private var laneNodes: [[SKSpriteNode]] = []
    private var previewNodes: [SKNode] = []
    private var hintNode: SKNode?
    private var arrowNode: SKNode?

    // Interaction
    private var pressLane: Int?
    private var pressTime: TimeInterval = 0
    private var previewShown = false
    private var lastUpdate: TimeInterval = 0

    // Timeline (we avoid SKAction run-blocks so that all state changes stay on the update loop)
    private struct Scheduled {
        var remaining: TimeInterval
        var block: () -> Void
    }
    private var scheduled: [Scheduled] = []

    init(rules: PixelRules, art: PixelArt, hooks: PixelSceneHooks, initial: PixelState, appearance: Appearance) {
        self.rules = rules
        self.art = art
        self.hooks = hooks
        self.appearance = appearance
        self.displayState = initial
        self.layout = PixelLayout(size: CGSize(width: 320, height: 480), columns: initial.width, rows: initial.height, slotCount: initial.slotColor.count, laneCount: rules.payload.lanes.count)
        super.init(size: CGSize(width: 320, height: 480))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
        isUserInteractionEnabled = true
        boardLayer.zPosition = 0
        blockLayer.zPosition = 2
        trayLayer.zPosition = 4
        laneLayer.zPosition = 8
        uiLayer.zPosition = 20
        fxLayer.zPosition = 30
        for n in [boardLayer, blockLayer, trayLayer, laneLayer, uiLayer, fxLayer] { addChild(n) }
        rebuild()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: - Public API

    func setHooks(_ h: PixelSceneHooks) { hooks = h }

    func applyAppearance(_ a: Appearance) {
        guard a != appearance else { return }
        appearance = a
        art.update(highContrast: a.highContrast, showPatterns: a.showPatterns)
        rebuild()
    }

    /// Instant, animation-free sync (undo, restart, resume).
    func jump(to state: PixelState) {
        syncAll(state)
    }

    func refreshOverlays() {
        refreshHint()
        refreshTutorial()
        refreshJam()
    }

    func rejectTap(lane: Int) {
        guard lane >= 0, lane < laneNodes.count, let front = laneNodes[lane].first else { return }
        front.removeAction(forKey: "wiggle")
        let w = SKAction.sequence([
            SKAction.rotate(toAngle: 0.08, duration: 0.05),
            SKAction.rotate(toAngle: -0.08, duration: 0.08),
            SKAction.rotate(toAngle: 0, duration: 0.05),
        ])
        front.run(w, withKey: "wiggle")
        if let tray = trayShape {
            tray.removeAction(forKey: "shake")
            let dx: CGFloat = 5
            tray.run(SKAction.sequence([
                SKAction.moveBy(x: dx, y: 0, duration: 0.04),
                SKAction.moveBy(x: -2 * dx, y: 0, duration: 0.08),
                SKAction.moveBy(x: dx, y: 0, duration: 0.04),
            ]), withKey: "shake")
        }
    }

    // MARK: - Scene lifecycle

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        if layout.size != size {
            rebuild()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(0.1, currentTime - lastUpdate)
        lastUpdate = currentTime
        if !scheduled.isEmpty {
            for i in scheduled.indices { scheduled[i].remaining -= dt }
            let due = scheduled.filter { $0.remaining <= 0 }
            scheduled.removeAll { $0.remaining <= 0 }
            for item in due { item.block() }
        }
        if let lane = pressLane, !previewShown {
            pressTime += dt
            if pressTime > 0.3 {
                previewShown = true
                showPreview(lane: lane)
                hooks.selectionHaptic()
            }
        }
    }

    // MARK: - Layout and static art

    private func rebuild() {
        let s = (size.width > 1 && size.height > 1) ? size : CGSize(width: 320, height: 480)
        layout = PixelLayout(size: s, columns: displayState.width, rows: displayState.height, slotCount: displayState.slotColor.count, laneCount: rules.payload.lanes.count)
        buildStatic()
        syncAll(displayState)
    }

    private func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x, y: size.height - pt.y) }
    private func center(_ r: CGRect) -> CGPoint { p(CGPoint(x: r.midX, y: r.midY)) }

    private var canvasColor: UIColor {
        appearance.highContrast ? (appearance.dark ? UIColor(white: 0.1, alpha: 1) : UIColor(white: 0.93, alpha: 1))
            : (appearance.dark ? UIColor(red: 0.2, green: 0.21, blue: 0.3, alpha: 1) : UIColor(red: 0.97, green: 0.93, blue: 0.85, alpha: 1))
    }
    private var canvasStroke: UIColor {
        appearance.highContrast ? (appearance.dark ? UIColor.white : UIColor.black)
            : (appearance.dark ? UIColor(red: 0.3, green: 0.31, blue: 0.42, alpha: 1) : UIColor(red: 0.89, green: 0.84, blue: 0.75, alpha: 1))
    }
    private var trayColor: UIColor {
        appearance.dark ? UIColor(red: 0.16, green: 0.17, blue: 0.25, alpha: 1) : UIColor(red: 0.91, green: 0.84, blue: 0.72, alpha: 1)
    }
    private var bayColor: UIColor {
        appearance.dark ? UIColor(red: 0.24, green: 0.25, blue: 0.36, alpha: 1) : UIColor(red: 0.84, green: 0.76, blue: 0.62, alpha: 1)
    }
    private var accentColor: UIColor {
        appearance.dark ? UIColor(red: 0.95, green: 0.64, blue: 0.48, alpha: 1) : UIColor(red: 0.91, green: 0.55, blue: 0.37, alpha: 1)
    }

    private func buildStatic() {
        boardLayer.removeAllChildren()
        trayLayer.removeAllChildren()
        slotBays.removeAll()
        trayShape = nil

        // Canvas
        let canvas = SKShapeNode(rectOf: layout.canvasRect.size, cornerRadius: 14)
        canvas.position = center(layout.canvasRect)
        canvas.fillColor = canvasColor
        canvas.strokeColor = canvasStroke
        canvas.lineWidth = appearance.highContrast ? 2 : 1
        boardLayer.addChild(canvas)

        // Faint peg dots, so cleared cells still read as part of the board.
        let dots = CGMutablePath()
        let r = max(1, layout.cell * 0.07)
        for i in 0..<(layout.columns * layout.rows) {
            let c = center(layout.cellRect(i))
            dots.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        let dotNode = SKShapeNode(path: dots)
        dotNode.fillColor = canvasStroke.withAlphaComponent(0.7)
        dotNode.strokeColor = .clear
        boardLayer.addChild(dotNode)

        // Lane rails
        for l in 0..<layout.laneCount {
            let hit = layout.laneHitRects[l]
            let rail = SKShapeNode(rectOf: CGSize(width: layout.laneFrontSize + 10, height: hit.height + layout.laneFrontSize * 0.9), cornerRadius: 14)
            rail.position = p(CGPoint(x: hit.midX, y: hit.minY - 4 + (hit.height + layout.laneFrontSize * 0.9) / 2))
            rail.fillColor = trayColor.withAlphaComponent(0.5)
            rail.strokeColor = .clear
            rail.zPosition = -1
            boardLayer.addChild(rail)
        }

        // Tray
        let tray = SKShapeNode(rectOf: layout.trayRect.size, cornerRadius: 16)
        tray.position = center(layout.trayRect)
        tray.fillColor = trayColor
        tray.strokeColor = canvasStroke
        tray.lineWidth = appearance.highContrast ? 2 : 1
        trayLayer.addChild(tray)
        trayShape = tray
        for i in 0..<layout.slotCount {
            let bay = SKShapeNode(rectOf: layout.slotRects[i].size, cornerRadius: layout.slotSize * 0.2)
            bay.position = center(layout.slotRects[i])
            bay.fillColor = bayColor
            bay.strokeColor = .clear
            bay.zPosition = 0.1
            trayLayer.addChild(bay)
            slotBays.append(bay)
        }
    }

    // MARK: - Syncing nodes to a state (instant, idempotent)

    private func cancelAnimations() {
        scheduled.removeAll()
        fxLayer.removeAllChildren()
        for n in blockNodes.values { n.removeAllActions() }
        animating = false
    }

    private func syncAll(_ s: PixelState, showJam: Bool = true) {
        cancelAnimations()
        hidePreview()
        displayState = s
        syncBlocks(s)
        syncTray(s)
        syncLanes(s)
        refreshHint()
        refreshTutorial()
        if showJam { refreshJam() } else { clearJam() }
    }

    private func syncBlocks(_ s: PixelState) {
        blockLayer.removeAllChildren()
        blockNodes.removeAll()
        let side = layout.cell
        for i in 0..<s.cells.count {
            let code = s.cells[i]
            if code == PixelCell.clear { continue }
            let node: SKSpriteNode
            if code == PixelCell.stone {
                node = SKSpriteNode(texture: art.stoneTexture(side: side))
            } else {
                node = SKSpriteNode(texture: art.blockTexture(String(Character(UnicodeScalar(code))), side: side))
            }
            node.size = CGSize(width: side, height: side)
            node.position = center(layout.cellRect(i))
            blockLayer.addChild(node)
            blockNodes[i] = node
        }
    }

    private func crateNode(color: String, count: Int, side: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: art.crateTexture(color, count: count, side: side))
        node.size = CGSize(width: side, height: side)
        return node
    }

    private func syncTray(_ s: PixelState) {
        for n in slotNodes.values { n.removeFromParent() }
        slotNodes.removeAll()
        slotRemaining.removeAll()
        for i in 0..<s.slotColor.count where s.slotColor[i] != 0 {
            let id = String(Character(UnicodeScalar(s.slotColor[i])))
            let node = crateNode(color: id, count: s.slotRemaining[i], side: layout.slotSize)
            node.position = center(layout.slotRects[i])
            node.zPosition = 1
            trayLayer.addChild(node)
            slotNodes[i] = node
            slotRemaining[i] = s.slotRemaining[i]
        }
    }

    private func laneCrates(_ lane: Int, _ s: PixelState) -> [PixelCrate] {
        let all = rules.payload.lanes[lane]
        let next = s.laneNext[lane]
        return next < all.count ? Array(all[next...]) : []
    }

    private func syncLanes(_ s: PixelState) {
        laneLayer.removeAllChildren()
        laneNodes = []
        for l in 0..<layout.laneCount {
            var nodes: [SKSpriteNode] = []
            let crates = laneCrates(l, s)
            if crates.isEmpty {
                let ghost = SKShapeNode(rectOf: layout.laneFrontRects[l].size, cornerRadius: layout.laneFrontSize * 0.2)
                ghost.position = center(layout.laneFrontRects[l])
                ghost.strokeColor = canvasStroke
                ghost.lineWidth = 2
                ghost.fillColor = .clear
                ghost.alpha = 0.5
                laneLayer.addChild(ghost)
            }
            for (k, crate) in crates.prefix(1 + PixelLayout.maxQueueShown).enumerated() {
                let node = crateNode(color: crate.color, count: crate.count, side: layout.laneFrontSize)
                place(node, role: k, lane: l)
                laneLayer.addChild(node)
                nodes.append(node)
            }
            let extra = crates.count - (1 + PixelLayout.maxQueueShown)
            if extra > 0 {
                let label = SKLabelNode(text: "+\(extra)")
                label.fontName = "AvenirNext-Bold"
                label.fontSize = max(11, layout.laneFrontSize * 0.2)
                label.fontColor = appearance.dark ? UIColor.white : UIColor(red: 0.35, green: 0.3, blue: 0.45, alpha: 1)
                label.verticalAlignmentMode = .top
                let last = layout.laneQueueCenters[l].last ?? CGPoint(x: layout.laneFrontRects[l].midX, y: layout.laneFrontRects[l].maxY)
                label.position = p(CGPoint(x: last.x, y: last.y + layout.laneFrontSize * layout.laneQueueScale * 0.5 + 1))
                label.zPosition = -2
                laneLayer.addChild(label)
            }
            laneNodes.append(nodes)
        }
    }

    /// Positions a lane sprite for `role` (0 = front, 1... = queue behind it).
    private func place(_ node: SKSpriteNode, role: Int, lane: Int) {
        if role == 0 {
            node.position = center(layout.laneFrontRects[lane])
            node.setScale(1)
            node.zPosition = 10
            node.alpha = 1
            node.colorBlendFactor = 0
        } else {
            let centers = layout.laneQueueCenters[lane]
            let c = centers[min(role - 1, centers.count - 1)]
            node.position = p(c)
            node.setScale(layout.laneQueueScale)
            node.zPosition = 10 - CGFloat(role)
            node.alpha = 0.92
            node.color = .black
            node.colorBlendFactor = 0.1 * CGFloat(role)
        }
    }

    // MARK: - Overlays: hint, tutorial arrow, jam

    private func refreshHint() {
        hintNode?.removeFromParent()
        hintNode = nil
        guard let lane = hooks.hintLane(), lane >= 0, lane < layout.laneCount, !laneNodes.isEmpty, !laneNodes[lane].isEmpty else { return }
        let r = layout.laneFrontRects[lane].insetBy(dx: -6, dy: -6)
        let ring = SKShapeNode(rectOf: r.size, cornerRadius: layout.laneFrontSize * 0.26)
        ring.position = center(r)
        ring.strokeColor = appearance.highContrast ? (appearance.dark ? UIColor.white : UIColor.black) : UIColor(red: 0.31, green: 0.69, blue: 0.42, alpha: 1)
        ring.lineWidth = 4
        ring.fillColor = .clear
        ring.glowWidth = appearance.highContrast ? 0 : 4
        if !hooks.reduceMotion() {
            ring.run(SKAction.repeatForever(SKAction.sequence([SKAction.fadeAlpha(to: 0.35, duration: 0.6), SKAction.fadeAlpha(to: 1, duration: 0.6)])))
        }
        uiLayer.addChild(ring)
        hintNode = ring
    }

    private func refreshTutorial() {
        arrowNode?.removeFromParent()
        arrowNode = nil
        guard let lane = hooks.tutorialLane(), lane >= 0, lane < layout.laneCount, !laneNodes.isEmpty, !laneNodes[lane].isEmpty else { return }
        let r = layout.laneFrontRects[lane]
        let node = SKNode()
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: 0, y: 0))
        tri.addLine(to: CGPoint(x: -11, y: 15))
        tri.addLine(to: CGPoint(x: 11, y: 15))
        tri.closeSubpath()
        let arrow = SKShapeNode(path: tri)
        arrow.fillColor = accentColor
        arrow.strokeColor = .white
        arrow.lineWidth = 2
        node.addChild(arrow)
        let label = SKLabelNode(text: "Tap!")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 16
        label.fontColor = accentColor
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 0, y: 19)
        node.addChild(label)
        node.position = p(CGPoint(x: r.midX, y: r.minY - 3))
        if !hooks.reduceMotion() {
            node.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 7, duration: 0.45),
                SKAction.moveBy(x: 0, y: -7, duration: 0.45),
            ])))
        }
        uiLayer.addChild(node)
        arrowNode = node
    }

    private func clearJam() {
        for bay in slotBays {
            bay.strokeColor = .clear
            bay.lineWidth = 0
        }
    }

    private func refreshJam() {
        let jammed = hooks.isStuck()
        for bay in slotBays {
            bay.strokeColor = jammed ? UIColor(red: 0.95, green: 0.66, blue: 0.24, alpha: 1) : .clear
            bay.lineWidth = jammed ? 3 : 0
        }
        if jammed, let tray = trayShape, !hooks.reduceMotion() {
            tray.removeAction(forKey: "jam")
            tray.run(SKAction.sequence([
                SKAction.rotate(toAngle: 0.012, duration: 0.07),
                SKAction.rotate(toAngle: -0.012, duration: 0.14),
                SKAction.rotate(toAngle: 0, duration: 0.07),
            ]), withKey: "jam")
        }
    }

    // MARK: - Preview ("what would this crate pack right now")

    private func showPreview(lane: Int) {
        hidePreview()
        guard lane >= 0, lane < layout.laneCount, let crate = rules.frontCrate(lane: lane, in: displayState) else { return }
        let cells = Set(rules.previewCells(lane: lane, in: displayState))
        let hasSlot = displayState.hasFreeSlot
        if hasSlot && !cells.isEmpty {
            for (idx, node) in blockNodes where !cells.contains(idx) { node.alpha = 0.35 }
            let ink = art.uiColor(crate.color)
            for idx in cells {
                let r = layout.cellRect(idx)
                let outline = SKShapeNode(rectOf: CGSize(width: r.width - 1, height: r.height - 1), cornerRadius: r.width * 0.2)
                outline.position = center(r)
                outline.strokeColor = appearance.dark ? UIColor.white : PixelArt.shade(ink, 0.55)
                outline.lineWidth = max(2, r.width * 0.12)
                outline.fillColor = .clear
                outline.zPosition = 3
                uiLayer.addChild(outline)
                previewNodes.append(outline)
            }
        }
        // Bubble above the crate
        let text: String
        if !hasSlot { text = "Tray is full" } else if cells.isEmpty { text = "Waits for blocks" } else { text = "Packs \(cells.count) now" }
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 14
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        let bw = CGFloat(text.count) * 8 + 22
        let bubble = SKShapeNode(rectOf: CGSize(width: bw, height: 26), cornerRadius: 13)
        bubble.fillColor = UIColor(red: 0.2, green: 0.17, blue: 0.3, alpha: 0.92)
        bubble.strokeColor = .clear
        let fr = layout.laneFrontRects[lane]
        let bx = min(max(fr.midX, bw / 2 + 4), size.width - bw / 2 - 4)
        bubble.position = p(CGPoint(x: bx, y: fr.minY - 22))
        bubble.zPosition = 6
        bubble.addChild(label)
        uiLayer.addChild(bubble)
        previewNodes.append(bubble)
        if !hooks.reduceMotion() {
            for n in previewNodes where n !== bubble {
                n.run(SKAction.repeatForever(SKAction.sequence([SKAction.fadeAlpha(to: 0.55, duration: 0.45), SKAction.fadeAlpha(to: 1, duration: 0.45)])))
            }
        }
    }

    private func hidePreview() {
        for n in previewNodes { n.removeFromParent() }
        previewNodes.removeAll()
        for n in blockNodes.values { n.alpha = 1 }
    }

    // MARK: - Touch handling

    private func topLeft(_ t: UITouch) -> CGPoint {
        let pt = t.location(in: self)
        return CGPoint(x: pt.x, y: size.height - pt.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let pt = topLeft(t)
        for (l, r) in layout.laneHitRects.enumerated() where r.contains(pt) {
            if rules.frontCrate(lane: l, in: displayState) != nil {
                pressLane = l
                pressTime = 0
                previewShown = false
            }
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let l = pressLane else { return }
        if !layout.laneHitRects[l].insetBy(dx: -14, dy: -14).contains(topLeft(t)) {
            hidePreview()
            pressLane = nil
            previewShown = false
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let l = pressLane else { return }
        let peeked = previewShown
        hidePreview()
        pressLane = nil
        previewShown = false
        if !peeked { hooks.tapLane(l) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        hidePreview()
        pressLane = nil
        previewShown = false
    }

    // MARK: - Animation

    private func schedule(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        scheduled.append(Scheduled(remaining: max(0.0001, delay), block: block))
    }

    private func slotCenter(_ slot: Int) -> CGPoint { center(layout.slotRects[slot]) }

    private func setSlotCount(_ slot: Int, to n: Int) {
        guard let node = slotNodes[slot], displayState.slotColor.indices.contains(slot) else { return }
        slotRemaining[slot] = n
        guard let id = slotColorId[slot] else { return }
        node.texture = art.crateTexture(id, count: max(0, n), side: layout.slotSize)
    }

    /// Color id of the crate currently shown in each slot while a transition plays.
    private var slotColorId: [Int: String] = [:]

    func play(_ t: PixelTransition, solved: Bool) {
        // Always start from the exact "before" picture (finishes any earlier animation).
        syncAll(t.before, showJam: false)
        guard layout.columns == t.before.width else { return }
        if hooks.reduceMotion() {
            playReduced(t, solved: solved)
        } else {
            playFull(t, solved: solved)
        }
    }

    private func idString(_ code: UInt8) -> String { String(Character(UnicodeScalar(code))) }

    private func playReduced(_ t: PixelTransition, solved: Bool) {
        animating = true
        // Crate appears in its slot, packed blocks and crumbled stones simply fade away.
        var gone = Set<Int>()
        for e in t.events {
            gone.formUnion(e.cells)
            gone.formUnion(e.crumbled)
        }
        var ghosts: [SKNode] = []
        for idx in gone {
            if let n = blockNodes[idx] { ghosts.append(n) }
        }
        for n in ghosts { n.run(SKAction.fadeOut(withDuration: 0.18)) }
        let after = t.after
        schedule(0.2) { [weak self] in
            guard let self = self else { return }
            self.syncAll(after)
            if solved { self.playCompletion() }
        }
    }

    private func playFull(_ t: PixelTransition, solved: Bool) {
        animating = true
        let sp = max(1.0, hooks.speed())
        let lane = t.move.lane
        guard lane < laneNodes.count, let hopper = laneNodes[lane].first else {
            syncAll(t.after)
            return
        }
        let crateId = t.crate.color

        // Total animated cells, used to budget the swarm so a long cascade never drags.
        let totalCells = max(1, t.events.reduce(0) { $0 + $1.cells.count })
        let nominal = 0.42 + Double(t.events.count) * 0.55 + Double(min(totalCells, 40)) * 0.03
        let scale = min(1.0, 2.3 / nominal) / sp
        func d(_ x: Double) -> TimeInterval { x * scale }

        // 1. The crate hops from its lane into the tray slot.
        let hopDuration = d(0.3)
        laneNodes[lane].removeFirst()
        let from = hopper.position
        let to = slotCenter(t.slot)
        let path = CGMutablePath()
        path.move(to: from)
        path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + 40))
        hopper.zPosition = 40
        hopper.removeAllActions()
        hopper.run(SKAction.group([
            SKAction.follow(path, asOffset: false, orientToPath: false, duration: hopDuration),
            SKAction.scale(to: layout.slotSize / layout.laneFrontSize, duration: hopDuration),
        ]))
        slotColorId[t.slot] = crateId
        // The rest of the lane slides forward.
        advanceLane(lane, after: t.before.laneNext[lane] + 1, duration: d(0.25))
        hooks.softHaptic()

        schedule(hopDuration) { [weak self] in
            guard let self = self else { return }
            hopper.removeFromParent()
            hopper.removeAllActions()
            let slotNode = self.crateNode(color: crateId, count: t.crate.count, side: self.layout.slotSize)
            slotNode.position = to
            slotNode.zPosition = 1
            self.trayLayer.addChild(slotNode)
            self.slotNodes[t.slot] = slotNode
            self.slotRemaining[t.slot] = t.crate.count
            slotNode.setScale(1.12)
            slotNode.run(SKAction.scale(to: 1, duration: d(0.12)))
        }

        // 2. Swarm events in order.
        var cursor = hopDuration + d(0.05)
        var remainingBySlot: [Int: Int] = [:]
        for (i, rem) in t.before.slotRemaining.enumerated() { remainingBySlot[i] = rem }
        remainingBySlot[t.slot] = t.crate.count
        for (i, c) in t.before.slotColor.enumerated() where c != 0 { slotColorId[i] = idString(c) }

        for e in t.events {
            let n = e.cells.count
            var eventLen: TimeInterval = d(0.08)
            if n > 0 {
                let k = min(n, max(4, Int(Double(40) * Double(n) / Double(totalCells))))
                let stagger = min(d(0.06), d(0.7) / Double(max(k, 1)))
                let out = d(0.2)
                let back = d(0.22)
                for j in 0..<k {
                    let cell = e.cells[j]
                    let start = cursor + stagger * Double(j)
                    let slot = e.slot
                    let colorId = idString(e.color)
                    schedule(start) { [weak self] in
                        self?.spawnPal(slot: slot, cell: cell, colorId: colorId, out: out, back: back)
                    }
                    schedule(start + out) { [weak self] in
                        self?.popBlock(cell)
                    }
                    schedule(start + out + back) { [weak self] in
                        guard let self = self else { return }
                        let left = (remainingBySlot[slot] ?? 1) - 1
                        remainingBySlot[slot] = left
                        self.setSlotCount(slot, to: left)
                        self.bump(slot)
                    }
                }
                eventLen = stagger * Double(k - 1) + out + back + d(0.05)
                if n > k {
                    let rest = Array(e.cells[k...])
                    let slot = e.slot
                    schedule(cursor + eventLen - d(0.05)) { [weak self] in
                        guard let self = self else { return }
                        for idx in rest { self.fadeBlock(idx) }
                        let left = (remainingBySlot[slot] ?? rest.count) - rest.count
                        remainingBySlot[slot] = left
                        self.setSlotCount(slot, to: left)
                    }
                }
            }
            let end = cursor + eventLen
            if !e.crumbled.isEmpty {
                let crumbled = e.crumbled
                schedule(end) { [weak self] in
                    for idx in crumbled { self?.crumbleStone(idx) }
                    self?.hooks.softHaptic()
                }
                eventLen += d(0.12)
            }
            if e.departed {
                let slot = e.slot
                schedule(end) { [weak self] in
                    self?.departCrate(slot: slot)
                    self?.hooks.selectionHaptic()
                }
                eventLen += d(0.1)
            }
            cursor += eventLen
        }

        // 3. Snap to the exact final picture.
        let after = t.after
        schedule(cursor + d(0.12)) { [weak self] in
            guard let self = self else { return }
            self.syncAll(after)
            if solved { self.playCompletion() }
        }
    }

    /// Moves the queued crates of `lane` one place forward (front crate has just left).
    private func advanceLane(_ lane: Int, after next: Int, duration: TimeInterval) {
        guard lane < laneNodes.count else { return }
        let all = rules.payload.lanes[lane]
        var nodes = laneNodes[lane]
        // Existing sprites (formerly queue 1, 2) take the next roles.
        for (k, node) in nodes.enumerated() {
            let role = k
            let target: CGPoint
            let targetScale: CGFloat
            if role == 0 {
                target = center(layout.laneFrontRects[lane]); targetScale = 1
            } else {
                let c = layout.laneQueueCenters[lane]
                target = p(c[min(role - 1, c.count - 1)]); targetScale = layout.laneQueueScale
            }
            node.zPosition = 10 - CGFloat(role)
            node.colorBlendFactor = role == 0 ? 0 : 0.1 * CGFloat(role)
            node.run(SKAction.group([
                SKAction.move(to: target, duration: duration),
                SKAction.scale(to: targetScale, duration: duration),
            ]))
        }
        // A fresh crate may now become visible at the back.
        let nextVisible = next + nodes.count
        if nextVisible < all.count, nodes.count < 1 + PixelLayout.maxQueueShown {
            let crate = all[nextVisible]
            let node = crateNode(color: crate.color, count: crate.count, side: layout.laneFrontSize)
            place(node, role: nodes.count, lane: lane)
            node.alpha = 0
            node.run(SKAction.fadeAlpha(to: 0.92, duration: duration))
            laneLayer.addChild(node)
            nodes.append(node)
        }
        laneNodes[lane] = nodes
    }

    private func spawnPal(slot: Int, cell: Int, colorId: String, out: TimeInterval, back: TimeInterval) {
        let palSide = min(max(layout.cell * 1.15, 18), 30)
        let container = SKNode()
        container.zPosition = 5
        let pal = SKSpriteNode(texture: art.palTexture(capColor: colorId, side: palSide))
        pal.size = CGSize(width: palSide, height: palSide)
        container.addChild(pal)
        container.name = "pal"
        let start = slotCenter(slot)
        let target = center(layout.cellRect(cell))
        container.position = start
        container.setScale(0.6)
        fxLayer.addChild(container)
        let carry = SKSpriteNode(texture: art.boxTexture(colorId, side: palSide * 0.5))
        carry.size = CGSize(width: palSide * 0.5, height: palSide * 0.5)
        carry.position = CGPoint(x: 0, y: palSide * 0.62)
        carry.isHidden = true
        carry.name = "carry"
        container.addChild(carry)
        container.run(SKAction.sequence([
            SKAction.group([
                SKAction.move(to: target, duration: out),
                SKAction.scale(to: 1, duration: out),
            ]),
            SKAction.group([
                SKAction.move(to: start, duration: back),
                SKAction.scale(to: 0.6, duration: back),
            ]),
            SKAction.removeFromParent(),
        ]))
        carry.run(SKAction.sequence([SKAction.wait(forDuration: out), SKAction.unhide()]))
    }

    private func popBlock(_ idx: Int) {
        guard let node = blockNodes[idx] else { return }
        node.run(SKAction.sequence([
            SKAction.scale(to: 1.18, duration: 0.05),
            SKAction.group([SKAction.scale(to: 0.2, duration: 0.09), SKAction.fadeOut(withDuration: 0.09)]),
            SKAction.removeFromParent(),
        ]))
        blockNodes[idx] = nil
    }

    private func fadeBlock(_ idx: Int) {
        guard let node = blockNodes[idx] else { return }
        node.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.12), SKAction.removeFromParent()]))
        blockNodes[idx] = nil
    }

    private func bump(_ slot: Int) {
        guard let node = slotNodes[slot] else { return }
        node.removeAction(forKey: "bump")
        node.run(SKAction.sequence([SKAction.scale(to: 1.07, duration: 0.04), SKAction.scale(to: 1, duration: 0.06)]), withKey: "bump")
    }

    private func crumbleStone(_ idx: Int) {
        let r = layout.cellRect(idx)
        if let node = blockNodes[idx] {
            node.run(SKAction.sequence([SKAction.group([SKAction.scale(to: 0.1, duration: 0.2), SKAction.fadeOut(withDuration: 0.2)]), SKAction.removeFromParent()]))
            blockNodes[idx] = nil
        }
        let c = center(r)
        let bits: [CGVector] = [CGVector(dx: -1, dy: 1), CGVector(dx: 1, dy: 1), CGVector(dx: -0.8, dy: -1), CGVector(dx: 1, dy: -0.8)]
        for v in bits {
            let b = SKSpriteNode(color: UIColor(white: 0.55, alpha: 1), size: CGSize(width: layout.cell * 0.22, height: layout.cell * 0.22))
            b.position = c
            b.zPosition = 6
            fxLayer.addChild(b)
            b.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: v.dx * layout.cell * 0.7, y: v.dy * layout.cell * 0.7, duration: 0.3),
                    SKAction.fadeOut(withDuration: 0.3),
                    SKAction.rotate(byAngle: 1.5, duration: 0.3),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    private func departCrate(slot: Int) {
        guard let node = slotNodes[slot] else { return }
        slotNodes[slot] = nil
        let dx = layout.slotSize * 1.4
        node.zPosition = 6
        node.run(SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.07),
            SKAction.group([
                SKAction.moveBy(x: dx, y: layout.slotSize * 0.3, duration: 0.28),
                SKAction.fadeOut(withDuration: 0.28),
                SKAction.scale(to: 0.7, duration: 0.28),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Completion flourish

    /// A calm reveal of the finished picture with a few sparkles, about a second long.
    private func playCompletion() {
        hooks.successHaptic()
        let grid = rules.payload.grid
        let reduce = hooks.reduceMotion()
        let rows = grid.count
        let cols = grid.first?.utf8.count ?? 0
        let cx = Double(cols - 1) / 2
        let cy = Double(rows - 1) / 2
        let maxD = max(1.0, (cx * cx + cy * cy).squareRoot())
        let sp = max(1.0, hooks.speed())
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.utf8.enumerated() where ch != PixelCell.clear && ch != PixelCell.stone {
                let node = SKSpriteNode(texture: art.blockTexture(idString(ch), side: layout.cell))
                node.size = CGSize(width: layout.cell, height: layout.cell)
                node.position = center(layout.cellRect(r * cols + c))
                node.alpha = 0
                node.zPosition = 1
                blockLayer.addChild(node)
                if reduce {
                    node.run(SKAction.fadeAlpha(to: 0.95, duration: 0.25))
                } else {
                    let dist = ((Double(c) - cx) * (Double(c) - cx) + (Double(r) - cy) * (Double(r) - cy)).squareRoot() / maxD
                    node.setScale(0.5)
                    node.run(SKAction.sequence([
                        SKAction.wait(forDuration: dist * 0.4 / sp),
                        SKAction.group([SKAction.fadeAlpha(to: 0.95, duration: 0.2 / sp), SKAction.scale(to: 1, duration: 0.2 / sp)]),
                    ]))
                }
            }
        }
        if !reduce {
            let colors: [UIColor] = [UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), UIColor.white, UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)]
            let area = layout.gridRect
            for i in 0..<14 {
                let dot = SKShapeNode(circleOfRadius: CGFloat(2 + i % 3))
                dot.fillColor = colors[i % colors.count]
                dot.strokeColor = .clear
                let x = area.minX + area.width * CGFloat((i * 37) % 100) / 100
                let y = area.maxY - area.height * CGFloat((i * 53) % 70) / 100
                dot.position = p(CGPoint(x: x, y: y))
                dot.alpha = 0
                dot.zPosition = 8
                fxLayer.addChild(dot)
                dot.run(SKAction.sequence([
                    SKAction.wait(forDuration: Double(i) * 0.04 / sp),
                    SKAction.group([
                        SKAction.fadeIn(withDuration: 0.12),
                        SKAction.moveBy(x: 0, y: 26, duration: 0.7 / sp),
                    ]),
                    SKAction.fadeOut(withDuration: 0.25),
                    SKAction.removeFromParent(),
                ]))
            }
        }
    }
}

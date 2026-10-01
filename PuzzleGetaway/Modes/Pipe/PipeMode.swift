import SwiftUI
import UIKit

// MARK: - Hint helper (plain value logic, no actor isolation)

extension PipeRules {
    /// A tap that moves `s` toward the configuration `target`: the tile nearest the source whose openings differ.
    func hintMove(toward target: PipeState, from s: PipeState) -> PipeMove? {
        guard s.rots.count == kinds.count, target.rots.count == kinds.count else { return nil }
        let source = sourceIndex ?? 0
        var best: (distance: Int, index: Int)?
        for i in kinds.indices where kinds[i] != "." && !fixed[i] {
            if mask(at: i, s) == mask(at: i, target) { continue }
            let d = abs(i / cols - source / cols) + abs(i % cols - source % cols)
            if best == nil || d < best!.distance { best = (d, i) }
        }
        guard let pick = best else { return nil }
        return PipeMove(r: pick.index / cols, c: pick.index % cols)
    }
}

// MARK: - Plugin

enum PipeMode: PuzzleModePlugin {
    static let mode = "pipe"
    static let displayName = "Flow Fix"

    @MainActor
    static func makeController(level: LevelEnvelope, snapshot: Data?, context: GameContext) -> AnyGameController {
        let payload = (try? level.decodePayload(PipePayload.self)) ?? PipePayload(grid: [["S0", "D0"]], fixed: nil)
        let rules = PipeRules(payload: payload)
        let solution = (try? level.decodeSolution(PipeMove.self)) ?? []
        let session = GameSession(rules: rules, initial: rules.initialState, solution: solution)
        if let snapshot = snapshot { session.restore(from: snapshot) }
        // The stored solution tells us one solved configuration; hints steer the player toward it.
        var target = rules.initialState
        var valid = true
        for move in solution {
            if let next = rules.apply(move, to: target) { target = next } else { valid = false }
        }
        let targetState: PipeState? = valid && rules.isSolved(target) ? target : nil
        if let targetState = targetState {
            session.hintProvider = { state in rules.hintMove(toward: targetState, from: state) }
        }
        let isTutorial = level.tutorial == "pipe.rotate"
        return PipeController(levelId: level.id, title: level.title, session: session, context: context,
                              payload: payload, tutorialMove: isTutorial ? solution.first : nil)
    }

    static func replay(level: LevelEnvelope) throws -> Bool {
        let payload = try level.decodePayload(PipePayload.self)
        let rules = PipeRules(payload: payload)
        var state = rules.initialState
        for move in try level.decodeSolution(PipeMove.self) {
            if rules.isSolved(state) { return false }
            guard let next = rules.apply(move, to: state) else { return false }
            state = next
        }
        return rules.isSolved(state)
    }
}

// MARK: - Controller

@MainActor
final class PipeController: SessionController<PipeRules> {
    let payload: PipePayload
    let tutorialMove: PipeMove?
    private var madeFirstMove = false

    init(levelId: String, title: String, session: GameSession<PipeRules>, context: GameContext,
         payload: PipePayload, tutorialMove: PipeMove?) {
        self.payload = payload
        self.tutorialMove = tutorialMove
        super.init(levelId: levelId, title: title, session: session, context: context)
        madeFirstMove = session.moveCount > 0
    }

    var rules: PipeRules { session.rules }

    /// The tile the board should point at: an explicit hint, or the tutorial arrow before the first move.
    var highlightedMove: PipeMove? {
        if let hint = session.activeHint { return hint }
        if let guide = tutorialMove, !madeFirstMove, session.moveCount == 0 { return guide }
        return nil
    }

    @discardableResult
    func rotate(row: Int, col: Int) -> Bool {
        let ok = attempt(PipeMove(r: row, c: col))
        if ok { madeFirstMove = true }
        return ok
    }

    var litDestinationCount: Int {
        let reached = rules.flow(session.state).reached
        return rules.destinationIndices.filter { reached[$0] }.count
    }

    /// Fraction of destinations that currently receive flow.
    override var progress: Double? {
        let total = rules.destinationIndices.count
        return total > 0 ? Double(litDestinationCount) / Double(total) : nil
    }

    override var accessibilitySummary: String {
        let total = rules.destinationIndices.count
        return "Flow Fix board, \(rules.rows) rows by \(rules.cols) columns. \(litDestinationCount) of \(total) \(total == 1 ? "lamp" : "lamps") lit."
    }

    override var boardView: AnyView {
        AnyView(PipeBoardView(controller: self))
    }
}

// MARK: - Pipe art

private enum PipeColors {
    static func brass(_ hc: Bool) -> Color { Color(hex: hc ? "#FFD966" : "#C9A24B") }
    static func brassEdge(_ hc: Bool) -> Color { hc ? Color.black : Color(hex: "#6E5019") }
    static let brassHighlight = Color(hex: "#F0DB9C")
    static func water(_ hc: Bool, solved: Bool) -> Color { Color(hex: hc ? "#00A8F5" : (solved ? "#6FCBFF" : "#47B3EE")) }
    static let waterGlint = Color(hex: "#D8F4FF")
    static var slate: Color { Color(light: "#4C566A", dark: "#2F3542") }
    static var slateEdge: Color { Color(light: "#39414F", dark: "#1F242D") }
    static let lampOn = Color(hex: "#FFE18A")
    static let lampOff = Color(hex: "#6B7685")
}

private enum PipeArt {
    static func armEnd(_ dir: Int, size s: CGFloat) -> CGPoint {
        switch dir {
        case 0: return CGPoint(x: s / 2, y: 0)
        case 1: return CGPoint(x: s, y: s / 2)
        case 2: return CGPoint(x: s / 2, y: s)
        default: return CGPoint(x: 0, y: s / 2)
        }
    }

    /// Draws the tile's pipes in canonical (rotation 0) orientation. `entry` is the canonical arm the flow enters by.
    static func draw(_ g: inout GraphicsContext, size s: CGFloat, kind: Character, entry: Int?, reached: Bool,
                     solved: Bool, phase: Double, highContrast hc: Bool) {
        let center = CGPoint(x: s / 2, y: s / 2)
        let pw = s * 0.28
        let mask = PipeRules.baseMask(kind)
        let arms = (0..<4).filter { mask & (1 << $0) != 0 }

        var all = Path()
        for d in arms {
            all.move(to: center)
            all.addLine(to: armEnd(d, size: s))
        }
        // Brass pipe: dark edge, body, highlight.
        g.stroke(all, with: .color(PipeColors.brassEdge(hc)), style: StrokeStyle(lineWidth: pw + 4, lineCap: .butt, lineJoin: .round))
        g.stroke(all, with: .color(PipeColors.brass(hc)), style: StrokeStyle(lineWidth: pw, lineCap: .butt, lineJoin: .round))
        g.stroke(all, with: .color(PipeColors.brassHighlight.opacity(hc ? 0.0 : 0.55)), style: StrokeStyle(lineWidth: pw * 0.18, lineCap: .butt, lineJoin: .round))

        // Joint hubs and flanges.
        switch kind {
        case "l", "t", "x":
            let hub = CGRect(x: center.x - pw * 0.62, y: center.y - pw * 0.62, width: pw * 1.24, height: pw * 1.24)
            g.fill(Path(ellipseIn: hub), with: .color(PipeColors.brass(hc)))
            g.stroke(Path(ellipseIn: hub), with: .color(PipeColors.brassEdge(hc)), lineWidth: 2)
        case "i":
            for d in arms {
                let end = armEnd(d, size: s)
                let inward = CGPoint(x: end.x + (center.x - end.x) * 0.16, y: end.y + (center.y - end.y) * 0.16)
                var band = Path()
                let horizontal = d == 1 || d == 3
                band.move(to: CGPoint(x: inward.x + (horizontal ? 0 : -pw * 0.62), y: inward.y + (horizontal ? -pw * 0.62 : 0)))
                band.addLine(to: CGPoint(x: inward.x + (horizontal ? 0 : pw * 0.62), y: inward.y + (horizontal ? pw * 0.62 : 0)))
                g.stroke(band, with: .color(PipeColors.brassEdge(hc)), style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round))
                g.stroke(band, with: .color(PipeColors.brass(hc)), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
            }
        default:
            break
        }

        // Water.
        if reached {
            let water = PipeColors.water(hc, solved: solved)
            g.stroke(all, with: .color(water), style: StrokeStyle(lineWidth: pw * 0.52, lineCap: .butt, lineJoin: .round))
            g.fill(Path(ellipseIn: CGRect(x: center.x - pw * 0.26, y: center.y - pw * 0.26, width: pw * 0.52, height: pw * 0.52)), with: .color(water))
            if phase >= 0 {
                for d in arms {
                    var p = Path()
                    if d == entry {
                        p.move(to: armEnd(d, size: s))
                        p.addLine(to: center)
                    } else {
                        p.move(to: center)
                        p.addLine(to: armEnd(d, size: s))
                    }
                    g.stroke(p, with: .color(PipeColors.waterGlint.opacity(0.85)),
                             style: StrokeStyle(lineWidth: pw * 0.2, lineCap: .round, dash: [s * 0.1, s * 0.2], dashPhase: -CGFloat(phase) * s))
                }
            }
        }

        // Endpoints.
        if kind == "S" {
            let r = s * 0.27
            let plate = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            g.fill(Path(ellipseIn: plate), with: .color(PipeColors.brass(hc)))
            g.stroke(Path(ellipseIn: plate), with: .color(PipeColors.brassEdge(hc)), lineWidth: 2.5)
            var spokes = Path()
            spokes.move(to: CGPoint(x: center.x - r * 0.75, y: center.y))
            spokes.addLine(to: CGPoint(x: center.x + r * 0.75, y: center.y))
            spokes.move(to: CGPoint(x: center.x, y: center.y - r * 0.75))
            spokes.addLine(to: CGPoint(x: center.x, y: center.y + r * 0.75))
            g.stroke(spokes, with: .color(Color(hex: hc ? "#B3201A" : "#D8604A")), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
            g.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.28, y: center.y - r * 0.28, width: r * 0.56, height: r * 0.56)),
                   with: .color(PipeColors.water(hc, solved: solved)))
        } else if kind == "D" {
            let lit = reached
            let r = s * 0.27
            if lit {
                let glow = Gradient(colors: [PipeColors.lampOn.opacity(solved ? 0.95 : 0.7), PipeColors.lampOn.opacity(0)])
                g.fill(Path(ellipseIn: CGRect(x: center.x - s * 0.62, y: center.y - s * 0.62, width: s * 1.24, height: s * 1.24)),
                       with: .radialGradient(glow, center: center, startRadius: 0, endRadius: s * 0.62))
            }
            let plate = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            g.fill(Path(ellipseIn: plate), with: .color(PipeColors.brass(hc)))
            g.stroke(Path(ellipseIn: plate), with: .color(PipeColors.brassEdge(hc)), lineWidth: 2.5)
            let gr = r * 0.72
            let glass = CGRect(x: center.x - gr, y: center.y - gr, width: gr * 2, height: gr * 2)
            g.fill(Path(ellipseIn: glass), with: .color(lit ? PipeColors.lampOn : PipeColors.lampOff))
            g.stroke(Path(ellipseIn: glass), with: .color(PipeColors.brassEdge(hc)), lineWidth: 1.5)
            if lit {
                g.fill(Path(ellipseIn: CGRect(x: center.x - gr * 0.55, y: center.y - gr * 0.6, width: gr * 0.5, height: gr * 0.4)),
                       with: .color(Color.white.opacity(0.8)))
            }
        }
    }
}

// MARK: - Tile

private struct PipeTileView: View {
    let kind: Character
    let angle: Double
    let rot: Int
    let reached: Bool
    let entry: Int?
    let solved: Bool
    let fixed: Bool
    let hinted: Bool
    let cell: CGFloat
    let highContrast: Bool
    let animateWater: Bool
    let spring: Animation?
    let pulse: Bool

    var body: some View {
        let inset: CGFloat = max(1.5, cell * 0.04)
        let shape = RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
        return ZStack {
            shape.fill(kind == "." ? PipeColors.slateEdge.opacity(0.55) : PipeColors.slate)
            if reached {
                shape.fill(Color(hex: "#3B8FC4").opacity(solved ? 0.3 : 0.18))
            }
            shape.stroke(highContrast ? Color.white.opacity(0.7) : PipeColors.slateEdge, lineWidth: highContrast ? 1.5 : 1)
            if kind == "." {
                Circle().fill(PipeColors.slateEdge).frame(width: cell * 0.12, height: cell * 0.12)
            } else {
                pipes
                    .frame(width: cell, height: cell)
                    .rotationEffect(.degrees(angle))
                    .animation(spring, value: angle)
                    .scaleEffect(kind == "D" && pulse ? 1.18 : 1)
            }
            if hinted {
                RoundedRectangle(cornerRadius: cell * 0.16, style: .continuous)
                    .stroke(Color(hex: "#7CF09A"), lineWidth: 3.5)
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: cell * 0.34, weight: .bold))
                    .foregroundColor(Color(hex: "#7CF09A"))
                    .shadow(color: Color.black.opacity(0.5), radius: 2)
                    .offset(x: cell * 0.28, y: -cell * 0.28)
            }
            if fixed && kind != "S" && kind != "D" && kind != "." {
                Circle().fill(PipeColors.slateEdge).frame(width: cell * 0.1, height: cell * 0.1)
                    .offset(x: -cell * 0.36, y: -cell * 0.36)
            }
        }
        .padding(inset)
        .frame(width: cell, height: cell)
    }

    @ViewBuilder
    private var pipes: some View {
        let canonicalEntry = entry.map { (($0 - rot) % 4 + 4) % 4 }
        if reached && animateWater {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                canvas(entry: canonicalEntry, phase: t.truncatingRemainder(dividingBy: 100) * 0.45)
            }
        } else {
            canvas(entry: canonicalEntry, phase: -1)
        }
    }

    private func canvas(entry: Int?, phase: Double) -> some View {
        Canvas { ctx, size in
            var g = ctx
            PipeArt.draw(&g, size: min(size.width, size.height), kind: kind, entry: entry, reached: reached,
                         solved: solved, phase: phase, highContrast: highContrast)
        }
    }
}

// MARK: - Rain backdrop

private struct RainLayer: View {
    let animate: Bool

    var body: some View {
        if animate {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                streaks(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            streaks(time: 0)
        }
    }

    private func streaks(time: Double) -> some View {
        Canvas { ctx, size in
            for i in 0..<26 {
                let fx = (Double(i) * 0.6180339).truncatingRemainder(dividingBy: 1)
                let speed = 60 + Double((i * 37) % 50)
                let len = CGFloat(10 + (i * 7) % 12)
                let span = Double(size.height + len)
                let y = (Double((i * 53) % 100) / 100 * span + time * speed).truncatingRemainder(dividingBy: span) - Double(len)
                let x = CGFloat(fx) * size.width
                var p = Path()
                p.move(to: CGPoint(x: x, y: CGFloat(y)))
                p.addLine(to: CGPoint(x: x - len * 0.18, y: CGFloat(y) + len))
                ctx.stroke(p, with: .color(Color.white.opacity(0.09)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Board

@MainActor
struct PipeBoardView: View {
    @ObservedObject var controller: PipeController
    @ObservedObject private var settings: Settings
    @State private var angles: [Double]
    @State private var pulse = false
    @State private var bob = false

    init(controller: PipeController) {
        self.controller = controller
        _settings = ObservedObject(wrappedValue: controller.context.settings)
        _angles = State(initialValue: controller.session.state.rots.map { Double($0) * 90 })
    }

    private var rules: PipeRules { controller.rules }

    var body: some View {
        let state = controller.session.state
        let flow = rules.flow(state)
        let solved = controller.isSolved
        let highlight = controller.highlightedMove
        return GeometryReader { geo in
            let pad: CGFloat = 12
            let cell = max(10, floor(min((geo.size.width - 2 * pad) / CGFloat(max(1, rules.cols)),
                                         (geo.size.height - 2 * pad) / CGFloat(max(1, rules.rows)))))
            let boardW = cell * CGFloat(rules.cols) + 2 * pad
            let boardH = cell * CGFloat(rules.rows) + 2 * pad
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(light: "#5F6F82", dark: "#232A36"), Color(light: "#46556A", dark: "#171C25")],
                                         startPoint: .top, endPoint: .bottom))
                RainLayer(animate: !settings.effectiveReduceMotion)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(spacing: 0) {
                    ForEach(0..<rules.rows, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<rules.cols, id: \.self) { c in
                                tile(r: r, c: c, cell: cell, state: state, flow: flow, solved: solved, highlight: highlight)
                            }
                        }
                    }
                }
            }
            .frame(width: boardW, height: boardH)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(CGFloat(max(1, rules.cols)) / CGFloat(max(1, rules.rows)), contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controller.accessibilitySummary)
        .onAppear {
            if !settings.effectiveReduceMotion {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { bob = true }
            }
        }
        .onChange(of: controller.session.state.rots) { rots in syncAngles(rots) }
        .onChange(of: controller.isSolved) { isSolved in
            guard isSolved, !settings.effectiveReduceMotion else { return }
            withAnimation(.spring(response: settings.duration(0.35), dampingFraction: 0.5)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.duration(0.5)) {
                withAnimation(.easeOut(duration: settings.duration(0.3))) { pulse = false }
            }
        }
    }

    @ViewBuilder
    private func tile(r: Int, c: Int, cell: CGFloat, state: PipeState, flow: (reached: [Bool], parent: [Int]),
                      solved: Bool, highlight: PipeMove?) -> some View {
        let i = r * rules.cols + c
        let kind = rules.kinds[i]
        let reached = flow.reached[i]
        let parent = flow.parent[i]
        let hinted = highlight.map { $0.r == r && $0.c == c } ?? false
        let spring: Animation? = settings.effectiveReduceMotion ? nil : .spring(response: settings.duration(0.35), dampingFraction: 0.62)
        Button {
            tap(r: r, c: c)
        } label: {
            PipeTileView(kind: kind, angle: angles.indices.contains(i) ? angles[i] : Double(state.rots[i]) * 90,
                         rot: state.rots[i], reached: reached, entry: parent >= 0 ? parent : nil, solved: solved,
                         fixed: rules.fixed[i], hinted: hinted, cell: cell, highContrast: settings.highContrast,
                         animateWater: !settings.effectiveReduceMotion, spring: spring, pulse: pulse)
                .scaleEffect(hinted && bob && !settings.effectiveReduceMotion ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .allowsHitTesting(!solved && kind != ".")
        .accessibilityHidden(kind == ".")
        .accessibilityLabel(label(r: r, c: c, state: state, reached: reached))
        .accessibilityHint(kind == "." || rules.fixed[i] ? "" : "Double tap to rotate a quarter turn clockwise")
        .accessibilityAddTraits(.isButton)
    }

    private func label(r: Int, c: Int, state: PipeState, reached: Bool) -> String {
        let i = r * rules.cols + c
        let kind = rules.kinds[i]
        let openings = PipeRules.openingsText(rules.mask(at: i, state))
        var text = "Row \(r + 1), column \(c + 1): \(PipeRules.kindName(kind)), connects \(openings)"
        switch kind {
        case "S": text += ", fixed"
        case "D": text += reached ? ", lit, connected to source" : ", not lit"
        default:
            if rules.fixed[i] { text += ", fixed" }
            text += reached ? ", connected to source" : ", not connected"
        }
        return text
    }

    private func tap(r: Int, c: Int) {
        let i = r * rules.cols + c
        guard rules.kinds[i] != "." else { return }
        let ok = controller.rotate(row: r, col: c)
        if ok {
            let state = controller.session.state
            let reached = rules.flow(state).reached[i]
            let text = "Connects \(PipeRules.openingsText(rules.mask(at: i, state)))" + (reached ? ", connected to source" : "")
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    private func syncAngles(_ rots: [Int]) {
        var next = angles
        if next.count != rots.count { next = rots.map { Double($0) * 90 } }
        for i in rots.indices {
            let old = ((Int((next[i] / 90).rounded()) % 4) + 4) % 4
            let diff = (rots[i] - old + 4) % 4
            if diff == 0 { continue }
            next[i] += diff == 3 ? -90 : 90 * Double(diff)
        }
        angles = next
    }
}

import SwiftUI
import UIKit

// MARK: - Plugin

enum ParkingMode: PuzzleModePlugin {
    static let mode = "parking"
    static let displayName = "Baggage Jam"

    @MainActor
    static func makeController(level: LevelEnvelope, snapshot: Data?, context: GameContext) -> AnyGameController {
        let payload = (try? level.decodePayload(ParkingPayload.self))
            ?? ParkingPayload(size: 6, vehicles: [ParkingVehicle(id: "T", r: 0, c: 0, len: 2, axis: "h", target: true)],
                              gates: [ParkingGate(target: "T", edge: "right", index: 0)])
        let rules = ParkingRules(payload: payload)
        let solution = (try? level.decodeSolution(ParkingMove.self)) ?? []
        let session = GameSession(rules: rules, initial: rules.initialState, solution: solution)
        if let snapshot = snapshot { session.restore(from: snapshot) }
        let isTutorial = level.tutorial == "parking.slide"
        return ParkingController(levelId: level.id, title: level.title, session: session, context: context,
                                 payload: payload, tutorialMove: isTutorial ? solution.first : nil)
    }

    static func replay(level: LevelEnvelope) throws -> Bool {
        let payload = try level.decodePayload(ParkingPayload.self)
        let rules = ParkingRules(payload: payload)
        var state = rules.initialState
        for move in try level.decodeSolution(ParkingMove.self) {
            if rules.isSolved(state) { return false }
            guard let next = rules.apply(move, to: state) else { return false }
            state = next
        }
        return rules.isSolved(state)
    }
}

// MARK: - Controller

@MainActor
final class ParkingController: SessionController<ParkingRules> {
    let payload: ParkingPayload
    /// First stored move, shown as a pointing arrow on tutorial levels until the first move is made.
    let tutorialMove: ParkingMove?
    private var madeFirstMove = false

    init(levelId: String, title: String, session: GameSession<ParkingRules>, context: GameContext,
         payload: ParkingPayload, tutorialMove: ParkingMove?) {
        self.payload = payload
        self.tutorialMove = tutorialMove
        super.init(levelId: levelId, title: title, session: session, context: context)
        madeFirstMove = session.moveCount > 0
    }

    var rules: ParkingRules { session.rules }

    /// The move the board should point at: an explicit hint, or the tutorial arrow before the first move.
    var highlightedMove: ParkingMove? {
        if let hint = session.activeHint { return hint }
        if let guide = tutorialMove, !madeFirstMove, session.moveCount == 0 { return guide }
        return nil
    }

    @discardableResult
    func slide(id: String, delta: Int) -> Bool {
        let ok = attempt(ParkingMove(id: id, delta: delta))
        if ok { madeFirstMove = true }
        return ok
    }

    /// Fraction of target vehicles sitting at their gate; hidden on single-target boards (it would only jump 0 to 1).
    override var progress: Double? {
        let targets = rules.vehicles.indices.filter { rules.vehicles[$0].isTarget }
        guard targets.count > 1 else { return nil }
        let out = targets.filter { rules.isAtGate(session.state, vehicle: $0) }.count
        return Double(out) / Double(targets.count)
    }

    override var accessibilitySummary: String {
        let n = rules.size
        let targets = payload.gates.map { gate -> String in
            let line = (gate.edge == "left" || gate.edge == "right") ? "row \(gate.index + 1)" : "column \(gate.index + 1)"
            return "the golden vehicle needs to reach the \(gate.edge) gate in \(line)"
        }
        return "Baggage Jam board, \(n) by \(n), \(payload.vehicles.count) vehicles. " + targets.joined(separator: "; ") + "."
    }

    override var boardView: AnyView {
        AnyView(ParkingBoardView(controller: self))
    }
}

// MARK: - Vehicle look

enum ParkingVehicleKind {
    case cart, train, tug, trolley

    var displayName: String {
        switch self {
        case .cart: return "luggage cart"
        case .train: return "mini train"
        case .tug: return "service tug"
        case .trolley: return "baggage trolley"
        }
    }

    static func kind(for vehicle: ParkingVehicle, index: Int) -> ParkingVehicleKind {
        if vehicle.isTarget { return .cart }
        if vehicle.len >= 3 { return index % 2 == 0 ? .train : .trolley }
        switch index % 3 {
        case 0: return .cart
        case 1: return .tug
        default: return .train
        }
    }
}

private let vehiclePaletteIds = ["b", "t", "p", "g", "i", "k", "o", "r", "n", "s"]

/// Draws one vehicle in a local horizontal frame (front toward +x). Used by the board's Canvas.
enum ParkingVehicleArt {
    static func draw(_ g: inout GraphicsContext, kind: ParkingVehicleKind, length L: CGFloat, width W: CGFloat,
                     body: Color, outline: Color, isTarget: Bool, highContrast: Bool, beacon: Double) {
        let inset = W * 0.1
        let bodyRect = CGRect(x: inset, y: inset, width: L - 2 * inset, height: W - 2 * inset)
        let radius = W * 0.26
        let lineW: CGFloat = highContrast ? 2.5 : 1.4
        let dark = Color.black.opacity(0.28)
        let window = Color(hex: "#CFE9F7")

        // Soft shadow.
        g.fill(Path(roundedRect: bodyRect.offsetBy(dx: 0, dy: W * 0.05), cornerRadius: radius), with: .color(Color.black.opacity(0.18)))

        // Wheels poke out of the sides (cart, tug, trolley).
        if kind != .train {
            let wheelW = W * 0.3
            let wheelH = W * 0.13
            for fx in [0.18, 0.82] {
                let x = L * CGFloat(fx) - wheelW / 2
                for y in [inset - wheelH * 0.6, W - inset - wheelH * 0.4] {
                    g.fill(Path(roundedRect: CGRect(x: x, y: y, width: wheelW, height: wheelH), cornerRadius: wheelH / 2),
                           with: .color(Color(hex: "#2F3140")))
                }
            }
        }

        switch kind {
        case .cart:
            g.fill(Path(roundedRect: bodyRect, cornerRadius: radius), with: .color(body))
            let bed = bodyRect.insetBy(dx: W * 0.1, dy: W * 0.1)
            g.fill(Path(roundedRect: bed, cornerRadius: radius * 0.6), with: .color(Color.white.opacity(0.28)))
            let cases = max(1, Int((L / W).rounded()))
            let slotW = bed.width / CGFloat(cases)
            let suitcaseColors = [Color(hex: "#E5594F"), Color(hex: "#5DA9E8"), Color(hex: "#6DC47A")]
            for i in 0..<cases {
                let rect = CGRect(x: bed.minX + slotW * CGFloat(i) + slotW * 0.1, y: bed.minY + bed.height * 0.08,
                                  width: slotW * 0.8, height: bed.height * 0.84)
                g.fill(Path(roundedRect: rect, cornerRadius: W * 0.1), with: .color(isTarget ? Color(hex: "#8A5A2B") : suitcaseColors[i % 3]))
                g.stroke(Path(roundedRect: rect, cornerRadius: W * 0.1), with: .color(dark), lineWidth: lineW)
                // Belt and handle.
                var belt = Path()
                belt.move(to: CGPoint(x: rect.midX, y: rect.minY))
                belt.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                g.stroke(belt, with: .color(Color.white.opacity(0.55)), lineWidth: lineW * 1.4)
                let handle = CGRect(x: rect.midX - rect.width * 0.18, y: rect.minY - W * 0.03, width: rect.width * 0.36, height: W * 0.06)
                g.fill(Path(roundedRect: handle, cornerRadius: W * 0.03), with: .color(dark))
            }
            // Front bumper.
            g.fill(Path(roundedRect: CGRect(x: bodyRect.maxX - W * 0.1, y: bodyRect.minY + W * 0.2, width: W * 0.14, height: bodyRect.height - W * 0.4), cornerRadius: W * 0.05),
                   with: .color(dark))

        case .train:
            let count = max(2, Int((L / W).rounded()))
            let segW = bodyRect.width / CGFloat(count)
            for i in 0..<count {
                let isEngine = i == count - 1
                let rect = CGRect(x: bodyRect.minX + segW * CGFloat(i) + (i == 0 ? 0 : W * 0.04), y: bodyRect.minY,
                                  width: segW - (i == 0 ? W * 0.04 : W * 0.08) + (isEngine ? W * 0.04 : 0), height: bodyRect.height)
                let shape = Path(roundedRect: rect, cornerRadius: isEngine ? radius : radius * 0.7)
                g.fill(shape, with: .color(isEngine ? body.opacity(0.78) : body))
                g.stroke(shape, with: .color(dark), lineWidth: lineW)
                if isEngine {
                    g.fill(Path(ellipseIn: CGRect(x: rect.midX - W * 0.16, y: rect.midY - W * 0.16, width: W * 0.32, height: W * 0.32)), with: .color(dark))
                    g.fill(Path(ellipseIn: CGRect(x: rect.maxX - W * 0.2, y: rect.midY - W * 0.07, width: W * 0.14, height: W * 0.14)), with: .color(Color(hex: "#FFE9A0")))
                } else {
                    for k in 0..<2 {
                        let wr = CGRect(x: rect.minX + rect.width * (0.14 + 0.42 * CGFloat(k)), y: rect.minY + rect.height * 0.26,
                                        width: rect.width * 0.32, height: rect.height * 0.48)
                        g.fill(Path(roundedRect: wr, cornerRadius: W * 0.07), with: .color(window))
                        g.stroke(Path(roundedRect: wr, cornerRadius: W * 0.07), with: .color(dark), lineWidth: lineW * 0.7)
                    }
                }
            }

        case .tug:
            let shape = Path(roundedRect: bodyRect, cornerRadius: radius)
            g.fill(shape, with: .color(body))
            g.stroke(shape, with: .color(dark), lineWidth: lineW)
            let cab = CGRect(x: bodyRect.minX + W * 0.06, y: bodyRect.minY + W * 0.08, width: bodyRect.width * 0.5, height: bodyRect.height - W * 0.16)
            g.fill(Path(roundedRect: cab, cornerRadius: radius * 0.8), with: .color(Color.white.opacity(0.3)))
            let win = CGRect(x: cab.maxX - cab.width * 0.38, y: cab.minY + cab.height * 0.18, width: cab.width * 0.3, height: cab.height * 0.64)
            g.fill(Path(roundedRect: win, cornerRadius: W * 0.06), with: .color(window))
            // Hood stripe and headlights.
            for y in [bodyRect.minY + W * 0.12, bodyRect.maxY - W * 0.12 - W * 0.1] {
                g.fill(Path(ellipseIn: CGRect(x: bodyRect.maxX - W * 0.18, y: y, width: W * 0.1, height: W * 0.1)), with: .color(Color(hex: "#FFE9A0")))
            }
            // Beacon on the cab roof.
            let bc = CGPoint(x: cab.minX + cab.width * 0.3, y: cab.midY)
            let glow = W * (0.2 + 0.14 * CGFloat(beacon))
            g.fill(Path(ellipseIn: CGRect(x: bc.x - glow, y: bc.y - glow, width: glow * 2, height: glow * 2)), with: .color(Color(hex: "#F59B3D").opacity(0.25 + 0.2 * beacon)))
            g.fill(Path(ellipseIn: CGRect(x: bc.x - W * 0.1, y: bc.y - W * 0.1, width: W * 0.2, height: W * 0.2)), with: .color(Color(hex: "#F59B3D")))
            g.stroke(Path(ellipseIn: CGRect(x: bc.x - W * 0.1, y: bc.y - W * 0.1, width: W * 0.2, height: W * 0.2)), with: .color(dark), lineWidth: lineW)

        case .trolley:
            let shape = Path(roundedRect: bodyRect, cornerRadius: radius * 0.8)
            g.fill(shape, with: .color(body))
            g.stroke(shape, with: .color(dark), lineWidth: lineW)
            // Push handle at the back.
            var handle = Path()
            handle.move(to: CGPoint(x: bodyRect.minX + W * 0.1, y: bodyRect.minY + W * 0.08))
            handle.addLine(to: CGPoint(x: bodyRect.minX + W * 0.1, y: bodyRect.maxY - W * 0.08))
            g.stroke(handle, with: .color(dark), style: StrokeStyle(lineWidth: W * 0.09, lineCap: .round))
            // Stacked parcels.
            let boxes = max(2, Int((L / W).rounded()))
            let area = CGRect(x: bodyRect.minX + W * 0.28, y: bodyRect.minY + W * 0.1, width: bodyRect.width - W * 0.38, height: bodyRect.height - W * 0.2)
            let boxW = area.width / CGFloat(boxes)
            let boxColors = [Color(hex: "#B07E55"), Color(hex: "#C99A6E"), Color(hex: "#9A6B45")]
            for i in 0..<boxes {
                let rect = CGRect(x: area.minX + boxW * CGFloat(i) + boxW * 0.07, y: area.minY + (i % 2 == 0 ? 0 : area.height * 0.12),
                                  width: boxW * 0.86, height: area.height * (i % 2 == 0 ? 1 : 0.76))
                g.fill(Path(roundedRect: rect, cornerRadius: W * 0.06), with: .color(boxColors[i % 3]))
                g.stroke(Path(roundedRect: rect, cornerRadius: W * 0.06), with: .color(dark), lineWidth: lineW)
                var tape = Path()
                tape.move(to: CGPoint(x: rect.minX, y: rect.midY))
                tape.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                g.stroke(tape, with: .color(Color(hex: "#F1EBDD").opacity(0.8)), lineWidth: W * 0.06)
            }
        }

        if kind == .cart || kind == .trolley {
            g.stroke(Path(roundedRect: bodyRect, cornerRadius: radius), with: .color(outline), lineWidth: lineW)
        }
        if isTarget {
            g.stroke(Path(roundedRect: bodyRect.insetBy(dx: -1, dy: -1), cornerRadius: radius), with: .color(Color(hex: "#FFF3B8")), lineWidth: lineW * 1.6)
        }
    }
}

// MARK: - Board

@MainActor
struct ParkingBoardView: View {
    @ObservedObject var controller: ParkingController
    @ObservedObject private var settings: Settings
    @Environment(\.theme) private var theme

    @State private var selectedID: String?
    @State private var dragID: String?
    @State private var dragOffset: CGFloat = 0
    @State private var rolledOut = false
    @State private var departedGone = false
    @State private var showPuff = false
    @State private var bob = false

    init(controller: ParkingController) {
        self.controller = controller
        _settings = ObservedObject(wrappedValue: controller.context.settings)
    }

    private var rules: ParkingRules { controller.rules }
    private var state: ParkingState { controller.session.state }
    private let margin: CGFloat = 0.62

    var body: some View {
        GeometryReader { geo in
            let n = CGFloat(rules.size)
            let cell = max(8, min(geo.size.width, geo.size.height) / (n + 2 * margin))
            let side = cell * n
            ZStack(alignment: .topLeading) {
                floorView(cell: cell, side: side)
                ForEach(Array(rules.gates.enumerated()), id: \.offset) { _, gate in
                    gateView(gate, cell: cell, side: side)
                }
                if let ghost = highlightGhost(cell: cell) { ghost }
                ForEach(Array(rules.vehicles.enumerated()), id: \.offset) { index, vehicle in
                    vehicleView(index: index, vehicle: vehicle, cell: cell)
                }
                if let id = selectedID, !controller.isSolved, let index = rules.index(of: id) {
                    stopChips(index: index, cell: cell)
                }
                if showPuff { puffs(cell: cell, side: side) }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controller.accessibilitySummary)
        .onAppear {
            if controller.isSolved {
                rolledOut = true
                departedGone = true
            }
            if !settings.effectiveReduceMotion {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { bob = true }
            }
        }
        .onChange(of: controller.isSolved) { solved in
            if solved { depart() } else {
                rolledOut = false
                departedGone = false
                showPuff = false
            }
        }
    }

    // MARK: Floor and gates

    private func floorView(cell: CGFloat, side: CGFloat) -> some View {
        Canvas { ctx, _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            ctx.fill(Path(roundedRect: rect.insetBy(dx: -cell * 0.12, dy: -cell * 0.12), cornerRadius: cell * 0.3), with: .color(Color(light: "#8E8A7F", dark: "#20222E")))
            ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.18), with: .color(Color(light: "#E6E1D3", dark: "#3A3D4B")))
            let n = rules.size
            // Subtle checker so the grid reads without heavy lines.
            for r in 0..<n {
                for c in 0..<n where (r + c) % 2 == 0 {
                    let cellRect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                    ctx.fill(Path(cellRect), with: .color(Color.black.opacity(0.035)))
                }
            }
            // Painted lane lines for target lanes.
            let paint = Color(hex: settings.highContrast ? "#8A6A00" : "#F2C23C")
            for gate in rules.gates {
                var line = Path()
                if gate.edge == "left" || gate.edge == "right" {
                    let y = (CGFloat(gate.index) + 0.5) * cell
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: side, y: y))
                } else {
                    let x = (CGFloat(gate.index) + 0.5) * cell
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: side))
                }
                ctx.stroke(line, with: .color(paint.opacity(0.55)), style: StrokeStyle(lineWidth: cell * 0.06, lineCap: .round, dash: [cell * 0.22, cell * 0.2]))
            }
            // Painted border with corner ticks.
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: cell * 0.04, dy: cell * 0.04), cornerRadius: cell * 0.15), with: .color(paint.opacity(0.7)),
                       style: StrokeStyle(lineWidth: cell * 0.05, dash: [cell * 0.4, cell * 0.25]))
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture { selectedID = nil }
        .accessibilityHidden(true)
    }

    private func gateView(_ gate: ParkingGate, cell: CGFloat, side: CGFloat) -> some View {
        let w = cell * margin * 0.9
        let center: CGPoint
        let angle: Double
        let offsetCell = (CGFloat(gate.index) + 0.5) * cell
        switch gate.edge {
        case "right": center = CGPoint(x: side + w / 2 + cell * 0.04, y: offsetCell); angle = 0
        case "left": center = CGPoint(x: -w / 2 - cell * 0.04, y: offsetCell); angle = 180
        case "bottom": center = CGPoint(x: offsetCell, y: side + w / 2 + cell * 0.04); angle = 90
        default: center = CGPoint(x: offsetCell, y: -w / 2 - cell * 0.04); angle = 270
        }
        let open = rolledOut
        return GateArt(width: w, height: cell, open: open, highContrast: settings.highContrast, animation: settings.animation(0.3))
            .frame(width: w, height: cell)
            .rotationEffect(.degrees(angle))
            .position(center)
            .accessibilityElement()
            .accessibilityLabel("Gate, \(gate.edge) side, \(open ? "open" : "closed")")
    }

    // MARK: Vehicles

    private func color(for index: Int, vehicle: ParkingVehicle) -> Color {
        let hc = settings.highContrast
        let id = vehicle.isTarget ? "y" : vehiclePaletteIds[index % vehiclePaletteIds.count]
        if let c = controller.context.palette.color(id) { return c.color(highContrast: hc) }
        return vehicle.isTarget ? Color(hex: hc ? "#8A6A00" : "#F2B632") : Color.gray
    }

    private func gateEdge(of vehicle: ParkingVehicle) -> String? {
        rules.gates.first { $0.target == vehicle.id }?.edge
    }

    private func vehicleView(index: Int, vehicle: ParkingVehicle, cell: CGFloat) -> some View {
        let kind = ParkingVehicleKind.kind(for: vehicle, index: index)
        let pos = state.positions[index]
        let horizontal = vehicle.isHorizontal
        let w = (horizontal ? CGFloat(vehicle.len) : 1) * cell
        let h = (horizontal ? 1 : CGFloat(vehicle.len)) * cell
        let dragging = dragID == vehicle.id
        let drag = dragging ? dragOffset : 0
        let edge = gateEdge(of: vehicle)
        let exitSign: CGFloat = (edge == "left" || edge == "top") ? -1 : 1
        let exit: CGFloat = (vehicle.isTarget && rolledOut) ? exitSign * (CGFloat(vehicle.len) + 1.2) * cell : 0
        let x = horizontal ? CGFloat(pos) * cell + drag + exit : CGFloat(vehicle.c) * cell
        let y = horizontal ? CGFloat(vehicle.r) * cell : CGFloat(pos) * cell + drag + exit
        let flip = edge == "left" || edge == "top"
        let selected = selectedID == vehicle.id
        let highlight = controller.highlightedMove
        let hinted = highlight?.id == vehicle.id
        let fill = color(for: index, vehicle: vehicle)
        let outline = settings.highContrast ? Color.black : Color.black.opacity(0.35)
        let hc = settings.highContrast
        let animates = !settings.effectiveReduceMotion
        let tugBeacon = kind == .tug && animates

        return ZStack {
            if tugBeacon {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    vehicleCanvas(kind: kind, vehicle: vehicle, fill: fill, outline: outline, hc: hc, flip: flip,
                                  beacon: 0.5 + 0.5 * sin(t * 5), w: w, h: h)
                }
            } else {
                vehicleCanvas(kind: kind, vehicle: vehicle, fill: fill, outline: outline, hc: hc, flip: flip,
                              beacon: 0.6, w: w, h: h)
            }
            if vehicle.isTarget {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: cell * 0.36, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                    .accessibilityHidden(true)
            }
            if selected || hinted {
                RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                    .stroke(hinted ? theme.success : theme.accent, lineWidth: hinted ? 4 : 3)
                    .padding(cell * 0.05)
                    .opacity(hinted && !selected ? (bob ? 1 : 0.45) : 1)
            }
            if let move = highlight, hinted {
                Image(systemName: arrowName(for: move, vehicle: vehicle))
                    .font(.system(size: cell * 0.5, weight: .heavy))
                    .foregroundColor(theme.success)
                    .padding(6)
                    .background(Circle().fill(theme.surface.opacity(0.92)))
                    .offset(x: horizontal ? (bob && animates ? (move.delta > 0 ? 6 : -6) : 0) : 0,
                            y: horizontal ? 0 : (bob && animates ? (move.delta > 0 ? 6 : -6) : 0))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: w, height: h)
        .opacity(vehicle.isTarget && departedGone ? 0 : 1)
        .offset(x: x, y: y)
        .zIndex(dragging ? 3 : (selected ? 2 : (vehicle.isTarget ? 1 : 0)))
        .animation(settings.effectiveReduceMotion ? nil : .easeInOut(duration: settings.duration(0.2)), value: pos)
        .contentShape(Rectangle())
        .gesture(dragGesture(index: index, vehicle: vehicle, cell: cell))
        .onTapGesture { toggleSelection(vehicle: vehicle) }
        .allowsHitTesting(!controller.isSolved)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(index: index, vehicle: vehicle, kind: kind))
        .accessibilityValue(accessibilityValue(index: index, vehicle: vehicle))
        .accessibilityHint(horizontal ? "Swipe up to slide right, swipe down to slide left. Double tap to select." : "Swipe up to slide down, swipe down to slide up. Double tap to select.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggleSelection(vehicle: vehicle) }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: accessibleSlide(vehicle: vehicle, delta: 1)
            case .decrement: accessibleSlide(vehicle: vehicle, delta: -1)
            @unknown default: break
            }
        }
    }

    private func vehicleCanvas(kind: ParkingVehicleKind, vehicle: ParkingVehicle, fill: Color, outline: Color,
                               hc: Bool, flip: Bool, beacon: Double, w: CGFloat, h: CGFloat) -> some View {
        Canvas { ctx, size in
            var g = ctx
            let L: CGFloat
            let W: CGFloat
            if vehicle.isHorizontal {
                L = size.width
                W = size.height
            } else {
                g.translateBy(x: size.width, y: 0)
                g.rotate(by: .degrees(90))
                L = size.height
                W = size.width
            }
            if flip {
                g.translateBy(x: L, y: 0)
                g.scaleBy(x: -1, y: 1)
            }
            ParkingVehicleArt.draw(&g, kind: kind, length: L, width: W, body: fill, outline: outline,
                                   isTarget: vehicle.isTarget, highContrast: hc, beacon: beacon)
        }
        .frame(width: w, height: h)
    }

    private func arrowName(for move: ParkingMove, vehicle: ParkingVehicle) -> String {
        if vehicle.isHorizontal { return move.delta > 0 ? "arrow.right" : "arrow.left" }
        return move.delta > 0 ? "arrow.down" : "arrow.up"
    }

    // MARK: Interaction

    private func dragGesture(index: Int, vehicle: ParkingVehicle, cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !controller.isSolved else { return }
                let raw = vehicle.isHorizontal ? value.translation.width : value.translation.height
                let range = rules.slideRange(state, vehicle: index)
                let clamped = min(max(raw, CGFloat(range.min) * cell), CGFloat(range.max) * cell)
                if dragID != vehicle.id {
                    dragID = vehicle.id
                    selectedID = nil
                }
                dragOffset = clamped
            }
            .onEnded { _ in
                guard dragID == vehicle.id else { return }
                let delta = Int((dragOffset / cell).rounded())
                if delta != 0 {
                    let animation = settings.effectiveReduceMotion ? nil : Animation.easeInOut(duration: settings.duration(0.2))
                    withAnimation(animation) {
                        _ = controller.slide(id: vehicle.id, delta: delta)
                        dragID = nil
                        dragOffset = 0
                    }
                } else {
                    withAnimation(settings.animation(0.15)) {
                        dragID = nil
                        dragOffset = 0
                    }
                }
            }
    }

    private func stopChips(index: Int, cell: CGFloat) -> some View {
        let vehicle = rules.vehicles[index]
        let pos = state.positions[index]
        let range = rules.slideRange(state, vehicle: index)
        let deltas = range.min <= range.max ? Array(range.min...range.max).filter { $0 != 0 } : []
        return ZStack(alignment: .topLeading) {
            ForEach(deltas, id: \.self) { delta in
                // The chip marks the cell the leading edge of the vehicle will occupy after the slide.
                let lead = delta > 0 ? pos + vehicle.len - 1 + delta : pos + delta
                let cx = vehicle.isHorizontal ? CGFloat(lead) * cell : CGFloat(vehicle.c) * cell
                let cy = vehicle.isHorizontal ? CGFloat(vehicle.r) * cell : CGFloat(lead) * cell
                Button {
                    selectedID = nil
                    withAnimation(settings.animation(0.2)) { _ = controller.slide(id: vehicle.id, delta: delta) }
                } label: {
                    ZStack {
                        Circle().fill(theme.accent.opacity(0.9))
                        Image(systemName: chipArrow(vehicle: vehicle, delta: delta))
                            .font(.system(size: cell * 0.3, weight: .bold))
                            .foregroundColor(theme.accentText)
                    }
                    .frame(width: cell * 0.62, height: cell * 0.62)
                    .frame(width: max(cell, 44), height: max(cell, 44))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: cell, height: cell)
                .offset(x: cx, y: cy)
                .accessibilityLabel("Slide \(directionWord(vehicle: vehicle, delta: delta)) \(abs(delta)) \(abs(delta) == 1 ? "cell" : "cells")")
            }
        }
        .zIndex(5)
    }

    private func chipArrow(vehicle: ParkingVehicle, delta: Int) -> String {
        if vehicle.isHorizontal { return delta > 0 ? "chevron.right" : "chevron.left" }
        return delta > 0 ? "chevron.down" : "chevron.up"
    }

    private func directionWord(vehicle: ParkingVehicle, delta: Int) -> String {
        if vehicle.isHorizontal { return delta > 0 ? "right" : "left" }
        return delta > 0 ? "down" : "up"
    }

    private func toggleSelection(vehicle: ParkingVehicle) {
        guard !controller.isSolved else { return }
        controller.context.haptics.selection()
        selectedID = selectedID == vehicle.id ? nil : vehicle.id
    }

    private func accessibleSlide(vehicle: ParkingVehicle, delta: Int) {
        guard !controller.isSolved else { return }
        let word = directionWord(vehicle: vehicle, delta: delta)
        if controller.slide(id: vehicle.id, delta: delta) {
            let pos = controller.session.state.positions[rules.index(of: vehicle.id) ?? 0]
            let spot = vehicle.isHorizontal ? "column \(pos + 1)" : "row \(pos + 1)"
            UIAccessibility.post(notification: .announcement, argument: "Slid \(word), now starting at \(spot)")
        } else {
            UIAccessibility.post(notification: .announcement, argument: "Blocked, cannot slide \(word)")
        }
    }

    // MARK: Hint ghost

    private func highlightGhost(cell: CGFloat) -> AnyView? {
        guard let move = controller.highlightedMove, let index = rules.index(of: move.id), !controller.isSolved else { return nil }
        let vehicle = rules.vehicles[index]
        let target = state.positions[index] + move.delta
        let w = (vehicle.isHorizontal ? CGFloat(vehicle.len) : 1) * cell
        let h = (vehicle.isHorizontal ? 1 : CGFloat(vehicle.len)) * cell
        let x = vehicle.isHorizontal ? CGFloat(target) * cell : CGFloat(vehicle.c) * cell
        let y = vehicle.isHorizontal ? CGFloat(vehicle.r) * cell : CGFloat(target) * cell
        return AnyView(
            RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                .strokeBorder(theme.success.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                .background(RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous).fill(theme.success.opacity(0.12)))
                .frame(width: w - cell * 0.1, height: h - cell * 0.1)
                .offset(x: x + cell * 0.05, y: y + cell * 0.05)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }

    // MARK: Completion

    private func depart() {
        controller.context.haptics.selection()
        selectedID = nil
        if settings.effectiveReduceMotion {
            withAnimation(.easeOut(duration: 0.25)) {
                rolledOut = true
                departedGone = true
            }
            return
        }
        showPuff = true
        withAnimation(.easeIn(duration: settings.duration(0.6))) { rolledOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.duration(0.5)) {
            withAnimation(.easeOut(duration: settings.duration(0.2))) { departedGone = true }
        }
    }

    private func puffs(cell: CGFloat, side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(rules.gates.enumerated()), id: \.offset) { _, gate in
                let along = (CGFloat(gate.index) + 0.5) * cell
                let px: CGFloat = gate.edge == "right" ? side + cell * 0.25 : (gate.edge == "left" ? -cell * 0.25 : along)
                let py: CGFloat = gate.edge == "bottom" ? side + cell * 0.25 : (gate.edge == "top" ? -cell * 0.25 : along)
                PuffView(size: cell * 0.7, duration: settings.duration(0.7))
                    .position(x: px, y: py)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .zIndex(6)
    }

    // MARK: Accessibility text

    private func accessibilityLabel(index: Int, vehicle: ParkingVehicle, kind: ParkingVehicleKind) -> String {
        let capitalized = String(kind.displayName.prefix(1)).uppercased() + String(kind.displayName.dropFirst())
        let name = vehicle.isTarget ? "Golden \(kind.displayName), target" : capitalized
        return "\(name), length \(vehicle.len), \(vehicle.isHorizontal ? "horizontal" : "vertical")"
    }

    private func accessibilityValue(index: Int, vehicle: ParkingVehicle) -> String {
        let pos = state.positions[index]
        let range = rules.slideRange(state, vehicle: index)
        let place: String
        if vehicle.isHorizontal {
            place = "row \(vehicle.r + 1), columns \(pos + 1) to \(pos + vehicle.len)"
        } else {
            place = "column \(vehicle.c + 1), rows \(pos + 1) to \(pos + vehicle.len)"
        }
        let lowWord = vehicle.isHorizontal ? "left" : "up"
        let highWord = vehicle.isHorizontal ? "right" : "down"
        var room: [String] = []
        if range.min < 0 { room.append("\(-range.min) \(lowWord)") }
        if range.max > 0 { room.append("\(range.max) \(highWord)") }
        let free = room.isEmpty ? "blocked" : "room to slide " + room.joined(separator: ", ")
        return "\(place), \(free)"
    }
}

// MARK: - Gate and puff art

private struct GateArt: View {
    let width: CGFloat
    let height: CGFloat
    let open: Bool
    let highContrast: Bool
    let animation: Animation?

    var body: some View {
        let gold = Color(hex: highContrast ? "#8A6A00" : "#F2B632")
        ZStack(alignment: .top) {
            // Chevrons pointing out of the bay.
            Canvas { ctx, size in
                for i in 0..<2 {
                    var p = Path()
                    let x = size.width * (0.62 + 0.2 * CGFloat(i))
                    p.move(to: CGPoint(x: x - size.width * 0.1, y: size.height * 0.32))
                    p.addLine(to: CGPoint(x: x + size.width * 0.06, y: size.height * 0.5))
                    p.addLine(to: CGPoint(x: x - size.width * 0.1, y: size.height * 0.68))
                    ctx.stroke(p, with: .color(gold), style: StrokeStyle(lineWidth: size.height * 0.07, lineCap: .round, lineJoin: .round))
                }
            }
            // Barrier arm, hinged at its post; lifts away when the gate opens.
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                Canvas { ctx, size in
                    let stripe = size.height / 6
                    for i in 0..<6 where i % 2 == 0 {
                        ctx.fill(Path(CGRect(x: 0, y: CGFloat(i) * stripe, width: size.width, height: stripe)), with: .color(Color(hex: "#E5594F")))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(width: width * 0.2, height: height * 0.82)
            .scaleEffect(x: 1, y: open ? 0.14 : 1, anchor: .top)
            .animation(animation, value: open)
            .position(x: width * 0.28, y: height * 0.5)
            Circle()
                .fill(gold)
                .frame(width: width * 0.3, height: width * 0.3)
                .position(x: width * 0.28, y: height * 0.06)
        }
        .frame(width: width, height: height)
    }
}

private struct PuffView: View {
    let size: CGFloat
    let duration: TimeInterval
    @State private var expanded = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: size * (0.55 - 0.1 * CGFloat(i)), height: size * (0.55 - 0.1 * CGFloat(i)))
                    .offset(x: CGFloat(i - 1) * size * (expanded ? 0.55 : 0.1), y: CGFloat(i % 2 == 0 ? -1 : 1) * size * (expanded ? 0.3 : 0.05))
            }
        }
        .scaleEffect(expanded ? 1.5 : 0.5)
        .opacity(expanded ? 0 : 0.9)
        .onAppear {
            withAnimation(.easeOut(duration: max(0.2, duration))) { expanded = true }
        }
    }
}

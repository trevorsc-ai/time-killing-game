import SwiftUI

/// Canvas drawing for the Bolt ("Tool Bench") board: a wooden workbench, threaded steel bolts, hex nuts with washers,
/// end-stop caps for capped bolts, rust-speckled nuts with a tiny color tag, and nuts that lift off, glide and spin down
/// the target bolt.
enum BoltRenderer {
    // Geometry in units of the bolt width `u`.
    static let slotH: CGFloat = 0.43
    static let nutH: CGFloat = 0.33
    static let washerH: CGFloat = 0.05
    static let nutW: CGFloat = 0.80
    static let baseOffset: CGFloat = 0.40

    /// Y of the bottom edge of the nut body at stack index `idx` for a bolt drawn in `rect`.
    static func nutBottom(_ rect: CGRect, u: CGFloat, idx: Int) -> CGFloat {
        rect.maxY - baseOffset * u - CGFloat(idx) * slotH * u - washerH * u
    }

    static func rodTop(_ rect: CGRect, u: CGFloat, cap: Int, capped: Bool) -> CGFloat {
        rect.maxY - baseOffset * u - CGFloat(cap) * slotH * u - (capped ? 0.02 : 0.30) * u
    }

    // MARK: Entry point

    static func draw(_ context: GraphicsContext, size: CGSize, layout: SortLayout, frame: SortFrame) {
        guard layout.unit > 0, layout.rects.count == frame.state.tubes.count else { return }
        let u = layout.unit
        let n = layout.rects.count
        let baseCap = frame.caps.max() ?? 4

        drawBench(context, size: size, frame: frame)
        for row in layout.rows { drawRail(context, row: row, u: u, frame: frame) }

        let progress = frame.animProgress
        let anim: SortPourAnim? = progress != nil ? frame.anim : nil

        // Which nuts are away from their bolts or already landed (bolt animation is per nut).
        var started = 0
        var landed = 0
        if let a = anim {
            let t = frame.time - a.start
            for j in 0..<a.count {
                let tj = (t - Double(j) * a.stagger) / max(a.nutDuration, 0.001)
                if tj > 0 { started += 1 }
                if tj >= 1 { landed += 1 }
            }
        }

        var poses = layout.rects
        for i in 0..<n {
            let rect = layout.rects[i]
            let dx = frame.shakeX(i, unit: u)
            var c = context
            c.translateBy(x: dx, y: 0)
            let capped = frame.caps[i] < baseCap
            drawBolt(c, rect: rect, u: u, cap: frame.caps[i], capped: capped, frame: frame, selected: frame.lift(i), locked: !frame.state.locks[i].isEmpty)

            // Nuts currently resting on this bolt.
            let layers: [SortLayer]
            var extra: [(String, Int)] = []   // landed nuts: (color, index)
            if let a = anim {
                if i == a.from {
                    layers = Array(a.pre.tubes[i].dropLast(started))
                } else if i == a.to {
                    layers = a.pre.tubes[i]
                    for j in 0..<landed { extra.append((a.color, a.pre.tubes[i].count + j)) }
                } else {
                    layers = frame.state.tubes[i]
                }
            } else {
                layers = frame.state.tubes[i]
            }
            let runLen = frame.selected == i || frame.previousSelected == i ? frame.topRunLength[i] : 0
            let liftAmount = CGFloat(frame.lift(i)) * u * (capped ? 0.10 : 0.34)
            for (idx, layer) in layers.enumerated() {
                let inRun = runLen > 0 && idx >= layers.count - runLen
                let y = nutBottom(rect, u: u, idx: idx) - (inRun ? liftAmount : 0)
                drawNut(c, cx: rect.midX, bottom: y, u: u, layer: layer, frame: frame, spin: 0)
            }
            for (color, idx) in extra {
                drawNut(c, cx: rect.midX, bottom: nutBottom(rect, u: u, idx: idx), u: u, layer: SortLayer(color), frame: frame, spin: 0)
            }
            if frame.complete[i] && anim?.to != i {
                let top = rodTop(rect, u: u, cap: frame.caps[i], capped: capped)
                let glow = CGRect(x: rect.minX - u * 0.02, y: top - u * 0.05, width: u * 1.04, height: rect.maxY - top + u * 0.03)
                c.stroke(SortFx.rounded(glow, u * 0.2), with: .color(frame.successColor.opacity(0.85)), lineWidth: 2)
            }
            poses[i] = rect.offsetBy(dx: dx, dy: 0)
        }

        // Lock tags.
        for i in 0..<n {
            let r = layout.rects[i]
            let top = rodTop(r, u: u, cap: frame.caps[i], capped: frame.caps[i] < baseCap)
            if !frame.state.locks[i].isEmpty {
                SortFx.lockTag(context, center: CGPoint(x: r.midX, y: top - u * 0.28), unit: u, frame: frame, color: frame.state.locks[i], alpha: 1, lift: 0)
            } else if let ev = frame.unlocks[i], !frame.reduceMotion {
                let t = (frame.time - ev.start) / 0.6
                if t >= 0 && t < 1 {
                    SortFx.lockTag(context, center: CGPoint(x: r.midX, y: top - u * 0.28), unit: u, frame: frame, color: ev.color,
                                   alpha: 1 - t, lift: CGFloat(SortMath.easeOut(t)) * u * 0.6)
                }
            }
        }

        // Flying nuts.
        if let a = anim {
            let src = layout.rects[a.from]
            let dst = layout.rects[a.to]
            let srcCapped = frame.caps[a.from] < baseCap
            let dstCapped = frame.caps[a.to] < baseCap
            let hover = min(rodTop(src, u: u, cap: frame.caps[a.from], capped: srcCapped),
                            rodTop(dst, u: u, cap: frame.caps[a.to], capped: dstCapped)) - u * 0.55
            let t = frame.time - a.start
            for j in 0..<a.count {
                let tj = (t - Double(j) * a.stagger) / max(a.nutDuration, 0.001)
                if tj <= 0 || tj >= 1 { continue }
                let srcIdx = a.pre.tubes[a.from].count - 1 - j
                let dstIdx = a.pre.tubes[a.to].count + j
                let y0 = nutBottom(src, u: u, idx: srcIdx)
                let y1 = nutBottom(dst, u: u, idx: dstIdx)
                var x = src.midX
                var y = y0
                var spin = 0.0
                if tj < 0.28 {
                    let e = SortMath.smooth(tj / 0.28)
                    y = SortMath.lerp(y0, hover, e)
                    spin = e * 2 * Double.pi
                } else if tj < 0.62 {
                    let e = SortMath.smooth((tj - 0.28) / 0.34)
                    x = SortMath.lerp(src.midX, dst.midX, e)
                    y = hover - CGFloat(sin(Double.pi * e)) * u * 0.12
                    spin = 2 * Double.pi
                } else {
                    let e = SortMath.smooth((tj - 0.62) / 0.38)
                    x = dst.midX
                    y = SortMath.lerp(hover, y1, e)
                    spin = 2 * Double.pi + e * 4 * Double.pi
                }
                // the washer rides along under the nut
                let layer = a.pre.tubes[a.from][srcIdx]
                drawNut(context, cx: x, bottom: y, u: u, layer: layer, frame: frame, spin: spin)
                poses[a.to] = dst
            }
        }

        SortFx.overlays(context, layout: layout, frame: frame) { poses[$0] }
    }

    // MARK: Bench

    static func drawBench(_ ctx: GraphicsContext, size: CGSize, frame: SortFrame) {
        let rect = CGRect(origin: .zero, size: size)
        let lightA = frame.isDark ? SortRGB(hex: "#6A4E36") : SortRGB(hex: "#D7AA73")
        let lightB = frame.isDark ? SortRGB(hex: "#4F3A28") : SortRGB(hex: "#BC8650")
        ctx.fill(SortFx.rounded(rect, 22), with: .linearGradient(
            Gradient(colors: [lightA.color, lightB.color]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        var c = ctx
        c.clip(to: SortFx.rounded(rect, 22))
        let plankH = max(48, size.height / 5)
        var y: CGFloat = 0
        var idx = 0
        while y < size.height {
            let tint = SortMath.hash(idx, 7)
            c.fill(Path(CGRect(x: 0, y: y, width: size.width, height: plankH)),
                   with: .color((tint > 0.5 ? Color.white : Color.black).opacity(0.04 + 0.04 * tint)))
            c.fill(Path(CGRect(x: 0, y: y + plankH - 2, width: size.width, height: 2)), with: .color(Color.black.opacity(0.22)))
            c.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color.white.opacity(0.14)))
            // grain
            for g in 0..<5 {
                var line = Path()
                let gy = y + plankH * (0.15 + 0.17 * CGFloat(g)) + CGFloat(SortMath.hash(idx, g + 20)) * 6
                let sx = CGFloat(SortMath.hash(idx, g + 40)) * size.width * 0.4
                line.move(to: CGPoint(x: sx, y: gy))
                line.addCurve(to: CGPoint(x: sx + size.width * 0.5, y: gy + 3),
                              control1: CGPoint(x: sx + size.width * 0.15, y: gy - 3),
                              control2: CGPoint(x: sx + size.width * 0.3, y: gy + 5))
                c.stroke(line, with: .color(Color.black.opacity(0.07)), lineWidth: 1)
            }
            // a couple of screws at the plank ends
            for sx in [CGFloat(14), size.width - 14] {
                c.fill(SortFx.ellipse(CGPoint(x: sx, y: y + plankH / 2), 7, 7), with: .color(Color.black.opacity(0.28)))
                c.fill(SortFx.ellipse(CGPoint(x: sx - 0.5, y: y + plankH / 2 - 0.5), 5, 5), with: .color(Color(.sRGB, red: 0.7, green: 0.72, blue: 0.75, opacity: 0.9)))
            }
            y += plankH
            idx += 1
        }
    }

    static func drawRail(_ ctx: GraphicsContext, row: (baseline: CGFloat, minX: CGFloat, maxX: CGFloat), u: CGFloat, frame: SortFrame) {
        let rect = CGRect(x: row.minX - u * 0.3, y: row.baseline - u * 0.22, width: row.maxX - row.minX + u * 0.6, height: u * 0.30)
        let top = SortRGB(hex: "#7E8996")
        let bottom = SortRGB(hex: "#4C5561")
        ctx.fill(SortFx.rounded(rect.offsetBy(dx: 0, dy: 3), u * 0.08), with: .color(Color.black.opacity(0.22)))
        ctx.fill(SortFx.rounded(rect, u * 0.08), with: .linearGradient(
            Gradient(colors: [top.lighter(0.2).color, top.color, bottom.color]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        ctx.fill(Path(CGRect(x: rect.minX + u * 0.1, y: rect.minY + 1.5, width: rect.width - u * 0.2, height: 1.5)), with: .color(Color.white.opacity(0.4)))
    }

    // MARK: Bolt

    static func drawBolt(_ ctx: GraphicsContext, rect: CGRect, u: CGFloat, cap: Int, capped: Bool, frame: SortFrame, selected: Double, locked: Bool) {
        let cx = rect.midX
        let top = rodTop(rect, u: u, cap: cap, capped: capped)
        let baseY = rect.maxY - baseOffset * u + u * 0.12
        let rw = u * 0.20
        let steel = SortRGB(hex: "#9AA6B4")

        // soft glow when selected
        if selected > 0.01 {
            let col = CGRect(x: rect.minX, y: top - u * 0.25, width: u, height: rect.maxY - top + u * 0.15)
            SortFx.ring(ctx, rect: col, color: frame.accentColor, alpha: 0.75 * selected, width: 2.5, radius: u * 0.25)
        }
        // mounting plate
        let plate = CGRect(x: cx - u * 0.50, y: rect.maxY - baseOffset * u + u * 0.02, width: u, height: u * 0.20)
        ctx.fill(SortFx.rounded(plate.offsetBy(dx: 0, dy: 2), u * 0.07), with: .color(Color.black.opacity(0.22)))
        ctx.fill(SortFx.rounded(plate, u * 0.07), with: .linearGradient(
            Gradient(colors: [SortRGB(hex: "#B7C0CB").color, SortRGB(hex: "#6E7886").color]),
            startPoint: CGPoint(x: plate.midX, y: plate.minY), endPoint: CGPoint(x: plate.midX, y: plate.maxY)))
        for sx in [plate.minX + u * 0.1, plate.maxX - u * 0.1] {
            ctx.fill(SortFx.ellipse(CGPoint(x: sx, y: plate.midY), u * 0.09, u * 0.09), with: .color(Color.black.opacity(0.35)))
        }
        // rod
        let rod = CGRect(x: cx - rw / 2, y: top, width: rw, height: baseY - top)
        ctx.fill(SortFx.rounded(rod, rw * 0.35), with: .linearGradient(
            Gradient(stops: [
                .init(color: steel.darker(0.25).color, location: 0),
                .init(color: steel.lighter(0.55).color, location: 0.35),
                .init(color: steel.color, location: 0.62),
                .init(color: steel.darker(0.35).color, location: 1),
            ]),
            startPoint: CGPoint(x: rod.minX, y: 0), endPoint: CGPoint(x: rod.maxX, y: 0)))
        // thread
        var c = ctx
        c.clip(to: SortFx.rounded(rod, rw * 0.35))
        var y = top + u * 0.04
        var thread = Path()
        while y < baseY {
            thread.move(to: CGPoint(x: rod.minX - 1, y: y + u * 0.05))
            thread.addLine(to: CGPoint(x: rod.maxX + 1, y: y - u * 0.02))
            y += u * 0.085
        }
        c.stroke(thread, with: .color(Color.black.opacity(0.30)), lineWidth: max(1, u * 0.018))
        // rod tip
        ctx.fill(SortFx.ellipse(CGPoint(x: cx, y: top + 1), rw * 0.95, rw * 0.45), with: .color(steel.lighter(0.5).color))
        // end-stop cap for capped bolts
        if capped {
            let capRect = CGRect(x: cx - u * 0.26, y: top - u * 0.20, width: u * 0.52, height: u * 0.22)
            let orange = SortRGB(hex: "#E96A3C")
            ctx.fill(SortFx.rounded(capRect.offsetBy(dx: 0, dy: 2), u * 0.07), with: .color(Color.black.opacity(0.22)))
            ctx.fill(SortFx.rounded(capRect, u * 0.07), with: .linearGradient(
                Gradient(colors: [orange.lighter(0.25).color, orange.darker(0.12).color]),
                startPoint: CGPoint(x: capRect.midX, y: capRect.minY), endPoint: CGPoint(x: capRect.midX, y: capRect.maxY)))
            var stripes = ctx
            stripes.clip(to: SortFx.rounded(capRect, u * 0.07))
            var sp = Path()
            var sx = capRect.minX - u * 0.1
            while sx < capRect.maxX {
                sp.move(to: CGPoint(x: sx, y: capRect.maxY))
                sp.addLine(to: CGPoint(x: sx + u * 0.12, y: capRect.minY))
                sx += u * 0.16
            }
            stripes.stroke(sp, with: .color(Color.white.opacity(0.55)), lineWidth: max(2, u * 0.05))
            ctx.stroke(SortFx.rounded(capRect, u * 0.07), with: .color(Color.black.opacity(0.35)), lineWidth: 1)
        }
        if locked {
            ctx.fill(SortFx.rounded(CGRect(x: rect.minX, y: top - u * 0.1, width: u, height: rect.maxY - top), u * 0.2), with: .color(Color.black.opacity(0.18)))
        }
    }

    // MARK: Nut

    private static let rustDark = SortRGB(hex: "#7A3F1B")
    private static let rustLight = SortRGB(hex: "#C57934")

    /// Draws a hex nut (side view) with its washer. `bottom` is the y of the nut body's bottom edge. `spin` rotates the
    /// hex prism about the rod (radians) so its facets slide sideways.
    static func drawNut(_ ctx: GraphicsContext, cx: CGFloat, bottom: CGFloat, u: CGFloat, layer: SortLayer, frame: SortFrame, spin: Double) {
        let nw = nutW * u
        let nh = nutH * u
        let body = CGRect(x: cx - nw / 2, y: bottom - nh, width: nw, height: nh)
        let base = layer.hidden ? SortRGB(hex: "#9AA3AF") : frame.rgb(layer.c)

        // washer
        let ww = nw * 1.12
        let washer = CGRect(x: cx - ww / 2, y: bottom, width: ww, height: washerH * u)
        ctx.fill(SortFx.rounded(washer, u * 0.02), with: .linearGradient(
            Gradient(colors: [SortRGB(hex: "#D4DAE2").color, SortRGB(hex: "#7B8693").color]),
            startPoint: CGPoint(x: washer.midX, y: washer.minY), endPoint: CGPoint(x: washer.midX, y: washer.maxY)))

        // facets
        var c = ctx
        let clipShape = SortFx.rounded(body, u * 0.07)
        c.clip(to: clipShape)
        c.fill(Path(body), with: .color(base.darker(0.2).color))
        let r = Double(nw) / 2
        for m in 0..<6 {
            let a0 = (30.0 + 60.0 * Double(m)) * Double.pi / 180 + spin
            let a1 = a0 + Double.pi / 3
            let normal = a0 + Double.pi / 6
            let shade = cos(normal)
            if shade <= 0 { continue }
            let x0 = CGFloat(r * sin(a0))
            let x1 = CGFloat(r * sin(a1))
            let face = CGRect(x: cx + min(x0, x1), y: body.minY, width: abs(x1 - x0), height: nh)
            let f = base.mixed(with: SortRGB(r: 0, g: 0, b: 0), (1 - shade) * 0.38).lighter(shade > 0.85 ? 0.10 : 0)
            c.fill(Path(face), with: .linearGradient(
                Gradient(colors: [f.lighter(0.16).color, f.darker(0.12).color]),
                startPoint: CGPoint(x: face.midX, y: face.minY), endPoint: CGPoint(x: face.midX, y: face.maxY)))
            c.fill(Path(CGRect(x: face.minX, y: face.minY, width: 1, height: nh)), with: .color(Color.black.opacity(0.22)))
        }
        // chamfer highlights
        c.fill(Path(CGRect(x: body.minX, y: body.minY, width: nw, height: max(1.5, u * 0.035))), with: .color(Color.white.opacity(0.40)))
        c.fill(Path(CGRect(x: body.minX, y: body.maxY - max(1.5, u * 0.03), width: nw, height: max(1.5, u * 0.03))), with: .color(Color.black.opacity(0.22)))

        // rust speckles
        if !layer.rust.isEmpty {
            c.fill(Path(body), with: .color(rustDark.alpha(0.28)))
            let seed = Int(layer.rust.unicodeScalars.first?.value ?? 1) &* 31 &+ Int(layer.c.unicodeScalars.first?.value ?? 1)
            for k in 0..<16 {
                let px = body.minX + CGFloat(SortMath.hash(seed, k)) * nw
                let py = body.minY + CGFloat(SortMath.hash(seed, k + 50)) * nh
                let pr = u * CGFloat(0.015 + 0.03 * SortMath.hash(seed, k + 90))
                c.fill(SortFx.ellipse(CGPoint(x: px, y: py), pr * 2, pr * 1.6), with: .color((k % 3 == 0 ? rustLight : rustDark).alpha(0.8)))
            }
        }
        // symbol or "?"
        if layer.hidden {
            SortFx.text(c, "?", at: CGPoint(x: cx, y: body.midY), size: nh * 0.8, color: Color.white.opacity(0.9))
        } else if frame.showPatterns, let sym = frame.symbol(layer.c) {
            let s = nh * 0.62
            SortFx.symbol(c, name: sym, in: CGRect(x: cx - s / 2, y: body.midY - s / 2, width: s, height: s), color: SortFx.contrast(base))
        }
        ctx.stroke(clipShape, with: .color(base.darker(0.45).alpha(0.7)), lineWidth: 1)

        // rust tag: color of the nut that must be completed first
        if !layer.rust.isEmpty {
            let tagR = u * 0.115
            let center = CGPoint(x: body.maxX - tagR * 0.9, y: body.maxY - tagR * 0.5)
            let tagColor = frame.rgb(layer.rust)
            ctx.fill(SortFx.ellipse(CGPoint(x: center.x, y: center.y + 1.5), tagR * 2.1, tagR * 2.1), with: .color(Color.black.opacity(0.25)))
            ctx.fill(SortFx.ellipse(center, tagR * 2, tagR * 2), with: .color(tagColor.color))
            ctx.stroke(SortFx.ellipse(center, tagR * 2, tagR * 2), with: .color(Color.white.opacity(0.9)), lineWidth: 1.3)
            if frame.showPatterns, let sym = frame.symbol(layer.rust) {
                let s = tagR * 1.25
                SortFx.symbol(ctx, name: sym, in: CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s), color: SortFx.contrast(tagColor))
            }
        }
    }
}

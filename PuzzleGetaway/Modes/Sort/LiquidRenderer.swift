import SwiftUI

/// Canvas drawing for the Liquid ("Color Mixer") board: glass tubes on a snack-cart counter, painterly layered liquid
/// with a gentle meniscus, tilt-and-pour animation with a liquid stream, frosted "?" layers, padlock tags and sparkles.
enum LiquidRenderer {
    struct Band {
        var c: String
        var hidden: Bool
        var h: Double
    }

    // MARK: Entry point

    static func draw(_ context: GraphicsContext, size: CGSize, layout: SortLayout, frame: SortFrame) {
        guard layout.unit > 0, layout.rects.count == frame.state.tubes.count else { return }
        let u = layout.unit
        let n = layout.rects.count

        for row in layout.rows { drawShelf(context, row: row, u: u, frame: frame) }

        let progress = frame.animProgress
        let anim: SortPourAnim? = progress != nil ? frame.anim : nil
        let p = progress ?? 1

        for i in 0..<n {
            let lift = frame.lift(i)
            drawShadow(context, rect: layout.rects[i], u: u, lift: lift)
        }

        var poses = layout.rects
        for i in 0..<n where i != anim?.from {
            let base = layout.rects[i]
            let lift = frame.lift(i)
            let dx = frame.shakeX(i, unit: u)
            let dy = -CGFloat(lift) * u * 0.42
            var c = context
            c.translateBy(x: base.midX + dx, y: base.minY + dy)
            let local = CGRect(x: -u / 2, y: 0, width: u, height: base.height)
            let bands = bandsFor(i, frame: frame, anim: anim, p: p)
            let locked = !frame.state.locks[i].isEmpty
            let complete = frame.complete[i] && anim?.to != i
            drawTube(c, frame: frame, rect: local, bands: bands, cap: frame.caps[i], tilt: 0, locked: locked, complete: complete)
            poses[i] = base.offsetBy(dx: dx, dy: dy)
        }

        // Padlock tags (and the little pop when one opens).
        for i in 0..<n {
            let r = layout.rects[i]
            if !frame.state.locks[i].isEmpty {
                SortFx.lockTag(context, center: CGPoint(x: r.midX + frame.shakeX(i, unit: u), y: r.minY - u * 0.30), unit: u,
                               frame: frame, color: frame.state.locks[i], alpha: 1, lift: 0)
            } else if let ev = frame.unlocks[i], !frame.reduceMotion {
                let t = (frame.time - ev.start) / 0.6
                if t >= 0 && t < 1 {
                    SortFx.lockTag(context, center: CGPoint(x: r.midX, y: r.minY - u * 0.30), unit: u, frame: frame,
                                   color: ev.color, alpha: 1 - t, lift: CGFloat(SortMath.easeOut(t)) * u * 0.6)
                }
            }
        }

        if let a = anim {
            drawPour(context, layout: layout, frame: frame, anim: a, p: p, poses: &poses)
        }

        SortFx.overlays(context, layout: layout, frame: frame) { poses[$0] }
    }

    // MARK: Bands

    static func bandsFor(_ i: Int, frame: SortFrame, anim: SortPourAnim?, p: Double) -> [Band] {
        if let a = anim, i == a.to {
            var bands = a.pre.tubes[i].map { Band(c: $0.c, hidden: $0.hidden, h: 1) }
            let fe = SortMath.smooth((p - 0.30) / 0.50)
            for _ in 0..<a.count { bands.append(Band(c: a.color, hidden: false, h: fe)) }
            return bands
        }
        return frame.state.tubes[i].map { Band(c: $0.c, hidden: $0.hidden, h: 1) }
    }

    // MARK: Pour

    private static func drawPour(_ context: GraphicsContext, layout: SortLayout, frame: SortFrame, anim a: SortPourAnim,
                                 p: Double, poses: inout [CGRect]) {
        let u = layout.unit
        let src = layout.rects[a.from]
        let dst = layout.rects[a.to]
        let dir: CGFloat = dst.midX >= src.midX ? 1 : -1
        let enter = SortMath.smooth(p / 0.30)
        let leave = SortMath.smooth((p - 0.80) / 0.20)
        let w = enter * (1 - leave)
        let f = SortMath.clamp((p - 0.30) / 0.50)
        let fe = SortMath.smooth(f)
        let thetaPour = 0.72 + 0.50 * fe
        let theta = thetaPour * w

        let restStart = CGPoint(x: src.midX, y: src.minY - u * 0.42)
        let restEnd = CGPoint(x: src.midX, y: src.minY)
        let pourMouth = CGPoint(x: dst.midX - dir * (u / 2) * CGFloat(cos(thetaPour)),
                                y: dst.minY - u * 0.55 - (u / 2) * CGFloat(sin(thetaPour)))
        let hump = CGFloat(sin(Double.pi * w)) * u * 0.30
        let bx = SortMath.lerp(restStart.x, pourMouth.x, enter)
        let by = SortMath.lerp(restStart.y, pourMouth.y, enter) - hump
        let mouth = CGPoint(x: SortMath.lerp(bx, restEnd.x, leave), y: SortMath.lerp(by, restEnd.y, leave))

        // Source bands: remaining layers plus the poured run draining away.
        let pre = a.pre.tubes[a.from]
        let keepCount = pre.count - a.count
        let baseLayers: [SortLayer] = p >= 0.85 ? a.post.tubes[a.from] : Array(pre[0..<keepCount])
        var bands = baseLayers.map { Band(c: $0.c, hidden: $0.hidden, h: 1) }
        for k in keepCount..<pre.count {
            bands.append(Band(c: pre[k].c, hidden: pre[k].hidden, h: 1 - fe))
        }
        var c = context
        c.translateBy(x: mouth.x, y: mouth.y)
        let tilt = Double(dir) * theta
        c.rotate(by: .radians(tilt))
        let local = CGRect(x: -u / 2, y: 0, width: u, height: src.height)
        drawTube(c, frame: frame, rect: local, bands: bands, cap: frame.caps[a.from], tilt: tilt, locked: false, complete: false)
        poses[a.from] = CGRect(x: mouth.x - u / 2, y: mouth.y, width: u, height: src.height)

        // Stream from the lip into the target.
        if f > 0.001 && f < 0.999 {
            let lip = CGPoint(x: mouth.x + dir * (u / 2) * CGFloat(cos(theta)), y: mouth.y + (u / 2) * CGFloat(sin(theta)))
            let dstBands = bandsFor(a.to, frame: frame, anim: a, p: p)
            let wall = u * 0.07
            let layerH = (dst.height - wall - u * 0.14) / CGFloat(max(frame.caps[a.to], 1))
            let fill = dstBands.reduce(CGFloat(0)) { $0 + CGFloat($1.h) } * layerH
            let endY = dst.maxY - wall - fill
            let grow = SortMath.clamp(f / 0.12)
            let retract = SortMath.clamp((f - 0.88) / 0.12)
            let topY = lip.y + (endY - lip.y) * CGFloat(retract)
            let botY = lip.y + (endY - lip.y) * CGFloat(grow)
            if botY > topY + 1 {
                let sx = SortMath.lerp(lip.x, dst.midX, 0.65)
                let sw = u * CGFloat(0.15 - 0.04 * f)
                let rgb = frame.rgb(a.color)
                let r = CGRect(x: sx - sw / 2, y: topY, width: sw, height: botY - topY)
                context.fill(SortFx.rounded(r, sw / 2), with: .linearGradient(
                    Gradient(colors: [rgb.darker(0.12).color, rgb.lighter(0.25).color, rgb.darker(0.08).color]),
                    startPoint: CGPoint(x: r.minX, y: r.midY), endPoint: CGPoint(x: r.maxX, y: r.midY)))
                if grow > 0.95 && retract < 0.95 {
                    let ripple = 1 + 0.25 * sin(frame.time * 18)
                    context.fill(SortFx.ellipse(CGPoint(x: sx, y: endY), sw * 3.4 * CGFloat(ripple), sw * 1.0),
                                 with: .color(rgb.lighter(0.3).alpha(0.8)))
                }
            }
        }
    }

    // MARK: Pieces

    static func drawShelf(_ ctx: GraphicsContext, row: (baseline: CGFloat, minX: CGFloat, maxX: CGFloat), u: CGFloat, frame: SortFrame) {
        let rect = CGRect(x: row.minX - u * 0.35, y: row.baseline - u * 0.10, width: row.maxX - row.minX + u * 0.7, height: u * 0.34)
        let top = frame.isDark ? SortRGB(hex: "#7A6048") : SortRGB(hex: "#EFD9B8")
        let bottom = frame.isDark ? SortRGB(hex: "#4E3C2C") : SortRGB(hex: "#CFA67A")
        ctx.fill(SortFx.rounded(rect.offsetBy(dx: 0, dy: 3), u * 0.12), with: .color(Color.black.opacity(0.12)))
        ctx.fill(SortFx.rounded(rect, u * 0.12), with: .linearGradient(
            Gradient(colors: [top.color, bottom.color]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        ctx.fill(SortFx.rounded(CGRect(x: rect.minX + u * 0.06, y: rect.minY + 1, width: rect.width - u * 0.12, height: u * 0.07), u * 0.035),
                 with: .color(Color.white.opacity(0.35)))
    }

    static func drawShadow(_ ctx: GraphicsContext, rect: CGRect, u: CGFloat, lift: Double) {
        let alpha = 0.16 * (1 - 0.5 * lift)
        ctx.fill(SortFx.ellipse(CGPoint(x: rect.midX, y: rect.maxY - u * 0.01), u * 1.05, u * 0.20), with: .color(Color.black.opacity(alpha)))
    }

    private static func lowerHalfEllipse(cx: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> Path {
        let rx = w / 2
        let ry = h / 2
        let k: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: cx - rx, y: y))
        p.addCurve(to: CGPoint(x: cx, y: y + ry), control1: CGPoint(x: cx - rx, y: y + k * ry), control2: CGPoint(x: cx - k * rx, y: y + ry))
        p.addCurve(to: CGPoint(x: cx + rx, y: y), control1: CGPoint(x: cx + k * rx, y: y + ry), control2: CGPoint(x: cx + rx, y: y + k * ry))
        p.closeSubpath()
        return p
    }

    private static let frosted = SortRGB(hex: "#C9D2DE")

    /// Draws one tube in its local coordinates (origin = mouth center is NOT assumed: `rect` is the body rectangle).
    /// `tilt` is the tube's rotation in radians; the liquid surface is kept horizontal in the world.
    static func drawTube(_ ctx: GraphicsContext, frame: SortFrame, rect: CGRect, bands: [Band], cap: Int, tilt: Double,
                         locked: Bool, complete: Bool) {
        let w = rect.width
        let wall = w * 0.07
        let outer = SortFx.tubePath(rect)
        ctx.fill(outer, with: .color(frame.isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.45)))

        let innerRect = CGRect(x: rect.minX + wall, y: rect.minY, width: w - 2 * wall, height: rect.height - wall)
        let innerPath = SortFx.tubePath(innerRect)
        let layerH = (innerRect.height - w * 0.14) / CGFloat(max(cap, 1))
        let iw = innerRect.width
        let totalH = bands.reduce(CGFloat(0)) { $0 + CGFloat($1.h) } * layerH
        let surfaceY = innerRect.maxY - totalH

        var lc = ctx
        lc.clip(to: innerPath)

        if !bands.isEmpty {
            var fc = lc
            fc.translateBy(x: rect.midX, y: surfaceY)
            fc.rotate(by: .radians(-tilt))
            let cosT = max(0.35, CGFloat(cos(tilt)))
            let ew = iw / cosT
            let eh = iw * 0.17
            let big = w * 6

            // Band extents from the top surface downward.
            var tops = [CGFloat](repeating: 0, count: bands.count)
            var bottoms = [CGFloat](repeating: 0, count: bands.count)
            var depth: CGFloat = 0
            for idx in stride(from: bands.count - 1, through: 0, by: -1) {
                let bh = CGFloat(bands[idx].h) * layerH
                tops[idx] = depth
                bottoms[idx] = depth + bh
                depth += bh
            }
            for idx in 0..<bands.count {
                let band = bands[idx]
                let bh = bottoms[idx] - tops[idx]
                if bh <= 0.05 { continue }
                let rgb = band.hidden ? frosted : frame.rgb(band.c)
                let bottomExtent = idx == 0 ? tops[idx] + big : bottoms[idx]
                let r = CGRect(x: -big, y: tops[idx], width: big * 2, height: bottomExtent - tops[idx])
                let shade = Gradient(colors: [rgb.lighter(0.10).color, rgb.darker(0.10).color])
                let shading = GraphicsContext.Shading.linearGradient(shade, startPoint: CGPoint(x: 0, y: tops[idx]),
                                                                    endPoint: CGPoint(x: 0, y: tops[idx] + max(bh, 1)))
                fc.fill(Path(r), with: shading)
                if idx > 0 {
                    // Curved lower edge of this layer overlapping the one below it.
                    let arc = lowerHalfEllipse(cx: 0, y: bottoms[idx], w: ew, h: eh)
                    fc.fill(arc, with: .color(rgb.darker(0.06).color))
                    fc.stroke(arc, with: .color(rgb.darker(0.35).alpha(0.45)), lineWidth: 1)
                }
            }
            // Top surface sheen (meniscus).
            if let topIdx = bands.indices.last(where: { bands[$0].h > 0.02 }) {
                let band = bands[topIdx]
                let rgb = band.hidden ? frosted : frame.rgb(band.c)
                let y = tops[topIdx]
                fc.fill(SortFx.ellipse(CGPoint(x: 0, y: y), ew, eh), with: .color(rgb.lighter(0.28).color))
                fc.fill(SortFx.ellipse(CGPoint(x: -ew * 0.12, y: y - eh * 0.08), ew * 0.55, eh * 0.45), with: .color(Color.white.opacity(0.28)))
                fc.stroke(SortFx.ellipse(CGPoint(x: 0, y: y), ew, eh), with: .color(rgb.darker(0.25).alpha(0.35)), lineWidth: 1)
            }
            // Symbols / hidden marks.
            for idx in 0..<bands.count {
                let band = bands[idx]
                let bh = bottoms[idx] - tops[idx]
                if band.h < 0.6 || bh < 4 { continue }
                let center = CGPoint(x: 0, y: tops[idx] + bh / 2 + (idx > 0 ? eh * 0.12 : 0))
                let size = min(iw * 0.5, bh * 0.62)
                if band.hidden {
                    SortFx.text(fc, "?", at: center, size: size * 1.25, color: Color(.sRGB, red: 0.30, green: 0.36, blue: 0.46, opacity: 0.85))
                    // a few frost scratches
                    for s in 0..<3 {
                        var line = Path()
                        let ox = iw * (CGFloat(s) * 0.26 - 0.3)
                        line.move(to: CGPoint(x: ox, y: center.y - bh * 0.35))
                        line.addLine(to: CGPoint(x: ox + iw * 0.12, y: center.y - bh * 0.05))
                        fc.stroke(line, with: .color(Color.white.opacity(0.45)), lineWidth: 1.2)
                    }
                } else if frame.showPatterns, let sym = frame.symbol(band.c) {
                    let rgb = frame.rgb(band.c)
                    SortFx.symbol(fc, name: sym, in: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                                  color: SortFx.contrast(rgb))
                }
            }
        }

        // Glass lighting on top of the liquid.
        lc.fill(Path(innerRect), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color.black.opacity(0.18), location: 0),
                .init(color: Color.black.opacity(0), location: 0.22),
                .init(color: Color.white.opacity(0.10), location: 0.34),
                .init(color: Color.clear, location: 0.60),
                .init(color: Color.black.opacity(0.14), location: 1),
            ]),
            startPoint: CGPoint(x: innerRect.minX, y: 0), endPoint: CGPoint(x: innerRect.maxX, y: 0)))

        if locked {
            ctx.fill(outer, with: .color(Color.black.opacity(0.22)))
        }
        let lineW: CGFloat = frame.highContrast ? 2.6 : 1.6
        ctx.stroke(outer, with: .color(frame.glassStroke), lineWidth: lineW)
        // Highlights
        let hl = CGRect(x: rect.minX + w * 0.17, y: rect.minY + rect.height * 0.10, width: w * 0.09, height: rect.height * 0.55)
        ctx.fill(SortFx.rounded(hl, w * 0.045), with: .color(Color.white.opacity(0.38)))
        let hl2 = CGRect(x: rect.minX + w * 0.31, y: rect.minY + rect.height * 0.14, width: w * 0.035, height: rect.height * 0.22)
        ctx.fill(SortFx.rounded(hl2, w * 0.0175), with: .color(Color.white.opacity(0.24)))
        // Rim
        let rim = CGRect(x: rect.minX - w * 0.07, y: rect.minY - w * 0.05, width: w * 1.14, height: w * 0.14)
        ctx.fill(SortFx.rounded(rim, w * 0.07), with: .color(frame.isDark ? Color.white.opacity(0.22) : Color.white.opacity(0.55)))
        ctx.stroke(SortFx.rounded(rim, w * 0.07), with: .color(frame.glassStroke), lineWidth: lineW * 0.75)

        if complete {
            ctx.stroke(SortFx.tubePath(rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(frame.successColor.opacity(0.9)), lineWidth: 2)
        }
    }
}

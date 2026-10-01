import SwiftUI

// Shared drawing support for the Liquid ("Color Mixer") and Bolt ("Tool Bench") boards:
// color math, layout, the per-frame render input, and small effects (sparkles, rings, pointers, lock tags).

// MARK: - Color math

struct SortRGB {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var n: UInt64 = 0
        Scanner(string: s).scanHexInt64(&n)
        self.init(r: Double((n >> 16) & 0xFF) / 255, g: Double((n >> 8) & 0xFF) / 255, b: Double(n & 0xFF) / 255)
    }

    func mixed(with o: SortRGB, _ t: Double) -> SortRGB {
        SortRGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    func lighter(_ t: Double) -> SortRGB { mixed(with: SortRGB(r: 1, g: 1, b: 1), t) }
    func darker(_ t: Double) -> SortRGB { mixed(with: SortRGB(r: 0, g: 0, b: 0), t) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    func alpha(_ opacity: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: opacity) }

    /// Perceived brightness 0...1.
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
}

enum SortMath {
    static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }
    static func smooth(_ x: Double) -> Double {
        let t = clamp(x)
        return t * t * (3 - 2 * t)
    }
    static func easeOut(_ x: Double) -> Double {
        let t = clamp(x)
        return 1 - (1 - t) * (1 - t) * (1 - t)
    }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    /// Small deterministic pseudo-random value in 0..<1 (for speckles, wood grain and sparkles).
    static func hash(_ a: Int, _ b: Int = 0) -> Double {
        var h = UInt64(truncatingIfNeeded: a &* 73_856_093) ^ UInt64(truncatingIfNeeded: b &* 19_349_663)
        h = (h ^ (h >> 13)) &* 0x5bd1_e995
        h = h ^ (h >> 15)
        return Double(h % 10_000) / 10_000.0
    }
}

// MARK: - Layout

struct SortLayout {
    /// Tube/bolt width (the unit all proportions are expressed in).
    var unit: CGFloat = 0
    /// Body rectangles (width `unit`) in canvas coordinates; heights depend on the container's capacity.
    var rects: [CGRect] = []
    /// One entry per row: the baseline y and the horizontal extent of the shelf/rail.
    var rows: [(baseline: CGFloat, minX: CGFloat, maxX: CGFloat)] = []
    var rowOfTube: [Int] = []

    /// Height of a container of capacity `cap`, in units.
    static func heightUnits(cap: Int, variant: SortVariant) -> Double {
        switch variant {
        case .liquid: return Double(cap) * 0.66 + 0.42
        case .bolt: return Double(cap) * 0.43 + 0.95
        }
    }

    static func make(caps: [Int], size: CGSize, variant: SortVariant) -> SortLayout {
        let n = caps.count
        guard n > 0, size.width > 20, size.height > 20 else { return SortLayout() }
        let maxCap = caps.max() ?? 4
        let hUnits = heightUnits(cap: maxCap, variant: variant)
        let gapX: Double = variant == .liquid ? 0.34 : 0.30
        let gapY: Double = variant == .liquid ? 0.66 : 0.50
        let topPad: Double = 0.60
        let bottomPad: Double = 0.30
        let marginX: CGFloat = 14
        let marginY: CGFloat = 8
        let maxUnit: CGFloat = variant == .liquid ? 84 : 80

        var bestRows = 1
        var bestUnit: CGFloat = 0
        let maxRows = n >= 4 ? 2 : 1
        for rows in 1...maxRows {
            let per = Int((Double(n) / Double(rows)).rounded(.up))
            let uW = (size.width - 2 * marginX) / (CGFloat(per) + CGFloat(per - 1) * CGFloat(gapX))
            let totalUnits = Double(rows) * hUnits + Double(rows - 1) * gapY + topPad + bottomPad
            let uH = (size.height - 2 * marginY) / CGFloat(totalUnits)
            let u = min(uW, uH, maxUnit)
            if u > bestUnit + 0.5 {
                bestUnit = u
                bestRows = rows
            }
        }
        let u = max(bestUnit, 8)
        let per = Int((Double(n) / Double(bestRows)).rounded(.up))
        let rowH = CGFloat(hUnits) * u
        let totalH = CGFloat(bestRows) * rowH + CGFloat(bestRows - 1) * CGFloat(gapY) * u
        let y0 = (size.height - totalH) / 2 + CGFloat(topPad - bottomPad) * u / 2

        var layout = SortLayout()
        layout.unit = u
        layout.rects = Array(repeating: .zero, count: n)
        layout.rowOfTube = Array(repeating: 0, count: n)
        for row in 0..<bestRows {
            let start = row * per
            let end = min(n, start + per)
            guard start < end else { continue }
            let count = end - start
            let rowW = CGFloat(count) * u + CGFloat(count - 1) * CGFloat(gapX) * u
            let x0 = (size.width - rowW) / 2
            let baseline = y0 + CGFloat(row) * (rowH + CGFloat(gapY) * u) + rowH
            for k in 0..<count {
                let i = start + k
                let h = CGFloat(heightUnits(cap: caps[i], variant: variant)) * u
                layout.rects[i] = CGRect(x: x0 + CGFloat(k) * (u + CGFloat(gapX) * u), y: baseline - h, width: u, height: h)
                layout.rowOfTube[i] = row
            }
            layout.rows.append((baseline: baseline, minX: x0, maxX: x0 + rowW))
        }
        return layout
    }
}

// MARK: - Animation / effect records

/// A pour (or nut transfer) in flight. The session state has already moved on; the board draws `pre` -> `post`.
struct SortPourAnim {
    var from: Int
    var to: Int
    /// Number of layers/nuts moved.
    var count: Int
    var color: String
    var start: Double
    var duration: Double
    /// Bolt boards: per-nut stagger and duration in seconds.
    var stagger: Double
    var nutDuration: Double
    var pre: SortState
    var post: SortState
}

struct SortUnlockEvent {
    var color: String
    var start: Double
}

// MARK: - Per-frame render input

struct SortFrame {
    var variant: SortVariant
    var state: SortState
    var caps: [Int]
    var anim: SortPourAnim?
    var time: Double
    var selected: Int?
    var previousSelected: Int?
    var selectionTime: Double
    var topRunLength: [Int]
    var shakeTube: Int?
    var shakeStart: Double
    var hint: SortMove?
    var tutorial: SortMove?
    var sparkles: [Int: Double]
    var unlocks: [Int: SortUnlockEvent]
    var solvedAt: Double?
    var complete: [Bool]
    var reduceMotion: Bool
    var showPatterns: Bool
    var highContrast: Bool
    var isDark: Bool
    var palette: [String: PaletteColor]
    var hintColor: Color
    var successColor: Color
    var accentColor: Color

    func rgb(_ id: String) -> SortRGB {
        guard let p = palette[id] else { return SortRGB(r: 0.6, g: 0.6, b: 0.6) }
        return SortRGB(hex: highContrast ? p.highContrastHex : p.hex)
    }

    func symbol(_ id: String) -> String? { palette[id]?.symbol }

    /// Animation progress 0...1 of the active pour, or nil when no pour is playing.
    var animProgress: Double? {
        guard let a = anim, a.duration > 0 else { return nil }
        let p = (time - a.start) / a.duration
        return p >= 1 ? nil : SortMath.clamp(p)
    }

    /// Eased lift 0...1 of a tube that was just selected / deselected.
    func lift(_ i: Int) -> Double {
        if reduceMotion { return selected == i ? 1 : 0 }
        let t = SortMath.easeOut((time - selectionTime) / 0.2)
        if selected == i { return t }
        if previousSelected == i { return 1 - t }
        return 0
    }

    /// Horizontal shake offset for an invalid target.
    func shakeX(_ i: Int, unit: CGFloat) -> CGFloat {
        guard !reduceMotion, shakeTube == i else { return 0 }
        let t = time - shakeStart
        if t < 0 || t > 0.4 { return 0 }
        return CGFloat(sin(t * 38) * (1 - t / 0.4)) * unit * 0.09
    }

    var glassStroke: Color {
        if highContrast { return isDark ? .white : .black }
        return isDark ? Color.white.opacity(0.55) : SortRGB(hex: "#7C8DA3").alpha(0.8)
    }

    /// Pulse 0...1 for hints and pointers (steady when reduce-motion is on).
    var pulse: Double {
        reduceMotion ? 0.8 : 0.5 + 0.5 * sin(time * 4.2)
    }
}

// MARK: - Shared effects

enum SortFx {
    /// Draws an SF Symbol tinted `color`, fitted into `rect`.
    static func symbol(_ ctx: GraphicsContext, name: String, in rect: CGRect, color: Color) {
        var c = ctx
        var img = c.resolve(Image(systemName: name))
        img.shading = .color(color)
        let sz = img.size
        guard sz.width > 0, sz.height > 0, rect.width > 0, rect.height > 0 else { return }
        let s = min(rect.width / sz.width, rect.height / sz.height)
        let w = sz.width * s
        let h = sz.height * s
        c.draw(img, in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    static func text(_ ctx: GraphicsContext, _ s: String, at p: CGPoint, size: CGFloat, color: Color, weight: Font.Weight = .bold) {
        var c = ctx
        let resolved = c.resolve(Text(s).font(.system(size: size, weight: weight, design: .rounded)).foregroundColor(color))
        c.draw(resolved, at: p, anchor: .center)
    }

    /// Contrast color (white or near-black) for symbols drawn over `rgb`.
    static func contrast(_ rgb: SortRGB) -> Color {
        rgb.luminance > 0.62 ? Color.black.opacity(0.62) : Color.white.opacity(0.92)
    }

    /// Bottom-rounded container silhouette (open at the top). Built from Beziers so it works on every iOS version.
    static func tubePath(_ r: CGRect) -> Path {
        var p = Path()
        let rb = r.width / 2
        let k: CGFloat = 0.5523 * rb
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - rb))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.minX, y: r.maxY - rb + k),
                   control2: CGPoint(x: r.midX - k, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY - rb),
                   control1: CGPoint(x: r.midX + k, y: r.maxY),
                   control2: CGPoint(x: r.maxX, y: r.maxY - rb + k))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }

    static func ellipse(_ center: CGPoint, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h))
    }

    static func rounded(_ r: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: r, cornerRadius: radius, style: .continuous)
    }

    /// Four-point sparkle.
    static func star(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        let k = r * 0.28
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + k, y: c.y - k))
        p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        p.addLine(to: CGPoint(x: c.x + k, y: c.y + k))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - k, y: c.y + k))
        p.addLine(to: CGPoint(x: c.x - r, y: c.y))
        p.addLine(to: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }

    /// Small burst of sparkles from `center`, starting at `start` (seconds), lasting about 0.9s.
    static func sparkles(_ ctx: GraphicsContext, center: CGPoint, unit: CGFloat, start: Double, time: Double, seed: Int) {
        let t = (time - start) / 0.9
        if t < 0 || t > 1 { return }
        let e = SortMath.easeOut(t)
        let alpha = 1 - t
        var c = ctx
        c.opacity = alpha
        // expanding ring
        c.stroke(ellipse(center, unit * CGFloat(0.5 + 1.5 * e), unit * CGFloat(0.25 + 0.7 * e)),
                 with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)
        let gold = Color(.sRGB, red: 1.0, green: 0.85, blue: 0.42, opacity: 1)
        for i in 0..<8 {
            let ang = (Double(i) / 8.0) * 2 * Double.pi + SortMath.hash(seed, i) * 0.6
            let dist = Double(unit) * (0.35 + 0.95 * e) * (0.8 + 0.4 * SortMath.hash(seed, i + 40))
            let pt = CGPoint(x: center.x + CGFloat(cos(ang) * dist), y: center.y + CGFloat(sin(ang) * dist) * 0.8 - CGFloat(e) * unit * 0.3)
            let r = unit * CGFloat(0.10 + 0.07 * SortMath.hash(seed, i + 80)) * CGFloat(1 - 0.4 * t)
            c.fill(star(pt, r), with: .color(i % 2 == 0 ? Color.white : gold))
        }
    }

    /// Soft glowing outline used for hints, selection and tutorial pointers.
    static func ring(_ ctx: GraphicsContext, rect: CGRect, color: Color, alpha: Double, width: CGFloat, radius: CGFloat) {
        var c = ctx
        c.opacity = alpha
        c.stroke(rounded(rect, radius), with: .color(color.opacity(0.35)), lineWidth: width * 3)
        c.stroke(rounded(rect, radius), with: .color(color), lineWidth: width)
    }

    /// Bobbing pointer above `point`.
    static func pointer(_ ctx: GraphicsContext, above point: CGPoint, unit: CGFloat, color: Color, time: Double, still: Bool) {
        let bob = still ? 0 : CGFloat(sin(time * 5)) * unit * 0.08
        let r = CGRect(x: point.x - unit * 0.22, y: point.y - unit * 0.62 + bob, width: unit * 0.44, height: unit * 0.44)
        var c = ctx
        c.fill(ellipse(CGPoint(x: r.midX, y: r.midY), unit * 0.56, unit * 0.56), with: .color(Color.white.opacity(0.9)))
        symbol(c, name: "arrowtriangle.down.fill", in: r, color: color)
    }

    /// Padlock tag: needed color + symbol on a small hanging tag.
    static func lockTag(_ ctx: GraphicsContext, center: CGPoint, unit: CGFloat, frame: SortFrame, color id: String, alpha: Double, lift: CGFloat) {
        let rgb = frame.rgb(id)
        var c = ctx
        c.opacity = alpha
        let r = CGRect(x: center.x - unit * 0.48, y: center.y - unit * 0.22 - lift, width: unit * 0.96, height: unit * 0.44)
        c.fill(rounded(r.offsetBy(dx: 0, dy: 2), unit * 0.14), with: .color(Color.black.opacity(0.18)))
        c.fill(rounded(r, unit * 0.14), with: .linearGradient(
            Gradient(colors: [rgb.lighter(0.18).color, rgb.darker(0.1).color]),
            startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        c.stroke(rounded(r, unit * 0.14), with: .color(frame.isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.35)), lineWidth: 1.4)
        let fg = contrast(rgb)
        symbol(c, name: "lock.fill", in: CGRect(x: r.minX + unit * 0.10, y: r.minY + unit * 0.07, width: unit * 0.30, height: unit * 0.30), color: fg)
        if let sym = frame.symbol(id), frame.showPatterns {
            symbol(c, name: sym, in: CGRect(x: r.maxX - unit * 0.42, y: r.minY + unit * 0.08, width: unit * 0.30, height: unit * 0.28), color: fg)
        } else {
            c.fill(ellipse(CGPoint(x: r.maxX - unit * 0.27, y: r.midY), unit * 0.24, unit * 0.24), with: .color(fg.opacity(0.55)))
        }
    }

    /// Shared overlays: hint rings, tutorial pointer, sparkles and unlock pops. `pose` maps a container index to the
    /// rectangle it is currently drawn at.
    static func overlays(_ ctx: GraphicsContext, layout: SortLayout, frame: SortFrame, pose: (Int) -> CGRect) {
        let u = layout.unit
        if let h = frame.hint {
            for (idx, isSource) in [(h.from, true), (h.to, false)] where layout.rects.indices.contains(idx) {
                let r = pose(idx).insetBy(dx: -u * 0.10, dy: -u * 0.08)
                ring(ctx, rect: r, color: frame.hintColor, alpha: 0.45 + 0.5 * frame.pulse, width: isSource ? 3 : 2.2, radius: u * 0.3)
                if !isSource {
                    pointer(ctx, above: CGPoint(x: r.midX, y: r.minY), unit: u, color: frame.hintColor, time: frame.time, still: frame.reduceMotion)
                }
            }
        }
        if let t = frame.tutorial, frame.anim == nil {
            let target: Int
            if let sel = frame.selected, sel == t.from { target = t.to } else { target = t.from }
            if layout.rects.indices.contains(target) {
                let r = pose(target).insetBy(dx: -u * 0.10, dy: -u * 0.08)
                ring(ctx, rect: r, color: frame.accentColor, alpha: 0.35 + 0.55 * frame.pulse, width: 3, radius: u * 0.3)
                pointer(ctx, above: CGPoint(x: r.midX, y: r.minY), unit: u, color: frame.accentColor, time: frame.time, still: frame.reduceMotion)
            }
        }
        if !frame.reduceMotion {
            for (i, start) in frame.sparkles where layout.rects.indices.contains(i) {
                let r = layout.rects[i]
                sparkles(ctx, center: CGPoint(x: r.midX, y: r.minY + u * 0.1), unit: u, start: start, time: frame.time, seed: i + 1)
            }
            if let solved = frame.solvedAt {
                for i in layout.rects.indices where !frame.state.tubes[i].isEmpty {
                    let r = layout.rects[i]
                    sparkles(ctx, center: CGPoint(x: r.midX, y: r.minY + u * 0.2), unit: u * 0.8, start: solved + Double(i) * 0.05, time: frame.time, seed: i + 101)
                }
            }
        }
    }
}

import SwiftUI
import UIKit
import SpriteKit

/// Draws every Pixel Picnic bitmap (blocks, stones, crates, Parcel Pals, tiny boxes) with UIKit and caches the
/// resulting SpriteKit textures. Nothing here depends on game state.
final class PixelArt {
    let palette: Palette
    private(set) var highContrast: Bool
    private(set) var showPatterns: Bool
    private var cache: [String: SKTexture] = [:]

    init(palette: Palette, highContrast: Bool, showPatterns: Bool) {
        self.palette = palette
        self.highContrast = highContrast
        self.showPatterns = showPatterns
    }

    func update(highContrast: Bool, showPatterns: Bool) {
        if highContrast != self.highContrast || showPatterns != self.showPatterns {
            self.highContrast = highContrast
            self.showPatterns = showPatterns
            cache.removeAll()
        }
    }

    // MARK: Colors

    func paletteColor(_ id: String) -> PaletteColor? { palette.color(id) }

    func uiColor(_ id: String) -> UIColor {
        guard let c = palette.color(id) else { return UIColor.systemGray }
        return UIColor(Color(hex: highContrast ? c.highContrastHex : c.hex))
    }

    func index(of id: String) -> Int {
        palette.colors.firstIndex { $0.id == id } ?? 0
    }

    static func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    static func shade(_ color: UIColor, _ factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, max(0, r * factor)), green: min(1, max(0, g * factor)), blue: min(1, max(0, b * factor)), alpha: a)
    }

    func inkColor(on base: UIColor) -> UIColor {
        PixelArt.luminance(base) > 0.62 ? UIColor(red: 0.16, green: 0.14, blue: 0.22, alpha: 1) : UIColor.white
    }

    // MARK: Textures

    private func render(_ size: CGSize, _ draw: (CGContext, CGRect) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            draw(ctx.cgContext, CGRect(origin: .zero, size: size))
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    /// A pixel block. Large blocks carry the color's symbol, small blocks a pattern overlay (when patterns are on).
    func blockTexture(_ id: String, side: CGFloat) -> SKTexture {
        let key = "b|\(id)|\(Int(side * 10))|\(highContrast)|\(showPatterns)"
        if let t = cache[key] { return t }
        let base = uiColor(id)
        let idx = index(of: id)
        let symbol = palette.color(id)?.symbol
        let t = render(CGSize(width: side, height: side)) { ctx, bounds in
            let gap = max(0.5, side * 0.035)
            let r = bounds.insetBy(dx: gap, dy: gap)
            let radius = side * 0.2
            let path = UIBezierPath(roundedRect: r, cornerRadius: radius)
            base.setFill()
            path.fill()
            ctx.saveGState()
            path.addClip()
            UIColor.white.withAlphaComponent(0.26).setFill()
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.16))
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width * 0.14, height: r.height))
            UIColor.black.withAlphaComponent(0.17).setFill()
            ctx.fill(CGRect(x: r.minX, y: r.maxY - r.height * 0.18, width: r.width, height: r.height * 0.18))
            ctx.fill(CGRect(x: r.maxX - r.width * 0.15, y: r.minY, width: r.width * 0.15, height: r.height))
            // soft sheen speck
            UIColor.white.withAlphaComponent(0.22).setFill()
            ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.2, width: r.width * 0.16, height: r.height * 0.1))
            ctx.restoreGState()
            if self.highContrast {
                PixelArt.shade(base, 0.6).setStroke()
                path.lineWidth = max(1, side * 0.05)
                path.stroke()
            }
            if self.showPatterns {
                let ink = self.inkColor(on: base).withAlphaComponent(0.85)
                if side >= 26, let symbol = symbol {
                    PixelArt.drawSymbol(symbol, in: r.insetBy(dx: r.width * 0.24, dy: r.height * 0.24), ink: ink)
                } else {
                    PixelArt.drawPattern(idx, in: r.insetBy(dx: r.width * 0.22, dy: r.height * 0.22), ink: ink.withAlphaComponent(0.7))
                }
            }
        }
        cache[key] = t
        return t
    }

    func stoneTexture(side: CGFloat) -> SKTexture {
        let key = "s|\(Int(side * 10))|\(highContrast)"
        if let t = cache[key] { return t }
        let base = highContrast ? UIColor(white: 0.32, alpha: 1) : UIColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1)
        let t = render(CGSize(width: side, height: side)) { ctx, bounds in
            let gap = max(0.5, side * 0.035)
            let r = bounds.insetBy(dx: gap, dy: gap)
            let path = UIBezierPath(roundedRect: r, cornerRadius: side * 0.3)
            base.setFill()
            path.fill()
            ctx.saveGState()
            path.addClip()
            UIColor.white.withAlphaComponent(0.22).setFill()
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.2))
            UIColor.black.withAlphaComponent(0.2).setFill()
            ctx.fill(CGRect(x: r.minX, y: r.maxY - r.height * 0.22, width: r.width, height: r.height * 0.22))
            ctx.restoreGState()
            let crack = UIBezierPath()
            crack.move(to: CGPoint(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.2))
            crack.addLine(to: CGPoint(x: r.minX + r.width * 0.48, y: r.minY + r.height * 0.5))
            crack.addLine(to: CGPoint(x: r.minX + r.width * 0.4, y: r.minY + r.height * 0.8))
            crack.move(to: CGPoint(x: r.minX + r.width * 0.48, y: r.minY + r.height * 0.5))
            crack.addLine(to: CGPoint(x: r.minX + r.width * 0.72, y: r.minY + r.height * 0.58))
            UIColor.black.withAlphaComponent(0.4).setStroke()
            crack.lineWidth = max(1, side * 0.06)
            crack.lineCapStyle = .round
            crack.stroke()
        }
        cache[key] = t
        return t
    }

    /// A crate with symbol (top-left) and a big count.
    func crateTexture(_ id: String, count: Int, side: CGFloat) -> SKTexture {
        let key = "c|\(id)|\(count)|\(Int(side * 10))|\(highContrast)"
        if let t = cache[key] { return t }
        let base = uiColor(id)
        let ink = inkColor(on: base)
        let symbol = palette.color(id)?.symbol
        let t = render(CGSize(width: side, height: side)) { ctx, bounds in
            let r = bounds.insetBy(dx: side * 0.04, dy: side * 0.04)
            let radius = side * 0.2
            let path = UIBezierPath(roundedRect: r, cornerRadius: radius)
            UIColor.black.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: r.offsetBy(dx: 0, dy: side * 0.04), cornerRadius: radius).fill()
            base.setFill()
            path.fill()
            ctx.saveGState()
            path.addClip()
            UIColor.white.withAlphaComponent(0.22).setFill()
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.14))
            UIColor.black.withAlphaComponent(0.14).setFill()
            ctx.fill(CGRect(x: r.minX, y: r.maxY - r.height * 0.16, width: r.width, height: r.height * 0.16))
            // plank seams
            UIColor.black.withAlphaComponent(0.12).setFill()
            ctx.fill(CGRect(x: r.minX, y: r.minY + r.height * 0.33, width: r.width, height: max(1, side * 0.02)))
            ctx.fill(CGRect(x: r.minX, y: r.minY + r.height * 0.66, width: r.width, height: max(1, side * 0.02)))
            ctx.restoreGState()
            PixelArt.shade(base, 0.62).setStroke()
            path.lineWidth = max(1.5, side * 0.05)
            path.stroke()
            // nails
            UIColor.white.withAlphaComponent(0.4).setFill()
            let nail = max(1.5, side * 0.035)
            for p in [CGPoint(x: r.minX + side * 0.1, y: r.maxY - side * 0.1), CGPoint(x: r.maxX - side * 0.1, y: r.maxY - side * 0.1)] {
                ctx.fillEllipse(in: CGRect(x: p.x - nail, y: p.y - nail, width: nail * 2, height: nail * 2))
            }
            if let symbol = symbol {
                PixelArt.drawSymbol(symbol, in: CGRect(x: r.minX + side * 0.1, y: r.minY + side * 0.08, width: side * 0.26, height: side * 0.26), ink: ink)
            }
            let text = "\(count)"
            let fontSize = side * (text.count >= 3 ? 0.34 : 0.46)
            let font = PixelArt.roundedFont(size: fontSize, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let sz = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: bounds.midX - sz.width / 2 + side * 0.04, y: bounds.midY - sz.height / 2 + side * 0.1), withAttributes: attrs)
        }
        cache[key] = t
        return t
    }

    /// A Parcel Pal: a round helper with a colored cap.
    func palTexture(capColor id: String, side: CGFloat) -> SKTexture {
        let key = "p|\(id)|\(Int(side * 10))|\(highContrast)"
        if let t = cache[key] { return t }
        let cap = uiColor(id)
        let t = render(CGSize(width: side, height: side)) { ctx, bounds in
            let body = CGRect(x: side * 0.14, y: side * 0.28, width: side * 0.72, height: side * 0.62)
            UIColor.black.withAlphaComponent(0.18).setFill()
            ctx.fillEllipse(in: body.offsetBy(dx: 0, dy: side * 0.04))
            UIColor(red: 1.0, green: 0.96, blue: 0.9, alpha: 1).setFill()
            ctx.fillEllipse(in: body)
            UIColor(red: 0.45, green: 0.32, blue: 0.2, alpha: 1).setStroke()
            ctx.setLineWidth(max(1, side * 0.05))
            ctx.strokeEllipse(in: body)
            // cap
            let capRect = CGRect(x: side * 0.16, y: side * 0.16, width: side * 0.68, height: side * 0.4)
            cap.setFill()
            let capPath = UIBezierPath()
            capPath.move(to: CGPoint(x: capRect.minX, y: capRect.maxY))
            capPath.addCurve(to: CGPoint(x: capRect.maxX, y: capRect.maxY), controlPoint1: CGPoint(x: capRect.minX, y: capRect.minY - side * 0.12), controlPoint2: CGPoint(x: capRect.maxX, y: capRect.minY - side * 0.12))
            capPath.close()
            capPath.fill()
            UIBezierPath(roundedRect: CGRect(x: side * 0.5, y: capRect.maxY - side * 0.07, width: side * 0.4, height: side * 0.09), cornerRadius: side * 0.045).fill()
            // eyes
            UIColor(red: 0.2, green: 0.16, blue: 0.25, alpha: 1).setFill()
            let eye = max(1.2, side * 0.06)
            ctx.fillEllipse(in: CGRect(x: side * 0.36 - eye, y: side * 0.62 - eye, width: eye * 2, height: eye * 2.2))
            ctx.fillEllipse(in: CGRect(x: side * 0.62 - eye, y: side * 0.62 - eye, width: eye * 2, height: eye * 2.2))
            // feet
            UIColor(red: 0.45, green: 0.32, blue: 0.2, alpha: 1).setFill()
            ctx.fillEllipse(in: CGRect(x: side * 0.28, y: side * 0.86, width: side * 0.18, height: side * 0.1))
            ctx.fillEllipse(in: CGRect(x: side * 0.54, y: side * 0.86, width: side * 0.18, height: side * 0.1))
        }
        cache[key] = t
        return t
    }

    /// A tiny parcel carried by a Pal.
    func boxTexture(_ id: String, side: CGFloat) -> SKTexture {
        let key = "x|\(id)|\(Int(side * 10))|\(highContrast)"
        if let t = cache[key] { return t }
        let base = uiColor(id)
        let t = render(CGSize(width: side, height: side)) { ctx, bounds in
            let r = bounds.insetBy(dx: side * 0.06, dy: side * 0.06)
            let path = UIBezierPath(roundedRect: r, cornerRadius: side * 0.18)
            base.setFill()
            path.fill()
            PixelArt.shade(base, 0.6).setStroke()
            path.lineWidth = max(1, side * 0.08)
            path.stroke()
            UIColor.white.withAlphaComponent(0.55).setFill()
            ctx.fill(CGRect(x: r.midX - side * 0.07, y: r.minY, width: side * 0.14, height: r.height))
        }
        cache[key] = t
        return t
    }

    // MARK: Drawing helpers

    static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: d, size: size)
        }
        return base
    }

    static func drawSymbol(_ name: String, in rect: CGRect, ink: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: max(6, rect.height), weight: .bold)
        guard let img = UIImage(systemName: name, withConfiguration: config)?.withTintColor(ink, renderingMode: .alwaysOriginal) else { return }
        let aspect = img.size.width / max(img.size.height, 1)
        var w = rect.width
        var h = w / max(aspect, 0.01)
        if h > rect.height {
            h = rect.height
            w = h * aspect
        }
        img.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    /// Twelve simple glyphs, one per palette color, for blocks too small to hold a symbol.
    static func drawPattern(_ index: Int, in r: CGRect, ink: UIColor) {
        ink.setFill()
        ink.setStroke()
        let lw = max(1, r.width * 0.2)
        switch index % 12 {
        case 0: // dot
            UIBezierPath(ovalIn: r.insetBy(dx: r.width * 0.2, dy: r.height * 0.2)).fill()
        case 1: // horizontal bar
            UIBezierPath(roundedRect: CGRect(x: r.minX, y: r.midY - lw / 2, width: r.width, height: lw), cornerRadius: lw / 2).fill()
        case 2: // vertical bar
            UIBezierPath(roundedRect: CGRect(x: r.midX - lw / 2, y: r.minY, width: lw, height: r.height), cornerRadius: lw / 2).fill()
        case 3: // slash
            let p = UIBezierPath()
            p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.lineWidth = lw; p.lineCapStyle = .round; p.stroke()
        case 4: // plus
            UIBezierPath(roundedRect: CGRect(x: r.minX, y: r.midY - lw / 2, width: r.width, height: lw), cornerRadius: lw / 2).fill()
            UIBezierPath(roundedRect: CGRect(x: r.midX - lw / 2, y: r.minY, width: lw, height: r.height), cornerRadius: lw / 2).fill()
        case 5: // ring
            let p = UIBezierPath(ovalIn: r.insetBy(dx: lw / 2, dy: lw / 2))
            p.lineWidth = lw * 0.8; p.stroke()
        case 6: // two dots
            let d = r.width * 0.34
            UIBezierPath(ovalIn: CGRect(x: r.minX, y: r.minY, width: d, height: d)).fill()
            UIBezierPath(ovalIn: CGRect(x: r.maxX - d, y: r.maxY - d, width: d, height: d)).fill()
        case 7: // corner squares
            let d = r.width * 0.36
            ctxFill(CGRect(x: r.minX, y: r.minY, width: d, height: d))
            ctxFill(CGRect(x: r.maxX - d, y: r.maxY - d, width: d, height: d))
        case 8: // chevron
            let p = UIBezierPath()
            p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.25)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.15)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.25))
            p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        case 9: // x
            let p = UIBezierPath()
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.lineWidth = lw * 0.8; p.lineCapStyle = .round; p.stroke()
        case 10: // three dots
            let d = r.width * 0.28
            UIBezierPath(ovalIn: CGRect(x: r.minX, y: r.minY, width: d, height: d)).fill()
            UIBezierPath(ovalIn: CGRect(x: r.maxX - d, y: r.minY, width: d, height: d)).fill()
            UIBezierPath(ovalIn: CGRect(x: r.midX - d / 2, y: r.maxY - d, width: d, height: d)).fill()
        default: // square outline
            let p = UIBezierPath(roundedRect: r.insetBy(dx: lw / 2, dy: lw / 2), cornerRadius: lw / 2)
            p.lineWidth = lw * 0.8; p.stroke()
        }
    }

    private static func ctxFill(_ rect: CGRect) {
        UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.2).fill()
    }
}

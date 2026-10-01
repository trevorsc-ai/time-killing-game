import SwiftUI

// MARK: - Drawing helpers

private extension GraphicsContext {
    func fillBox(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0, _ color: Color) {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        let path: Path = r > 0 ? Path(roundedRect: rect, cornerRadius: r) : Path(rect)
        fill(path, with: .color(color))
    }

    func fillDisc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    func fillOval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)), with: .color(color))
    }

    func fillPoly(_ points: [CGPoint], _ color: Color) {
        guard let first = points.first else { return }
        var p = Path()
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        fill(p, with: .color(color))
    }

    func strokeLine(_ a: CGPoint, _ b: CGPoint, _ width: CGFloat, _ color: Color) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat, _ color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - size))
        p.addQuadCurve(to: CGPoint(x: cx + size, y: cy), control: CGPoint(x: cx, y: cy))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy + size), control: CGPoint(x: cx, y: cy))
        p.addQuadCurve(to: CGPoint(x: cx - size, y: cy), control: CGPoint(x: cx, y: cy))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy - size), control: CGPoint(x: cx, y: cy))
        fill(p, with: .color(color))
    }
}

private func hexColor(_ hex: String) -> Color { Color(hex: hex) }

/// Picks the entry for `stage`, clamping to the last one.
private func pick(_ stage: Int, _ hexes: [String]) -> Color {
    let i = max(0, min(stage, hexes.count - 1))
    return Color(hex: hexes[i])
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: - Public view

/// Vector illustration of a restoration project at a given stage (0 = untouched, up to the destination's stage count).
/// d1 is the Station Snack Cart (7 looks: 0...6); d2-d4 have 4 looks (0...3). Other destinations get a simple lantern.
struct RestorationArtView: View {
    let destinationId: String
    let stage: Int
    var showcase: Bool = false
    var animated: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animated)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                let s = min(size.width / 240, size.height / 180)
                guard s > 0 else { return }
                var g = context
                g.translateBy(x: (size.width - 240 * s) / 2, y: (size.height - 180 * s) / 2)
                g.scaleBy(x: s, y: s)
                g.clip(to: Path(CGRect(x: 0, y: 0, width: 240, height: 180)))
                switch destinationId {
                case "d1": RestorationArt.snackCart(g, stage: stage, t: t, showcase: showcase)
                case "d2": RestorationArt.gardenCar(g, stage: stage, t: t, showcase: showcase)
                case "d3": RestorationArt.luggageBay(g, stage: stage, t: t, showcase: showcase)
                case "d4": RestorationArt.rainyPlatform(g, stage: stage, t: t, showcase: showcase)
                default: RestorationArt.lanternFallback(g, stage: stage, t: t)
                }
            }
        }
        .aspectRatio(240.0 / 180.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RestorationArt.description(destinationId: destinationId, stage: stage))
    }
}

enum RestorationArt {
    static func description(destinationId: String, stage: Int) -> String {
        let name: String
        switch destinationId {
        case "d1": name = "snack cart"
        case "d2": name = "greenhouse car"
        case "d3": name = "baggage bay"
        case "d4": name = "rainy platform"
        default: name = "project"
        }
        return stage == 0 ? "The \(name), waiting to be restored" : "The \(name), restored to stage \(stage)"
    }

    // MARK: Station Snack Cart

    static func snackCart(_ gIn: GraphicsContext, stage s: Int, t: Double, showcase: Bool) {
        var g = gIn
        // Backdrop: station wall and platform
        g.fillBox(0, 0, 240, 180, pick(s, ["#E6DCCB", "#EFE3CF", "#F7E6CB", "#F9E8CF", "#FBE4C2", "#FDE8C8", "#FFEFD2"]))
        g.fillBox(0, 0, 240, 118, pick(s, ["#D8CCBA", "#E4D6C0", "#F2DDBB", "#F3DDBA", "#EFD2A8", "#F6D9AE", "#FBE0B0"]))
        g.fillBox(0, 112, 240, 6, pick(s, ["#BFB2A0", "#CDBFA8", "#DDC7A0", "#DDC7A0", "#D6BD94", "#E2C79B", "#EACF9F"]))
        g.fillBox(0, 138, 240, 42, pick(s, ["#B7AA98", "#C8BAA3", "#D9C6A5", "#D9C6A5", "#D2B98F", "#DEC59C", "#E6CDA0"]))
        g.fillBox(0, 138, 240, 3, pick(s, ["#A09384", "#B2A38C", "#C6B18E", "#C6B18E", "#BEA47A", "#CCB188", "#D4B98A"]))
        // Wall lamp glow for the later stages
        if s >= 4 {
            g.fillBox(0, 0, 240, 180, Color(hex: "#FFC66E").opacity(0.10 + 0.03 * Double(s - 4)))
        }
        // Shadow
        g.fillOval(120, 152, 84, 7, Color.black.opacity(0.14))

        // Whole cart: a little bounce at showcase, a sad tilt at stage 0
        var c = g
        if showcase { c.translateBy(x: 0, y: CGFloat(sin(t * 2.2)) * 1.6) }
        if s == 0 {
            c.translateBy(x: 120, y: 152)
            c.rotate(by: .degrees(-3))
            c.translateBy(x: -120, y: -152)
        }

        let body = pick(s, ["#8E8176", "#C9A67F", "#E98B5F", "#E98B5F", "#E98B5F", "#E98B5F", "#EE8E63"])
        let trim = pick(s, ["#6F645B", "#A9835F", "#FFF1D6", "#FFF1D6", "#FFF1D6", "#FFF1D6", "#FFF6E2"])
        let dark = pick(s, ["#5E544C", "#8A6A4E", "#C46A43", "#C46A43", "#C46A43", "#C46A43", "#CC6E47"])
        let hatch = pick(s, ["#4B423B", "#5E463A", "#6B4F45", "#6B4F45", "#5A3F3A", "#5A3F3A", "#5A3F3A"])

        // Awning posts and canopy
        if s >= 3 {
            c.fillBox(46, 46, 5, 36, Color(hex: "#B9926A"))
            c.fillBox(189, 46, 5, 36, Color(hex: "#B9926A"))
            c.fillBox(48, 34, 144, 7, r: 3, Color(hex: "#C9473E"))
            let stripeColors: [Color] = [Color(hex: "#E5594F"), Color(hex: "#FFF4DC")]
            for i in 0..<7 {
                let topW: CGFloat = 144.0 / 7.0
                let botW: CGFloat = 176.0 / 7.0
                let tx = 48 + CGFloat(i) * topW
                let bx = 32 + CGFloat(i) * botW
                let col = stripeColors[i % 2]
                c.fillPoly([pt(tx, 40), pt(tx + topW, 40), pt(bx + botW, 62), pt(bx, 62)], col)
                c.fillDisc(bx + botW / 2, 62, botW / 2, col)
            }
        } else if s == 0 {
            // A bent pole and a torn rag
            c.strokeLine(pt(52, 82), pt(41, 52), 4, Color(hex: "#7A6B5C"))
            c.fillPoly([pt(41, 52), pt(58, 56), pt(48, 66)], Color(hex: "#B7ADA0"))
        }

        // Wheels
        let wheelY: CGFloat = 138
        let wheelXs: [CGFloat] = [78, 162]
        for (i, wx) in wheelXs.enumerated() {
            let broken = s == 0 && i == 0
            let cy = wheelY + (broken ? 5 : 0)
            let tire = s == 0 ? Color(hex: "#5A4E48") : Color(hex: "#4B4155")
            let rim = pick(s, ["#A5603C", "#8C7F73", "#F2C14E", "#F2C14E", "#F2C14E", "#F2C14E", "#F6CF63"])
            c.fillDisc(wx, cy, 15, tire)
            c.fillDisc(wx, cy, 9.5, rim)
            c.fillDisc(wx, cy, 3.5, Color(hex: "#E8D9BD"))
            if s >= 1 || !broken {
                for k in 0..<4 {
                    let a = Double(k) * .pi / 4
                    let dx = CGFloat(cos(a)) * 9
                    let dy = CGFloat(sin(a)) * 9
                    c.strokeLine(pt(wx - dx, cy - dy), pt(wx + dx, cy + dy), 1.5, Color(hex: "#E8D9BD").opacity(0.8))
                }
            }
            if broken {
                // A missing wedge and a crack
                c.fillPoly([pt(wx, cy), pt(wx - 17, cy - 8), pt(wx - 6, cy - 17)], pick(s, ["#B7AA98"]))
                c.strokeLine(pt(wx + 2, cy + 2), pt(wx + 9, cy + 12), 1.5, Color(hex: "#3F3732"))
            }
        }

        // Body
        c.fillBox(48, 84, 144, 54, r: 8, body)
        c.fillBox(48, 124, 144, 14, r: 6, dark)
        c.fillBox(40, 76, 160, 10, r: 5, trim)
        c.fillBox(62, 92, 116, 30, r: 6, hatch)
        if s >= 1 {
            c.fillBox(54, 87, 132, 3, r: 1.5, Color.white.opacity(0.25))
        }
        if s == 0 {
            // Rust, a hole, cobweb
            c.fillOval(70, 130, 10, 4, Color(hex: "#A5603C").opacity(0.85))
            c.fillOval(168, 88, 8, 4, Color(hex: "#A5603C").opacity(0.8))
            c.fillOval(100, 80, 9, 3, Color(hex: "#A5603C").opacity(0.7))
            c.fillBox(150, 98, 24, 20, r: 3, Color(hex: "#2F2925"))
            c.strokeLine(pt(62, 92), pt(86, 112), 1, Color.white.opacity(0.5))
            c.strokeLine(pt(62, 92), pt(92, 100), 1, Color.white.opacity(0.5))
            c.strokeLine(pt(62, 92), pt(70, 118), 1, Color.white.opacity(0.5))
        }
        if s == 1 {
            // Swept clean: bare wood grain
            c.strokeLine(pt(60, 128), pt(180, 128), 1, Color(hex: "#A9835F").opacity(0.7))
            c.strokeLine(pt(60, 133), pt(180, 133), 1, Color(hex: "#A9835F").opacity(0.5))
        }

        // Stocked shelves (stage 5+)
        if s >= 5 {
            c.fillBox(62, 106, 116, 3, Color(hex: "#FFF1D6"))
            let jar: [String] = ["#F28FB8", "#F7D154", "#6DC47A", "#5DA9E8", "#AC70D8", "#F59B3D", "#41BDB3"]
            for i in 0..<7 {
                let jx = 67 + CGFloat(i) * 15.5
                c.fillBox(jx, 96, 11, 10, r: 3, Color(hex: jar[i]))
                c.fillBox(jx + 2, 94, 7, 3, r: 1, Color(hex: "#FFF1D6"))
            }
            for i in 0..<5 {
                let dx = 76 + CGFloat(i) * 22
                c.fillDisc(dx, 115, 6, Color(hex: i % 2 == 0 ? "#F28FB8" : "#E8B27A"))
                c.fillDisc(dx, 115, 2.2, hatch)
            }
            // Counter treats: cups, plate of donuts, teapot
            c.fillBox(78, 62, 10, 13, r: 3, Color(hex: "#FFFFFF"))
            c.fillBox(90, 66, 10, 9, r: 3, Color(hex: "#5DA9E8"))
            c.fillBox(108, 72, 34, 4, r: 2, Color(hex: "#FFF1D6"))
            c.fillDisc(118, 69, 5, Color(hex: "#F28FB8"))
            c.fillDisc(118, 69, 1.8, Color(hex: "#FFF1D6"))
            c.fillDisc(131, 69, 5, Color(hex: "#F7D154"))
            c.fillDisc(131, 69, 1.8, Color(hex: "#FFF1D6"))
            c.fillOval(166, 66, 10, 8, Color(hex: "#41BDB3"))
            c.fillBox(160, 58, 12, 4, r: 2, Color(hex: "#2E948B"))
            c.strokeLine(pt(175, 66), pt(183, 61), 2.5, Color(hex: "#41BDB3"))
        }

        // Lanterns and string lights (stage 4+)
        if s >= 4 {
            let pulse = 0.75 + 0.25 * sin(t * 2.4)
            for lx in [52, 188] as [CGFloat] {
                c.fillDisc(lx, 74, 20, Color(hex: "#FFD36E").opacity(0.22 * pulse))
                c.strokeLine(pt(lx, 62), pt(lx, 67), 1.5, Color(hex: "#4B4155"))
                c.fillBox(lx - 6, 67, 12, 16, r: 5, Color(hex: "#FFD36E"))
                c.fillBox(lx - 7, 65, 14, 3, r: 1.5, Color(hex: "#4B4155"))
            }
            let bulbs: [String] = ["#FFD36E", "#F28FB8", "#7DD6CE", "#F7D154"]
            for i in 0..<9 {
                let bx = 38 + CGFloat(i) * 20.5
                let on = (Int(t * 2) + i) % 3 != 0 || s < 6
                c.fillDisc(bx, 66, 2.4, Color(hex: bulbs[i % 4]).opacity(on ? 1 : 0.45))
            }
        }

        // Grand reopening: sign, bunting, steam, sparkles
        if s >= 6 {
            c.strokeLine(pt(98, 18), pt(98, 34), 1.5, Color(hex: "#8F8296"))
            c.strokeLine(pt(142, 18), pt(142, 34), 1.5, Color(hex: "#8F8296"))
            c.fillBox(80, 8, 80, 18, r: 7, Color(hex: "#41BDB3"))
            c.draw(Text("OPEN").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(.white),
                   at: pt(120, 17))
            let flags: [String] = ["#F28FB8", "#F7D154", "#5DA9E8", "#6DC47A", "#F59B3D"]
            for i in 0..<12 {
                let f = CGFloat(i) / 11
                let fx = 6 + f * 228
                let sag = 6 * sin(Double(f) * .pi)
                var tri = Path()
                tri.move(to: pt(fx - 5, 4 + CGFloat(sag)))
                tri.addLine(to: pt(fx + 5, 4 + CGFloat(sag)))
                tri.addLine(to: pt(fx, 15 + CGFloat(sag)))
                tri.closeSubpath()
                c.fill(tri, with: .color(Color(hex: flags[i % flags.count])))
            }
            for i in 0..<3 {
                let phase = (t * 0.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let ph = CGFloat(phase)
                let px: CGFloat = 175 + ph * 10 + CGFloat(sin(phase * 7 + Double(i))) * 3
                let py: CGFloat = 52 - ph * 30
                c.fillDisc(px, py, 3 + ph * 5, Color.white.opacity((1 - phase) * 0.8))
            }
            let spots: [CGPoint] = [pt(30, 40), pt(212, 44), pt(120, 50), pt(22, 96), pt(220, 100)]
            for (i, p) in spots.enumerated() {
                let tw = 0.5 + 0.5 * sin(t * 3 + Double(i) * 1.7)
                c.sparkle(p.x, p.y, CGFloat(3 + 4 * tw), Color(hex: "#FFE29A"))
            }
        }
        if showcase {
            let confetti: [String] = ["#F28FB8", "#F7D154", "#5DA9E8", "#6DC47A", "#E5594F", "#AC70D8"]
            for i in 0..<18 {
                let x = CGFloat((i * 37 + 11) % 236) + 2
                let fall = (t * 24 + Double(i) * 17).truncatingRemainder(dividingBy: 150)
                let y = CGFloat(fall)
                c.fillBox(x, y, 4, 6, r: 1, Color(hex: confetti[i % confetti.count]).opacity(0.85))
            }
        }
    }

    // MARK: Garden Express

    static func gardenCar(_ gIn: GraphicsContext, stage s: Int, t: Double, showcase: Bool) {
        let g = gIn
        g.fillBox(0, 0, 240, 180, pick(s, ["#D9E3DA", "#E1EFDB", "#E6F4D8", "#EAF8D6"]))
        // Hills
        g.fillOval(50, 128, 90, 40, pick(s, ["#B8C9B5", "#BFDDB9", "#BDE2B0", "#B5E2A5"]))
        g.fillOval(190, 132, 80, 34, pick(s, ["#A9BCA6", "#B1D3AB", "#AEDA9F", "#A5DB92"]))
        g.fillBox(0, 138, 240, 42, pick(s, ["#A4B79F", "#9FCC93", "#92CD84", "#84CE72"]))
        g.fillBox(0, 150, 240, 4, Color(hex: "#8F8296"))
        g.fillOval(120, 156, 100, 6, Color.black.opacity(0.12))
        if s >= 1 {
            // A sun peeking out
            g.fillDisc(206, 28, 14, Color(hex: "#FFE29A").opacity(0.9))
        }

        // Car body
        let body = pick(s, ["#7E9C86", "#6FAE7C", "#5FB36F", "#5FB36F"])
        let trim = pick(s, ["#5F7A68", "#4F9A5E", "#FFF1D6", "#FFF1D6"])
        g.fillBox(20, 88, 200, 50, r: 10, body)
        g.fillBox(20, 124, 200, 14, r: 6, trim)
        // Wheels
        for wx in [56, 90, 150, 184] as [CGFloat] {
            g.fillDisc(wx, 142, 11, Color(hex: "#4B4155"))
            g.fillDisc(wx, 142, 4, Color(hex: "#E8D9BD"))
        }
        // Glass house
        g.fillBox(26, 40, 188, 52, r: 16, pick(s, ["#B3C0B8", "#CBEAEC", "#D6F2F2", "#DDF6F4"]))
        for i in 0..<7 {
            g.fillBox(26 + CGFloat(i) * 31, 40, 3, 52, trim)
        }
        g.fillBox(24, 36, 192, 7, r: 3, trim)

        // Planters inside
        for i in 0..<5 {
            let px = 36 + CGFloat(i) * 37
            g.fillBox(px, 78, 28, 12, r: 3, pick(s, ["#9D8A74", "#B07E55", "#B07E55", "#B07E55"]))
            if s >= 2 {
                g.fillBox(px + 2, 77, 24, 4, r: 2, Color(hex: "#5B3F2E"))
            } else {
                g.strokeLine(pt(px + 6, 78), pt(px + 12, 83), 1, Color(hex: "#6F5C48"))
            }
            let cx = px + 14
            if s == 0 {
                g.strokeLine(pt(cx, 77), pt(cx - 4, 68), 1.5, Color(hex: "#8A7A5E"))
            } else if s == 2 {
                g.fillPoly([pt(cx, 77), pt(cx - 6, 68), pt(cx - 1, 72)], Color(hex: "#6DC47A"))
                g.fillPoly([pt(cx, 77), pt(cx + 6, 68), pt(cx + 1, 72)], Color(hex: "#58B068"))
            } else if s >= 3 {
                let sway = CGFloat(sin(t * 1.5 + Double(i))) * 1.5
                g.strokeLine(pt(cx, 78), pt(cx + sway, 56), 2, Color(hex: "#4FA05F"))
                g.fillOval(cx - 6 + sway / 2, 68, 6, 3, Color(hex: "#6DC47A"))
                g.fillOval(cx + 6 + sway / 2, 62, 6, 3, Color(hex: "#6DC47A"))
                let petals: [String] = ["#F28FB8", "#F7D154", "#AC70D8", "#E5594F", "#F59B3D"]
                let colr = Color(hex: petals[i % petals.count])
                for k in 0..<5 {
                    let a = Double(k) * 2 * .pi / 5
                    g.fillDisc(cx + sway + CGFloat(cos(a)) * 4.5, 54 + CGFloat(sin(a)) * 4.5, 3.4, colr)
                }
                g.fillDisc(cx + sway, 54, 2.6, Color(hex: "#FFE29A"))
            }
        }

        // Windows below the glass
        for i in 0..<5 {
            let wx = 30 + CGFloat(i) * 37
            g.fillBox(wx, 98, 28, 22, r: 4, trim)
            if s == 0 {
                g.fillBox(wx + 3, 101, 22, 16, r: 3, Color(hex: "#A9B3AE"))
                g.strokeLine(pt(wx + 5, 104), pt(wx + 12, 103), 1, Color.white.opacity(0.6))
            } else {
                g.fillBox(wx + 3, 101, 22, 16, r: 3, Color(hex: "#2E5B45"))
                g.fillPoly([pt(wx + 3, 101), pt(wx + 25, 101), pt(wx + 21, 108), pt(wx + 7, 108)], Color(hex: "#CDEBF0"))
            }
        }

        // Butterflies (full bloom)
        if s >= 3 {
            let bf: [(CGFloat, CGFloat, String)] = [(70, 30, "#F28FB8"), (160, 24, "#F7D154")]
            for (i, b) in bf.enumerated() {
                let flap = CGFloat(abs(sin(t * 8 + Double(i)))) * 4 + 1.5
                let bx = b.0 + CGFloat(sin(t * 1.2 + Double(i) * 2)) * 8
                let by = b.1 + CGFloat(cos(t * 1.7 + Double(i))) * 4
                g.fillOval(bx - 3, by, flap, 4, Color(hex: b.2))
                g.fillOval(bx + 3, by, flap, 4, Color(hex: b.2))
            }
        }
        if showcase {
            for i in 0..<6 {
                let tw = 0.5 + 0.5 * sin(t * 3 + Double(i) * 1.3)
                g.sparkle(CGFloat(24 + i * 38), CGFloat(18 + (i % 2) * 14), CGFloat(2 + 3 * tw), Color(hex: "#FFE29A"))
            }
        }
    }

    // MARK: Baggage Bay

    private static func suitcase(_ g: GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                                 color: Color, angle: Double, tag: Bool, brass: Bool) {
        var c = g
        c.translateBy(x: x + w / 2, y: y + h / 2)
        c.rotate(by: .degrees(angle))
        c.translateBy(x: -w / 2, y: -h / 2)
        let metal = brass ? Color(hex: "#F2C14E") : Color(hex: "#6F645B")
        c.fillBox(0, 0, w, h, r: 4, color)
        c.fillBox(w * 0.22, 0, 2.5, h, metal.opacity(0.8))
        c.fillBox(w * 0.74, 0, 2.5, h, metal.opacity(0.8))
        c.fillBox(w * 0.34, -4, w * 0.32, 4, r: 2, metal)
        if brass {
            c.fillBox(0, 0, 4, 4, r: 1, metal)
            c.fillBox(w - 4, 0, 4, 4, r: 1, metal)
            c.fillBox(0, h - 4, 4, 4, r: 1, metal)
            c.fillBox(w - 4, h - 4, 4, 4, r: 1, metal)
            c.fillBox(w / 2 - 3, h * 0.45, 6, 5, r: 1.5, metal)
        }
        if tag {
            c.fillBox(w * 0.5, h * 0.12, 9, 11, r: 2, Color(hex: "#FFF6E2"))
            c.fillDisc(w * 0.5 + 4.5, h * 0.12 + 4, 1.8, Color(hex: "#E5594F"))
        }
    }

    static func luggageBay(_ gIn: GraphicsContext, stage s: Int, t: Double, showcase: Bool) {
        let g = gIn
        g.fillBox(0, 0, 240, 180, pick(s, ["#D8D3CD", "#DFDDDA", "#E2E6EE", "#E8EBF6"]))
        g.fillBox(0, 0, 240, 128, pick(s, ["#C9C3BC", "#D3D4D6", "#D6DEEF", "#DDE4F6"]))
        g.fillBox(0, 128, 240, 52, pick(s, ["#A59E96", "#B6B3B0", "#BDC5DD", "#C2CBE6"]))
        g.fillBox(0, 128, 240, 3, pick(s, ["#8F8880", "#A09D9A", "#A6AECA", "#ABB4D2"]))
        if s >= 1 {
            // Tidy shelves
            for sy in [60, 100] as [CGFloat] {
                g.fillBox(14, sy, 212, 5, r: 2, pick(s, ["#9A8467", "#9A8467", "#8F7A5E", "#C99A3C"]))
            }
            g.fillBox(14, 40, 5, 90, Color(hex: s >= 3 ? "#C99A3C" : "#8F7A5E"))
            g.fillBox(221, 40, 5, 90, Color(hex: s >= 3 ? "#C99A3C" : "#8F7A5E"))
            let cols: [String] = ["#5DA9E8", "#F28FB8", "#6DC47A", "#F59B3D", "#AC70D8", "#41BDB3"]
            let muted: [String] = ["#8D9DB0", "#B79AA6", "#93AE96", "#BC9A74", "#A494B8", "#8DB0AC"]
            for i in 0..<5 {
                let w: CGFloat = 30
                let x = 24 + CGFloat(i) * 38
                let col = Color(hex: s >= 2 ? cols[i % 6] : muted[i % 6])
                suitcase(g, x: x, y: 38, w: w, h: 22, color: col, angle: 0, tag: s >= 2, brass: s >= 3)
                let col2 = Color(hex: s >= 2 ? cols[(i + 2) % 6] : muted[(i + 2) % 6])
                suitcase(g, x: x + 2, y: 80, w: 26, h: 20, color: col2, angle: 0, tag: s >= 2, brass: s >= 3)
            }
            if s >= 2 {
                // Shelf labels
                for i in 0..<5 {
                    g.fillBox(26 + CGFloat(i) * 38, 62, 26, 6, r: 2, Color(hex: "#FFF6E2"))
                    g.fillBox(28 + CGFloat(i) * 38, 63.5, 8, 3, r: 1, Color(hex: cols[i % 6]))
                }
            }
            // Trolley
            let brass = s >= 3
            g.fillBox(150, 112, 60, 5, r: 2, Color(hex: brass ? "#F2C14E" : "#8F8296"))
            g.strokeLine(pt(206, 112), pt(214, 90), 3, Color(hex: brass ? "#F2C14E" : "#8F8296"))
            g.fillDisc(160, 124, 5, Color(hex: "#4B4155"))
            g.fillDisc(200, 124, 5, Color(hex: "#4B4155"))
            suitcase(g, x: 158, y: 90, w: 34, h: 22, color: Color(hex: s >= 2 ? "#E5594F" : "#B07E55"), angle: 0, tag: s >= 2, brass: brass)
        } else {
            // A jumble
            let pile: [(CGFloat, CGFloat, CGFloat, CGFloat, String, Double)] = [
                (40, 108, 40, 24, "#8D7F73", -8), (92, 112, 34, 20, "#9A8467", 12), (130, 100, 38, 26, "#7C7870", 20),
                (70, 84, 36, 22, "#A08A6E", 24), (150, 126, 30, 18, "#8D7F73", -18), (176, 96, 34, 24, "#9A8467", -12),
                (24, 80, 30, 20, "#7C7870", 34)
            ]
            for p in pile {
                suitcase(g, x: p.0, y: p.1, w: p.2, h: p.3, color: Color(hex: p.4), angle: p.5, tag: false, brass: false)
            }
            // dust bunnies
            g.fillOval(200, 150, 8, 4, Color.white.opacity(0.5))
            g.fillOval(30, 150, 6, 3, Color.white.opacity(0.5))
        }
        if s >= 3 {
            for i in 0..<5 {
                let tw = 0.5 + 0.5 * sin(t * 3 + Double(i) * 1.9)
                g.sparkle(CGFloat(30 + i * 45), CGFloat(34 + (i % 3) * 30), CGFloat(2 + 3.5 * tw), Color(hex: "#FFF2B8"))
            }
        }
    }

    // MARK: Rainy Platform

    static func rainyPlatform(_ gIn: GraphicsContext, stage s: Int, t: Double, showcase: Bool) {
        let g = gIn
        g.fillBox(0, 0, 240, 180, pick(s, ["#AEB9C1", "#BBC9D1", "#C6D8DF", "#D4EAF0"]))
        // Back wall
        g.fillBox(0, 72, 240, 66, pick(s, ["#9AA4AB", "#A7B4BB", "#B3C5CC", "#BCD2D9"]))
        // Platform
        g.fillBox(0, 138, 240, 42, pick(s, ["#8C9298", "#98A0A6", "#A3AEB4", "#AEBBC1"]))
        g.fillBox(0, 138, 240, 3, Color(hex: "#F2D16B"))
        if s >= 3 {
            // Rainbow
            let arcs: [String] = ["#E5594F", "#F59B3D", "#F7D154", "#6DC47A", "#5DA9E8"]
            for (i, col) in arcs.enumerated() {
                var p = Path()
                p.addArc(center: pt(190, 70), radius: CGFloat(38 - i * 4), startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                g.stroke(p, with: .color(Color(hex: col).opacity(0.55)), lineWidth: 3.5)
            }
        }
        // Windows with window boxes (stage 3)
        for wx in [40, 150] as [CGFloat] {
            g.fillBox(wx, 84, 50, 34, r: 4, Color(hex: "#FFF1D6"))
            g.fillBox(wx + 4, 88, 42, 26, r: 3, pick(s, ["#6F7C83", "#7C8D95", "#8FB0BC", "#A8D4E0"]))
            if s >= 3 {
                g.fillBox(wx - 2, 116, 54, 9, r: 3, Color(hex: "#B07E55"))
                let petals: [String] = ["#F28FB8", "#F7D154", "#AC70D8", "#E5594F", "#F59B3D", "#F28FB8"]
                for k in 0..<6 {
                    let fx = wx + 4 + CGFloat(k) * 8.5
                    g.strokeLine(pt(fx, 118), pt(fx, 110), 1.5, Color(hex: "#4FA05F"))
                    g.fillDisc(fx, 108, 3.6, Color(hex: petals[k]))
                    g.fillDisc(fx, 108, 1.3, Color(hex: "#FFE29A"))
                }
            }
        }
        // Posts and roof
        for px in [22, 212] as [CGFloat] {
            g.fillBox(px, 62, 6, 78, Color(hex: "#5F6B72"))
        }
        let roof = pick(s, ["#6F7C83", "#76848B", "#7E8F97", "#86A0A9"])
        g.fillPoly([pt(8, 70), pt(24, 44), pt(216, 44), pt(232, 70)], roof)
        g.fillBox(8, 68, 224, 6, r: 3, pick(s, ["#58646B", "#5E6C73", "#657880", "#6E8791"]))
        if s == 0 {
            // A hole in the roof
            g.fillPoly([pt(96, 46), pt(128, 46), pt(124, 62), pt(100, 62)], Color(hex: "#2F3A40"))
        } else if s == 1 {
            // A neat patch with stitches
            g.fillBox(96, 48, 36, 18, r: 3, Color(hex: "#E98B5F"))
            for k in 0..<5 {
                g.strokeLine(pt(100 + CGFloat(k) * 7, 50), pt(100 + CGFloat(k) * 7, 54), 1.2, Color(hex: "#FFF1D6"))
            }
        } else {
            g.fillBox(96, 48, 36, 18, r: 3, Color(hex: "#E98B5F").opacity(0.9))
        }
        // Gutter and downpipe
        if s >= 2 {
            g.fillBox(8, 73, 224, 4, r: 2, Color(hex: "#8FB0BC"))
            g.fillBox(207, 76, 6, 62, Color(hex: "#8FB0BC"))
            g.fillBox(198, 120, 28, 20, r: 4, Color(hex: "#B07E55"))
            g.fillBox(198, 124, 28, 3, Color(hex: "#8A6A4E"))
            // Water stream down the pipe
            for k in 0..<4 {
                let ph = (t * 1.1 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
                g.fillDisc(210, 80 + CGFloat(ph) * 56, 1.8, Color(hex: "#5DA9E8"))
            }
        } else {
            // A crooked, dripping pipe
            g.strokeLine(pt(206, 76), pt(214, 108), 5, Color(hex: "#6F7C83"))
            g.strokeLine(pt(214, 108), pt(200, 128), 5, Color(hex: "#6F7C83"))
        }
        // Puddle under the hole
        if s == 0 {
            g.fillOval(112, 148, 26, 5, Color(hex: "#6E8EA0").opacity(0.7))
        }
        // Rain
        let drops = [30, 22, 14, 8][max(0, min(s, 3))]
        for i in 0..<drops {
            let x = CGFloat((i * 53 + 17) % 236) + 2
            let fall = (t * 70 + Double(i) * 31).truncatingRemainder(dividingBy: 90)
            let y = CGFloat(fall) - 8
            if y < 0 { continue }
            let underRoof = x > 8 && x < 232 && y > 44
            if underRoof { continue }
            g.strokeLine(pt(x, y), pt(x - 2, y + 7), 1.2, Color.white.opacity(0.55))
        }
        if s == 0 {
            for k in 0..<5 {
                let ph = (t * 1.6 + Double(k) / 5).truncatingRemainder(dividingBy: 1)
                g.strokeLine(pt(112 + CGFloat(k) * 4, 62 + CGFloat(ph) * 82), pt(112 + CGFloat(k) * 4, 66 + CGFloat(ph) * 82), 1.5, Color(hex: "#9CC4DA"))
            }
        }
        if showcase {
            for i in 0..<6 {
                let tw = 0.5 + 0.5 * sin(t * 3 + Double(i) * 1.3)
                g.sparkle(CGFloat(30 + i * 36), CGFloat(20 + (i % 2) * 14), CGFloat(2 + 3 * tw), Color(hex: "#FFFFFF"))
            }
        }
    }

    // MARK: Fallback

    static func lanternFallback(_ gIn: GraphicsContext, stage s: Int, t: Double) {
        let g = gIn
        g.fillBox(0, 0, 240, 180, Color(hex: "#F6E7CE"))
        let glow = 0.15 + 0.1 * Double(min(s, 3))
        g.fillDisc(120, 88, 56, Color(hex: "#FFD36E").opacity(glow + 0.05 * sin(t * 2)))
        g.fillBox(104, 56, 32, 56, r: 14, Color(hex: "#FFD36E"))
        g.fillBox(100, 50, 40, 8, r: 4, Color(hex: "#4B4155"))
        g.fillBox(100, 112, 40, 8, r: 4, Color(hex: "#4B4155"))
    }
}

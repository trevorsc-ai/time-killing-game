import SwiftUI

/// The Lantern Line train, drawn with vector shapes. `tier` (0...3) shows how well restored it is:
/// 0 dusty and rusty, 1 freshly painted, 2 lanterns glowing, 3 garlands and steam.
struct LanternTrainView: View {
    var tier: Int
    var animated: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animated)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                LanternTrainView.draw(&context, size: size, tier: tier, t: t)
            }
        }
        .aspectRatio(320.0 / 150.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LanternTrainView.description(tier: tier))
    }

    static func description(tier: Int) -> String {
        switch tier {
        case 0: return "The Lantern Line train, dusty and waiting to be repaired"
        case 1: return "The Lantern Line train with a fresh coat of paint"
        case 2: return "The Lantern Line train with glowing lanterns"
        default: return "The Lantern Line train, fully restored, with garlands and steam"
        }
    }

    private static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, tier: Int, t: Double) {
        let s = min(size.width / 320, size.height / 150)
        guard s > 0 else { return }
        ctx.translateBy(x: (size.width - 320 * s) / 2, y: (size.height - 150 * s) / 2)
        ctx.scaleBy(x: s, y: s)

        let restored = tier >= 1
        let body = restored ? Color(hex: "#3FB6AC") : Color(hex: "#A59A92")
        let bodyDark = restored ? Color(hex: "#2E948B") : Color(hex: "#867A72")
        let roof = restored ? Color(hex: "#E98B5F") : Color(hex: "#7C716B")
        let trim = restored ? Color(hex: "#FFF1D6") : Color(hex: "#B8AEA4")
        let wheel = Color(hex: "#4B4155")
        let hub = Color(hex: "#E8D9BD")
        let glass: Color
        if tier >= 2 { glass = Color(hex: "#FFE29A") } else if tier == 1 { glass = Color(hex: "#C5E8F0") } else { glass = Color(hex: "#6E6A74") }

        // Ground and rails
        ctx.fill(rr(0, 130, 320, 20, 0), with: .color(restored ? Color(hex: "#E9DCC2") : Color(hex: "#D9CFC0")))
        ctx.fill(rr(0, 126, 320, 4, 2), with: .color(Color(hex: "#8F8296")))
        var sx: CGFloat = 6
        while sx < 320 {
            ctx.fill(rr(sx, 131, 8, 4, 1), with: .color(Color(hex: "#A89A86")))
            sx += 16
        }

        // Two carriages
        for i in 0..<2 {
            let x = CGFloat(10 + i * 98)
            ctx.fill(rr(x + 88, 106, 12, 5, 2), with: .color(wheel))
            ctx.fill(rr(x, 56, 90, 56, 9), with: .color(body))
            ctx.fill(rr(x, 98, 90, 14, 6), with: .color(bodyDark))
            ctx.fill(rr(x - 3, 49, 96, 11, 5.5), with: .color(roof))
            ctx.fill(rr(x, 90, 90, 5, 0), with: .color(trim))
            for w in 0..<3 {
                let wx = x + 8 + CGFloat(w) * 27
                ctx.fill(rr(wx, 66, 21, 20, 5), with: .color(trim))
                if tier == 0 && i == 1 && w == 1 {
                    ctx.fill(rr(wx + 2, 68, 17, 16, 4), with: .color(Color(hex: "#55515C")))
                } else {
                    ctx.fill(rr(wx + 2, 68, 17, 16, 4), with: .color(glass))
                }
            }
            for wheelX in [x + 20, x + 70] {
                ctx.fill(circle(wheelX, 118, 10), with: .color(wheel))
                ctx.fill(circle(wheelX, 118, 4), with: .color(hub))
            }
            if restored {
                ctx.fill(rr(x + 4, 58, 82, 4, 2), with: .color(Color.white.opacity(0.28)))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: x + 10, y: 98, width: 16, height: 8)), with: .color(Color(hex: "#B5704A").opacity(0.85)))
                ctx.fill(Path(ellipseIn: CGRect(x: x + 58, y: 72, width: 12, height: 7)), with: .color(Color(hex: "#B5704A").opacity(0.7)))
            }
            if tier >= 2 {
                // Roof lantern with a soft glow
                let lx = x + 45
                ctx.fill(circle(lx, 40, 15), with: .color(Color(hex: "#FFD36E").opacity(0.28)))
                ctx.fill(rr(lx - 1.5, 44, 3, 6, 1), with: .color(wheel))
                ctx.fill(rr(lx - 5, 32, 10, 13, 4), with: .color(Color(hex: "#FFD36E")))
                ctx.fill(rr(lx - 6, 30, 12, 3, 1.5), with: .color(wheel))
            }
        }

        // Engine
        ctx.fill(rr(236, 66, 74, 44, 18), with: .color(body))
        ctx.fill(rr(236, 96, 74, 14, 7), with: .color(bodyDark))
        ctx.fill(rr(282, 42, 14, 28, 3), with: .color(restored ? Color(hex: "#4B4155") : Color(hex: "#6B6270")))
        ctx.fill(rr(278, 37, 22, 8, 4), with: .color(roof))
        ctx.fill(rr(254, 52, 18, 18, 9), with: .color(restored ? Color(hex: "#F2C14E") : Color(hex: "#B9A56B")))
        ctx.fill(rr(206, 52, 42, 58, 6), with: .color(body))
        ctx.fill(rr(202, 44, 50, 11, 5.5), with: .color(roof))
        ctx.fill(rr(214, 62, 26, 24, 5), with: .color(trim))
        ctx.fill(rr(217, 65, 20, 18, 4), with: .color(glass))
        ctx.fill(rr(236, 88, 74, 4, 0), with: .color(trim))
        ctx.fill(circle(311, 82, 7), with: .color(trim))
        if tier >= 2 {
            ctx.fill(circle(311, 82, 18), with: .color(Color(hex: "#FFD36E").opacity(0.3)))
            ctx.fill(circle(311, 82, 6), with: .color(Color(hex: "#FFD36E")))
        } else {
            ctx.fill(circle(311, 82, 5), with: .color(restored ? Color(hex: "#F6E3A8") : Color(hex: "#8A8078")))
        }
        var catcher = Path()
        catcher.move(to: CGPoint(x: 304, y: 112))
        catcher.addLine(to: CGPoint(x: 318, y: 126))
        catcher.addLine(to: CGPoint(x: 298, y: 126))
        catcher.closeSubpath()
        ctx.fill(catcher, with: .color(roof))
        for wheelX in [222, 258, 292] as [CGFloat] {
            let r: CGFloat = wheelX == 222 ? 13 : 11
            ctx.fill(circle(wheelX, 126 - r + 1, r), with: .color(wheel))
            ctx.fill(circle(wheelX, 126 - r + 1, 4.5), with: .color(hub))
        }
        if restored {
            ctx.fill(rr(240, 70, 60, 4, 2), with: .color(Color.white.opacity(0.28)))
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: 244, y: 76, width: 18, height: 9)), with: .color(Color(hex: "#B5704A").opacity(0.8)))
            ctx.fill(Path(ellipseIn: CGRect(x: 210, y: 94, width: 14, height: 8)), with: .color(Color(hex: "#B5704A").opacity(0.7)))
        }

        // Garlands (tier 3)
        if tier >= 3 {
            let flags: [Color] = [Color(hex: "#F28FB8"), Color(hex: "#F7D154"), Color(hex: "#5DA9E8"), Color(hex: "#6DC47A")]
            var line = Path()
            line.move(to: CGPoint(x: 8, y: 46))
            line.addQuadCurve(to: CGPoint(x: 100, y: 46), control: CGPoint(x: 54, y: 62))
            line.addQuadCurve(to: CGPoint(x: 198, y: 46), control: CGPoint(x: 150, y: 62))
            ctx.stroke(line, with: .color(Color(hex: "#8F8296")), lineWidth: 1.2)
            for i in 0..<10 {
                let f = CGFloat(i) / 9
                let x: CGFloat = 16 + f * 176
                let seg: CGFloat = f < 0.5 ? f * 2 : (f - 0.5) * 2
                let dip: CGFloat = pow(2 * seg - 1, 2)
                let y: CGFloat = 47 + 8 * (1 - dip)
                var flag = Path()
                flag.move(to: CGPoint(x: x - 4, y: y))
                flag.addLine(to: CGPoint(x: x + 4, y: y))
                flag.addLine(to: CGPoint(x: x, y: y + 9))
                flag.closeSubpath()
                ctx.fill(flag, with: .color(flags[i % flags.count]))
            }
        }

        // Steam
        if tier >= 1 {
            let puffs = tier >= 3 ? 5 : 3
            for i in 0..<puffs {
                let phase = (t * 0.45 + Double(i) / Double(puffs)).truncatingRemainder(dividingBy: 1)
                let ph = CGFloat(phase)
                let wobble = CGFloat(sin(phase * 6 + Double(i)))
                let px: CGFloat = 289 + ph * 26 + wobble * 3
                let py: CGFloat = 34 - ph * 34
                let pr: CGFloat = 4 + ph * 8
                let opacity = (1 - phase) * (tier >= 3 ? 0.7 : 0.45)
                ctx.fill(circle(px, py, pr), with: .color(Color.white.opacity(opacity)))
            }
        }
    }
}

/// A brief in-app splash: the train puffs in from the left (about 0.9 s). It never blocks touches and is skipped
/// when Reduce Motion is on.
struct SplashView: View {
    let onFinish: () -> Void
    @Environment(\.theme) private var theme
    @State private var offset: CGFloat = -1.2
    @State private var opacity: Double = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    LanternTrainView(tier: 2, animated: true)
                        .frame(width: min(geo.size.width * 0.8, 380))
                        .offset(x: offset * geo.size.width)
                    Text("Puzzle Getaway")
                        .font(Theme.font(.title, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { offset = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                withAnimation(.easeIn(duration: 0.25)) { opacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) { onFinish() }
        }
    }
}

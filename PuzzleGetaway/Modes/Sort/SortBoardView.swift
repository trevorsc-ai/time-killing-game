import SwiftUI

extension SortFrame {
    func at(_ t: Double) -> SortFrame {
        var f = self
        f.time = t
        return f
    }
}

/// The board shown by the shell for Liquid and Bolt levels: a Canvas drawing plus one accessible, tappable element per
/// tube/bolt. Sizes itself to whatever space it is given (1 or 2 rows depending on count and aspect ratio).
struct SortBoardView: View {
    @ObservedObject var controller: SortController
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let layout = SortLayout.make(caps: controller.rules.caps, size: geo.size, variant: controller.variant)
            ZStack(alignment: .topLeading) {
                boardCanvas(size: geo.size, layout: layout)
                ForEach(0..<layout.rects.count, id: \.self) { i in
                    tubeTarget(i, layout: layout)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 260)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sortBoard")
    }

    @ViewBuilder
    private func boardCanvas(size: CGSize, layout: SortLayout) -> some View {
        let isDark = colorScheme == .dark
        let base = controller.makeFrame(time: Date().timeIntervalSinceReferenceDate, isDark: isDark, theme: theme)
        if controller.needsFrames {
            TimelineView(.animation) { timeline in
                drawing(frame: base.at(timeline.date.timeIntervalSinceReferenceDate), layout: layout)
            }
        } else {
            drawing(frame: base, layout: layout)
        }
    }

    private func drawing(frame: SortFrame, layout: SortLayout) -> some View {
        let variant = controller.variant
        return Canvas { context, size in
            switch variant {
            case .liquid: LiquidRenderer.draw(context, size: size, layout: layout, frame: frame)
            case .bolt: BoltRenderer.draw(context, size: size, layout: layout, frame: frame)
            }
        }
        .accessibilityHidden(true)
    }

    private func tubeTarget(_ i: Int, layout: SortLayout) -> some View {
        let r = layout.rects[i]
        let u = layout.unit
        let width = max(u * 1.12, Theme.minTapTarget)
        let height = max(r.height + u * 0.7, Theme.minTapTarget)
        return Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { controller.tap(i) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(controller.accessibilityLabel(forTube: i))
            .accessibilityHint(controller.accessibilityHint(forTube: i))
            .accessibilityValue(controller.selected == i ? "Selected" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("sortTube\(i)")
            .position(x: r.midX, y: r.midY - u * 0.25)
    }
}

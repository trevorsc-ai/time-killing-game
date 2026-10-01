import SwiftUI

/// The Lantern Line route: eight stops along a winding track. Tap a stop for its intro (first time) and level list.
struct MapView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.theme) private var theme
    @StateObject private var toast = ToastCenter()
    @State private var intro: Destination?
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 150

    private let nodeSize: CGFloat = 72
    private let edgeInset: CGFloat = 22

    private var destinations: [Destination] { model.progression.destinations }

    /// First open stop that still has levels to play (where the train is parked).
    private var currentStopId: String? {
        for d in destinations where model.progression.isDestinationUnlocked(d.id, save: model.save) {
            if model.progression.hasLevels(d.id) && !model.progression.isDestinationComplete(d.id, save: model.save) {
                return d.id
            }
        }
        return destinations.first(where: { model.progression.isDestinationUnlocked($0.id, save: model.save) })?.id
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(destinations.enumerated()), id: \.element.id) { index, dest in
                            stopRow(index: index, dest: dest)
                                .frame(height: rowHeight)
                                .id(dest.id)
                        }
                    }
                    .background(trackBackground)
                    .padding(.horizontal, edgeInset)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    if let id = currentStopId {
                        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }

            if let message = toast.message {
                ToastView(text: message)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
            if let dest = intro {
                introOverlay(dest)
            }
        }
        .animation(model.settings.effectiveReduceMotion ? nil : .easeInOut(duration: 0.2), value: toast.message)
        .screenBackground()
        .navigationTitle("Lantern Line Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Track

    private func nodeCenterX(_ index: Int, width: CGFloat) -> CGFloat {
        index % 2 == 0 ? nodeSize / 2 : width - nodeSize / 2
    }

    private var trackBackground: some View {
        let count = destinations.count
        let openFlags: [Bool] = destinations.map { model.progression.isDestinationUnlocked($0.id, save: model.save) }
        let height = rowHeight
        let node = nodeSize
        return Canvas { context, size in
            guard count > 1 else { return }
            var points: [CGPoint] = []
            for i in 0..<count {
                let x: CGFloat = i % 2 == 0 ? node / 2 : size.width - node / 2
                points.append(CGPoint(x: x, y: CGFloat(i) * height + height / 2))
            }
            for i in 0..<(count - 1) {
                let a = points[i]
                let b = points[i + 1]
                var seg = Path()
                seg.move(to: a)
                seg.addCurve(to: b,
                             control1: CGPoint(x: a.x, y: a.y + height * 0.62),
                             control2: CGPoint(x: b.x, y: b.y - height * 0.62))
                let lit = openFlags[i + 1]
                let bed: Color = lit ? theme.accent.opacity(0.35) : theme.stroke
                context.stroke(seg, with: .color(bed), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                context.stroke(seg, with: .color(theme.background),
                               style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [4, 9]))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Stop rows

    private func stopRow(index: Int, dest: Destination) -> some View {
        let unlocked = model.progression.isDestinationUnlocked(dest.id, save: model.save)
        let hasLevels = model.progression.hasLevels(dest.id)
        let complete = model.progression.isDestinationComplete(dest.id, save: model.save)
        let stars = model.progression.stars(in: dest.id, save: model.save)
        let maxStars = model.progression.maxStars(in: dest.id)
        let done = model.progression.completedCount(in: dest.id, save: model.save)
        let total = model.progression.levels(in: dest.id).count
        let isCurrent = currentStopId == dest.id
        let leading = index % 2 == 0

        let node = ZStack {
            Circle()
                .fill(unlocked ? Color(hex: dest.theme.primary) : theme.surfaceAlt)
                .frame(width: nodeSize, height: nodeSize)
                .overlay(Circle().stroke(complete ? theme.success : theme.stroke, lineWidth: complete ? 4 : theme.strokeWidth))
                .shadow(color: Color.black.opacity(unlocked ? 0.15 : 0.04), radius: 6, x: 0, y: 3)
            Image(systemName: unlocked ? DestinationInfo.icon(for: dest.id) : (dest.comingSoon ? "hourglass" : "lock.fill"))
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(unlocked ? Color.white : theme.textSecondary)
            if isCurrent {
                Image(systemName: "tram.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(theme.accentText)
                    .padding(6)
                    .background(Circle().fill(theme.accent))
                    .offset(x: leading ? 28 : -28, y: -30)
            }
        }
        .frame(width: nodeSize, height: nodeSize)

        let text = VStack(alignment: leading ? .leading : .trailing, spacing: 3) {
            Text(dest.name)
                .font(Theme.font(.headline, weight: .bold))
                .foregroundColor(unlocked || dest.comingSoon ? theme.textPrimary : theme.textSecondary)
                .multilineTextAlignment(leading ? .leading : .trailing)
            statusLine(dest: dest, unlocked: unlocked, hasLevels: hasLevels, stars: stars, maxStars: maxStars,
                       done: done, total: total)
        }
        .frame(maxWidth: 230, alignment: leading ? .leading : .trailing)

        return Button {
            tap(dest)
        } label: {
            HStack(spacing: 14) {
                if leading {
                    node
                    text
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    text
                    node
                }
            }
            .frame(minHeight: nodeSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(dest: dest, unlocked: unlocked, hasLevels: hasLevels,
                                              stars: stars, maxStars: maxStars, done: done, total: total))
        .accessibilityHint(unlocked ? "Opens this stop" : "")
        .accessibilityIdentifier("destination-\(dest.id)")
    }

    @ViewBuilder
    private func statusLine(dest: Destination, unlocked: Bool, hasLevels: Bool,
                            stars: Int, maxStars: Int, done: Int, total: Int) -> some View {
        if dest.comingSoon {
            Text("Coming soon")
                .font(Theme.caption).foregroundColor(theme.textSecondary)
        } else if !unlocked {
            Text(lockedHint(for: dest))
                .font(Theme.caption).foregroundColor(theme.textSecondary)
        } else if !hasLevels {
            Text("Track being laid…")
                .font(Theme.caption).foregroundColor(theme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundColor(theme.warning).font(.caption)
                    Text("\(stars) / \(maxStars)")
                        .font(Theme.font(.footnote, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }
                Text("\(done) of \(total) levels")
                    .font(Theme.caption).foregroundColor(theme.textSecondary)
            }
        }
    }

    private func lockedHint(for dest: Destination) -> String {
        guard let prev = model.progression.previousDestination(before: dest.id) else { return "Locked" }
        return "Finish \(model.progression.unlockPercent)% of \(prev.name)"
    }

    private func accessibilityText(dest: Destination, unlocked: Bool, hasLevels: Bool,
                                   stars: Int, maxStars: Int, done: Int, total: Int) -> String {
        if dest.comingSoon { return "\(dest.name), coming soon" }
        if !unlocked { return "\(dest.name), locked. \(lockedHint(for: dest))" }
        if !hasLevels { return "\(dest.name). The track is still being laid." }
        return "\(dest.name). \(stars) of \(maxStars) stars. \(done) of \(total) levels done."
    }

    private func tap(_ dest: Destination) {
        model.haptics.selection()
        if dest.comingSoon {
            toast.show("\(dest.name) is still being built. Check back soon!")
            return
        }
        if !model.progression.isDestinationUnlocked(dest.id, save: model.save) {
            toast.show("\(lockedHint(for: dest)) to open this stop.")
            return
        }
        if model.save.tutorialsSeen.contains("intro.\(dest.id)") {
            router.push(.levelSelect(destinationId: dest.id))
        } else {
            intro = dest
        }
    }

    // MARK: Intro card

    private func introOverlay(_ dest: Destination) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { intro = nil }
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Image(systemName: DestinationInfo.icon(for: dest.id))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(Color.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color(hex: dest.theme.primary)))
                Text(dest.name)
                    .font(Theme.heading)
                    .foregroundColor(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(dest.intro)
                    .font(Theme.body)
                    .foregroundColor(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("All aboard") {
                    model.markTutorialSeen("intro.\(dest.id)")
                    intro = nil
                    router.push(.levelSelect(destinationId: dest.id))
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("introContinue")
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius + 6, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 8)
            .padding(24)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

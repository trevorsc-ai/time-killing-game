import SwiftUI

// Mode plugins for Liquid Sort ("Color Mixer") and Bolt Sort ("Tool Bench"). Both share `SortRules`,
// `SortController` and the Canvas board; only the variant (vocabulary and renderer) differs.

enum LiquidMode: PuzzleModePlugin {
    static let mode = "liquid"
    static let displayName = "Color Mixer"

    @MainActor
    static func makeController(level: LevelEnvelope, snapshot: Data?, context: GameContext) -> AnyGameController {
        SortSupport.makeController(variant: .liquid, level: level, snapshot: snapshot, context: context)
    }

    static func replay(level: LevelEnvelope) throws -> Bool {
        try SortSupport.replay(level: level, variant: .liquid)
    }
}

enum BoltMode: PuzzleModePlugin {
    static let mode = "bolt"
    static let displayName = "Tool Bench"

    @MainActor
    static func makeController(level: LevelEnvelope, snapshot: Data?, context: GameContext) -> AnyGameController {
        SortSupport.makeController(variant: .bolt, level: level, snapshot: snapshot, context: context)
    }

    static func replay(level: LevelEnvelope) throws -> Bool {
        try SortSupport.replay(level: level, variant: .bolt)
    }
}

enum SortSupport {
    @MainActor
    static func makeController(variant: SortVariant, level: LevelEnvelope, snapshot: Data?, context: GameContext) -> AnyGameController {
        let payload = (try? level.decodePayload(SortPayload.self))
            ?? SortPayload(capacity: 2, tubes: [["r", "r"], ["r", "r"], []])
        let rules = SortRules(payload: payload, variant: variant)
        let solution = (try? level.decodeSolution(SortMove.self)) ?? []
        let session = GameSession(rules: rules, initial: SortRules.initialState(payload), solution: solution)
        if let snapshot = snapshot { session.restore(from: snapshot) }
        return SortController(level: level, variant: variant, payload: payload, session: session, context: context)
    }

    static func replay(level: LevelEnvelope, variant: SortVariant) throws -> Bool {
        let payload = try level.decodePayload(SortPayload.self)
        let rules = SortRules(payload: payload, variant: variant)
        var state = SortRules.initialState(payload)
        for move in try level.decodeSolution(SortMove.self) {
            if rules.isSolved(state) { return false }
            guard let next = rules.apply(move, to: state) else { return false }
            state = next
        }
        return rules.isSolved(state)
    }
}

// MARK: - Controller

@MainActor
final class SortController: SessionController<SortRules> {
    let variant: SortVariant
    let payload: SortPayload
    let paletteMap: [String: PaletteColor]
    /// First stored solution move on tutorial levels: the board points at it until the player moves.
    let tutorialMove: SortMove?

    // UI-only state (not part of the saved snapshot).
    @Published private(set) var selected: Int?
    @Published private(set) var previousSelected: Int?
    @Published private(set) var anim: SortPourAnim?
    @Published private(set) var shakeTube: Int?
    @Published private(set) var sparkles: [Int: Double] = [:]
    @Published private(set) var unlocks: [Int: SortUnlockEvent] = [:]
    @Published private(set) var solvedAt: Double?
    @Published private(set) var isAnimating = false
    private(set) var selectionTime: Double = 0
    private(set) var shakeStart: Double = 0
    private var animDeadline: Double = 0
    private var hasMoved = false
    private var checkTask: Task<Void, Never>?

    init(level: LevelEnvelope, variant: SortVariant, payload: SortPayload, session: GameSession<SortRules>, context: GameContext) {
        self.variant = variant
        self.payload = payload
        var map: [String: PaletteColor] = [:]
        for c in context.palette.colors { map[c.id] = c }
        self.paletteMap = map
        if level.tutorial != nil, let first = (try? level.decodeSolution(SortMove.self))?.first {
            self.tutorialMove = first
        } else {
            self.tutorialMove = nil
        }
        super.init(levelId: level.id, title: level.title, session: session, context: context)
    }

    var rules: SortRules { session.rules }

#if DEBUG
    override func debugSolveStep() {
        let solution = session.storedSolution
        guard !session.isSolved, session.moveCount < solution.count else { return }
        performPour(solution[session.moveCount])
    }
#endif

    /// Fraction of colors that are fully gathered into one pure tube.
    override var progress: Double? {
        var totals: [String: Int] = [:]
        for t in payload.tubes { for c in t { totals[c, default: 0] += 1 } }
        guard !totals.isEmpty else { return nil }
        var done = 0
        for t in session.state.tubes {
            guard let first = t.first, !first.hidden else { continue }
            if t.allSatisfy({ $0.c == first.c && !$0.hidden }), t.count == totals[first.c] { done += 1 }
        }
        return min(1, Double(done) / Double(totals.count))
    }

    private var now: Double { Date().timeIntervalSinceReferenceDate }

    var tutorialActive: Bool {
        tutorialMove != nil && !hasMoved && session.moveCount == 0 && !session.isSolved
    }

    /// True while the board needs continuous redraws (animations, pulsing hint or tutorial pointer).
    var needsFrames: Bool {
        if isAnimating { return true }
        if context.settings.effectiveReduceMotion { return false }
        return session.activeHint != nil || tutorialActive
    }

    // MARK: Interaction

    /// Tap on tube/bolt `i`: pick it up, pour into it, put it back, or reject the tap.
    func tap(_ i: Int) {
        let state = session.state
        guard !session.isSolved, state.tubes.indices.contains(i) else { return }
        if let from = selected {
            if from == i {
                setSelection(nil)
                context.haptics.selection()
                return
            }
            let move = SortMove(from: from, to: i)
            if rules.apply(move, to: state) != nil {
                performPour(move)
            } else {
                reject(i)
            }
        } else if rules.canSource(state, from: i) {
            setSelection(i)
            context.haptics.selection()
        } else {
            reject(i)
        }
    }

    private func reject(_ i: Int) {
        context.haptics.invalid()
        guard !context.settings.effectiveReduceMotion else { return }
        shakeTube = i
        shakeStart = now
        touchEffects(duration: 0.45)
    }

    private func setSelection(_ i: Int?) {
        if selected == i { return }
        previousSelected = selected
        selected = i
        selectionTime = now
        touchEffects(duration: 0.3)
    }

    private func performPour(_ move: SortMove) {
        let pre = session.state
        let count = rules.transferCount(move, in: pre)
        let color = pre.tubes[move.from].last?.c ?? ""
        guard attempt(move) else { return }
        let post = session.state
        hasMoved = true
        setSelection(nil)

        var endTime = now
        if !context.settings.effectiveReduceMotion {
            let base = context.settings.duration(1.0)
            var duration = 1.35 * base
            var stagger = 0.0
            var nutDuration = 0.0
            if variant == .bolt {
                nutDuration = 0.80 * base
                stagger = 0.13 * base
                duration = nutDuration + stagger * Double(max(count - 1, 0))
            }
            anim = SortPourAnim(from: move.from, to: move.to, count: count, color: color, start: now, duration: duration,
                                stagger: stagger, nutDuration: nutDuration, pre: pre, post: post)
            endTime = now + duration
            touchEffects(duration: duration + 0.1)
        } else {
            anim = nil
        }

        for i in post.tubes.indices {
            if rules.isComplete(post, tube: i) && !rules.isComplete(pre, tube: i) {
                sparkles[i] = endTime
            }
            if !pre.locks[i].isEmpty && post.locks[i].isEmpty {
                unlocks[i] = SortUnlockEvent(color: pre.locks[i], start: endTime)
            }
        }
        if session.isSolved {
            solvedAt = endTime + 0.1
        }
        if !context.settings.effectiveReduceMotion && (!sparkles.isEmpty || solvedAt != nil || !unlocks.isEmpty) {
            touchEffects(duration: (endTime - now) + 2.0)
        }
    }

    private func clearTransient() {
        selected = nil
        previousSelected = nil
        anim = nil
        sparkles = [:]
        unlocks = [:]
        solvedAt = nil
        shakeTube = nil
    }

    override func undo() {
        clearTransient()
        super.undo()
    }

    override func restart() {
        clearTransient()
        super.restart()
    }

    // MARK: Effect clock

    private func touchEffects(duration: Double) {
        let until = now + duration + 0.05
        if until > animDeadline { animDeadline = until }
        if !isAnimating { isAnimating = true }
        scheduleEffectCheck()
    }

    private func scheduleEffectCheck() {
        checkTask?.cancel()
        let delay = max(0.02, animDeadline - now)
        checkTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            self?.effectsMayHaveExpired()
        }
    }

    private func effectsMayHaveExpired() {
        if now >= animDeadline - 0.01 {
            isAnimating = false
            anim = nil
            shakeTube = nil
            sparkles = [:]
            unlocks = [:]
        } else {
            scheduleEffectCheck()
        }
    }

    // MARK: Rendering input

    func makeFrame(time: Double, isDark: Bool, theme: Theme) -> SortFrame {
        let st = session.state
        let r = rules
        let reduce = context.settings.effectiveReduceMotion
        return SortFrame(
            variant: variant,
            state: st,
            caps: r.caps,
            anim: anim,
            time: time,
            selected: selected,
            previousSelected: previousSelected,
            selectionTime: selectionTime,
            topRunLength: st.tubes.indices.map { r.topRun(st, tube: $0) },
            shakeTube: shakeTube,
            shakeStart: shakeStart,
            hint: session.activeHint,
            tutorial: tutorialActive ? tutorialMove : nil,
            sparkles: sparkles,
            unlocks: unlocks,
            solvedAt: solvedAt,
            complete: st.tubes.indices.map { r.isComplete(st, tube: $0) },
            reduceMotion: reduce,
            showPatterns: context.settings.showPatterns,
            highContrast: context.settings.highContrast,
            isDark: isDark,
            palette: paletteMap,
            hintColor: theme.warning,
            successColor: theme.success,
            accentColor: theme.accent
        )
    }

    // MARK: Accessibility

    private func colorName(_ id: String) -> String { paletteMap[id]?.name ?? id }

    private func layerName(_ l: SortLayer) -> String {
        if l.hidden { return "hidden" }
        var name = colorName(l.c)
        if variant == .bolt { name += " nut" }
        if !l.rust.isEmpty { name += " (rusty until \(colorName(l.rust)) is complete)" }
        return name
    }

    func accessibilityLabel(forTube i: Int) -> String {
        let st = session.state
        guard st.tubes.indices.contains(i) else { return "" }
        let tube = st.tubes[i]
        let cap = rules.caps[i]
        var label = "\(variant.containerWord) \(i + 1): "
        if tube.isEmpty {
            label += "empty"
        } else {
            var names = tube.map { layerName($0) }
            names[names.count - 1] += " on top"
            label += names.joined(separator: ", ")
        }
        let space = cap - tube.count
        label += ", \(space) \(space == 1 ? "space" : "spaces")"
        if !st.locks[i].isEmpty { label += ", locked until \(colorName(st.locks[i])) is complete" }
        if let maxCap = rules.caps.max(), cap < maxCap { label += ", capped at \(cap)" }
        if rules.isComplete(st, tube: i) { label += ", complete" }
        return label
    }

    func accessibilityHint(forTube i: Int) -> String {
        let st = session.state
        if let from = selected {
            return from == i ? "Double tap to put it back" : "Double tap to pour here"
        }
        return rules.canSource(st, from: i) ? "Double tap to pick up" : ""
    }

    override var accessibilitySummary: String {
        session.state.tubes.indices.map { accessibilityLabel(forTube: $0) }.joined(separator: ". ")
    }

    override var boardView: AnyView {
        AnyView(SortBoardView(controller: self))
    }
}

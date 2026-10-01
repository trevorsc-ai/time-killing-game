import SwiftUI

/// Loads a level's controller and hosts the in-game screen. Also swaps levels in place (Next level, Replay).
struct GameScreen: View {
    let levelId: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.theme) private var theme
    @State private var level: LevelEnvelope?
    @State private var controller: AnyGameController?
    @State private var hostToken = UUID()
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let level = level, let controller = controller {
                GameHost(level: level, controller: controller, onLoad: { load($0.id) })
                    .id(hostToken)
            } else if loadFailed {
                VStack(spacing: 14) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 36))
                        .foregroundColor(theme.accent)
                    Text("This puzzle isn't ready yet")
                        .font(Theme.heading)
                        .foregroundColor(theme.textPrimary)
                    Text("The Parcel Pals are still working on it.")
                        .font(Theme.body)
                        .foregroundColor(theme.textSecondary)
                    Button("Go back") { router.pop() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("backButton")
                }
                .padding()
            } else {
                Text("Loading...")
                    .font(Theme.body)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if controller == nil { load(levelId) }
        }
    }

    private func load(_ id: String) {
        guard let found = model.progression.level(id: id) ?? model.content?.level(id: id),
              let made = model.makeController(for: found) else {
            loadFailed = true
            return
        }
        loadFailed = false
        level = found
        controller = made
        hostToken = UUID()
    }
}

/// The playing surface: top bar, board, thumb bar, tips, stuck card, pause and completion overlays.
struct GameHost: View {
    let level: LevelEnvelope
    @ObservedObject var controller: AnyGameController
    let onLoad: (LevelEnvelope) -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var showPause = false
    @State private var confirmLeave = false
    @State private var confirmRestart = false
    @State private var tip: TipCard?
    @State private var outcome: AppModel.CompletionOutcome?
    @State private var summary: CompletionSummary?
    @State private var handledSolve = false

    private var kind: PlayKind { PlayKind(level: level) }
    private var destination: Destination? { model.progression.destination(level.destination) }
    private var settings: Settings { model.settings }

    var body: some View {
        GeometryReader { geo in
            let wide = hSize == .regular && geo.size.width > geo.size.height
            ZStack {
                if wide {
                    HStack(spacing: 0) {
                        mainColumn
                        GameSidePanel(controller: controller, level: level, kind: kind, destination: destination,
                                      stageCount: stageCount, stars: destinationStars, nextStageText: nextStageText)
                            .frame(width: min(340, geo.size.width * 0.3))
                    }
                } else {
                    mainColumn
                }
                if controller.isStuck && !controller.isSolved && summary == nil && !showPause {
                    VStack {
                        Spacer()
                        StuckCardView(title: stuckTitle, canUndo: controller.canUndo,
                                      onUndo: { controller.undo() },
                                      onRestart: { controller.restart() })
                            .frame(maxWidth: 420)
                            .padding(.horizontal, Theme.spacing)
                            .padding(.bottom, 96)
                    }
                    .transition(.opacity)
                }
                if showPause {
                    PauseMenuView(levelSelectTitle: levelSelectTitle,
                                  onResume: { showPause = false },
                                  onRestart: { showPause = false; controller.restart() },
                                  onSettings: { showPause = false; leaveSaving { router.push(.settings) } },
                                  onLevelSelect: { showPause = false; goToLevelSelect() },
                                  onMainMenu: { showPause = false; leaveSaving { router.popToRoot() } })
                        .transition(.opacity)
                }
                if let summary = summary {
                    LevelCompleteView(summary: summary, settings: settings,
                                      onNext: { goNext() },
                                      onReplay: { replay() },
                                      onMap: { goToLevelSelectOrMap() },
                                      onRestoration: { goToRestoration() })
                        .transition(.opacity)
                }
            }
            .animation(settings.effectiveReduceMotion ? nil : .easeInOut(duration: 0.25), value: showPause)
            .animation(settings.effectiveReduceMotion ? nil : .easeInOut(duration: 0.3), value: summary == nil)
            .animation(settings.effectiveReduceMotion ? nil : .easeInOut(duration: 0.25), value: controller.isStuck)
        }
        .confirmationDialog("Leave this puzzle?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave puzzle") { leaveSaving { router.pop() } }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("Your progress is saved. You can pick it up again from Continue.")
        }
        .confirmationDialog("Restart this puzzle?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { controller.restart() }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("Your moves will be cleared. The puzzle starts over from the beginning.")
        }
        .onAppear { prepareTip() }
        .onDisappear { model.persistSnapshot(of: controller) }
        .onChange(of: controller.isSolved) { solved in
            if solved { handleSolved() }
        }
        .onChange(of: controller.moveCount) { _ in
            if tip != nil { dismissTip(chain: false) }
        }
    }

    // MARK: Layout pieces

    private var mainColumn: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 6)
                .padding(.bottom, 6)
#if DEBUG
            if TestHooks.enabled {
                // Invisible but fully hittable: plays the next stored-solution move (UI tests only).
                Button { controller.debugSolveStep() } label: {
                    Color.clear.frame(width: 120, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Solve step")
                .accessibilityIdentifier("solveStep")
            }
#endif
            if let fraction = controller.progress {
                HUDProgressBar(fraction: fraction, reduceMotion: settings.effectiveReduceMotion)
                    .padding(.horizontal, Theme.spacing + 4)
                    .padding(.bottom, 6)
                    .frame(maxWidth: 560)
            }
            if let tip = tip {
                TipCardView(tip: tip, onDismiss: { dismissTip(chain: true) }, onHideTips: hideTips)
                    .padding(.horizontal, Theme.spacing)
                    .padding(.bottom, 6)
                    .frame(maxWidth: 560)
                    .transition(.opacity)
            }
            controller.boardView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
            bottomBar
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var levelLabel: String {
        switch kind {
        case .campaign: return "Level \(level.order)"
        case .relax(let pool): return "Relax · \(Progression.relaxTitle(pool: pool))"
        case .daily: return "Daily Journey"
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HUDIconButton(systemImage: "chevron.left", label: "Back", identifier: "backButton") { backTapped() }
            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(levelLabel)
                    .font(Theme.font(.caption, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                Text(controller.title)
                    .font(Theme.font(.headline, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if settings.showMoveCounter {
                Text("Moves \(controller.moveCount)")
                    .font(Theme.font(.footnote, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.surfaceAlt))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Moves")
                    .accessibilityValue("\(controller.moveCount)")
                    .accessibilityIdentifier("moveCounter")
            }
            HUDIconButton(systemImage: "pause.fill", label: "Pause", identifier: "pauseButton") { showPause = true }
        }
    }

    private var bottomBar: some View {
        let undo = HUDActionButton(systemImage: "arrow.uturn.backward", title: "Undo", identifier: "undoButton",
                                   enabled: controller.canUndo && !controller.isSolved,
                                   hint: "Takes back your last move") { controller.undo() }
        let restart = HUDActionButton(systemImage: "arrow.counterclockwise", title: "Restart", identifier: "restartButton",
                                      enabled: !controller.isSolved,
                                      hint: "Starts this puzzle over") { restartTapped() }
        let hint = HUDActionButton(systemImage: "lightbulb.fill", title: "Hint", identifier: "hintButton",
                                   enabled: !controller.isSolved,
                                   hint: "Highlights a helpful move") { controller.requestHint() }
        return HStack(spacing: 12) {
            if settings.leftHanded {
                hint
                restart
                undo
            } else {
                undo
                restart
                hint
            }
        }
        .frame(maxWidth: 520)
    }

    private var stuckTitle: String {
        level.mode == "pixel" ? "The Pals are jammed" : "No moves left"
    }

    private var levelSelectTitle: String {
        switch kind {
        case .campaign: return "Level select"
        case .relax: return "Relax menu"
        case .daily: return "Daily Journey"
        }
    }

    // MARK: Restoration info (side panel)

    private var destinationStars: Int { model.progression.stars(in: level.destination, save: model.save) }
    private var stageCount: Int { model.progression.unlockedStageCount(in: level.destination, save: model.save) }
    private var nextStageText: String? {
        guard let next = model.progression.nextStage(in: level.destination, save: model.save) else { return nil }
        let more = max(0, next.starsRequired - destinationStars)
        return "\(more) more \(more == 1 ? "star" : "stars") for \u{201C}\(next.title)\u{201D}"
    }

    // MARK: Tips

    private func prepareTip() {
        guard tip == nil, summary == nil, settings.showTips, let content = model.content else { return }
        tip = TipLibrary.pending(for: level, seen: model.save.tutorialsSeen, content: content)
    }

    private func dismissTip(chain: Bool) {
        if let current = tip { model.markTutorialSeen(current.key) }
        tip = nil
        if chain { prepareTip() }
    }

    private func hideTips() {
        if let current = tip { model.markTutorialSeen(current.key) }
        settings.showTips = false
        tip = nil
    }

    // MARK: Actions

    private func backTapped() {
        if controller.moveCount > 0 && !controller.isSolved {
            confirmLeave = true
        } else {
            leaveSaving { router.pop() }
        }
    }

    private func restartTapped() {
        if controller.moveCount >= 3 && !controller.isSolved {
            confirmRestart = true
        } else {
            controller.restart()
        }
    }

    /// Stores the snapshot, then runs the navigation.
    private func leaveSaving(_ navigate: () -> Void) {
        model.persistSnapshot(of: controller)
        navigate()
    }

    private func goToLevelSelect() {
        leaveSaving { goToLevelSelectOrMap() }
    }

    private func goToLevelSelectOrMap() {
        switch kind {
        case .campaign:
            if destination != nil {
                router.set([.map, .levelSelect(destinationId: level.destination)])
            } else {
                router.popToRoot()
            }
        case .relax:
            router.set([.relax])
        case .daily:
            router.set([.daily])
        }
    }

    private func goToRestoration() {
        guard destination != nil else { return }
        router.set([.map, .levelSelect(destinationId: level.destination), .restoration(destinationId: level.destination)])
    }

    private func replay() {
        summary = nil
        handledSolve = false
        onLoad(level)
    }

    private func goNext() {
        switch kind {
        case .campaign:
            if let next = model.progression.nextLevel(after: level) {
                summary = nil
                onLoad(next)
            } else {
                goToLevelSelectOrMap()
            }
        case .relax(let pool):
            if let next = model.progression.currentRelaxEntry(pool: pool, save: model.save) {
                summary = nil
                onLoad(next)
            } else {
                goToLevelSelectOrMap()
            }
        case .daily:
            goToLevelSelectOrMap()
        }
    }

    // MARK: Solving

    private func handleSolved() {
        guard !handledSolve else { return }
        handledSolve = true
        tip = nil
        let stars = controller.stars
        let moves = controller.moveCount
        var newStages: [RestorationStage] = []
        var unlocked: Destination?
        switch kind {
        case .campaign:
            let result = model.recordCompletion(levelId: level.id, stars: stars, moves: moves)
            outcome = result
            newStages = result.newStages
            unlocked = result.unlockedDestination
        case .relax:
            model.completeRelax(level: level)
        case .daily:
            model.completeDaily(level: level)
        }
        let hasNext: Bool
        switch kind {
        case .campaign: hasNext = model.progression.nextLevel(after: level) != nil
        case .relax(let pool): hasNext = model.progression.currentRelaxEntry(pool: pool, save: model.save) != nil
        case .daily: hasNext = false
        }
        let built = CompletionSummary(kind: kind, level: level, stars: stars, moves: moves,
                                      hintsUsed: controller.hintsUsed, undoCount: controller.undoCount,
                                      newStages: newStages, unlockedDestination: unlocked,
                                      journeysTaken: model.save.dailyJourneysTaken.count, hasNext: hasNext)
        // Let the board's own flourish play first, then show the card.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            // The mode already played the success haptic at the moment of solving; no second buzz here.
            summary = built
        }
    }
}

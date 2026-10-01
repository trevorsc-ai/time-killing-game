import SwiftUI
import Combine

/// Type-erased controller the shell (HUD, containers) binds to. One instance per played level.
///
/// Modes either subclass `AnyGameController` directly or (recommended) use `SessionController<R>`,
/// which wraps a `GameSession<R>`. The shell only ever sees this base class.
///
/// Contract: any property that changes must trigger `objectWillChange` (SessionController forwards the
/// session's changes automatically). `snapshot()` must return data that the mode's `makeController(snapshot:)`
/// can restore exactly.
@MainActor
class AnyGameController: ObservableObject {
    let levelId: String
    let title: String

    init(levelId: String, title: String) {
        self.levelId = levelId
        self.title = title
    }

    // State the HUD reads (override in subclasses).
    var moveCount: Int { 0 }
    var canUndo: Bool { false }
    var isSolved: Bool { false }
    var isStuck: Bool { false }
    var hintsUsed: Int { 0 }
    var undoCount: Int { 0 }
    var stars: Int { 0 }
    /// Optional 0...1 completion fraction for the slim HUD progress bar. Nil hides the bar.
    var progress: Double? { nil }

#if DEBUG
    /// UI-test hook: plays the next move of the stored solution through the mode's normal move path.
    func debugSolveStep() {}
#endif

    // Actions the HUD triggers.
    func undo() {}
    func restart() {}
    func requestHint() {}

    /// Opaque resume data, stored in SaveData.inProgress[levelId].
    func snapshot() -> Data { Data() }

    /// The mode's board. The shell places it in the main area; it should size itself to the proposed space.
    var boardView: AnyView { AnyView(EmptyView()) }

    /// Short VoiceOver summary of the current board ("Tube 1: red, red ...").
    var accessibilitySummary: String { "" }
}

/// Convenience base class for modes built on `GameSession<R>`.
@MainActor
class SessionController<R: PuzzleRules>: AnyGameController {
    let session: GameSession<R>
    let context: GameContext
    private var cancellable: AnyCancellable?

    init(levelId: String, title: String, session: GameSession<R>, context: GameContext) {
        self.session = session
        self.context = context
        super.init(levelId: levelId, title: title)
        cancellable = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    override var moveCount: Int { session.moveCount }
    override var canUndo: Bool { session.canUndo }
    override var isSolved: Bool { session.isSolved }
    override var isStuck: Bool { session.isStuck }
    override var hintsUsed: Int { session.hintsUsed }
    override var undoCount: Int { session.undoCount }
    override var stars: Int { session.stars }

    override func undo() {
        if session.undo() { context.haptics.legalMove() } else { context.haptics.invalid() }
        context.onProgress()
    }

    override func restart() {
        session.restart()
        context.haptics.legalMove()
        context.onProgress()
    }

    override func requestHint() {
        _ = session.hint()
    }

    override func snapshot() -> Data { session.snapshot() }

#if DEBUG
    override func debugSolveStep() {
        let solution = session.storedSolution
        guard session.moveCount < solution.count else { return }
        attempt(solution[session.moveCount])
    }
#endif

    /// Perform a move with standard haptics (light on legal, success on completion, soft warning on illegal)
    /// and notify the shell so it can debounce-save. Returns whether the move was legal.
    @discardableResult
    func attempt(_ move: R.Move) -> Bool {
        let ok = session.perform(move)
        if ok {
            if session.isSolved { context.haptics.success() } else { context.haptics.legalMove() }
            context.onProgress()
        } else {
            context.haptics.invalid()
        }
        return ok
    }
}

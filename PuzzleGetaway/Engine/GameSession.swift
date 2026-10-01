import Foundation
import Combine

/// Mode-agnostic play session: state, multi-step undo, instant restart, counters, hints, stars, snapshot/resume.
///
/// Counting rules (documented contract):
/// - `moveCount` = number of moves currently applied (`undoStack.count`); undo decrements it.
/// - `undoCount` and `hintsUsed` accumulate for the whole session, including across `restart()`.
/// - `stars`: 0 until solved, then 1 (complete) + 1 if `hintsUsed == 0` + 1 if `undoCount <= 3`.
final class GameSession<R: PuzzleRules>: ObservableObject {
    let rules: R
    let initial: R.State
    /// Stored solution (from the level file), used as hint fallback.
    let storedSolution: [R.Move]
    let hintNodeBudget: Int
    /// Optional mode-specific hint source, consulted before the generic bounded BFS (for modes whose state space is
    /// too large to search, such as Flow Fix). Return nil to fall back to the generic solver.
    var hintProvider: ((R.State) -> R.Move?)?

    @Published private(set) var state: R.State
    @Published private(set) var undoStack: [R.State] = []
    @Published private(set) var undoCount: Int = 0
    @Published private(set) var hintsUsed: Int = 0
    /// The currently displayed hint (cleared by any move/undo/restart). Boards may highlight it.
    @Published private(set) var activeHint: R.Move?

    init(rules: R, initial: R.State, solution: [R.Move] = [], hintNodeBudget: Int = 50_000) {
        self.rules = rules
        self.initial = initial
        self.state = initial
        self.storedSolution = solution
        self.hintNodeBudget = hintNodeBudget
    }

    var moveCount: Int { undoStack.count }
    var canUndo: Bool { !undoStack.isEmpty }
    var isSolved: Bool { rules.isSolved(state) }
    var isStuck: Bool { !isSolved && rules.isStuck(state) }
    var legalMoves: [R.Move] { rules.legalMoves(state) }

    var stars: Int {
        guard isSolved else { return 0 }
        return 1 + (hintsUsed == 0 ? 1 : 0) + (undoCount <= 3 ? 1 : 0)
    }

    /// Applies a move. Returns false (state unchanged) if illegal or the puzzle is already solved.
    @discardableResult
    func perform(_ move: R.Move) -> Bool {
        guard !isSolved, let next = rules.apply(move, to: state) else { return false }
        undoStack.append(state)
        state = next
        activeHint = nil
        return true
    }

    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        state = previous
        undoCount += 1
        activeHint = nil
        return true
    }

    /// Instantly returns to the initial state (counters `undoCount`/`hintsUsed` are kept).
    func restart() {
        state = initial
        undoStack.removeAll()
        activeHint = nil
    }

    /// Returns a hint move (shortest-solution first move via bounded BFS, falling back to the stored solution).
    /// Each new hint increments `hintsUsed`; asking again while the same hint is displayed is free.
    func hint() -> R.Move? {
        guard !isSolved else { return nil }
        if let active = activeHint { return active }
        let move = hintProvider?(state)
            ?? HintSolver.hint(rules: rules, from: state, nodeBudget: hintNodeBudget)
            ?? HintSolver.solutionPathHint(rules: rules, initial: initial, solution: storedSolution, current: state)
        if let move = move {
            hintsUsed += 1
            activeHint = move
        }
        return move
    }

    // MARK: Snapshot / resume

    private struct Snapshot: Codable {
        var state: R.State
        var undoStack: [R.State]
        var undoCount: Int
        var hintsUsed: Int
    }

    /// JSON snapshot of the session for the save file.
    func snapshot() -> Data {
        let snap = Snapshot(state: state, undoStack: undoStack, undoCount: undoCount, hintsUsed: hintsUsed)
        return (try? JSONEncoder().encode(snap)) ?? Data()
    }

    /// Restores from `snapshot()` data. Returns false (and changes nothing) if the data is invalid.
    @discardableResult
    func restore(from data: Data) -> Bool {
        guard let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return false }
        state = snap.state
        undoStack = snap.undoStack
        undoCount = snap.undoCount
        hintsUsed = snap.hintsUsed
        activeHint = nil
        return true
    }
}

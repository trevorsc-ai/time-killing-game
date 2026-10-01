import Foundation

/// Generic bounded breadth-first solver used for hints.
enum HintSolver {
    /// Shortest solution from `start` (as a move list), or nil if none is found within `nodeBudget` expanded nodes.
    /// Returns `[]` if `start` is already solved.
    static func solve<R: PuzzleRules>(rules: R, from start: R.State, nodeBudget: Int = 50_000) -> [R.Move]? {
        if rules.isSolved(start) { return [] }
        if let custom = rules.hintSolution(from: start, nodeBudget: nodeBudget) { return custom }
        var states: [R.State] = [start]
        var parent: [Int] = [-1]
        var moveInto: [R.Move?] = [nil]
        var visited: Set<R.State> = [start]
        var head = 0
        var expanded = 0
        while head < states.count {
            if expanded >= nodeBudget { return nil }
            let s = states[head]
            let index = head
            head += 1
            expanded += 1
            for m in rules.legalMoves(s) {
                guard let next = rules.apply(m, to: s), !visited.contains(next) else { continue }
                visited.insert(next)
                states.append(next)
                parent.append(index)
                moveInto.append(m)
                if rules.isSolved(next) {
                    var path: [R.Move] = []
                    var i = states.count - 1
                    while i > 0, let mv = moveInto[i] {
                        path.append(mv)
                        i = parent[i]
                    }
                    return path.reversed()
                }
            }
        }
        return nil
    }

    /// First move of a shortest solution from `state`, or nil if none within budget (or already solved).
    static func hint<R: PuzzleRules>(rules: R, from state: R.State, nodeBudget: Int = 50_000) -> R.Move? {
        solve(rules: rules, from: state, nodeBudget: nodeBudget)?.first
    }

    /// Fallback: if `current` lies on the path produced by replaying the stored `solution` from `initial`,
    /// returns the next stored move.
    static func solutionPathHint<R: PuzzleRules>(
        rules: R, initial: R.State, solution: [R.Move], current: R.State
    ) -> R.Move? {
        var s = initial
        for m in solution {
            if s == current { return m }
            guard let next = rules.apply(m, to: s) else { return nil }
            s = next
        }
        return nil
    }
}

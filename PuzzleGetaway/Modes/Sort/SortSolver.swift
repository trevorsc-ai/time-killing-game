import Foundation

/// A* solver for Liquid / Bolt Sort with canonical state hashing (tube order does not matter).
/// TypeScript mirror: tools/forge/src/solvers/sortSolver.ts. Used for hints and in tests.
enum SortSolver {
    struct Result {
        var solution: [SortMove]?
        var expanded: Int
        /// True when the whole reachable space was searched (so a nil solution proves "unsolvable").
        var exhausted: Bool
    }

    /// Canonical key: tubes described by (capacity, lock, layers) and sorted.
    static func canonicalKey(_ rules: SortRules, _ s: SortState) -> String {
        var parts: [String] = []
        parts.reserveCapacity(s.tubes.count)
        for i in s.tubes.indices {
            var str = String(rules.caps[i])
            if !s.locks[i].isEmpty { str += "L" + s.locks[i] }
            str += ":"
            for l in s.tubes[i] {
                str += l.c
                if l.hidden { str += "?" }
                if !l.rust.isEmpty { str += "~" + l.rust }
            }
            parts.append(str)
        }
        parts.sort()
        return parts.joined(separator: "|")
    }

    /// Number of color boundaries (adjacent differing layers): an admissible lower bound on remaining moves.
    static func boundaries(_ s: SortState) -> Int {
        var n = 0
        for t in s.tubes where t.count > 1 {
            for i in 1..<t.count where t[i].c != t[i - 1].c { n += 1 }
        }
        return n
    }

    /// Legal moves minus provably pointless ones (a whole plain uniform tube into an equal-capacity empty tube).
    static func prunedMoves(_ rules: SortRules, _ s: SortState) -> [SortMove] {
        var out: [SortMove] = []
        for m in rules.legalMoves(s) {
            let src = s.tubes[m.from]
            if s.tubes[m.to].isEmpty && rules.caps[m.from] == rules.caps[m.to] && isPlainUniform(src) { continue }
            out.append(m)
        }
        return out
    }

    private static func isPlainUniform(_ t: [SortLayer]) -> Bool {
        guard let first = t.first else { return false }
        for l in t where l.c != first.c || l.hidden || !l.rust.isEmpty { return false }
        return true
    }

    private struct Entry {
        var f: Int
        var g: Int
        var idx: Int
    }

    private struct MinHeap {
        var a: [Entry] = []

        var isEmpty: Bool { a.isEmpty }

        private func less(_ x: Entry, _ y: Entry) -> Bool {
            x.f < y.f || (x.f == y.f && x.g > y.g)
        }

        mutating func push(_ e: Entry) {
            a.append(e)
            var i = a.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                if !less(a[i], a[p]) { break }
                a.swapAt(i, p)
                i = p
            }
        }

        mutating func pop() -> Entry? {
            guard !a.isEmpty else { return nil }
            let top = a[0]
            let last = a.removeLast()
            if !a.isEmpty {
                a[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1
                    let r = l + 1
                    var m = i
                    if l < a.count && less(a[l], a[m]) { m = l }
                    if r < a.count && less(a[r], a[m]) { m = r }
                    if m == i { break }
                    a.swapAt(i, m)
                    i = m
                }
            }
            return top
        }
    }

    /// Weighted A*. `weight` 1 gives an optimal solution (the heuristic is admissible and consistent).
    static func solve(rules: SortRules, from start: SortState, weight: Int = 1, budget: Int = 50_000) -> Result {
        if rules.isSolved(start) { return Result(solution: [], expanded: 0, exhausted: true) }
        var states: [SortState] = [start]
        var keys: [String] = [canonicalKey(rules, start)]
        var parent: [Int] = [-1]
        var moveInto: [SortMove?] = [nil]
        var gs: [Int] = [0]
        var best: [String: Int] = [keys[0]: 0]
        var heap = MinHeap()
        heap.push(Entry(f: weight * boundaries(start), g: 0, idx: 0))
        var expanded = 0
        while let e = heap.pop() {
            let node = e.idx
            if let b = best[keys[node]], b < gs[node] { continue }
            let s = states[node]
            if rules.isSolved(s) {
                var path: [SortMove] = []
                var i = node
                while i > 0, let mv = moveInto[i] {
                    path.append(mv)
                    i = parent[i]
                }
                return Result(solution: path.reversed(), expanded: expanded, exhausted: false)
            }
            if expanded >= budget { return Result(solution: nil, expanded: expanded, exhausted: false) }
            expanded += 1
            for m in prunedMoves(rules, s) {
                guard let next = rules.apply(m, to: s) else { continue }
                let g = gs[node] + 1
                let k = canonicalKey(rules, next)
                if let b = best[k], b <= g { continue }
                best[k] = g
                states.append(next)
                keys.append(k)
                parent.append(node)
                moveInto.append(m)
                gs.append(g)
                heap.push(Entry(f: g + weight * boundaries(next), g: g, idx: states.count - 1))
            }
        }
        return Result(solution: nil, expanded: expanded, exhausted: true)
    }

    /// Hint solver: an optimal search first, then weighted searches for bigger boards. Nil if nothing is found
    /// within `nodeBudget` expanded nodes per attempt (or the position is provably unsolvable).
    static func solveForHint(rules: SortRules, from start: SortState, nodeBudget: Int) -> [SortMove]? {
        let first = solve(rules: rules, from: start, weight: 1, budget: max(1, nodeBudget / 2))
        if let sol = first.solution { return sol }
        if first.exhausted { return nil }
        for w in [3, 8] {
            let r = solve(rules: rules, from: start, weight: w, budget: max(1, nodeBudget))
            if let sol = r.solution { return sol }
            if r.exhausted { return nil }
        }
        return nil
    }
}

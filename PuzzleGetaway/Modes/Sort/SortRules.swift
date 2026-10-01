import Foundation

// Shared rules for Liquid Sort ("Color Mixer") and Bolt Sort ("Tool Bench").
// Canonical description: docs/rules.md. TypeScript mirror: tools/forge/src/modes/sortcore.ts.
// Keep the two implementations identical.

/// Which presentation/vocabulary the rules are used for. The rules themselves are identical.
enum SortVariant: String, Codable {
    case liquid
    case bolt

    var containerWord: String { self == .liquid ? "Tube" : "Bolt" }
    var layerWord: String { self == .liquid ? "layer" : "nut" }
}

// MARK: - Payload (level JSON)

struct SortLock: Codable, Hashable {
    var tube: Int
    var color: String
}

struct SortRustSpec: Codable, Hashable {
    var bolt: Int
    var index: Int
    var color: String
}

/// `payload` of liquid and bolt levels (see docs/level-format.md).
struct SortPayload: Codable, Hashable {
    var capacity: Int?
    var capacities: [Int]?
    var tubes: [[String]]
    var hidden: [[Int]]?
    var locks: [SortLock]?
    var rusty: [SortRustSpec]?

    init(capacity: Int? = nil, capacities: [Int]? = nil, tubes: [[String]], hidden: [[Int]]? = nil,
         locks: [SortLock]? = nil, rusty: [SortRustSpec]? = nil) {
        self.capacity = capacity
        self.capacities = capacities
        self.tubes = tubes
        self.hidden = hidden
        self.locks = locks
        self.rusty = rusty
    }
}

// MARK: - State and move

/// One layer (liquid) or nut (bolt). `rust` is the tag color while the nut is rusty, "" otherwise.
struct SortLayer: Codable, Hashable {
    var c: String
    var hidden: Bool
    var rust: String

    init(_ c: String, hidden: Bool = false, rust: String = "") {
        self.c = c
        self.hidden = hidden
        self.rust = rust
    }
}

struct SortState: Codable, Hashable {
    /// Layers bottom to top.
    var tubes: [[SortLayer]]
    /// `locks[i]` is the color that opens tube i, or "" when it is not (or no longer) locked.
    var locks: [String]

    /// Order-preserving text form, identical to the forge's `fingerprint` (used by golden tests).
    var fingerprint: String {
        let t = tubes.map { tube in
            tube.map { l in l.c + (l.hidden ? "?" : "") + (l.rust.isEmpty ? "" : "~" + l.rust) }.joined()
        }.joined(separator: "|")
        return t + "#" + locks.joined(separator: ",")
    }
}

struct SortMove: Codable, Hashable {
    var from: Int
    var to: Int
}

// MARK: - Rules

struct SortRules: PuzzleRules {
    let caps: [Int]
    let variant: SortVariant

    init(payload: SortPayload, variant: SortVariant = .liquid) {
        let base = payload.capacity ?? 4
        if let c = payload.capacities, c.count == payload.tubes.count {
            caps = c
        } else {
            caps = Array(repeating: base, count: payload.tubes.count)
        }
        self.variant = variant
    }

    /// Initial state from a payload: applies hidden / rust / locks, reveals every top, settles locks and rust.
    static func initialState(_ payload: SortPayload) -> SortState {
        var tubes: [[SortLayer]] = payload.tubes.map { $0.map { SortLayer($0) } }
        for pair in payload.hidden ?? [] where pair.count == 2 {
            let t = pair[0], l = pair[1]
            if tubes.indices.contains(t), tubes[t].indices.contains(l) { tubes[t][l].hidden = true }
        }
        for r in payload.rusty ?? [] {
            if tubes.indices.contains(r.bolt), tubes[r.bolt].indices.contains(r.index) {
                tubes[r.bolt][r.index].rust = r.color
            }
        }
        var locks = Array(repeating: "", count: payload.tubes.count)
        for l in payload.locks ?? [] where locks.indices.contains(l.tube) { locks[l.tube] = l.color }
        for i in tubes.indices { revealTop(&tubes[i]) }
        return settle(SortState(tubes: tubes, locks: locks))
    }

    // MARK: PuzzleRules

    func legalMoves(_ s: SortState) -> [SortMove] {
        var out: [SortMove] = []
        let n = s.tubes.count
        for from in 0..<n where canSource(s, from: from) {
            for to in 0..<n where to != from && canTarget(s, from: from, to: to) {
                out.append(SortMove(from: from, to: to))
            }
        }
        return out
    }

    /// Source tube is non-empty, unlocked, and its top nut is neither hidden nor rusty.
    func canSource(_ s: SortState, from: Int) -> Bool {
        guard s.tubes.indices.contains(from) else { return false }
        let t = s.tubes[from]
        guard let top = t.last, s.locks[from].isEmpty else { return false }
        return !top.hidden && top.rust.isEmpty
    }

    /// Assumes `canSource(from)`.
    func canTarget(_ s: SortState, from: Int, to: Int) -> Bool {
        guard s.tubes.indices.contains(to), s.tubes.indices.contains(from) else { return false }
        let dst = s.tubes[to]
        guard s.locks[to].isEmpty, dst.count < caps[to] else { return false }
        guard let dtop = dst.last else { return true }
        guard let stop = s.tubes[from].last else { return false }
        return dtop.c == stop.c
    }

    /// Length of the contiguous top run of a tube that a pour would move (0 when the tube cannot be a source).
    func topRun(_ s: SortState, tube: Int) -> Int {
        guard canSource(s, from: tube) else { return 0 }
        let src = s.tubes[tube]
        let topC = src[src.count - 1].c
        var run = 0
        var i = src.count - 1
        while i >= 0 {
            let l = src[i]
            if l.c != topC || l.hidden || !l.rust.isEmpty { break }
            run += 1
            i -= 1
        }
        return run
    }

    /// Number of layers a legal move would transfer (0 when the move is illegal).
    func transferCount(_ m: SortMove, in s: SortState) -> Int {
        guard m.from != m.to, canSource(s, from: m.from), canTarget(s, from: m.from, to: m.to) else { return 0 }
        return min(topRun(s, tube: m.from), caps[m.to] - s.tubes[m.to].count)
    }

    func apply(_ m: SortMove, to s: SortState) -> SortState? {
        let k = transferCount(m, in: s)
        if k <= 0 { return nil }
        var tubes = s.tubes
        let src = tubes[m.from]
        let moved = Array(src[(src.count - k)...])
        var newSrc = Array(src[..<(src.count - k)])
        SortRules.revealTop(&newSrc)
        tubes[m.from] = newSrc
        tubes[m.to] = tubes[m.to] + moved
        return SortRules.settle(SortState(tubes: tubes, locks: s.locks))
    }

    func isSolved(_ s: SortState) -> Bool {
        var seen = Set<String>()
        for t in s.tubes {
            guard let first = t.first else { continue }
            for l in t where l.c != first.c { return false }
            if !seen.insert(first.c).inserted { return false }
        }
        return true
    }

    // MARK: Helpers

    static func revealTop(_ t: inout [SortLayer]) {
        if let last = t.last, last.hidden { t[t.count - 1].hidden = false }
    }

    /// Colors completed in `tubes`: exactly one tube holds the color and that tube is single-colored.
    static func completedColors(_ tubes: [[SortLayer]]) -> Set<String> {
        var holders: [String: Int] = [:]
        var impure = Set<String>()
        for t in tubes where !t.isEmpty {
            let here = Set(t.map { $0.c })
            for c in here { holders[c, default: 0] += 1 }
            if here.count > 1 { for c in here { impure.insert(c) } }
        }
        var done = Set<String>()
        for (c, n) in holders where n == 1 && !impure.contains(c) { done.insert(c) }
        return done
    }

    /// Opens satisfied locks and clears satisfied rust.
    static func settle(_ s: SortState) -> SortState {
        var needs = s.locks.contains { !$0.isEmpty }
        if !needs {
            needs = s.tubes.contains { tube in tube.contains { layer in !layer.rust.isEmpty } }
        }
        guard needs else { return s }
        let done = completedColors(s.tubes)
        guard !done.isEmpty else { return s }
        var out = s
        for i in out.locks.indices where !out.locks[i].isEmpty && done.contains(out.locks[i]) {
            out.locks[i] = ""
        }
        for t in out.tubes.indices {
            for l in out.tubes[t].indices {
                let r = out.tubes[t][l].rust
                if !r.isEmpty && done.contains(r) { out.tubes[t][l].rust = "" }
            }
        }
        return out
    }

    /// True when tube `i` is full of a single, fully revealed color (it will not need to change any more).
    func isComplete(_ s: SortState, tube i: Int) -> Bool {
        guard s.tubes.indices.contains(i) else { return false }
        let t = s.tubes[i]
        guard let first = t.first, t.count == caps[i] else { return false }
        for l in t where l.c != first.c || l.hidden { return false }
        return true
    }

    // MARK: Hints

    /// Mode-specific solver used by the hint system (canonical-state A*).
    func hintSolution(from s: SortState, nodeBudget: Int) -> [SortMove]? {
        SortSolver.solveForHint(rules: self, from: s, nodeBudget: nodeBudget)
    }
}

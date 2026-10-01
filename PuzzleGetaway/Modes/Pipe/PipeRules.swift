import Foundation

// Flow Fix rules. Canonical description: docs/rules.md ("Flow Fix"). Mirrors tools/forge/src/modes/pipe/rules.ts.
// Openings are a 4-bit mask N=1, E=2, S=4, W=8; rotation is 90 degrees clockwise.

struct PipePayload: Codable, Hashable {
    /// Tile tokens: code (`. i l t x S D`) plus rotation digit 0...3, e.g. "l2".
    var grid: [[String]]
    /// `[row, col]` tiles that cannot be rotated.
    var fixed: [[Int]]?
}

/// `{r, c}`: rotate the tile at (r, c) 90 degrees clockwise.
struct PipeMove: Codable, Hashable {
    var r: Int
    var c: Int
}

/// Current rotation (0...3) of every tile, row-major.
struct PipeState: Codable, Hashable {
    var rots: [Int]
}

enum PipeDir {
    static let north = 1
    static let east = 2
    static let south = 4
    static let west = 8
    /// Row/column deltas indexed by bit position: N, E, S, W.
    static let dr = [-1, 0, 1, 0]
    static let dc = [0, 1, 0, -1]
    static let names = ["up", "right", "down", "left"]
}

struct PipeRules: PuzzleRules {
    let rows: Int
    let cols: Int
    let kinds: [Character]
    let fixed: [Bool]
    let initialRots: [Int]

    init(payload: PipePayload) {
        let rowCount = payload.grid.count
        let colCount = payload.grid.first?.count ?? 0
        var kinds: [Character] = []
        var rots: [Int] = []
        for row in payload.grid {
            for c in 0..<colCount {
                let token = c < row.count ? Array(row[c]) : [".", "0"]
                kinds.append(token.first ?? ".")
                rots.append(token.count > 1 ? (Int(String(token[1])) ?? 0) % 4 : 0)
            }
        }
        var fixed = [Bool](repeating: false, count: rowCount * colCount)
        for f in payload.fixed ?? [] where f.count == 2 && f[0] >= 0 && f[0] < rowCount && f[1] >= 0 && f[1] < colCount {
            fixed[f[0] * colCount + f[1]] = true
        }
        self.rows = rowCount
        self.cols = colCount
        self.kinds = kinds
        self.fixed = fixed
        self.initialRots = rots
    }

    var initialState: PipeState { PipeState(rots: initialRots) }

    var sourceIndex: Int? { kinds.firstIndex(of: "S") }
    var destinationIndices: [Int] { kinds.indices.filter { kinds[$0] == "D" } }

    // MARK: Masks

    static func rotate(_ mask: Int) -> Int { ((mask << 1) & 15) | (mask >> 3) }

    static func baseMask(_ kind: Character) -> Int {
        switch kind {
        case "i": return PipeDir.north | PipeDir.south
        case "l": return PipeDir.north | PipeDir.east
        case "t": return PipeDir.east | PipeDir.south | PipeDir.west
        case "x": return 15
        case "S", "D": return PipeDir.north
        default: return 0
        }
    }

    static func mask(_ kind: Character, rot: Int) -> Int {
        var m = baseMask(kind)
        for _ in 0..<(((rot % 4) + 4) % 4) { m = rotate(m) }
        return m
    }

    func mask(at i: Int, _ s: PipeState) -> Int { PipeRules.mask(kinds[i], rot: s.rots[i]) }

    // MARK: Moves

    func legalMoves(_ s: PipeState) -> [PipeMove] {
        var out: [PipeMove] = []
        for i in kinds.indices where kinds[i] != "." && !fixed[i] {
            out.append(PipeMove(r: i / cols, c: i % cols))
        }
        return out
    }

    func apply(_ m: PipeMove, to s: PipeState) -> PipeState? {
        guard m.r >= 0, m.c >= 0, m.r < rows, m.c < cols else { return nil }
        let i = m.r * cols + m.c
        guard kinds[i] != ".", !fixed[i] else { return nil }
        var next = s
        next.rots[i] = (next.rots[i] + 1) % 4
        return next
    }

    // MARK: Connectivity

    /// Tiles reached by flow from the source. `parent[i]` is the direction index (0...3 = N, E, S, W) pointing from
    /// tile `i` toward the tile that fed it, or -1 for the source and unreached tiles.
    func flow(_ s: PipeState) -> (reached: [Bool], parent: [Int]) {
        var reached = [Bool](repeating: false, count: kinds.count)
        var parent = [Int](repeating: -1, count: kinds.count)
        guard let source = sourceIndex else { return (reached, parent) }
        reached[source] = true
        var queue = [source]
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            let r = i / cols
            let c = i % cols
            let m = mask(at: i, s)
            for d in 0..<4 where m & (1 << d) != 0 {
                let nr = r + PipeDir.dr[d]
                let nc = c + PipeDir.dc[d]
                guard nr >= 0, nc >= 0, nr < rows, nc < cols else { continue }
                let j = nr * cols + nc
                if reached[j] { continue }
                if mask(at: j, s) & (1 << ((d + 2) % 4)) != 0 {
                    reached[j] = true
                    parent[j] = (d + 2) % 4
                    queue.append(j)
                }
            }
        }
        return (reached, parent)
    }

    func isSolved(_ s: PipeState) -> Bool {
        let dests = destinationIndices
        guard !dests.isEmpty else { return false }
        let reached = flow(s).reached
        return dests.allSatisfy { reached[$0] }
    }

    // MARK: Text

    static func kindName(_ kind: Character) -> String {
        switch kind {
        case "i": return "straight pipe"
        case "l": return "elbow"
        case "t": return "tee splitter"
        case "x": return "cross"
        case "S": return "water source"
        case "D": return "lamp"
        default: return "empty"
        }
    }

    /// "up and right", "left, up and right", "none".
    static func openingsText(_ mask: Int) -> String {
        let names = (0..<4).filter { mask & (1 << $0) != 0 }.map { PipeDir.names[$0] }
        switch names.count {
        case 0: return "nothing"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

import Foundation

// Pixel Picnic ("Critter Clear") rules. Canonical spec: docs/rules.md. TypeScript mirror:
// tools/forge/src/modes/pixel/rules.ts. Keep both identical; PixelRulesTests replays golden fixtures from the forge.

// MARK: - Payload and moves

struct PixelCrate: Codable, Hashable {
    var color: String
    var count: Int
    /// Display metadata from the level file; the app derives symbols/patterns from the palette instead.
    var pattern: String?

    init(color: String, count: Int, pattern: String? = nil) {
        self.color = color
        self.count = count
        self.pattern = pattern
    }
}

struct PixelPayload: Codable, Hashable {
    /// Rows of equal length: palette id, `.` (empty, cleared from the start) or `#` (stone).
    var grid: [String]
    var slots: Int
    /// Lanes, front crate first.
    var lanes: [[PixelCrate]]
}

struct PixelMove: Codable, Hashable {
    var lane: Int
}

// MARK: - State

enum PixelCell {
    static let clear: UInt8 = 46 // "."
    static let stone: UInt8 = 35 // "#"

    static func isPixel(_ c: UInt8) -> Bool { c != clear && c != stone }
}

struct PixelState: Codable, Hashable {
    var width: Int
    var height: Int
    /// Row-major ASCII codes. `PixelCell.clear` = cleared, `PixelCell.stone` = stone, otherwise a palette id.
    var cells: [UInt8]
    /// Per tray slot: palette id code, 0 = empty.
    var slotColor: [UInt8]
    /// Per tray slot: blocks the crate still has to pack.
    var slotRemaining: [Int]
    /// Per lane: number of crates already tapped (index of the current front crate).
    var laneNext: [Int]

    var pixelsLeft: Int { cells.reduce(0) { PixelCell.isPixel($1) ? $0 + 1 : $0 } }
    var occupiedSlots: Int { slotColor.reduce(0) { $1 != 0 ? $0 + 1 : $0 } }
    var hasFreeSlot: Bool { slotColor.contains(0) }
    var firstFreeSlot: Int? { slotColor.firstIndex(of: 0) }

    func rows() -> [String] {
        (0..<height).map { r in
            String(decoding: cells[(r * width)..<((r + 1) * width)], as: UTF8.self)
        }
    }

    /// Slots as `["r:3", "", "g:2"]` ("" = empty), the golden-fixture encoding.
    func slotStrings() -> [String] {
        slotColor.enumerated().map { i, c in
            c == 0 ? "" : "\(String(Character(UnicodeScalar(c)))):\(slotRemaining[i])"
        }
    }
}

/// One slot visit that packed, crumbled or departed. The scene animates from these; they never feed back into state.
struct PixelEvent: Equatable {
    var slot: Int
    var color: UInt8
    /// Cell indices (row * width + col) packed, in BFS order.
    var cells: [Int]
    /// Stones that crumbled right after this visit (row-major order).
    var crumbled: [Int]
    var departed: Bool
}

struct PixelTransition {
    var before: PixelState
    var after: PixelState
    var move: PixelMove
    /// Tray slot the tapped crate landed in.
    var slot: Int
    var crate: PixelCrate
    var events: [PixelEvent]
}

// MARK: - Rules

struct PixelRules: PuzzleRules {
    let payload: PixelPayload

    init(payload: PixelPayload) {
        self.payload = payload
    }

    func initialState() -> PixelState {
        let h = payload.grid.count
        let w = payload.grid.first?.utf8.count ?? 0
        var cells: [UInt8] = []
        cells.reserveCapacity(w * h)
        for row in payload.grid { cells.append(contentsOf: Array(row.utf8)) }
        return PixelState(
            width: w,
            height: h,
            cells: cells,
            slotColor: Array(repeating: 0, count: payload.slots),
            slotRemaining: Array(repeating: 0, count: payload.slots),
            laneNext: Array(repeating: 0, count: payload.lanes.count)
        )
    }

    // PuzzleRules

    func legalMoves(_ s: PixelState) -> [PixelMove] {
        guard s.hasFreeSlot else { return [] }
        var out: [PixelMove] = []
        for l in 0..<payload.lanes.count where s.laneNext[l] < payload.lanes[l].count {
            out.append(PixelMove(lane: l))
        }
        return out
    }

    func apply(_ m: PixelMove, to s: PixelState) -> PixelState? {
        applyDetailed(m, to: s)?.state
    }

    func isSolved(_ s: PixelState) -> Bool {
        !s.cells.contains { PixelCell.isPixel($0) }
    }

    // MARK: Crates

    /// The crate that a tap on `lane` would send, or nil if the lane is exhausted.
    func frontCrate(lane: Int, in s: PixelState) -> PixelCrate? {
        guard lane >= 0, lane < payload.lanes.count else { return nil }
        let idx = s.laneNext[lane]
        return idx < payload.lanes[lane].count ? payload.lanes[lane][idx] : nil
    }

    // MARK: Exposure

    func isExposed(_ s: PixelState, _ idx: Int) -> Bool {
        let w = s.width, h = s.height
        let r = idx / w
        let c = idx - r * w
        if r == 0 || c == 0 || r == h - 1 || c == w - 1 { return true }
        let clear = PixelCell.clear
        return s.cells[idx - w] == clear || s.cells[idx - 1] == clear || s.cells[idx + 1] == clear || s.cells[idx + w] == clear
    }

    /// One crate visit. Mutates `s`; returns the packed cell indices in BFS order.
    func pack(_ s: inout PixelState, slot: Int) -> [Int] {
        let color = s.slotColor[slot]
        let w = s.width, h = s.height
        var remaining = s.slotRemaining[slot]
        var visited = [Bool](repeating: false, count: w * h)
        var queue: [Int] = []
        for i in 0..<s.cells.count where s.cells[i] == color && isExposed(s, i) {
            visited[i] = true
            queue.append(i)
        }
        func enqueue(_ n: Int) {
            if s.cells[n] == color && !visited[n] {
                visited[n] = true
                queue.append(n)
            }
        }
        var packed: [Int] = []
        var head = 0
        while remaining > 0 && head < queue.count {
            let p = queue[head]
            head += 1
            s.cells[p] = PixelCell.clear
            remaining -= 1
            packed.append(p)
            let r = p / w
            let c = p - r * w
            // up, left, right, down
            if r > 0 { enqueue(p - w) }
            if c > 0 { enqueue(p - 1) }
            if c < w - 1 { enqueue(p + 1) }
            if r < h - 1 { enqueue(p + w) }
        }
        s.slotRemaining[slot] = remaining
        return packed
    }

    /// Crumbles stones 4-adjacent to any packed cell. Returns the crumbled indices (row-major).
    func crumble(_ s: inout PixelState, packed: [Int]) -> [Int] {
        let w = s.width, h = s.height
        var hit = Set<Int>()
        for p in packed {
            let r = p / w
            let c = p - r * w
            if r > 0, s.cells[p - w] == PixelCell.stone { hit.insert(p - w) }
            if c > 0, s.cells[p - 1] == PixelCell.stone { hit.insert(p - 1) }
            if c < w - 1, s.cells[p + 1] == PixelCell.stone { hit.insert(p + 1) }
            if r < h - 1, s.cells[p + w] == PixelCell.stone { hit.insert(p + w) }
        }
        let out = hit.sorted()
        for n in out { s.cells[n] = PixelCell.clear }
        return out
    }

    /// resolve(): repeat left-to-right passes until nothing changes. Mutates `s`.
    func resolve(_ s: inout PixelState) -> [PixelEvent] {
        var events: [PixelEvent] = []
        var changed = true
        while changed {
            changed = false
            for slot in 0..<s.slotColor.count {
                let color = s.slotColor[slot]
                if color == 0 { continue }
                let packed = pack(&s, slot: slot)
                let crumbled = packed.isEmpty ? [] : crumble(&s, packed: packed)
                let departed = s.slotRemaining[slot] == 0
                if departed { s.slotColor[slot] = 0 }
                if !packed.isEmpty || !crumbled.isEmpty || departed {
                    events.append(PixelEvent(slot: slot, color: color, cells: packed, crumbled: crumbled, departed: departed))
                    changed = true
                }
            }
        }
        return events
    }

    /// Applies a tap and reports everything that happened. Returns nil if the tap is illegal.
    func applyDetailed(_ m: PixelMove, to s: PixelState) -> PixelTransition? {
        guard m.lane >= 0, m.lane < payload.lanes.count,
              let crate = frontCrate(lane: m.lane, in: s),
              let slot = s.firstFreeSlot,
              let colorCode = crate.color.utf8.first
        else { return nil }
        var n = s
        n.laneNext[m.lane] += 1
        n.slotColor[slot] = colorCode
        n.slotRemaining[slot] = crate.count
        let events = resolve(&n)
        return PixelTransition(before: s, after: n, move: m, slot: slot, crate: crate, events: events)
    }

    /// Cells the front crate of `lane` would pack right now (union of the events of the slot it lands in).
    func previewCells(lane: Int, in s: PixelState) -> [Int] {
        guard let t = applyDetailed(PixelMove(lane: lane), to: s) else { return [] }
        return t.events.filter { $0.slot == t.slot }.flatMap { $0.cells }
    }
}

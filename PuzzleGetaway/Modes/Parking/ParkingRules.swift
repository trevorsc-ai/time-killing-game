import Foundation

// Baggage Jam rules. Canonical description: docs/rules.md ("Baggage Jam"). Mirrors tools/forge/src/modes/parking/rules.ts.

struct ParkingVehicle: Codable, Hashable {
    var id: String
    var r: Int
    var c: Int
    var len: Int
    /// "h" or "v".
    var axis: String
    var target: Bool?

    var isHorizontal: Bool { axis == "h" }
    var isTarget: Bool { target ?? false }
    /// Position along the vehicle's own axis (column for "h", row for "v").
    var startPosition: Int { isHorizontal ? c : r }
}

struct ParkingGate: Codable, Hashable {
    var target: String
    /// "left" | "right" | "top" | "bottom"
    var edge: String
    var index: Int
}

struct ParkingPayload: Codable, Hashable {
    var size: Int?
    var vehicles: [ParkingVehicle]
    var gates: [ParkingGate]

    var boardSize: Int { size ?? 6 }
}

/// `{id, delta}`: slide vehicle `id` by `delta` cells along its axis (positive = right / down).
struct ParkingMove: Codable, Hashable {
    var id: String
    var delta: Int
}

/// Position of every vehicle along its own axis, in payload order.
struct ParkingState: Codable, Hashable {
    var positions: [Int]
}

struct ParkingRules: PuzzleRules {
    let size: Int
    let vehicles: [ParkingVehicle]
    let gates: [ParkingGate]

    init(payload: ParkingPayload) {
        self.size = payload.boardSize
        self.vehicles = payload.vehicles
        self.gates = payload.gates
    }

    var initialState: ParkingState {
        ParkingState(positions: vehicles.map { $0.startPosition })
    }

    func index(of id: String) -> Int? {
        vehicles.firstIndex { $0.id == id }
    }

    /// Cell (row-major) -> vehicle index, or -1.
    func occupancy(_ s: ParkingState) -> [Int] {
        var grid = [Int](repeating: -1, count: size * size)
        for (i, v) in vehicles.enumerated() {
            for k in 0..<v.len {
                let r = v.isHorizontal ? v.r : s.positions[i] + k
                let c = v.isHorizontal ? s.positions[i] + k : v.c
                grid[r * size + c] = i
            }
        }
        return grid
    }

    /// Inclusive legal delta range `(min <= 0, max >= 0)` for vehicle `i`.
    func slideRange(_ s: ParkingState, vehicle i: Int, occupancy occ: [Int]? = nil) -> (min: Int, max: Int) {
        let grid = occ ?? occupancy(s)
        let v = vehicles[i]
        let pos = s.positions[i]
        func cell(_ q: Int) -> Int { v.isHorizontal ? grid[v.r * size + q] : grid[q * size + v.c] }
        var lo = 0
        while pos + lo - 1 >= 0 && cell(pos + lo - 1) == -1 { lo -= 1 }
        var hi = 0
        while pos + v.len + hi < size && cell(pos + v.len + hi) == -1 { hi += 1 }
        return (lo, hi)
    }

    func legalMoves(_ s: ParkingState) -> [ParkingMove] {
        let occ = occupancy(s)
        var out: [ParkingMove] = []
        for (i, v) in vehicles.enumerated() {
            let range = slideRange(s, vehicle: i, occupancy: occ)
            if range.min > range.max { continue }
            for d in range.min...range.max where d != 0 {
                out.append(ParkingMove(id: v.id, delta: d))
            }
        }
        return out
    }

    func apply(_ m: ParkingMove, to s: ParkingState) -> ParkingState? {
        guard let i = index(of: m.id), m.delta != 0 else { return nil }
        let range = slideRange(s, vehicle: i)
        guard m.delta >= range.min, m.delta <= range.max else { return nil }
        var next = s
        next.positions[i] += m.delta
        return next
    }

    func isSolved(_ s: ParkingState) -> Bool {
        for g in gates {
            guard let i = index(of: g.target) else { return false }
            let v = vehicles[i]
            let pos = s.positions[i]
            switch g.edge {
            case "right": if !(v.isHorizontal && pos + v.len == size) { return false }
            case "left": if !(v.isHorizontal && pos == 0) { return false }
            case "bottom": if !(!v.isHorizontal && pos + v.len == size) { return false }
            case "top": if !(!v.isHorizontal && pos == 0) { return false }
            default: return false
            }
        }
        return !gates.isEmpty
    }

    /// True if vehicle `i` currently sits on the board edge of its gate (used for "gate is open" visuals).
    func isAtGate(_ s: ParkingState, vehicle i: Int) -> Bool {
        let v = vehicles[i]
        guard let g = gates.first(where: { $0.target == v.id }) else { return false }
        let pos = s.positions[i]
        switch g.edge {
        case "right", "bottom": return pos + v.len == size
        default: return pos == 0
        }
    }
}

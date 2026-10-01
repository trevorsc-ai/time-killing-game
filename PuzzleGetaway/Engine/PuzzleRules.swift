import Foundation

/// Pure, deterministic game rules for one puzzle mode. Must match docs/rules.md and the forge's TypeScript rules.
///
/// - `State` is the complete board state (including anything needed to resume: revealed layers, unlocked flags, ...).
/// - `Move` is one player action; its Codable JSON form is what level files store in `solution`.
/// - Rules are value-semantic and side-effect free; animation and haptics live in the scene/controller.
protocol PuzzleRules {
    associatedtype State: Codable & Hashable
    associatedtype Move: Codable & Hashable

    /// All legal moves from `s`, in a deterministic order.
    func legalMoves(_ s: State) -> [Move]
    /// The resulting state, or nil if `m` is illegal in `s`.
    func apply(_ m: Move, to s: State) -> State?
    func isSolved(_ s: State) -> Bool
    /// No way forward (but not solved). Default: `!isSolved && legalMoves.isEmpty`.
    func isStuck(_ s: State) -> Bool
}

extension PuzzleRules {
    func isStuck(_ s: State) -> Bool {
        !isSolved(s) && legalMoves(s).isEmpty
    }
}

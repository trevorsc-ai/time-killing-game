import Foundation

/// Everything a mode needs from the app when building a controller.
@MainActor
struct GameContext {
    let settings: Settings
    let haptics: Haptics
    let palette: Palette
    /// Called by controllers after any state change worth persisting (moves, undo, restart). The shell
    /// responds by saving `snapshot()` through the debounced SaveStore.
    var onProgress: () -> Void

    init(settings: Settings, haptics: Haptics, palette: Palette, onProgress: @escaping () -> Void = {}) {
        self.settings = settings
        self.haptics = haptics
        self.palette = palette
        self.onProgress = onProgress
    }

    /// Convenience for tests and previews.
    static func standalone(palette: Palette = Palette(colors: [])) -> GameContext {
        let s = Settings()
        return GameContext(settings: s, haptics: Haptics(settings: s), palette: palette)
    }
}

/// A puzzle mode. Implement one per mode (e.g. `LiquidMode`) and add it to `ModeRegistry.plugins`.
protocol PuzzleModePlugin {
    /// Matches `LevelEnvelope.mode` ("liquid", "bolt", "pixel", "parking", "pipe", "demo").
    static var mode: String { get }
    static var displayName: String { get }

    /// Builds the controller for `level`. If `snapshot` is non-nil and valid, restore it; otherwise start fresh.
    @MainActor
    static func makeController(level: LevelEnvelope, snapshot: Data?, context: GameContext) -> AnyGameController

    /// Replays `level.solution` from `level.payload` with the canonical rules. Returns true iff every move
    /// is legal and the final state is solved. Throws on undecodable payload/moves. Used by SolutionReplayTests.
    static func replay(level: LevelEnvelope) throws -> Bool
}

enum ModeRegistry {
    /// === MODE REGISTRATIONS ===
    /// Add exactly ONE line per mode, with a trailing comma. (Merge conflicts here are expected and trivial.)
    private static let plugins: [PuzzleModePlugin.Type] = [
        DemoMode.self,
        // LiquidMode.self,
        // BoltMode.self,
        // PixelMode.self,
        // ParkingMode.self,
        // PipeMode.self,
    ]
    /// === END MODE REGISTRATIONS ===

    static let all: [String: PuzzleModePlugin.Type] = {
        var d: [String: PuzzleModePlugin.Type] = [:]
        for p in plugins { d[p.mode] = p }
        return d
    }()

    static func plugin(for mode: String) -> PuzzleModePlugin.Type? { all[mode] }
}

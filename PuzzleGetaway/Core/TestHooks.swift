import Foundation

#if DEBUG
/// UI-test only launch arguments. Compiled out of release builds.
///  - `-PGUITestHooks`: the HUD shows an (almost) invisible "Solve step" button that plays the next stored-solution move.
///  - `-PGOpenLevel <levelId>`: opens that level straight away (it does not need to be unlocked).
enum TestHooks {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-PGUITestHooks") }

    static var openLevelId: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-PGOpenLevel"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif

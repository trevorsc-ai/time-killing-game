import SwiftUI
import Combine

/// Root observable state: progress (SaveData), settings, bundled content, persistence.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var save: SaveData
    @Published private(set) var content: ContentStore?
    @Published private(set) var contentError: String?
    let settings: Settings
    let haptics: Haptics
    let saveStore: SaveStore
    /// How the save was loaded at launch (fresh / main / backup). The shell may show a "recovered" notice for .backup.
    let loadSource: SaveStore.Source

    private var cancellables = Set<AnyCancellable>()

    /// - Parameter saveStore: inject a temp-directory store in tests.
    init(saveStore: SaveStore = SaveStore(), content: ContentStore? = nil) {
        // UI tests launch with -PGResetSave to start from a clean slate.
        if ProcessInfo.processInfo.arguments.contains("-PGResetSave") { saveStore.wipe() }
        self.saveStore = saveStore
        let loaded = saveStore.load()
        self.save = loaded.data
        self.loadSource = loaded.source
        let settings = Settings(values: loaded.data.settings)
        self.settings = settings
        self.haptics = Haptics(settings: settings)
        if let content = content {
            self.content = content
        } else {
            do { self.content = try ContentStore.load() } catch {
                self.contentError = String(describing: error)
            }
        }
        // Persist settings changes (objectWillChange fires before the change lands, so hop to the next runloop).
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.save.settings = self.settings.values
                self.scheduleSave()
            }
            .store(in: &cancellables)
    }

    var theme: Theme { Theme(highContrast: settings.highContrast) }

    // MARK: Persistence

    func scheduleSave() {
        saveStore.requestSave { [weak self] in
            // Runs on the main queue (SaveStore debounces via DispatchQueue.main).
            self?.save ?? SaveData()
        }
    }

    /// Flush immediately (scenePhase .inactive / .background).
    func saveNow() {
        scheduleSave()
        saveStore.saveNow()
    }

    func replaceSave(_ newSave: SaveData) {
        save = newSave
        settings.values = newSave.settings
        saveNow()
    }

    // MARK: Gameplay plumbing

    func makeContext(onProgress: @escaping () -> Void = {}) -> GameContext {
        GameContext(settings: settings, haptics: haptics, palette: content?.palette ?? Palette(colors: []), onProgress: onProgress)
    }

    /// Builds a controller for `level` (restoring any in-progress snapshot). Nil if the mode isn't registered.
    func makeController(for level: LevelEnvelope) -> AnyGameController? {
        guard let plugin = ModeRegistry.plugin(for: level.mode) else { return nil }
        let id = level.id
        let context = makeContext { [weak self] in self?.noteProgress(levelId: id) }
        controllers[id] = nil
        let controller = plugin.makeController(level: level, snapshot: save.inProgress[level.id], context: context)
        controllers[id] = controller
        return controller
    }

    private var controllers: [String: AnyGameController] = [:]

    /// Called by controllers (via GameContext.onProgress) after state changes: stores the snapshot, debounced.
    private func noteProgress(levelId: String) {
        guard let controller = controllers[levelId], !controller.isSolved else { return }
        save.inProgress[levelId] = controller.snapshot()
        scheduleSave()
    }

    func recordCompletion(levelId: String, stars: Int, moves: Int) {
        save.recordCompletion(levelId: levelId, stars: stars, moves: moves)
        saveNow()
    }

    func markTutorialSeen(_ key: String) {
        save.tutorialsSeen.insert(key)
        scheduleSave()
    }

    /// First unsolved level (destination order) whose mode is registered; real destinations before "demo".
    func quickPlayLevel() -> LevelEnvelope? {
        guard let content = content else { return nil }
        let playable = content.allLevels.filter { ModeRegistry.plugin(for: $0.mode) != nil }
        return playable.first { save.progress[$0.id] == nil } ?? playable.first
    }
}

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

    /// Pure progression rules over the bundled content (unlocks, stars, targets). Rebuilt only at init.
    private(set) var progression: Progression

    /// UI-test hooks (launch arguments): `-PGDemoOnly` plays only the demo levels (mapped into d1), `-PGShowMoves` shows the move counter,
    /// `-PGNoSplash` skips the brief launch splash.
    let skipSplash: Bool

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
        var loadedContent: ContentStore? = content
        if loadedContent == nil {
            do { loadedContent = try ContentStore.load() } catch {
                self.contentError = String(describing: error)
            }
        }
        self.content = loadedContent
        let args = ProcessInfo.processInfo.arguments
        if let loadedContent = loadedContent {
            self.progression = Progression(content: loadedContent, demoOnly: args.contains("-PGDemoOnly"))
        } else {
            self.progression = Progression(destinations: [], levels: [])
        }
        self.skipSplash = args.contains("-PGNoSplash")
        if args.contains("-PGShowMoves") { settings.showMoveCounter = true }
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
        if save.lastPlayedLevelId != id {
            save.lastPlayedLevelId = id
            scheduleSave()
        }
        return controller
    }

    /// Stores the controller's current snapshot right now (leaving a puzzle, backgrounding). No-op once solved.
    func persistSnapshot(of controller: AnyGameController) {
        guard !controller.isSolved else { return }
        if controller.moveCount > 0 || save.inProgress[controller.levelId] != nil {
            save.inProgress[controller.levelId] = controller.snapshot()
        }
        saveNow()
    }

    private var controllers: [String: AnyGameController] = [:]

    /// Called by controllers (via GameContext.onProgress) after state changes: stores the snapshot, debounced.
    private func noteProgress(levelId: String) {
        guard let controller = controllers[levelId], !controller.isSolved else { return }
        save.inProgress[levelId] = controller.snapshot()
        scheduleSave()
    }

    /// What a completion changed, for the Level Complete screen.
    struct CompletionOutcome {
        var destinationId: String?
        var newStages: [RestorationStage] = []
        var unlockedDestination: Destination?
        var isFirstCompletion = false
        var starsBeforeForLevel = 0
    }

    @discardableResult
    func recordCompletion(levelId: String, stars: Int, moves: Int) -> CompletionOutcome {
        var outcome = CompletionOutcome()
        let level = progression.level(id: levelId)
        let destId = level?.destination
        let isCampaign = destId.map { progression.destination($0) != nil } ?? false
        let before = save
        outcome.isFirstCompletion = save.progress[levelId] == nil
        outcome.starsBeforeForLevel = save.progress[levelId]?.stars ?? 0
        save.recordCompletion(levelId: levelId, stars: stars, moves: moves)
        if isCampaign, let destId = destId {
            outcome.destinationId = destId
            let fromStars = progression.stars(in: destId, save: before)
            let toStars = progression.stars(in: destId, save: save)
            outcome.newStages = progression.newlyUnlockedStages(in: destId, fromStars: fromStars, toStars: toStars)
            for stage in outcome.newStages { save.scrapbookUnlocked.insert(stage.scrapbookArtId) }
            if let next = progression.nextDestination(after: destId),
               !progression.isDestinationUnlocked(next.id, save: before),
               progression.isDestinationUnlocked(next.id, save: save) {
                outcome.unlockedDestination = next
            }
        }
        saveNow()
        return outcome
    }

    /// Relax: remember that this puzzle was solved and move the pool on to the next one (only if it was the current one).
    func completeRelax(level: LevelEnvelope) {
        let pool = level.destination
        let wasCurrent = progression.currentRelaxEntry(pool: pool, save: save)?.id == level.id
        save.recordCompletion(levelId: level.id, stars: 0, moves: 0)
        if wasCurrent { save.relaxPositions[pool] = (save.relaxPositions[pool] ?? 0) + 1 }
        saveNow()
    }

    /// Daily Journey: count today's journey (a set of dates, no streaks).
    func completeDaily(level: LevelEnvelope, on date: Date = Date()) {
        save.recordCompletion(levelId: level.id, stars: 0, moves: 0)
        save.dailyJourneysTaken.insert(Progression.dateKey(date))
        saveNow()
    }

    func markRestorationStagesSeen(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        for id in ids { save.restorationStagesSeen.insert(id) }
        scheduleSave()
    }

    func resetTutorials() {
        save.tutorialsSeen = []
        scheduleSave()
    }

    /// When the main save file was last written (nil if never saved).
    var lastSaveDate: Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: saveStore.mainURL.path)
        return attrs?[.modificationDate] as? Date
    }

    func markTutorialSeen(_ key: String) {
        save.tutorialsSeen.insert(key)
        scheduleSave()
    }

    /// Quick Play target: first unsolved unlocked level; else a Relax puzzle.
    func quickPlayLevel() -> LevelEnvelope? {
        progression.quickPlayLevel(save: save)
    }

    /// Continue target: the exact in-progress puzzle, else the next unsolved level.
    func continueLevel() -> LevelEnvelope? {
        progression.continueLevel(save: save)
    }
}

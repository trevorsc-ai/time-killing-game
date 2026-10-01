import SwiftUI

/// Every screen reachable via NavigationStack. In-game overlays (pause, level complete, tips) are not screens.
enum Screen: Hashable {
    case game(levelId: String)
    case map
    case levelSelect(destinationId: String)
    case relax
    case daily
    case scrapbook
    case settings
    case backup
    case restoration(destinationId: String)
}

/// Owns the NavigationStack path. Inject as an environment object.
@MainActor
final class Router: ObservableObject {
    @Published var path: [Screen] = []

    func push(_ screen: Screen) { path.append(screen) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

    /// Replaces the whole stack (e.g. jump back to a level list with the map underneath).
    func set(_ screens: [Screen]) { path = screens }
}

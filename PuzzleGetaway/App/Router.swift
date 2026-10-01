import SwiftUI

/// Every screen reachable via NavigationStack. The Shell agent extends this enum (one case per screen).
enum Screen: Hashable {
    case game(levelId: String)
    case map
    case levelSelect(destinationId: String)
    case relax
    case daily
    case scrapbook
    case settings
    case backup
}

/// Owns the NavigationStack path. Inject as an environment object.
@MainActor
final class Router: ObservableObject {
    @Published var path: [Screen] = []

    func push(_ screen: Screen) { path.append(screen) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}

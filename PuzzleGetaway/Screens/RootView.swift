import SwiftUI

/// Hosts the NavigationStack and maps `Screen` values to views. STUB: the Shell agent replaces the destinations.
struct RootView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack(path: $router.path) {
            MainMenuView()
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .game(let levelId):
                        GameScreen(levelId: levelId)
                    case .settings:
                        SettingsStubView()
                    default:
                        PlaceholderScreen(title: String(describing: screen))
                    }
                }
        }
        .background(theme.background.ignoresSafeArea())
    }
}

struct PlaceholderScreen: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text("\(title) - coming soon")
            .font(Theme.heading)
            .foregroundColor(theme.textSecondary)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
    }
}

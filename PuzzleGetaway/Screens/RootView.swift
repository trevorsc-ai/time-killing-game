import SwiftUI

/// Hosts the NavigationStack, maps `Screen` values to views, and shows the brief launch splash.
struct RootView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var showSplash = true

    var body: some View {
        ZStack {
            NavigationStack(path: $router.path) {
                MainMenuView()
                    .navigationDestination(for: Screen.self) { screen in
                        destination(for: screen)
                    }
            }
            .tint(theme.accent)
            if showSplash {
                SplashView { showSplash = false }
                    .transition(.opacity)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            if model.skipSplash || model.settings.effectiveReduceMotion { showSplash = false }
        }
    }

    @ViewBuilder
    private func destination(for screen: Screen) -> some View {
        switch screen {
        case .game(let levelId):
            GameScreen(levelId: levelId)
        case .map:
            MapView()
        case .levelSelect(let destinationId):
            LevelSelectView(destinationId: destinationId)
        case .relax:
            RelaxView()
        case .daily:
            DailyView()
        case .scrapbook:
            ScrapbookView()
        case .settings:
            SettingsView()
        case .backup:
            BackupView()
        case .restoration(let destinationId):
            RestorationView(destinationId: destinationId)
        }
    }
}

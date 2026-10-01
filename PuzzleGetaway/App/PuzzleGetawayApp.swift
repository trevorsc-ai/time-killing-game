import SwiftUI

@main
struct PuzzleGetawayApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(router)
                .environment(\.theme, model.theme)
                .tint(model.theme.accent)
        }
        .onChange(of: scenePhase) { phase in
            // Immediate save whenever we leave the foreground.
            if phase == .inactive || phase == .background {
                model.saveNow()
            }
        }
    }
}

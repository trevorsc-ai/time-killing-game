import SwiftUI

/// STUB main menu. The Shell agent replaces this.
struct MainMenuView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Spacer()
            Text("Puzzle Getaway")
                .font(Theme.title)
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("All aboard the Lantern Line")
                .font(Theme.body)
                .foregroundColor(theme.textSecondary)
            Spacer()
            if let error = model.contentError {
                Text(error).font(Theme.caption).foregroundColor(theme.warning)
            }
            Button("Quick Play") {
                if let level = model.quickPlayLevel() {
                    router.push(.game(levelId: level.id))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("quickPlayButton")
            Button("Settings") { router.push(.settings) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("settingsButton")
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

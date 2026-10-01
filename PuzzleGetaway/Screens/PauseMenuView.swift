import SwiftUI

/// Gentle pause card: Resume, Restart, Settings, Level select, Main menu. Nothing is lost by pausing.
struct PauseMenuView: View {
    let levelSelectTitle: String
    let onResume: () -> Void
    let onRestart: () -> Void
    let onSettings: () -> Void
    let onLevelSelect: () -> Void
    let onMainMenu: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onResume)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Paused")
                    .font(Theme.heading)
                    .foregroundColor(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Take your time. Your progress is saved.")
                    .font(Theme.caption)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button(action: onResume) {
                    Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pauseResume")
                row("Restart", "arrow.counterclockwise", "pauseRestart", onRestart)
                row("Settings", "gearshape.fill", "pauseSettings", onSettings)
                row(levelSelectTitle, "square.grid.2x2.fill", "pauseLevelSelect", onLevelSelect)
                row("Main menu", "house.fill", "pauseMainMenu", onMainMenu)
            }
            .padding(22)
            .frame(maxWidth: 380)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius + 6, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 8)
            .padding(24)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func row(_ title: String, _ icon: String, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier(id)
    }
}

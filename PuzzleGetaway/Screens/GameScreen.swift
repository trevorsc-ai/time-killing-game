import SwiftUI

/// STUB game container: hosts `controller.boardView` with a minimal HUD (Undo / Restart / Hint).
/// The Shell agent replaces this with the full container (pause, complete screen, tips, iPad layout).
struct GameScreen: View {
    let levelId: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.theme) private var theme
    @State private var controller: AnyGameController?

    var body: some View {
        Group {
            if let controller = controller {
                GameContent(controller: controller, onBack: { router.pop() })
            } else {
                Text("Loading...")
                    .font(Theme.body)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard controller == nil, let level = model.content?.level(id: levelId) else { return }
            controller = model.makeController(for: level)
        }
    }
}

private struct GameContent: View {
    @ObservedObject var controller: AnyGameController
    let onBack: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Theme.spacing) {
            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("backButton")
                Spacer()
                Text(controller.title)
                    .font(Theme.heading)
                    .foregroundColor(theme.textPrimary)
                Spacer()
                if model.settings.showMoveCounter {
                    Text("Moves: \(controller.moveCount)")
                        .font(Theme.caption)
                        .foregroundColor(theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            controller.boardView
            Spacer(minLength: 0)
            if controller.isSolved {
                VStack(spacing: Theme.smallSpacing) {
                    Text("Solved! \(String(repeating: "★", count: controller.stars))")
                        .font(Theme.heading)
                        .foregroundColor(theme.success)
                        .accessibilityIdentifier("solvedLabel")
                    Button("Continue", action: onBack).buttonStyle(PrimaryButtonStyle())
                }
                .cardStyle()
            } else if controller.isStuck {
                Text("The Pals are jammed. Try Undo or Restart.")
                    .font(Theme.body)
                    .foregroundColor(theme.warning)
                    .cardStyle()
            }
            HStack(spacing: Theme.spacing) {
                Button("Undo") { controller.undo() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!controller.canUndo)
                    .accessibilityIdentifier("undoButton")
                Button("Restart") { controller.restart() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("restartButton")
                Button("Hint") { controller.requestHint() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(controller.isSolved)
                    .accessibilityIdentifier("hintButton")
            }
            .environment(\.layoutDirection, model.settings.leftHanded ? .rightToLeft : .leftToRight)
        }
        .padding()
        .onChange(of: controller.isSolved) { solved in
            if solved {
                model.recordCompletion(levelId: controller.levelId, stars: controller.stars, moves: controller.moveCount)
            }
        }
    }
}

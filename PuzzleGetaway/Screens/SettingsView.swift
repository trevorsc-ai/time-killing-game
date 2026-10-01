import SwiftUI

/// Settings and accessibility. Everything scrolls, so large Dynamic Type sizes work.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        SettingsForm(settings: model.settings)
    }
}

private struct SettingsForm: View {
    @ObservedObject var settings: Settings
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.theme) private var theme
    @State private var confirmReset = false
    @State private var resetDone = false

    var body: some View {
        Form {
            Section {
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
                    .accessibilityIdentifier("toggleHaptics")
            } header: {
                Text("Feel")
            } footer: {
                Text("Gentle taps when you move or finish a puzzle. There is no sound in this game.")
            }

            Section {
                Toggle("Reduce motion", isOn: $settings.reduceMotion)
                    .accessibilityIdentifier("toggleReduceMotion")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Animation speed")
                    Picker("Animation speed", selection: $settings.animationSpeed) {
                        Text("1×").tag(1)
                        Text("2×").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("pickerSpeed")
                }
            } header: {
                Text("Motion")
            } footer: {
                Text("Reduce motion also follows your device's Reduce Motion setting.")
            }

            Section {
                Toggle("Color symbols and patterns", isOn: $settings.showPatterns)
                    .accessibilityIdentifier("togglePatterns")
                Toggle("High contrast", isOn: $settings.highContrast)
                    .accessibilityIdentifier("toggleHighContrast")
            } header: {
                Text("Seeing")
            } footer: {
                Text("Symbols help tell colors apart without relying on color alone.")
            }

            Section {
                Toggle("Left-handed controls", isOn: $settings.leftHanded)
                    .accessibilityIdentifier("toggleLeftHanded")
                Toggle("Show move counter", isOn: $settings.showMoveCounter)
                    .accessibilityIdentifier("toggleMoveCounter")
                Toggle("Tutorial tips", isOn: $settings.showTips)
                    .accessibilityIdentifier("toggleTips")
                Button("Show tutorials again") { confirmReset = true }
                    .frame(minHeight: Theme.minTapTarget, alignment: .leading)
                    .accessibilityIdentifier("resetTutorials")
                if resetDone {
                    Text("Tips will appear again the next time you meet them.")
                        .font(Theme.caption)
                        .foregroundColor(theme.textSecondary)
                }
            } header: {
                Text("Playing")
            }

            Section {
                Button {
                    router.push(.backup)
                } label: {
                    HStack {
                        Label("Progress and backup", systemImage: "externaldrive.fill")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(theme.textSecondary)
                    }
                    .frame(minHeight: Theme.minTapTarget)
                }
                .accessibilityIdentifier("openBackup")
            } header: {
                Text("Your progress")
            } footer: {
                Text("Puzzle Getaway works fully offline. No account, no ads, no tracking.")
            }
        }
        .clearScrollBackground()
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Show tutorials again?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Show them again") {
                model.resetTutorials()
                resetDone = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tip cards and stop introductions will appear again as you meet them.")
        }
    }
}

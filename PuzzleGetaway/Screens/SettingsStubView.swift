import SwiftUI

/// STUB settings screen with the basic toggles. The Shell agent replaces this.
struct SettingsStubView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsForm(settings: model.settings)
    }
}

private struct SettingsForm: View {
    @ObservedObject var settings: Settings
    @Environment(\.theme) private var theme

    var body: some View {
        Form {
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
            Toggle("Reduce motion", isOn: $settings.reduceMotion)
            Toggle("Double animation speed", isOn: Binding(
                get: { settings.animationSpeed == 2 },
                set: { settings.animationSpeed = $0 ? 2 : 1 }
            ))
            Toggle("Show color patterns", isOn: $settings.showPatterns)
            Toggle("High contrast", isOn: $settings.highContrast)
            Toggle("Left-handed HUD", isOn: $settings.leftHanded)
            Toggle("Show move counter", isOn: $settings.showMoveCounter)
        }
        .navigationTitle("Settings")
    }
}

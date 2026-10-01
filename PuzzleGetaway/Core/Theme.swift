import SwiftUI
import UIKit

// MARK: - Color helpers

extension Color {
    /// "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var n: UInt64 = 0
        Scanner(string: s).scanHexInt64(&n)
        self.init(
            .sRGB,
            red: Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8) & 0xFF) / 255,
            blue: Double(n & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Color that adapts to light / dark appearance.
    init(light: String, dark: String) {
        self.init(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(Color(hex: hex))
        })
    }
}

extension PaletteColor {
    /// Resolved SwiftUI color, honoring the high-contrast setting.
    func color(highContrast: Bool) -> Color {
        Color(hex: highContrast ? highContrastHex : hex)
    }
}

// MARK: - Theme

/// Design tokens. Use `@Environment(\.theme) var theme`; `AppModel`/root view injects a theme matching Settings.
struct Theme: Equatable {
    var highContrast: Bool = false

    // Colors (adapt to dark mode; high contrast pushes text/stroke toward extremes).
    var background: Color { highContrast ? Color(light: "#FFFFFF", dark: "#000000") : Color(light: "#FFF6E8", dark: "#1D1F2E") }
    var surface: Color { highContrast ? Color(light: "#FFFFFF", dark: "#0A0A0A") : Color(light: "#FFFFFF", dark: "#2A2D40") }
    var surfaceAlt: Color { highContrast ? Color(light: "#EDEDED", dark: "#1A1A1A") : Color(light: "#F7ECD9", dark: "#353850") }
    var textPrimary: Color { highContrast ? Color(light: "#000000", dark: "#FFFFFF") : Color(light: "#3A3350", dark: "#F4EFE6") }
    var textSecondary: Color { highContrast ? Color(light: "#222222", dark: "#E6E6E6") : Color(light: "#6E6788", dark: "#BDB8CE") }
    var accent: Color { highContrast ? Color(light: "#A8470F", dark: "#FFB27A") : Color(light: "#E98B5F", dark: "#F2A27A") }
    var accentText: Color { highContrast ? Color(light: "#FFFFFF", dark: "#000000") : Color(light: "#FFFFFF", dark: "#2A1E14") }
    var success: Color { highContrast ? Color(light: "#0B6B25", dark: "#7CF09A") : Color(light: "#4FB06A", dark: "#6FD08A") }
    var warning: Color { highContrast ? Color(light: "#8A4B00", dark: "#FFC266") : Color(light: "#F2A93D", dark: "#F6BC62") }
    var stroke: Color { highContrast ? Color(light: "#000000", dark: "#FFFFFF") : Color(light: "#E3D6BE", dark: "#44486A") }
    var strokeWidth: CGFloat { highContrast ? 2 : 1 }

    // Metrics
    static let minTapTarget: CGFloat = 44
    static let cornerRadius: CGFloat = 20
    static let smallCornerRadius: CGFloat = 12
    static let spacing: CGFloat = 16
    static let smallSpacing: CGFloat = 8

    // Typography: SF Rounded, scales with Dynamic Type.
    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
    static var title: Font { font(.largeTitle, weight: .bold) }
    static var heading: Font { font(.title2, weight: .semibold) }
    static var body: Font { font(.body) }
    static var caption: Font { font(.footnote) }
    static var button: Font { font(.headline, weight: .semibold) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Styles

private struct CardModifier: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .padding(Theme.spacing)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(theme.stroke, lineWidth: theme.strokeWidth)
            )
    }
}

private struct MinTargetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Rounded card surface with stroke.
    func cardStyle() -> some View { modifier(CardModifier()) }
    /// Guarantees a 44x44pt minimum hit area.
    func minTapTarget() -> some View { modifier(MinTargetModifier()) }
}

/// Filled rounded primary button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button)
            .foregroundColor(theme.accentText)
            .padding(.horizontal, Theme.spacing * 1.5)
            .padding(.vertical, 12)
            .frame(minHeight: Theme.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4))
            )
    }
}

/// Soft secondary button (HUD actions).
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button)
            .foregroundColor(theme.textPrimary.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 10)
            .frame(minHeight: Theme.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                    .fill(theme.surfaceAlt.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                    .stroke(theme.stroke, lineWidth: theme.strokeWidth)
            )
    }
}

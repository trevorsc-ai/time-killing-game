import SwiftUI

// MARK: - Backgrounds

extension View {
    /// Fills the screen with the theme background (ignoring safe areas behind the content).
    func screenBackground() -> some View {
        modifier(ScreenBackgroundModifier())
    }

    /// Reads a clean scroll background in Forms and Lists (iOS 16).
    func clearScrollBackground() -> some View {
        scrollContentBackground(.hidden)
    }
}

private struct ScreenBackgroundModifier: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
    }
}

// MARK: - Stars

struct StarRow: View {
    let earned: Int
    var total: Int = 3
    var size: CGFloat = 16
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: i < earned ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(i < earned ? theme.warning : theme.stroke)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned) of \(total) stars")
    }
}

// MARK: - Progress bar

struct SoftProgressBar: View {
    let value: Double
    var tint: Color?
    var height: CGFloat = 12
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.surfaceAlt)
                Capsule()
                    .fill(tint ?? theme.accent)
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(value, 0), 1))))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .overlay(Capsule().stroke(theme.stroke, lineWidth: theme.strokeWidth))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

// MARK: - Toast

/// A gentle, self-dismissing note (no modal, no buttons).
struct ToastView: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(Theme.font(.subheadline, weight: .medium))
            .foregroundColor(theme.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().stroke(theme.stroke, lineWidth: theme.strokeWidth))
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Small helper to show a toast for a couple of seconds.
@MainActor
final class ToastCenter: ObservableObject {
    @Published var message: String?
    private var token = 0

    func show(_ text: String, seconds: Double = 2.6) {
        token += 1
        let mine = token
        message = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self = self, self.token == mine else { return }
            self.message = nil
        }
    }
}

// MARK: - Cards and rows

/// Rounded surface with a soft shadow, the base for tappable cards.
struct SoftCard<Content: View>: View {
    let padding: CGFloat
    let content: Content
    @Environment(\.theme) private var theme

    init(padding: CGFloat = Theme.spacing, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(theme.stroke, lineWidth: theme.strokeWidth)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 3)
    }
}

/// Plain button style that only dims on press (cards use their own visuals).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

// MARK: - Mode metadata

enum ModeInfo {
    static func icon(for mode: String) -> String {
        switch mode {
        case "liquid": return "drop.fill"
        case "bolt": return "gearshape.fill"
        case "pixel": return "square.grid.3x3.fill"
        case "parking": return "car.fill"
        case "pipe": return "arrow.triangle.branch"
        default: return "puzzlepiece.fill"
        }
    }

    static func name(for mode: String) -> String {
        if let plugin = ModeRegistry.plugin(for: mode) { return plugin.displayName }
        switch mode {
        case "liquid": return "Liquid"
        case "bolt": return "Bolt"
        case "pixel": return "Pixel Picnic"
        case "parking": return "Baggage Jam"
        case "pipe": return "Flow Fix"
        default: return mode.capitalized
        }
    }
}

enum DestinationInfo {
    static func icon(for id: String) -> String {
        switch id {
        case "d1": return "cup.and.saucer.fill"
        case "d2": return "leaf.fill"
        case "d3": return "suitcase.fill"
        case "d4": return "cloud.rain.fill"
        case "d5": return "wrench.and.screwdriver.fill"
        case "d6": return "books.vertical.fill"
        case "d7": return "sun.max.fill"
        case "d8": return "snowflake"
        default: return "tram.fill"
        }
    }
}

// MARK: - Play kinds

/// How a level is being played: campaign (stars, unlocks), Relax (unscored) or Daily Journey.
enum PlayKind: Equatable {
    case campaign
    case relax(pool: String)
    case daily

    init(level: LevelEnvelope) {
        if level.destination == Progression.dailyPool {
            self = .daily
        } else if level.destination.hasPrefix("relax-") {
            self = .relax(pool: level.destination)
        } else {
            self = .campaign
        }
    }

    var isScored: Bool { self == .campaign }
}

import SwiftUI

// MARK: - Buttons

/// Round 44pt+ icon button for the top bar (Back, Pause).
struct HUDIconButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(theme.surfaceAlt))
                .overlay(Circle().stroke(theme.stroke, lineWidth: theme.strokeWidth))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// Thumb-bar action: icon over a short label, 44pt minimum in both directions.
struct HUDActionButton: View {
    let systemImage: String
    let title: String
    let identifier: String
    var enabled: Bool = true
    var hint: String = ""
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(Theme.font(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(theme.textPrimary.opacity(enabled ? 1 : 0.35))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(theme.surfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(theme.stroke, lineWidth: theme.strokeWidth)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Cards

/// First-time tutorial tip: dismissible, never blocks the board.
struct TipCardView: View {
    let tip: TipCard
    let onDismiss: () -> Void
    let onHideTips: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        SoftCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(theme.warning)
                        .font(.system(size: 20))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tip.title)
                            .font(Theme.font(.headline, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(tip.body)
                            .font(Theme.font(.subheadline))
                            .foregroundColor(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    Button("Hide tips", action: onHideTips)
                        .font(Theme.font(.footnote, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                        .frame(minHeight: Theme.minTapTarget)
                        .accessibilityIdentifier("tipHide")
                    Spacer(minLength: 0)
                    Button("Got it", action: onDismiss)
                        .font(Theme.font(.subheadline, weight: .semibold))
                        .foregroundColor(theme.accentText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: Theme.minTapTarget)
                        .background(Capsule().fill(theme.accent))
                        .accessibilityIdentifier("tipDismiss")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Calm "nothing more to do here" card with Undo / Restart. No game over, ever.
struct StuckCardView: View {
    let title: String
    let canUndo: Bool
    let onUndo: () -> Void
    let onRestart: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        SoftCard {
            VStack(spacing: 10) {
                Text(title)
                    .font(Theme.heading)
                    .foregroundColor(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("That happens! Step back a move or start fresh. There's no rush.")
                    .font(Theme.body)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    if canUndo {
                        Button(action: onUndo) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("stuckUndo")
                        Button(action: onRestart) {
                            Label("Restart", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("stuckRestart")
                    } else {
                        Button(action: onRestart) {
                            Label("Restart", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("stuckRestart")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stuckCard")
    }
}

// MARK: - iPad side panel

/// Right-hand panel for iPad landscape: level info, star criteria, restoration preview.
struct GameSidePanel: View {
    @ObservedObject var controller: AnyGameController
    let level: LevelEnvelope
    let kind: PlayKind
    let destination: Destination?
    let stageCount: Int
    let stars: Int
    let nextStageText: String?
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                SoftCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(subtitle)
                            .font(Theme.caption)
                            .foregroundColor(theme.textSecondary)
                        Text(level.title)
                            .font(Theme.heading)
                            .foregroundColor(theme.textPrimary)
                        Label(ModeInfo.name(for: level.mode), systemImage: ModeInfo.icon(for: level.mode))
                            .font(Theme.font(.subheadline, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                        Text("Par \(level.par) · Moves \(controller.moveCount)")
                            .font(Theme.font(.subheadline))
                            .foregroundColor(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if kind.isScored {
                    SoftCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stars")
                                .font(Theme.font(.headline, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                            criterion("Finish the puzzle", met: controller.isSolved, always: false)
                            criterion("No hints (\(controller.hintsUsed) used)", met: controller.hintsUsed == 0, always: true)
                            criterion("3 or fewer undos (\(controller.undoCount) used)", met: controller.undoCount <= 3, always: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    SoftCard {
                        Text("No stars, no pressure. Undo as much as you like.")
                            .font(Theme.body)
                            .foregroundColor(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let dest = destination, kind == .campaign, !dest.restorationStages.isEmpty {
                    SoftCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dest.restorationTitle)
                                .font(Theme.font(.headline, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                            RestorationArtView(destinationId: dest.id, stage: stageCount, showcase: false, animated: false)
                                .aspectRatio(1.3, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                            Text("Stage \(stageCount) of \(dest.restorationStages.count) · \(stars) stars")
                                .font(Theme.caption)
                                .foregroundColor(theme.textSecondary)
                            if let text = nextStageText {
                                Text(text).font(Theme.caption).foregroundColor(theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(Theme.spacing)
        }
    }

    private var subtitle: String {
        switch kind {
        case .campaign: return "Level \(level.order)" + (destination.map { " · \($0.name)" } ?? "")
        case .relax(let pool): return "Relax · \(Progression.relaxTitle(pool: pool))"
        case .daily: return "Daily Journey"
        }
    }

    private func criterion(_ text: String, met: Bool, always: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundColor(met ? theme.success : theme.stroke)
            Text(text)
                .font(Theme.font(.subheadline))
                .foregroundColor(theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

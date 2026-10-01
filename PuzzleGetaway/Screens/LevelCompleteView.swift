import SwiftUI

/// Everything the completion card shows, gathered by the game screen.
struct CompletionSummary {
    var kind: PlayKind
    var level: LevelEnvelope
    var stars: Int
    var moves: Int
    var hintsUsed: Int
    var undoCount: Int
    var newStages: [RestorationStage]
    var unlockedDestination: Destination?
    var journeysTaken: Int
    var hasNext: Bool
}

/// Level Complete card: kind, never shaming. Stars show what was earned and gently how to earn the rest.
struct LevelCompleteView: View {
    let summary: CompletionSummary
    let settings: Settings
    let onNext: () -> Void
    let onReplay: () -> Void
    let onMap: () -> Void
    let onRestoration: () -> Void
    @Environment(\.theme) private var theme
    @State private var shown = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                cardContent.padding(22)
                ScrollView { cardContent.padding(22) }
            }
            .frame(maxWidth: 440)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius + 6, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 8)
            .padding(20)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { animateStars() }
    }

    private var cardContent: some View {
        VStack(spacing: 14) {
            Text(headline)
                .font(Theme.title)
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("levelCompleteTitle")
            if summary.kind.isScored {
                starsBlock
            } else {
                Text(summary.kind == .daily ? "Journey complete. See you on the next one." : "Nicely done. No stars, no pressure.")
                    .font(Theme.body)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
                if summary.kind == .daily {
                    Text("Journeys taken: \(summary.journeysTaken)")
                        .font(Theme.font(.headline, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }
            }
            movesLine
            if !summary.newStages.isEmpty { restorationBanner }
            if let dest = summary.unlockedDestination {
                Label("A new stop opened: \(dest.name)", systemImage: "map.fill")
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
            }
            buttons
        }

    }

    private var headline: String {
        switch summary.kind {
        case .campaign: return "Level complete!"
        case .relax: return "Puzzle solved"
        case .daily: return "Journey taken"
        }
    }

    // MARK: Stars

    private var starsBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < summary.stars ? "star.fill" : "star")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(i < summary.stars ? theme.warning : theme.stroke)
                        .scaleEffect(i < shown ? 1 : 0.4)
                        .opacity(i < shown || i >= summary.stars ? 1 : 0)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(summary.stars) of 3 stars")
            VStack(alignment: .leading, spacing: 6) {
                criterion(done: true, earnedText: "Finished the puzzle", missedText: "")
                criterion(done: summary.hintsUsed == 0,
                          earnedText: "Solved without hints",
                          missedText: "Hints are there to help. Try one without next time for a star.")
                criterion(done: summary.undoCount <= 3,
                          earnedText: "Three undos or fewer",
                          missedText: "Undo as often as you like. Three or fewer earns a star.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func criterion(done: Bool, earnedText: String, missedText: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundColor(done ? theme.success : theme.textSecondary)
            Text(done ? earnedText : missedText)
                .font(Theme.font(.subheadline))
                .foregroundColor(done ? theme.textPrimary : theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var movesLine: some View {
        let moves = summary.moves
        let par = summary.level.par
        let text: String
        if !summary.kind.isScored {
            text = ""
        } else if moves <= par {
            text = "\(moves) moves. Right on par!"
        } else {
            text = "\(moves) moves. Par is \(par), just a friendly target."
        }
        return Group {
            if !text.isEmpty {
                Text(text)
                    .font(Theme.font(.subheadline, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var restorationBanner: some View {
        VStack(spacing: 8) {
            Label("Restoration unlocked!", systemImage: "sparkles")
                .font(Theme.font(.headline, weight: .bold))
                .foregroundColor(theme.textPrimary)
            Text(summary.newStages.map { $0.title }.joined(separator: ", "))
                .font(Theme.font(.subheadline))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("See what changed", action: onRestoration)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("seeRestoration")
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            switch summary.kind {
            case .campaign:
                if summary.hasNext {
                    Button(action: onNext) { Text("Next level").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("nextLevelButton")
                } else {
                    Button(action: onMap) { Text("Back to the map").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("mapButtonComplete")
                }
                HStack(spacing: 10) {
                    Button(action: onReplay) { Text("Replay").frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("replayButton")
                    if summary.hasNext {
                        Button(action: onMap) { Text("Map").frame(maxWidth: .infinity) }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("mapButtonComplete")
                    }
                }
            case .relax:
                Button(action: onNext) { Text("Next puzzle").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("nextPuzzleButton")
                HStack(spacing: 10) {
                    Button(action: onReplay) { Text("Replay").frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("replayButton")
                    Button(action: onMap) { Text("Relax menu").frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("mapButtonComplete")
                }
            case .daily:
                Button(action: onMap) { Text("Back to Daily Journey").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("mapButtonComplete")
                Button(action: onReplay) { Text("Play it again").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("replayButton")
            }
        }
    }

    // MARK: Motion

    private func animateStars() {
        guard summary.kind.isScored else { return }
        if settings.effectiveReduceMotion {
            shown = 3
            return
        }
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 * Double(i + 1)) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { shown = i + 1 }
            }
        }
    }
}

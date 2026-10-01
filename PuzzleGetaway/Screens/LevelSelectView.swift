import SwiftUI

/// Level grid for one destination, in `order`, with sequential unlock and the restoration progress bar.
struct LevelSelectView: View {
    let destinationId: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.theme) private var theme
    @StateObject private var toast = ToastCenter()

    private var destination: Destination? { model.progression.destination(destinationId) }
    private var levels: [LevelEnvelope] { model.progression.levels(in: destinationId) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: Theme.spacing) {
                    if let dest = destination {
                        header(dest)
                        restorationCard(dest)
                    }
                    if levels.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 130), spacing: 12)], spacing: 12) {
                            ForEach(levels) { level in
                                tile(level)
                            }
                        }
                    }
                }
                .padding(Theme.spacing)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            if let message = toast.message {
                ToastView(text: message).padding(.bottom, 24).transition(.opacity)
            }
        }
        .screenBackground()
        .navigationTitle(destination?.name ?? "Levels")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Pieces

    private func header(_ dest: Destination) -> some View {
        VStack(spacing: 6) {
            Text(dest.tagline)
                .font(Theme.body)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func restorationCard(_ dest: Destination) -> some View {
        let stars = model.progression.stars(in: dest.id, save: model.save)
        let count = model.progression.unlockedStageCount(in: dest.id, save: model.save)
        let total = dest.restorationStages.count
        let next = model.progression.nextStage(in: dest.id, save: model.save)
        let fraction: Double = {
            guard let next = next else { return 1 }
            let prevReq = count > 0 ? dest.restorationStages[count - 1].starsRequired : 0
            let span = max(1, next.starsRequired - prevReq)
            return Double(stars - prevReq) / Double(span)
        }()
        return Button {
            router.push(.restoration(destinationId: dest.id))
        } label: {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        RestorationArtView(destinationId: dest.id, stage: count, showcase: false, animated: false)
                            .frame(width: 84, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dest.restorationTitle)
                                .font(Theme.font(.headline, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text("Stage \(count) of \(total) · \(stars) stars")
                                .font(Theme.caption)
                                .foregroundColor(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundColor(theme.textSecondary)
                    }
                    SoftProgressBar(value: fraction)
                    if let next = next {
                        Text("\(max(0, next.starsRequired - stars)) more \(next.starsRequired - stars == 1 ? "star" : "stars") for \u{201C}\(next.title)\u{201D}")
                            .font(Theme.caption)
                            .foregroundColor(theme.textSecondary)
                    } else {
                        Text("Fully restored. Take a look!")
                            .font(Theme.caption)
                            .foregroundColor(theme.success)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dest.restorationTitle). Stage \(count) of \(total). \(stars) stars collected.")
        .accessibilityHint("Opens the restoration scene")
        .accessibilityIdentifier("restorationLink")
    }

    private var emptyState: some View {
        SoftCard {
            VStack(spacing: 10) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 30))
                    .foregroundColor(theme.accent)
                Text("Track being laid…")
                    .font(Theme.heading)
                    .foregroundColor(theme.textPrimary)
                Text("The Parcel Pals are still hammering the rails here. Puzzles will roll in soon.")
                    .font(Theme.body)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("trackBeingLaid")
    }

    private func tile(_ level: LevelEnvelope) -> some View {
        let result = model.save.progress[level.id]
        let unlocked = model.progression.isLevelUnlocked(level, save: model.save)
        let solved = result != nil
        let isNext = unlocked && !solved
        let inProgress = model.save.inProgress[level.id] != nil
        let modeName = ModeInfo.name(for: level.mode)
        return Button {
            if unlocked {
                router.push(.game(levelId: level.id))
            } else {
                model.haptics.invalid()
                toast.show("Finish the level before this one to open it.")
            }
        } label: {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: unlocked ? ModeInfo.icon(for: level.mode) : "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(unlocked ? theme.accent : theme.textSecondary)
                    Spacer(minLength: 0)
                    if inProgress && !solved {
                        Circle().fill(theme.warning).frame(width: 8, height: 8)
                    }
                }
                Text("\(level.order)")
                    .font(Theme.font(.title2, weight: .bold))
                    .foregroundColor(unlocked ? theme.textPrimary : theme.textSecondary)
                if solved {
                    StarRow(earned: result?.stars ?? 0, size: 13)
                } else {
                    StarRow(earned: 0, size: 13).opacity(unlocked ? 0.6 : 0.25)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallCornerRadius + 2, style: .continuous)
                    .fill(unlocked ? theme.surface : theme.surfaceAlt.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallCornerRadius + 2, style: .continuous)
                    .stroke(isNext ? theme.accent : theme.stroke, lineWidth: isNext ? 2.5 : theme.strokeWidth)
            )
            .shadow(color: Color.black.opacity(unlocked ? 0.06 : 0), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tileLabel(level: level, modeName: modeName, unlocked: unlocked, stars: result?.stars, inProgress: inProgress))
        .accessibilityIdentifier("level-\(level.id)")
    }

    private func tileLabel(level: LevelEnvelope, modeName: String, unlocked: Bool, stars: Int?, inProgress: Bool) -> String {
        if !unlocked { return "Level \(level.order), locked" }
        var text = "Level \(level.order), \(level.title), \(modeName)"
        if let stars = stars { text += ", \(stars) of 3 stars" } else if inProgress { text += ", in progress" } else { text += ", not played yet" }
        return text
    }
}

import SwiftUI

/// The restoration scene for one destination: a vector illustration that improves with each unlocked stage.
/// New stages play a small unlock animation the first time they are seen; a fully completed destination gets a showcase.
struct RestorationView: View {
    let destinationId: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    @State private var shownStage = 0
    @State private var didSetup = false
    @State private var banner: String?
    @State private var burst = false

    private var destination: Destination? { model.progression.destination(destinationId) }
    private var stages: [RestorationStage] { destination?.restorationStages ?? [] }
    private var stars: Int { model.progression.stars(in: destinationId, save: model.save) }
    private var unlockedCount: Int { model.progression.unlockedStageCount(in: destinationId, save: model.save) }
    private var isShowcase: Bool {
        !stages.isEmpty && unlockedCount == stages.count && model.progression.isDestinationComplete(destinationId, save: model.save)
    }
    private var reduceMotion: Bool { model.settings.effectiveReduceMotion }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                if stages.isEmpty {
                    Text("This project isn't ready yet. The Pals are still drawing up plans.")
                        .font(Theme.body)
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    scene
                    if let banner = banner {
                        Label(banner, systemImage: "sparkles")
                            .font(Theme.font(.headline, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                            .transition(.opacity)
                            .accessibilityIdentifier("stageUnlockedBanner")
                    }
                    progressCard
                    stageList
                }
            }
            .padding(Theme.spacing)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(destination?.restorationTitle ?? "Restoration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setUp() }
    }

    // MARK: Scene

    private var scene: some View {
        ZStack {
            RestorationArtView(destinationId: destinationId, stage: shownStage,
                               showcase: isShowcase && shownStage == stages.count,
                               animated: !reduceMotion)
                .id(shownStage)
                .transition(.opacity)
            if burst && !reduceMotion {
                StarBurst()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).stroke(theme.stroke, lineWidth: theme.strokeWidth))
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        .accessibilityIdentifier("restorationScene")
    }

    private var progressCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                if isShowcase {
                    Label("Fully restored", systemImage: "rosette")
                        .font(Theme.font(.headline, weight: .bold))
                        .foregroundColor(theme.success)
                    Text("Every level here is done and the \(destination?.name ?? "project") is shining. Thank you, driver!")
                        .font(Theme.body)
                        .foregroundColor(theme.textPrimary)
                } else if let next = model.progression.nextStage(in: destinationId, save: model.save) {
                    Text("Next: \(next.title)")
                        .font(Theme.font(.headline, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                    let prevReq = unlockedCount > 0 ? stages[unlockedCount - 1].starsRequired : 0
                    let span = max(1, next.starsRequired - prevReq)
                    SoftProgressBar(value: Double(stars - prevReq) / Double(span))
                    let more = max(0, next.starsRequired - stars)
                    Text("\(more) more \(more == 1 ? "star" : "stars") to go. You have \(stars).")
                        .font(Theme.caption)
                        .foregroundColor(theme.textSecondary)
                } else {
                    Label("All stages restored", systemImage: "checkmark.seal.fill")
                        .font(Theme.font(.headline, weight: .bold))
                        .foregroundColor(theme.success)
                    Text("Finish the remaining levels to see the grand showcase.")
                        .font(Theme.body)
                        .foregroundColor(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stageList: some View {
        VStack(spacing: 8) {
            stageRow(index: 0, title: "Before", stars: 0, unlocked: true)
            ForEach(Array(stages.enumerated()), id: \.element.id) { i, stage in
                stageRow(index: i + 1, title: stage.title, stars: stage.starsRequired, unlocked: stage.starsRequired <= stars)
            }
        }
    }

    private func stageRow(index: Int, title: String, stars required: Int, unlocked: Bool) -> some View {
        let selected = shownStage == index
        return Button {
            guard unlocked else { return }
            model.haptics.selection()
            select(index)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: unlocked ? (selected ? "circle.inset.filled" : "circle") : "lock.fill")
                    .foregroundColor(unlocked ? theme.accent : theme.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.font(.subheadline, weight: .semibold))
                        .foregroundColor(unlocked ? theme.textPrimary : theme.textSecondary)
                    if index > 0 {
                        Text("\(required) stars")
                            .font(Theme.caption)
                            .foregroundColor(theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(minHeight: Theme.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                    .fill(selected ? theme.accent.opacity(0.14) : theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                    .stroke(selected ? theme.accent : theme.stroke, lineWidth: selected ? 2 : theme.strokeWidth)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(index == 0 ? "Before restoration" : "Stage \(index), \(title), \(unlocked ? "unlocked" : "locked, needs \(required) stars")")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("stage-\(index)")
    }

    // MARK: Behavior

    private func select(_ index: Int) {
        if reduceMotion { shownStage = index } else {
            withAnimation(.easeInOut(duration: 0.4)) { shownStage = index }
        }
    }

    private func setUp() {
        guard !didSetup else { return }
        didSetup = true
        let seenIds = model.save.restorationStagesSeen
        let limit = unlockedCount
        let unseen = stages.enumerated().filter { pair in
            pair.offset < limit && !seenIds.contains(pair.element.id)
        }
        // Stages the player has never looked at yet: start one step before, then reveal.
        guard let firstUnseen = unseen.first else {
            shownStage = unlockedCount
            return
        }
        shownStage = firstUnseen.offset
        let newest = unseen.last?.element
        let ids = unseen.map { $0.element.id }
        let target = unlockedCount
        let delay = reduceMotion ? 0.0 : 0.7
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if reduceMotion {
                shownStage = target
            } else {
                withAnimation(.easeInOut(duration: 0.6)) { shownStage = target }
                burst = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { burst = false }
            }
            if let newest = newest {
                banner = "Stage unlocked: \(newest.title)"
            }
            model.haptics.success()
            model.markRestorationStagesSeen(ids)
        }
    }
}

/// A short ring of stars that drifts outward and fades (not shown with Reduce Motion).
private struct StarBurst: View {
    @State private var spread = false
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10 * 2 * Double.pi
                Image(systemName: i % 2 == 0 ? "star.fill" : "sparkle")
                    .font(.system(size: 18))
                    .foregroundColor(theme.warning)
                    .offset(x: spread ? CGFloat(cos(angle)) * 120 : 0, y: spread ? CGFloat(sin(angle)) * 80 : 0)
                    .opacity(spread ? 0 : 1)
                    .scaleEffect(spread ? 1.4 : 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { spread = true }
        }
    }
}

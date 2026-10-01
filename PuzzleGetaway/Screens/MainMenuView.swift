import SwiftUI

/// Main menu: the restored-looking Lantern Line train, a big Continue, Quick Play, and the other doors.
struct MainMenuView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var showRecoveredNote = true

    private var totalStars: Int { model.save.totalStars }
    private var tier: Int { Progression.trainTier(totalStars: totalStars) }

    private var continueTarget: LevelEnvelope? { model.continueLevel() }

    private var continueSubtitle: String {
        guard let level = continueTarget else { return "Puzzles are on their way" }
        let name = levelName(level)
        if model.progression.hasInProgress(save: model.save) { return "Pick up where you left off: \(name)" }
        if model.save.progress.isEmpty { return "Your journey starts here: \(name)" }
        return "Next up: \(name)"
    }

    private func levelName(_ level: LevelEnvelope) -> String {
        let kind = PlayKind(level: level)
        switch kind {
        case .campaign: return "Level \(level.order), \(level.title)"
        case .relax: return level.title
        case .daily: return "Daily Journey"
        }
    }

    private var scrapbookCounts: (unlocked: Int, total: Int) {
        let entries = model.progression.scrapbookEntries()
        let unlocked = model.progression.unlockedArtIds(save: model.save)
        return (entries.filter { unlocked.contains($0.artId) }.count, entries.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(spacing: 4) {
                    Text("Puzzle Getaway")
                        .font(Theme.title)
                        .foregroundColor(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("All aboard the Lantern Line")
                        .font(Theme.body)
                        .foregroundColor(theme.textSecondary)
                }
                .padding(.top, 8)

                LanternTrainView(tier: tier, animated: !model.settings.effectiveReduceMotion)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 8)

                if let error = model.contentError {
                    Text(error).font(Theme.caption).foregroundColor(theme.warning)
                }

                if model.loadSource == .backup && showRecoveredNote {
                    recoveredNote
                }

                Button {
                    if let level = continueTarget { router.push(.game(levelId: level.id)) }
                } label: {
                    VStack(spacing: 4) {
                        Text("Continue")
                            .font(Theme.font(.title2, weight: .bold))
                        Text(continueSubtitle)
                            .font(Theme.font(.footnote, weight: .medium))
                            .multilineTextAlignment(.center)
                            .opacity(0.9)
                    }
                    .foregroundColor(theme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous)
                            .fill(theme.accent.opacity(continueTarget == nil ? 0.4 : 1))
                    )
                    .shadow(color: theme.accent.opacity(0.35), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(PressableStyle())
                .disabled(continueTarget == nil)
                .accessibilityIdentifier("continueButton")
                .accessibilityLabel("Continue")
                .accessibilityHint(continueSubtitle)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    menuTile(id: "quickPlayButton", icon: "bolt.fill", title: "Quick Play",
                             subtitle: "Jump into a puzzle") {
                        if let level = model.quickPlayLevel() { router.push(.game(levelId: level.id)) }
                    }
                    menuTile(id: "mapButton", icon: "map.fill", title: "Map",
                             subtitle: "\(totalStars) \(totalStars == 1 ? "star" : "stars") collected") {
                        router.push(.map)
                    }
                    menuTile(id: "relaxButton", icon: "leaf.fill", title: "Relax",
                             subtitle: "No stars, no pressure") {
                        router.push(.relax)
                    }
                    menuTile(id: "dailyButton", icon: "sun.max.fill", title: "Daily Journey",
                             subtitle: journeysSubtitle) {
                        router.push(.daily)
                    }
                    menuTile(id: "scrapbookButton", icon: "photo.on.rectangle.angled", title: "Scrapbook",
                             subtitle: "\(scrapbookCounts.unlocked) of \(scrapbookCounts.total) pictures") {
                        router.push(.scrapbook)
                    }
                    menuTile(id: "settingsButton", icon: "gearshape.fill", title: "Settings",
                             subtitle: "Comfort and access") {
                        router.push(.settings)
                    }
                }

                VStack(spacing: 8) {
                    Label("Offline · no account needed", systemImage: "wifi.slash")
                        .font(Theme.caption)
                        .foregroundColor(theme.textSecondary)
                        .accessibilityIdentifier("offlineNote")
                    Button {
                        router.push(.backup)
                    } label: {
                        Label("Saved on this device · Backup", systemImage: "externaldrive.fill")
                            .font(Theme.font(.footnote, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: Theme.minTapTarget)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("backupButton")
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, Theme.spacing)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var journeysSubtitle: String {
        let n = model.save.dailyJourneysTaken.count
        return n == 0 ? "A fresh puzzle each day" : "\(n) \(n == 1 ? "journey" : "journeys") taken"
    }

    private var recoveredNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.text.square.fill").foregroundColor(theme.accent)
            Text("We restored your progress from a safety copy. Everything is fine.")
                .font(Theme.caption)
                .foregroundColor(theme.textPrimary)
            Spacer(minLength: 0)
            Button {
                showRecoveredNote = false
            } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).minTapTarget()
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
    }

    private func menuTile(id: String, icon: String, title: String, subtitle: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.accentText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.font(.headline, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.font(.caption))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(12)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(theme.stroke, lineWidth: theme.strokeWidth)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityIdentifier(id)
    }
}

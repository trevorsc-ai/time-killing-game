import SwiftUI

/// Gallery of pixel illustrations, one unlocked by each restoration stage. Locked ones show as silhouettes.
struct ScrapbookView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @State private var selected: ScrapbookEntry?

    private var entries: [ScrapbookEntry] { model.progression.scrapbookEntries() }
    private var unlocked: Set<String> { model.progression.unlockedArtIds(save: model.save) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                let have = entries.filter { unlocked.contains($0.artId) }.count
                Text("\(have) of \(entries.count) pictures collected")
                    .font(Theme.font(.subheadline, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .accessibilityIdentifier("scrapbookCount")
                if entries.isEmpty {
                    Text("Your scrapbook will fill up as you restore the Lantern Line.")
                        .font(Theme.body)
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 14)], spacing: 14) {
                        ForEach(entries) { entry in
                            cell(entry)
                        }
                    }
                }
            }
            .padding(Theme.spacing)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Scrapbook")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { entry in
            ScrapbookDetailView(entry: entry, isUnlocked: unlocked.contains(entry.artId),
                                starsNeeded: starsNeeded(entry))
                .environmentObject(model)
                .environment(\.theme, model.theme)
        }
    }

    private func starsNeeded(_ entry: ScrapbookEntry) -> Int {
        max(0, entry.stage.starsRequired - model.progression.stars(in: entry.destinationId, save: model.save))
    }

    private func cell(_ entry: ScrapbookEntry) -> some View {
        let isUnlocked = unlocked.contains(entry.artId)
        let art = model.content.flatMap { PixelArtLibrary.load(id: entry.artId, content: $0) }
        let title = isUnlocked ? (art?.title ?? entry.stage.title) : "Locked"
        return Button {
            model.haptics.selection()
            selected = entry
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                        .fill(theme.surfaceAlt)
                    if let art = art, let content = model.content {
                        PixelArtView(art: art, palette: content.palette,
                                     silhouette: isUnlocked ? nil : theme.stroke,
                                     highContrast: model.settings.highContrast)
                            .padding(10)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundColor(theme.stroke)
                    }
                    if !isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(theme.textSecondary)
                            .padding(6)
                            .background(Circle().fill(theme.surface))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                Text(title)
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .foregroundColor(isUnlocked ? theme.textPrimary : theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(entry.destinationName)
                    .font(Theme.font(.caption2))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(10)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(theme.stroke, lineWidth: theme.strokeWidth)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isUnlocked ? "\(title), from \(entry.destinationName)" : "Locked picture from \(entry.destinationName), earn \(entry.stage.starsRequired) stars there")
        .accessibilityIdentifier("scrap-\(entry.artId)")
    }
}

/// Large view of one scrapbook picture with its caption.
struct ScrapbookDetailView: View {
    let entry: ScrapbookEntry
    let isUnlocked: Bool
    let starsNeeded: Int
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let art = model.content.flatMap { PixelArtLibrary.load(id: entry.artId, content: $0) }
        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.button)
                    .frame(minHeight: Theme.minTapTarget)
                    .accessibilityIdentifier("scrapbookDone")
            }
            .padding(.horizontal, Theme.spacing)
            ScrollView {
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(theme.surfaceAlt)
                        if let art = art, let content = model.content {
                            PixelArtView(art: art, palette: content.palette,
                                         silhouette: isUnlocked ? nil : theme.stroke,
                                         highContrast: model.settings.highContrast)
                                .padding(16)
                        }
                    }
                    .frame(maxWidth: 420)
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityHidden(true)
                    Text(isUnlocked ? (art?.title ?? entry.stage.title) : "Not yet collected")
                        .font(Theme.heading)
                        .foregroundColor(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if isUnlocked {
                        Text(art?.caption ?? "")
                            .font(Theme.body)
                            .foregroundColor(theme.textPrimary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Earn \(starsNeeded) more \(starsNeeded == 1 ? "star" : "stars") in \(entry.destinationName) to unlock \u{201C}\(entry.stage.title)\u{201D}.")
                            .font(Theme.body)
                            .foregroundColor(theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Text("\(entry.destinationName) · Stage \(entry.stageNumber)")
                        .font(Theme.caption)
                        .foregroundColor(theme.textSecondary)
                }
                .padding(Theme.spacing)
                .frame(maxWidth: .infinity)
            }
        }
        .screenBackground()
    }
}

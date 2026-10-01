import SwiftUI

/// Relax: three calm puzzle pools played in order. No stars, no scoring, unlimited undo.
struct RelaxView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.theme) private var theme

    private struct PoolInfo {
        let pool: String
        let title: String
        let blurb: String
        let icon: String
    }

    private let pools: [PoolInfo] = [
        PoolInfo(pool: "relax-liquid", title: "Liquid", blurb: "Pour and sort the colors, one tube at a time.", icon: "drop.fill"),
        PoolInfo(pool: "relax-pixel", title: "Pixel Picnic", blurb: "Help the Pals pack the picnic crates.", icon: "square.grid.3x3.fill"),
        PoolInfo(pool: "relax-pipe", title: "Flow Fix", blurb: "Turn the pipes so the water finds its way.", icon: "arrow.triangle.branch")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(spacing: 6) {
                    Text("No stars, no pressure")
                        .font(Theme.heading)
                        .foregroundColor(theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Pick a puzzle type and settle in. Undo as much as you like. We'll remember where you are.")
                        .font(Theme.body)
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 4)
                ForEach(pools, id: \.pool) { info in
                    poolCard(info)
                }
            }
            .padding(Theme.spacing)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Relax")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func poolCard(_ info: PoolInfo) -> some View {
        let count = model.progression.relaxCount(pool: info.pool)
        let position = model.save.relaxPositions[info.pool] ?? 0
        let entry = model.progression.currentRelaxEntry(pool: info.pool, save: model.save)
        let number = count > 0 ? (position % count) + 1 : 0
        return Button {
            if let entry = entry {
                model.haptics.selection()
                router.push(.game(levelId: entry.id))
            }
        } label: {
            SoftCard {
                HStack(spacing: 14) {
                    Image(systemName: entry == nil ? "hourglass" : info.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(theme.accentText)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(entry == nil ? theme.stroke : theme.accent))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title)
                            .font(Theme.font(.headline, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                        if entry == nil {
                            Text("These puzzles are still being packed. Check back soon.")
                                .font(Theme.caption)
                                .foregroundColor(theme.textSecondary)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text(info.blurb)
                                .font(Theme.caption)
                                .foregroundColor(theme.textSecondary)
                                .multilineTextAlignment(.leading)
                            Text("Puzzle \(number) of \(count)")
                                .font(Theme.font(.footnote, weight: .semibold))
                                .foregroundColor(theme.accent)
                        }
                    }
                    Spacer(minLength: 0)
                    if entry != nil {
                        Image(systemName: "chevron.right").foregroundColor(theme.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(entry == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(entry == nil ? "\(info.title), puzzles coming soon" : "\(info.title). Puzzle \(number) of \(count). \(info.blurb)")
        .accessibilityIdentifier("relax-\(info.pool)")
    }
}

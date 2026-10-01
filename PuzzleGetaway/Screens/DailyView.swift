import SwiftUI

/// Daily Journey: one puzzle per local date, picked by hashing the date. Only a "journeys taken" count: no streaks.
struct DailyView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: Router
    @Environment(\.theme) private var theme

    private var today: Date { Date() }
    private var entry: LevelEnvelope? { model.progression.dailyEntry(for: today) }
    private var takenToday: Bool { model.save.dailyJourneysTaken.contains(Progression.dateKey(today)) }
    private var taken: Int { model.save.dailyJourneysTaken.count }

    private var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: today)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 44))
                    .foregroundColor(theme.warning)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                Text("Today's journey")
                    .font(Theme.title)
                    .foregroundColor(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(dateText)
                    .font(Theme.body)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)

                if let entry = entry {
                    SoftCard {
                        VStack(spacing: 10) {
                            Label(ModeInfo.name(for: entry.mode), systemImage: ModeInfo.icon(for: entry.mode))
                                .font(Theme.font(.headline, weight: .semibold))
                                .foregroundColor(theme.textPrimary)
                            Text(entry.title)
                                .font(Theme.heading)
                                .foregroundColor(theme.textPrimary)
                                .multilineTextAlignment(.center)
                            Text(takenToday ? "You've taken today's journey. Go again whenever you like." : "A fresh puzzle, just for today.")
                                .font(Theme.body)
                                .foregroundColor(theme.textSecondary)
                                .multilineTextAlignment(.center)
                            Button(takenToday ? "Take it again" : "Start today's journey") {
                                router.push(.game(levelId: entry.id))
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("startDaily")
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    SoftCard {
                        VStack(spacing: 10) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 30))
                                .foregroundColor(theme.accent)
                            Text("Today's journey is still being packed")
                                .font(Theme.heading)
                                .foregroundColor(theme.textPrimary)
                                .multilineTextAlignment(.center)
                            Text("The Pals are wrapping up the daily puzzles. Come back soon!")
                                .font(Theme.body)
                                .foregroundColor(theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("dailyPlaceholder")
                }

                VStack(spacing: 4) {
                    Text("\(taken)")
                        .font(Theme.font(.largeTitle, weight: .bold))
                        .foregroundColor(theme.accent)
                    Text(taken == 1 ? "journey taken" : "journeys taken")
                        .font(Theme.caption)
                        .foregroundColor(theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("journeysTaken")
                Text("Miss a day? No problem. Every journey counts, whenever you take it.")
                    .font(Theme.caption)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.spacing)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Daily Journey")
        .navigationBarTitleDisplayMode(.inline)
    }
}

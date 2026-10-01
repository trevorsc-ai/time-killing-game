import Foundation
import UIKit

/// Haptic feedback (the game has no sound). Every call is a no-op when haptics are disabled in Settings.
@MainActor
final class Haptics {
    private let settings: Settings
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()
    private let select = UISelectionFeedbackGenerator()

    init(settings: Settings) {
        self.settings = settings
    }

    /// Light tap for a legal move.
    func legalMove() {
        guard settings.hapticsEnabled else { return }
        light.impactOccurred()
    }

    /// Success pattern for completing a puzzle.
    func success() {
        guard settings.hapticsEnabled else { return }
        notify.notificationOccurred(.success)
    }

    /// Soft warning for an invalid / rejected move.
    func invalid() {
        guard settings.hapticsEnabled else { return }
        soft.impactOccurred(intensity: 0.8)
    }

    /// Selection tick (picking up a tube, switching tabs, ...).
    func selection() {
        guard settings.hapticsEnabled else { return }
        select.selectionChanged()
    }
}

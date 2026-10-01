import Foundation
import SwiftUI
import UIKit

/// Persisted (Codable) settings values. Stored inside SaveData.
struct SettingsValues: Codable, Equatable {
    var hapticsEnabled: Bool = true
    var reduceMotion: Bool = false
    /// 1 = normal, 2 = double speed.
    var animationSpeed: Int = 1
    /// Show accessibility symbols (patterns) on colored items.
    var showPatterns: Bool = true
    var highContrast: Bool = false
    var leftHanded: Bool = false
    var showMoveCounter: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsValues()
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
        animationSpeed = try c.decodeIfPresent(Int.self, forKey: .animationSpeed) ?? d.animationSpeed
        showPatterns = try c.decodeIfPresent(Bool.self, forKey: .showPatterns) ?? d.showPatterns
        highContrast = try c.decodeIfPresent(Bool.self, forKey: .highContrast) ?? d.highContrast
        leftHanded = try c.decodeIfPresent(Bool.self, forKey: .leftHanded) ?? d.leftHanded
        showMoveCounter = try c.decodeIfPresent(Bool.self, forKey: .showMoveCounter) ?? d.showMoveCounter
    }
}

/// Observable settings used by views and modes. `AppModel` keeps it in sync with SaveData.
@MainActor
final class Settings: ObservableObject {
    @Published var hapticsEnabled: Bool = true
    @Published var reduceMotion: Bool = false
    @Published var animationSpeed: Int = 1
    @Published var showPatterns: Bool = true
    @Published var highContrast: Bool = false
    @Published var leftHanded: Bool = false
    @Published var showMoveCounter: Bool = false

    init(values: SettingsValues = SettingsValues()) {
        self.values = values
    }

    var values: SettingsValues {
        get {
            var v = SettingsValues()
            v.hapticsEnabled = hapticsEnabled
            v.reduceMotion = reduceMotion
            v.animationSpeed = animationSpeed
            v.showPatterns = showPatterns
            v.highContrast = highContrast
            v.leftHanded = leftHanded
            v.showMoveCounter = showMoveCounter
            return v
        }
        set {
            hapticsEnabled = newValue.hapticsEnabled
            reduceMotion = newValue.reduceMotion
            animationSpeed = newValue.animationSpeed
            showPatterns = newValue.showPatterns
            highContrast = newValue.highContrast
            leftHanded = newValue.leftHanded
            showMoveCounter = newValue.showMoveCounter
        }
    }

    /// True when either the in-app toggle or the system "Reduce Motion" setting is on.
    var effectiveReduceMotion: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled
    }

    /// Scales a base animation duration by the speed setting. Returns 0 when motion is reduced.
    func duration(_ base: TimeInterval) -> TimeInterval {
        effectiveReduceMotion ? 0 : base / Double(max(1, animationSpeed))
    }

    /// A SwiftUI animation honoring reduce-motion and speed; nil means "do not animate".
    func animation(_ base: TimeInterval = 0.25) -> Animation? {
        effectiveReduceMotion ? nil : .easeInOut(duration: duration(base))
    }
}

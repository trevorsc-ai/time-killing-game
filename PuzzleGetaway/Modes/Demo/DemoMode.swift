import SwiftUI

/// Placeholder "counter" puzzle used by the foundation's dummy level. Also a minimal template for real modes.
///
/// Payload: `{"start":0,"target":7,"deltas":[1,3]}`; move: `{"delta":3}`. Add a delta without exceeding the target.
struct DemoPayload: Codable, Hashable {
    var start: Int
    var target: Int
    var deltas: [Int]
}

struct DemoMove: Codable, Hashable {
    var delta: Int
}

struct DemoState: Codable, Hashable {
    var value: Int
}

struct DemoRules: PuzzleRules {
    let target: Int
    let deltas: [Int]

    func legalMoves(_ s: DemoState) -> [DemoMove] {
        deltas.filter { s.value + $0 <= target }.map { DemoMove(delta: $0) }
    }

    func apply(_ m: DemoMove, to s: DemoState) -> DemoState? {
        guard deltas.contains(m.delta), s.value + m.delta <= target else { return nil }
        return DemoState(value: s.value + m.delta)
    }

    func isSolved(_ s: DemoState) -> Bool { s.value == target }
}

enum DemoMode: PuzzleModePlugin {
    static let mode = "demo"
    static let displayName = "Demo Counter"

    @MainActor
    static func makeController(level: LevelEnvelope, snapshot: Data?, context: GameContext) -> AnyGameController {
        let payload = (try? level.decodePayload(DemoPayload.self)) ?? DemoPayload(start: 0, target: 1, deltas: [1])
        let rules = DemoRules(target: payload.target, deltas: payload.deltas)
        let solution = (try? level.decodeSolution(DemoMove.self)) ?? []
        let session = GameSession(rules: rules, initial: DemoState(value: payload.start), solution: solution)
        if let snapshot = snapshot { session.restore(from: snapshot) }
        return DemoController(levelId: level.id, title: level.title, session: session, context: context, payload: payload)
    }

    static func replay(level: LevelEnvelope) throws -> Bool {
        let payload = try level.decodePayload(DemoPayload.self)
        let rules = DemoRules(target: payload.target, deltas: payload.deltas)
        var state = DemoState(value: payload.start)
        for move in try level.decodeSolution(DemoMove.self) {
            guard let next = rules.apply(move, to: state) else { return false }
            state = next
        }
        return rules.isSolved(state)
    }
}

@MainActor
final class DemoController: SessionController<DemoRules> {
    let payload: DemoPayload

    init(levelId: String, title: String, session: GameSession<DemoRules>, context: GameContext, payload: DemoPayload) {
        self.payload = payload
        super.init(levelId: levelId, title: title, session: session, context: context)
    }

    override var accessibilitySummary: String {
        "Counter at \(session.state.value) of \(payload.target)"
    }

    override var boardView: AnyView {
        AnyView(DemoBoardView(controller: self))
    }
}

struct DemoBoardView: View {
    @ObservedObject var controller: DemoController
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Text("\(controller.session.state.value) / \(controller.payload.target)")
                .font(Theme.title)
                .foregroundColor(theme.textPrimary)
                .accessibilityIdentifier("demoValue")
            HStack(spacing: Theme.spacing) {
                ForEach(controller.payload.deltas, id: \.self) { delta in
                    Button("+\(delta)") {
                        controller.attempt(DemoMove(delta: delta))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("demoAdd\(delta)")
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .stroke(theme.success, lineWidth: controller.session.activeHint == DemoMove(delta: delta) ? 3 : 0)
                    )
                }
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controller.accessibilitySummary)
    }
}

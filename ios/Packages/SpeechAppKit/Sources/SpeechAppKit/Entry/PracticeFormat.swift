import Foundation

/// One of the three exercises, as a full screen in the chooser rather than a row.
public struct PracticeFormat: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case reading
        case monologue
        case conversation
    }

    /// What the start control says, and whether it can be pressed.
    public struct StartControl: Equatable, Sendable {
        public let title: String
        public let isEnabled: Bool
        /// A quiet line under the control. Conversation names what the month has left.
        public let note: String?

        public init(title: String, isEnabled: Bool, note: String? = nil) {
            self.title = title
            self.isEnabled = isEnabled
            self.note = note
        }
    }

    public let kind: Kind
    public let title: String
    public let line: String

    public var id: Kind { kind }

    public static let all: [PracticeFormat] = [
        PracticeFormat(
            kind: .reading,
            title: "Reading",
            line: "Read a passage aloud. Hear every sound."
        ),
        PracticeFormat(
            kind: .monologue,
            title: "Monologue",
            line: "One topic, three takes, a minute longer each."
        ),
        PracticeFormat(
            kind: .conversation,
            title: "Conversation",
            line: "Fifteen minutes with a partner. No script."
        )
    ]

    public static func startControl(
        for kind: Kind,
        budget: ConversationBudgetSnapshot
    ) -> StartControl {
        switch kind {
        case .reading:
            StartControl(title: "Choose a passage", isEnabled: true)
        case .monologue:
            StartControl(title: "Begin a talk", isEnabled: true)
        case .conversation:
            // A spent month says so in words. Dimming the control explains nothing.
            StartControl(
                title: budget.startEnabled ? "Begin rehearsal" : "Back next month",
                isEnabled: budget.startEnabled,
                note: "\(budget.label) this month"
            )
        }
    }
}

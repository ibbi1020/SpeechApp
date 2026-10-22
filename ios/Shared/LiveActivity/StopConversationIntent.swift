import AppIntents

/// Stop from the expanded island and the Lock Screen.
/// `LiveActivityIntent` runs in the app process. A plain `AppIntent` compiles and does nothing.
struct StopConversationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop"
    static let description = IntentDescription("Stop this rehearsal.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await ConversationIslandStop.run()
        return .result()
    }
}

/// Pause or resume from the expanded island and the Lock Screen.
struct PauseConversationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause"
    static let description = IntentDescription("Pause or resume this rehearsal.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await ConversationIslandPause.run()
        return .result()
    }
}

/// The widget and the app each compile this file. The system runs the app's copy.
enum ConversationIslandPause {
    @MainActor
    static var handler: (@MainActor () async -> Void)?

    static func run() async {
        let action = await MainActor.run { handler }
        await action?()
    }
}

/// The widget and the app each compile this file. The system runs the app's copy.
enum ConversationIslandStop {
    @MainActor
    static var handler: (@MainActor () async -> Void)?

    static func run() async {
        let action = await MainActor.run { handler }
        await action?()
    }
}

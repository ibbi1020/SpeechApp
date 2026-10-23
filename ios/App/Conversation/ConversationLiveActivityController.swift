import ActivityKit
import Foundation
import os
import SpeechAppKit

/// Starts, updates, and ends the one Conversation Live Activity.
/// A failed start does not stop the rehearsal.
@MainActor
final class ConversationLiveActivityController {
    static let shared = ConversationLiveActivityController()

    private static let log = Logger(subsystem: "com.speechapp", category: "LiveActivity")

    private var activityID: String?
    private var lastSnapshot: ConversationLiveActivitySnapshot?
    private var sweep: Task<Void, Never>?
    private var didSweep = false
    private var startDeclined = false

    var isLive: Bool { activityID != nil }

    private init() {
        ConversationIslandStop.handler = {
            await ConversationLiveActivityController.shared.end()
        }
    }

    /// A background `Activity.request` can fail. The next foreground sync may try again.
    func allowStart() {
        startDeclined = false
    }

    /// Ends activities left behind by a killed process. Once per launch, before the next start.
    func prepare() {
        guard sweep == nil else { return }
        sweep = Task { await self.sweepOrphans() }
    }

    /// Island Stop hangs up the live session, then drops the activity.
    func bindStop(_ stop: @escaping @MainActor () async -> Void) {
        ConversationIslandStop.handler = {
            await stop()
            await ConversationLiveActivityController.shared.end()
        }
    }

    func bindPause(_ pause: @escaping @MainActor () async -> Void) {
        ConversationIslandPause.handler = pause
    }

    func releaseStop() {
        ConversationIslandStop.handler = {
            await ConversationLiveActivityController.shared.end()
        }
        ConversationIslandPause.handler = nil
    }

    func sync(_ input: ConversationLiveActivityInput, id: UUID) async {
        if sweep == nil { prepare() }
        await sweep?.value
        switch ConversationLiveActivityPolicy.command(for: input) {
        case .none:
            break
        case .start(let snapshot):
            await start(snapshot, id: id)
        case .update(let snapshot):
            await update(snapshot)
        case .end:
            await end()
        }
    }

    func end() async {
        guard let id = activityID else { return }
        activityID = nil
        lastSnapshot = nil
        await ConversationActivityBridge.end(id: id)
    }

    private func start(_ snapshot: ConversationLiveActivitySnapshot, id: UUID) async {
        if activityID != nil {
            await update(snapshot)
            return
        }
        if startDeclined { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            startDeclined = true
            Self.log.info("Live Activities are off. The rehearsal continues.")
            return
        }
        let attributes = ConversationAttributes(conversationID: id)
        let content = ActivityContent(state: ConversationAttributes.ContentState(snapshot), staleDate: nil)
        do {
            let started = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activityID = started.id
            lastSnapshot = snapshot
        } catch {
            startDeclined = true
            Self.log.error("Live Activity did not start. The rehearsal continues.")
            activityID = nil
        }
    }

    private func update(_ snapshot: ConversationLiveActivitySnapshot) async {
        guard snapshot != lastSnapshot, let id = activityID else { return }
        let content = ActivityContent(state: ConversationAttributes.ContentState(snapshot), staleDate: nil)
        await ConversationActivityBridge.update(id: id, content: content)
        lastSnapshot = snapshot
    }

    private func sweepOrphans() async {
        guard didSweep == false else { return }
        didSweep = true
        for existing in Activity<ConversationAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// Looks up the activity off the main actor. `Activity.update` and `end` are concurrent.
private enum ConversationActivityBridge {
    static func end(id: String) async {
        guard let match = Activity<ConversationAttributes>.activities.first(where: { $0.id == id }) else { return }
        await match.end(nil, dismissalPolicy: .immediate)
    }

    static func update(id: String, content: ActivityContent<ConversationAttributes.ContentState>) async {
        guard let match = Activity<ConversationAttributes>.activities.first(where: { $0.id == id }) else { return }
        await match.update(content)
    }
}

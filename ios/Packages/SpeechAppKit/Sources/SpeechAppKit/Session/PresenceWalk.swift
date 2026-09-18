import Foundation

/// Live “with you” cursor that can walk ahead of ASR without committing heard occupancy.
public struct PresenceWalkState: Equatable, Sendable {
    public var presenceWordID: String?
    public var presenceProgress: Double
    /// Words fully walked by presence but not yet sticky-heard by ASR.
    public var presenceTrailIDs: [String]
    /// Word ID the fill clock is timing against.
    public var fillWordID: String?
    public var speechStartedAt: TimeInterval?

    public init(
        presenceWordID: String? = nil,
        presenceProgress: Double = 0,
        presenceTrailIDs: [String] = [],
        fillWordID: String? = nil,
        speechStartedAt: TimeInterval? = nil
    ) {
        self.presenceWordID = presenceWordID
        self.presenceProgress = presenceProgress
        self.presenceTrailIDs = presenceTrailIDs
        self.fillWordID = fillWordID
        self.speechStartedAt = speechStartedAt
    }
}

public enum PresenceWalkEvent: Equatable, Sendable {
    case advanced(from: String, to: String)
    case snapped(to: String)
}

/// Pure presence-walk clock — testable without audio / ASR.
public enum PresenceWalk {
    public static let maxWordsAhead = 8
    public static let silenceDecay: Double = 0.08

    public static func syllableDuration(syllableCount: Int) -> TimeInterval {
        max(0.18, Double(max(1, syllableCount)) * 0.22)
    }

    /// Mic tick: fill current presence word; when full and still speaking, walk ahead (capped).
    public static func tick(
        state: PresenceWalkState,
        speaking: Bool,
        now: TimeInterval,
        wordIDs: [String],
        syllableCounts: [String: Int],
        asrWordID: String?,
        heardIDs: Set<String>
    ) -> (PresenceWalkState, PresenceWalkEvent?) {
        var next = state
        guard let wordID = ensurePresenceWordID(in: &next, asrWordID: asrWordID, wordIDs: wordIDs),
              let presenceIndex = wordIDs.firstIndex(of: wordID) else {
            if next.presenceWordID == nil {
                next.presenceProgress = 0
            }
            return (next, nil)
        }

        if speaking {
            return tickWhileSpeaking(
                state: next,
                now: now,
                wordID: wordID,
                presenceIndex: presenceIndex,
                wordIDs: wordIDs,
                syllableCounts: syllableCounts,
                asrWordID: asrWordID,
                heardIDs: heardIDs
            )
        }

        return (decayFillOnSilence(next), nil)
    }

    /// Reconcile when ASR caret moves. Drops trail IDs that ASR sticky-heard.
    public static func reconcile(
        state: PresenceWalkState,
        asrWordID: String?,
        wordIDs: [String],
        heardIDs: Set<String>,
        speaking: Bool,
        now: TimeInterval
    ) -> (PresenceWalkState, PresenceWalkEvent?) {
        var next = state
        next.presenceTrailIDs = next.presenceTrailIDs.filter { !heardIDs.contains($0) }

        guard let asrWordID,
              let asrIndex = wordIDs.firstIndex(of: asrWordID) else {
            return (next, nil)
        }

        let presenceIndex = next.presenceWordID.flatMap { wordIDs.firstIndex(of: $0) }
        let asrCaughtUp = presenceIndex.map { asrIndex >= $0 } ?? true
        guard asrCaughtUp else {
            // ASR still behind presence — keep presence ahead; trail already filtered.
            return (next, nil)
        }

        let snapped = next.presenceWordID != asrWordID
        next.presenceWordID = asrWordID
        next.presenceProgress = 0
        next.fillWordID = asrWordID
        next.speechStartedAt = speaking ? now : nil
        next.presenceTrailIDs = next.presenceTrailIDs.filter { id in
            guard let idx = wordIDs.firstIndex(of: id) else { return false }
            return idx > asrIndex && !heardIDs.contains(id)
        }
        return (next, snapped ? .snapped(to: asrWordID) : nil)
    }

    // MARK: - Private

    /// Seeds `presenceWordID` from ASR / script start when unset. Returns the active word ID.
    private static func ensurePresenceWordID(
        in state: inout PresenceWalkState,
        asrWordID: String?,
        wordIDs: [String]
    ) -> String? {
        if let id = state.presenceWordID {
            return id
        }
        guard let seed = asrWordID ?? wordIDs.first else { return nil }
        state.presenceWordID = seed
        return seed
    }

    private static func tickWhileSpeaking(
        state: PresenceWalkState,
        now: TimeInterval,
        wordID: String,
        presenceIndex: Int,
        wordIDs: [String],
        syllableCounts: [String: Int],
        asrWordID: String?,
        heardIDs: Set<String>
    ) -> (PresenceWalkState, PresenceWalkEvent?) {
        var next = state

        if next.fillWordID != wordID || next.speechStartedAt == nil {
            next.fillWordID = wordID
            next.speechStartedAt = now
        }

        let duration = syllableDuration(syllableCount: syllableCounts[wordID] ?? 1)
        let elapsed = now - (next.speechStartedAt ?? now)
        next.presenceProgress = min(1, elapsed / duration)

        guard next.presenceProgress >= 1 else {
            return (next, nil)
        }

        let asrIndex = asrWordID.flatMap { wordIDs.firstIndex(of: $0) } ?? 0
        let canAdvance =
            (presenceIndex - asrIndex) < maxWordsAhead
            && presenceIndex + 1 < wordIDs.count

        guard canAdvance else {
            // Cap: hold full fill on presence word.
            next.presenceProgress = 1
            return (next, nil)
        }

        let fromID = wordIDs[presenceIndex]
        let toID = wordIDs[presenceIndex + 1]
        if !heardIDs.contains(fromID), !next.presenceTrailIDs.contains(fromID) {
            next.presenceTrailIDs.append(fromID)
        }
        next.presenceWordID = toID
        next.presenceProgress = 0
        next.fillWordID = toID
        next.speechStartedAt = now
        return (next, .advanced(from: fromID, to: toID))
    }

    /// Soft-decay progress only — never rewind presence index.
    private static func decayFillOnSilence(_ state: PresenceWalkState) -> PresenceWalkState {
        guard state.presenceProgress > 0 else { return state }
        var next = state
        next.presenceProgress = max(0, next.presenceProgress - silenceDecay)
        if next.presenceProgress == 0 {
            next.speechStartedAt = nil
        }
        return next
    }
}

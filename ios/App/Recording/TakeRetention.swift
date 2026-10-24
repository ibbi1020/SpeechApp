import Foundation
import os
import SpeechAppKit

/// A take can play on the report before it is in the gallery.
/// Leaving without Save deletes it. Save keeps it even when recordings are off.
@MainActor
enum TakeRetention {
    private static var discarded = Set<UUID>()
    private static var wanted = Set<UUID>()

    static func wantsLibrary(_ id: UUID) -> Bool {
        wanted.contains(id)
    }

    static func isDiscarded(_ id: UUID) -> Bool {
        discarded.contains(id)
    }

    /// Puts this take in the gallery. Safe to call before the file has finished saving.
    static func keepInLibrary(_ id: UUID) {
        discarded.remove(id)
        wanted.insert(id)
        guard var manifest = try? RecordingsService.store.load(id: id) else { return }
        manifest.inLibrary = true
        try? RecordingsService.store.save(manifest)
    }

    /// A take left on the report when the app closed is not in the gallery.
    static func discardTakesLeftFromLastLaunch() {
        guard let manifests = try? RecordingsService.store.list(includeHidden: true) else { return }
        for manifest in manifests where !manifest.inLibrary {
            discard(manifest.id)
        }
    }

    /// Drops a take that was never saved. A take already in the gallery stays.
    static func discard(_ id: UUID) {
        if wanted.contains(id) { return }
        if let manifest = try? RecordingsService.store.load(id: id), manifest.inLibrary { return }
        discarded.insert(id)
        try? RecordingsService.store.delete(id: id)
    }
}

/// The save steps for takes still being written. The gallery never reads this.
/// It only reads the finished manifest, so the report and the gallery stay the same take.
enum SaveProgressBoard {
    struct Snapshot: Sendable {
        var progress: SaveProgress
        var finished: Bool
    }

    private struct Entry: Sendable {
        var progress: SaveProgress
        var started: ContinuousClock.Instant
        var finished = false
    }

    private static let state = OSAllocatedUnfairLock<[UUID: Entry]>(initialState: [:])

    static var runsOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static func begin(
        id: UUID,
        durationSeconds: TimeInterval,
        willClean: Bool,
        includesTranscription: Bool
    ) {
        let progress = SaveProgress(
            durationSeconds: durationSeconds,
            willClean: willClean,
            includesTranscription: includesTranscription
        )
        let started = ContinuousClock.now
        state.withLock { entries in
            entries[id] = Entry(progress: progress, started: started)
        }
    }

    /// Milliseconds since `begin`. 0 when this save was never started.
    static func wallMilliseconds(id: UUID) -> Double {
        state.withLock { entries in
            guard let started = entries[id]?.started else { return 0 }
            let duration = started.duration(to: .now)
            return Double(duration.components.seconds) * 1_000
                + Double(duration.components.attoseconds) / 1e15
        }
    }

    static func update(id: UUID, _ step: SaveStep, _ fraction: Double) {
        state.withLock { entries in
            guard var entry = entries[id], !entry.finished else { return }
            entry.progress = entry.progress.updating(step, fraction: fraction)
            entries[id] = entry
        }
    }

    /// The save task has returned. A manifest may already be on disk.
    static func markFinished(id: UUID) {
        state.withLock { entries in
            if var entry = entries[id] {
                entry.finished = true
                entries[id] = entry
            } else {
                entries[id] = Entry(
                    progress: SaveProgress(
                        durationSeconds: 0,
                        willClean: false,
                        includesTranscription: false
                    ),
                    started: ContinuousClock.now,
                    finished: true
                )
            }
        }
    }

    static func snapshot(id: UUID) -> Snapshot? {
        state.withLock { entries in
            guard let entry = entries[id] else { return nil }
            return Snapshot(progress: entry.progress, finished: entry.finished)
        }
    }
}

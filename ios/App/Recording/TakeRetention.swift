import Foundation
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

import Foundation
import SpeechAppKit

/// App-owned root for on-device Monologue recordings + the Keep switch.
@MainActor
enum RecordingsService {
    private static let keepKey = "recordings.keepEnabled"

    static var keepRecordings: Bool {
        get {
            if UserDefaults.standard.object(forKey: keepKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: keepKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: keepKey) }
    }

    static var store: RecordingStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("Recordings", isDirectory: true)
        let store = RecordingStore(rootURL: root)
        try? store.prepareRoot(excludeFromBackup: true)
        return store
    }
}

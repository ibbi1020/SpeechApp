import Foundation
import OSLog

/// Words a person can act on. The technical reason belongs in the log, not on screen.
public enum UserFacingFailure {
    public static let practiceDidNotStart = "Practice couldn’t start. Try again."
    public static let connectionDropped = "The connection dropped. Try again."
    public static let microphoneOff = "The microphone is off. Turn it on in Settings and try again."
    public static let needsIPhone = "This practice needs an iPhone."
    public static let topicsDidNotLoad = "Topics didn’t load. Go back and try again."
    public static let nothingToPlay = "There’s nothing to play."
    public static let diskFull = "This recording didn’t save. Free up space and try again."
    public static let speakerDidNotStart = "The speaker didn’t turn on. Try again."
    public static let playbackDidNotStart = "Playback didn’t start. Try again."
    public static let recordingsDidNotLoad = "Recordings didn’t load. Go back and try again."
    public static let speechStillDownloading = "Speech is still downloading. Try again in a moment."
    public static let speechRecognitionOff = "Speech recognition is off. Turn it on in Settings and try again."

    private static let log = Logger(subsystem: "com.speechapp", category: "Errors")

    /// A sentence for the screen. Unknown failures still say practice did not start.
    public static func message(for error: Error) -> String {
        if let store = error as? RecordingStoreError {
            switch store {
            case .diskFull:
                return diskFull
            case .ioFailed:
                return recordingsDidNotLoad
            }
        }
        if let speech = error as? TranscriptionEngineError {
            switch speech {
            case .unavailable, .onDeviceUnsupported:
                return speechStillDownloading
            case .speechAuthorizationDenied:
                return speechRecognitionOff
            }
        }
        return practiceDidNotStart
    }

    /// Writes the engineer-facing reason. Call this whenever a message is shown.
    public static func log(_ error: Error, context: String) {
        log.error("\(context, privacy: .public): \(String(reflecting: error), privacy: .public)")
    }
}

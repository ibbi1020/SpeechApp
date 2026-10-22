import Foundation

/// Whether an `AVAudioSession` interruption should pause an exercise.
///
/// `type` is `AVAudioSession.InterruptionType.rawValue`. Began is a phone call,
/// FaceTime, Siri, an alarm, or another app taking the session. Ended is not a
/// resume: `shouldResume` is a playback hint, and a take or conversation stays
/// paused until the person taps resume.
public enum AudioInterruption {
    public static func shouldPause(type: UInt) -> Bool {
        switch type {
        case 1: // began
            true
        default:
            false
        }
    }
}

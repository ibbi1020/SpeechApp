import AVFoundation
import Foundation
import SpeechAppKit

/// Reads an `AVAudioSession` interruption note. Pause only on began.
enum SessionInterruption {
    static func shouldPause(_ note: Notification) -> Bool {
        let raw: UInt
        if let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt {
            raw = value
        } else if let number = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber {
            raw = number.uintValue
        } else {
            return false
        }
        return AudioInterruption.shouldPause(type: raw)
    }
}

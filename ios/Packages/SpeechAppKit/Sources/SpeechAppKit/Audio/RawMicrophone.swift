import Foundation

#if os(iOS)
import AVFoundation
#endif

/// Hear the microphone without Apple's voice filter.
///
/// Voice processing keeps speech and drops everything else. A hum is not
/// speech, so the filter takes it out, and the same filter cuts words when
/// the phone moves and the noise estimate resets. Measurement mode is the
/// mode Apple documents for turning that processing down. It is not enough
/// on its own: the voice unit has to be off, and the built-in mic has to stay
/// on one capsule so the beamformer does not retarget.
public enum RawMicrophone {
    /// Bottom, then front, then back, then top.
    /// The bottom capsule is one microphone. Front and back are arrays.
    public static let capsuleOrder = ["Bottom", "Front", "Back", "Top"]

    /// `AVAudioSession.Port.builtInMic` prints as this. A headset uses another port.
    public static let builtInPort = "MicrophoneBuiltIn"

    public static func preferredOrientation(
        among orientations: [String],
        order: [String] = capsuleOrder
    ) -> String? {
        for candidate in order where orientations.contains(candidate) {
            return candidate
        }
        return orientations.first
    }

    /// Lock only when the live route is the phone's own mic.
    /// An empty route is left alone so a headset can still attach.
    public static func shouldLockBuiltInMic(
        routePortTypes: [String],
        builtInPort: String = builtInPort
    ) -> Bool {
        !routePortTypes.isEmpty && routePortTypes.allSatisfy { $0 == builtInPort }
    }

    /// A hands-free port runs its own voice processor. Pull the mic back to the phone.
    /// A wired headset without that processor stays where it is.
    public static func shouldPreferBuiltIn(
        routePortTypes: [String],
        hardwareVoiceProcessed: Bool,
        builtInPort: String = builtInPort
    ) -> Bool {
        if hardwareVoiceProcessed { return true }
        return shouldLockBuiltInMic(routePortTypes: routePortTypes, builtInPort: builtInPort)
    }

    /// Mic energy that is not the phone speaker.
    /// `HumLevel.speakerLeak` is the fraction of playback a phone mic hears.
    public static func aboveSpeaker(micRMS: Float, speakerRMS: Float) -> Float {
        let leak = max(0, speakerRMS) * Float(HumLevel.speakerLeak)
        return max(0, micRMS - leak)
    }

#if os(iOS)
    /// The voice unit can only be switched while the engine is stopped.
    /// Leaving it on, even bypassed, still lets Voice Isolation win.
    public static func silenceVoiceProcessing(_ engine: AVAudioEngine) {
        if engine.isRunning {
            engine.stop()
        }
        try? engine.inputNode.setVoiceProcessingEnabled(false)
    }

    /// One built-in capsule, omnidirectional when the hardware allows it.
    /// Call after the session is active and before installing the tap.
    /// A wired headset is left alone. A hands-free route is not: that port
    /// has its own voice processor.
    public static func lockBuiltInCapsule(_ session: AVAudioSession) {
        let inputs = session.currentRoute.inputs
        let ports = inputs.map(\.portType.rawValue)
        let hardwareVoice = inputs.contains { $0.hasHardwareVoiceCallProcessing }
        guard shouldPreferBuiltIn(
            routePortTypes: ports,
            hardwareVoiceProcessed: hardwareVoice,
            builtInPort: AVAudioSession.Port.builtInMic.rawValue
        ) else {
            return
        }
        guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            return
        }
        let sources = builtIn.dataSources ?? []
        let order = [
            AVAudioSession.Orientation.bottom.rawValue,
            AVAudioSession.Orientation.front.rawValue,
            AVAudioSession.Orientation.back.rawValue,
            AVAudioSession.Orientation.top.rawValue,
        ]
        let names = sources.compactMap { $0.orientation?.rawValue }
        if let wanted = preferredOrientation(among: names, order: order),
           let source = sources.first(where: { $0.orientation?.rawValue == wanted }) {
            if source.supportedPolarPatterns?.contains(.omnidirectional) == true {
                try? source.setPreferredPolarPattern(.omnidirectional)
            }
            try? builtIn.setPreferredDataSource(source)
        }
        try? session.setPreferredInput(builtIn)
        // The pattern does not apply until this port is the live route.
        guard let active = session.currentRoute.inputs.first(where: { $0.portType == .builtInMic }),
              let selected = active.selectedDataSource,
              selected.supportedPolarPatterns?.contains(.omnidirectional) == true,
              selected.selectedPolarPattern != .omnidirectional
        else {
            return
        }
        try? selected.setPreferredPolarPattern(.omnidirectional)
    }

    /// Starting the engine can put the session back into voice chat.
    /// Put measurement mode back before the tap is read, and again after start.
    public static func useMeasurementMode(_ session: AVAudioSession) throws {
        if session.mode != .measurement {
            try session.setMode(.measurement)
        }
    }
#endif
}

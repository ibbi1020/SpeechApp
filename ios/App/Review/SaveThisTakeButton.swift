import SwiftUI

/// Last action on a report when this take was not kept.
/// One tap puts it in the gallery even if recordings are off.
struct SaveThisTakeButton: View {
    let recordingID: UUID
    @Binding var kept: Bool

    var body: some View {
        Button(kept ? "Saved on this phone" : "Save this take") {
            TakeRetention.keepInLibrary(recordingID)
            kept = true
        }
        .buttonStyle(SpeechSecondaryButtonStyle())
        .disabled(kept)
    }
}

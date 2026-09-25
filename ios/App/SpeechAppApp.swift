import SwiftUI
import SpeechAppKit

@main
struct SpeechAppApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .onAppear { VoiceOrbPreloader.warmup() }
        }
    }
}

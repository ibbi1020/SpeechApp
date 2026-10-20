import SwiftUI
import SpeechAppKit

@main
struct SpeechAppApp: App {
    @State private var appModel = AppModel()

    init() {
        UINavigationBar.appearance().tintColor = .white
        UIBarButtonItem.appearance().tintColor = .white
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .onAppear {
                    VoiceOrbPreloader.warmup()
                    Task { await appModel.refreshBudget() }
                }
        }
    }
}

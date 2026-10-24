import SwiftUI
import SpeechAppKit

/// Shows the launch mark still on white, then reveals Home with no motion.
struct SplashContainer<Content: View>: View {
    private var content: Content

    @State private var revealed = false
    @State private var didPlay = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .ignoresSafeArea()
                .opacity(revealed ? 1 : 0)
                .allowsHitTesting(revealed)
                .accessibilityHidden(!revealed)

            if !revealed {
                ZStack {
                    Color("LaunchBackground")
                    launchMark
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .allowsHitTesting(true)
            }
        }
        .persistentSystemOverlays(revealed ? .automatic : .hidden)
        .task { await play() }
    }

    /// Same asset the system launch screen draws, at that image's own size.
    /// Scaling it here, or using another asset, shows up as a second icon:
    /// iOS keeps the launch snapshot until the launch screen itself changes.
    private var launchMark: some View {
        Image("OratorMark")
    }

    private func play() async {
        guard !didPlay else { return }
        didPlay = true

        try? await Task.sleep(for: .seconds(SplashMotion.hold))
        guard !Task.isCancelled else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            revealed = true
        }
    }
}

#Preview("Splash") {
    SplashContainer {
        Color.black
    }
}

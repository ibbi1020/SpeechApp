import SwiftUI
import SpeechAppKit

private struct SplashRevealedKey: EnvironmentKey {
    /// False until SplashContainer has removed the mark and painted that frame.
    /// True here would let Home start its entrance underneath the splash.
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True only after the launch mark is gone and that frame is on screen.
    var splashRevealed: Bool {
        get { self[SplashRevealedKey.self] }
        set { self[SplashRevealedKey.self] = newValue }
    }
}

/// Shows the launch mark still on white, then reveals Home.
/// The mark itself does not move. Home may animate after it appears.
struct SplashContainer<Content: View>: View {
    private var content: Content

    @State private var revealed = false
    /// Flips after the mark is gone, on a later turn than `revealed`, so Home's
    /// entrance does not run inside the transaction that removes the splash.
    @State private var homeOnScreen = false
    @State private var didPlay = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .ignoresSafeArea()
                .environment(\.splashRevealed, homeOnScreen)
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

        // Let the mark leave and that frame draw before Home is allowed to move.
        await Task.yield()
        guard !Task.isCancelled else { return }
        homeOnScreen = true
    }
}

#Preview("Splash") {
    SplashContainer {
        Color.black
    }
}

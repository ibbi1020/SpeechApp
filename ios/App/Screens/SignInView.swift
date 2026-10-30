import AuthenticationServices
import SpeechAppKit
import SwiftUI
import UIKit

/// Sign-in in front of Home. Not a pushed screen, so the ceremony stack is unchanged.
/// The launch container ignores the safe area, so this screen pads for it itself.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var notice: String?
    @State private var googleSession = GoogleSignInSession()
    @State private var appleSignIn = AppleSignInCoordinator()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: SpeechSpacing.section)
                Text(EntryGreeting.appName)
                    .ceremonyType(.display)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: SpeechSpacing.section)
                sheet(bottomInset: geo.safeAreaInsets.bottom)
            }
            .padding(.top, geo.safeAreaInsets.top)
        }
        .background(CeremonyPalette.background.ignoresSafeArea())
    }

    /// Rounded housing for the two sign-in buttons. Fills to the physical bottom.
    private func sheet(bottomInset: CGFloat) -> some View {
        VStack(spacing: SpeechSpacing.related) {
            if let notice {
                Text(notice)
                    .ceremonyType(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, SpeechStartMetrics.extraInset)
            }

            providerButton("Continue with Apple", action: continueWithApple) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
            }

            providerButton("Continue with Google", action: continueWithGoogle) {
                GoogleMark()
            }

            #if DEBUG
            Button("Skip") {
                model.skipSignInForDebug()
            }
            .buttonStyle(.plain)
            .ceremonyType(.label)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            #endif
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, SpeechSpacing.section)
        .padding(.bottom, bottomInset + SpeechSpacing.page)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 32,
                style: .continuous
            )
            .fill(Color(white: 0.11))
        }
    }

    private func providerButton(
        _ title: String,
        action: @escaping () -> Void,
        @ViewBuilder mark: () -> some View
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SpeechSpacing.cluster) {
                Spacer(minLength: 0)
                mark()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(SpeechStartButtonStyle())
        .accessibilityLabel(title)
    }

    private func continueWithApple() {
        notice = nil
        appleSignIn.onFinish = { userID in
            acceptApple(userID: userID)
        }
        appleSignIn.onCancel = {}
        appleSignIn.onFailure = {
            notice = "Sign in with Apple didn’t work. Try again."
        }
        appleSignIn.start()
    }

    private func acceptApple(userID: String?) {
        guard let userID, userID.isEmpty == false else {
            notice = "Sign in with Apple didn’t work. Try again."
            return
        }
        notice = nil
        model.acceptAppleSignIn(userID: userID)
    }

    /// Opens Google. Keeps only the account id, same as Apple. No client secret.
    private func continueWithGoogle() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
        let clientID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clientID.isEmpty == false else {
            notice = "Google sign-in needs a client id."
            return
        }
        notice = nil
        Task {
            do {
                let userID = try await googleSession.signIn(clientID: clientID)
                model.acceptGoogleSignIn(userID: userID)
            } catch GoogleSignInFailure.canceled {
                return
            } catch {
                notice = "Google sign-in didn’t work. Try again."
            }
        }
    }
}

/// Four-color mark for the Google button. Drawn so the white capsule does not tint it black.
private struct GoogleMark: View {
    private static let blue = Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
    private static let red = Color(red: 234 / 255, green: 67 / 255, blue: 53 / 255)
    private static let yellow = Color(red: 251 / 255, green: 188 / 255, blue: 5 / 255)
    private static let green = Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255)

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let line = side * 0.18
            let center = CGPoint(x: side / 2, y: side / 2)
            let radius = (side - line) / 2

            func ring(from start: Double, to end: Double, color: Color) {
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(start),
                    endAngle: .degrees(end),
                    clockwise: false
                )
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: line, lineCap: .butt)
                )
            }

            ring(from: 0, to: 55, color: Self.blue)
            ring(from: 55, to: 145, color: Self.green)
            ring(from: 145, to: 215, color: Self.yellow)
            ring(from: 215, to: 325, color: Self.red)

            let bar = CGRect(
                x: center.x - line * 0.15,
                y: center.y - line / 2,
                width: side - line / 2 - (center.x - line * 0.15),
                height: line
            )
            context.fill(Path(bar), with: .color(Self.blue))
        }
        .accessibilityHidden(true)
    }
}

/// Custom Apple button still uses the system sign-in request. The capsule is ours.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    var onFinish: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onFailure: (() -> Void)?

    func start() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let userID = (authorization.credential as? ASAuthorizationAppleIDCredential)?.user ?? ""
        Task { @MainActor in
            if userID.isEmpty {
                onFailure?()
            } else {
                onFinish?(userID)
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        Task { @MainActor in
            if canceled {
                onCancel?()
            } else {
                onFailure?()
            }
        }
    }
}

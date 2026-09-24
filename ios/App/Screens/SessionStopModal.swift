import SwiftUI
import UIKit

/// Centered stop card used by Conversation and Monologue. Same chrome; each format supplies its own copy.
struct SessionStopModal: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var title: String
    var confirmTitle: String
    var dismissTitle: String
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(reduceTransparency ? 0.72 : 0.4)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(SpeechPrimaryButtonStyle(isDestructive: true, showsTint: true))
                    .padding(.top, 22)

                Button(dismissTitle, action: onDismiss)
                    .buttonStyle(SpeechSecondaryButtonStyle())
                    .padding(.top, 10)
            }
            .padding(24)
            .frame(maxWidth: 420, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal, SpeechSpacing.page)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// Blocks the navigation swipe-back while the stop modal is up.
struct NavigationPopLock: UIViewControllerRepresentable {
    var isLocked: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isLocked = isLocked
        controller.apply()
    }

    final class Controller: UIViewController {
        var isLocked = false

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        func apply() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = !isLocked
        }
    }
}

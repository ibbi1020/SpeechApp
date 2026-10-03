import SwiftUI
import UIKit
import SpeechAppKit

struct PassageLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                Text("Passages")
                    .speechType(.h1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Room for the serif swashes. A negative top inset clips them.
                    .padding(.top, 12)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: 16,
                        bottom: 4,
                        trailing: 16
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(.isHeader)
            }

            Section {
                ForEach(model.catalog.pickerPassages) { passage in
                    PassageLibraryRow(passage: passage) {
                        select(passage)
                    }
                }
            }
        }
        .listSectionSpacing(0)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SpeechScreenBackground())
        .speechPageTitle("Passages")
        .background(PassageBarTitleHidden())
    }

    private func select(_ passage: Passage) {
        model.selectPassage(passage)
    }
}

private struct PassageLibraryRow: View {
    let passage: Passage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(passage.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(passage.durationLabel)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(passage.title), \(passage.durationLabel)")
    }
}

/// Hides the inline bar title. The H1 in the list is the visible heading.
/// The navigation title string stays so the next screen's back button can name this one.
private struct PassageBarTitleHidden: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.apply()
    }

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            apply()
        }

        func apply() {
            guard let bar = navigationController?.navigationBar, let item = screenItem() else { return }
            item.standardAppearance = hiddenTitle(bar.standardAppearance)
            item.scrollEdgeAppearance = hiddenTitle(bar.scrollEdgeAppearance ?? bar.standardAppearance)
            if let compact = bar.compactAppearance {
                item.compactAppearance = hiddenTitle(compact)
            }
            if let compactEdge = bar.compactScrollEdgeAppearance {
                item.compactScrollEdgeAppearance = hiddenTitle(compactEdge)
            }
        }

        private func screenItem() -> UINavigationItem? {
            var current: UIViewController? = self
            while let controller = current {
                if controller.parent is UINavigationController {
                    return controller.navigationItem
                }
                current = controller.parent
            }
            return nil
        }

        private func hiddenTitle(_ appearance: UINavigationBarAppearance) -> UINavigationBarAppearance {
            let copy = appearance.copy()
            var title = copy.titleTextAttributes
            title[.foregroundColor] = UIColor.clear
            copy.titleTextAttributes = title
            return copy
        }
    }
}

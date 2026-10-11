import SwiftUI
import SpeechAppKit

/// The three exercises on one fixed screen. A horizontal swipe swaps the figure and the
/// copy in place; the back control, index and start button never move.
struct FormatChooserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    /// +1 when moving to the next format, -1 to the previous. Sets which way the copy slides.
    @State private var direction: CGFloat = 1
    @State private var dragOffset: CGFloat = 0

    private static let commitDistance: CGFloat = 60
    private static let copyTravel: CGFloat = 28

    private var formats: [PracticeFormat] { PracticeFormat.all }
    private var format: PracticeFormat { formats[index] }

    private var control: PracticeFormat.StartControl {
        PracticeFormat.startControl(for: format.kind, budget: model.budget)
    }

    var body: some View {
        ZStack {
            ZStack {
                DitherPlate(name: format.plateName, drop: format.kind.plateDrop)
                    .id(format.kind)
                    .transition(.opacity)
            }
            DitherPlateScrim()

            VStack(alignment: .leading, spacing: 0) {
                backButton
                ZStack(alignment: .topLeading) {
                    heading
                        .id(format.kind)
                        .transition(copyTransition)
                }
                .offset(x: dragOffset * 0.35)
                .opacity(1 - min(0.6, abs(dragOffset) / 300))
                Spacer(minLength: SpeechSpacing.section)
                footer
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, SpeechSpacing.related)
            .padding(.bottom, SpeechSpacing.page)
        }
        .contentShape(Rectangle())
        .gesture(swipe)
        .navigationTitle(EntryGreeting.appName)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var copyTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: direction * Self.copyTravel).combined(with: .opacity),
            removal: .offset(x: -direction * Self.copyTravel).combined(with: .opacity)
        )
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let width = value.translation.width
                let pastEdge = (index == 0 && width > 0) || (index == formats.count - 1 && width < 0)
                // Resists at the first and last format instead of stopping dead.
                dragOffset = pastEdge ? width * 0.25 : width
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                if projected <= -Self.commitDistance {
                    move(by: 1)
                } else if projected >= Self.commitDistance {
                    move(by: -1)
                }
                withAnimation(SpeechMotion.settle) { dragOffset = 0 }
            }
    }

    private func move(by step: Int) {
        let next = index + step
        guard formats.indices.contains(next) else { return }
        direction = CGFloat(step)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            index = next
        }
    }

    private var backButton: some View {
        Button {
            model.goHome()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
            Text(format.title)
                .speechType(.h2)
                .foregroundStyle(.primary)
            Text(format.line)
                .speechType(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Keeps the line clear of the figure's head, which sits right of centre.
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                    width * 0.6
                }
        }
        .padding(.top, SpeechSpacing.related)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe up or down to change exercise")
        .accessibilityAdjustableAction { adjustment in
            switch adjustment {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
    }

    private var footer: some View {
        VStack(spacing: SpeechSpacing.related) {
            PageIndex(count: formats.count, current: index)

            if let note = control.note {
                Text(note)
                    .speechType(.label)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Button(control.title) {
                model.start(format.kind)
            }
            .buttonStyle(SpeechStartButtonStyle())
            .disabled(control.isEnabled == false)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle, value: index)
    }
}

private extension PracticeFormat.Kind {
    /// The conversation plate's two heads sit level with the copy; the others clear it.
    var plateDrop: CGFloat {
        self == .conversation ? 0.12 : 0
    }
}

/// Three dots. The user only ever sees one format, so something has to say there are more.
private struct PageIndex: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { slot in
                Circle()
                    .fill(slot == current ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

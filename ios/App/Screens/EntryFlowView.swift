import SwiftUI
import SpeechAppKit

/// Home and the exercise chooser are one surface in two states. The figure and the copy
/// swap; the bottom button never leaves the screen and only changes its label. Every
/// existing push path hangs off this view unchanged.
struct EntryFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    /// +1 when moving to the next exercise, -1 to the previous. Sets which way the copy slides.
    @State private var direction: CGFloat = 1
    @State private var dragOffset: CGFloat = 0

    private static let commitDistance: CGFloat = 60
    private static let copyTravel: CGFloat = 16

    private var formats: [PracticeFormat] { PracticeFormat.all }
    private var format: PracticeFormat { formats[index] }
    private var choosing: Bool { model.isChoosingFormat }

    private var control: PracticeFormat.StartControl {
        PracticeFormat.startControl(for: format.kind, budget: model.budget)
    }

    private var swap: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.swap
    }

    var body: some View {
        ZStack {
            plate
            DitherPlateScrim()

            VStack(alignment: .leading, spacing: 0) {
                top
                Spacer(minLength: SpeechSpacing.section)
                bottom
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, SpeechSpacing.related)
            .padding(.bottom, SpeechSpacing.page)
        }
        .contentShape(Rectangle())
        .gesture(swipe, isEnabled: choosing)
        .animation(swap, value: choosing)
        .navigationTitle(EntryGreeting.appName)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Layers

    private var plate: some View {
        let name = choosing ? format.plateName : "PlateHome"
        return ZStack {
            DitherPlate(name: name, drop: choosing ? format.kind.plateDrop : 0)
                .id(name)
                .transition(.opacity)
        }
    }

    private var top: some View {
        ZStack(alignment: .topLeading) {
            if choosing {
                VStack(alignment: .leading, spacing: 0) {
                    backButton
                    ZStack(alignment: .topLeading) {
                        FormatHeading(format: format, onAdjust: move)
                            .id(format.kind)
                            .transition(copyTransition)
                    }
                    .offset(x: dragOffset * 0.35)
                    .opacity(1 - min(0.6, abs(dragOffset) / 300))
                }
                .transition(.opacity)
            } else {
                homeHeader
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottom: some View {
        VStack(spacing: SpeechSpacing.related) {
            if choosing {
                PageIndex(count: formats.count, current: index)
                    .transition(.opacity)

                if let note = control.note {
                    Text(note)
                        .speechType(.label)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }

            Button {
                choosing ? model.start(format.kind) : model.chooseFormat()
            } label: {
                Text(choosing ? control.title : "Begin")
                    .contentTransition(.opacity)
            }
            .buttonStyle(SpeechStartButtonStyle())
            .disabled(choosing && control.isEnabled == false)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Home

    private var homeHeader: some View {
        HStack(alignment: .top) {
            Text(EntryGreeting.line(hasBegunBefore: model.hasBegunBefore))
                .speechType(.h1)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: SpeechSpacing.related)

            Button {
                model.openRecordings()
            } label: {
                Image(systemName: "waveform")
                    .speechGlassIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your recordings")
        }
    }

    // MARK: Chooser

    private var backButton: some View {
        Button {
            model.goHome()
        } label: {
            Image(systemName: "chevron.left")
                .speechGlassIcon()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
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
                // Resists at the first and last exercise instead of stopping dead.
                dragOffset = pastEdge ? width * 0.25 : width
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                if projected <= -Self.commitDistance {
                    move(by: 1)
                } else if projected >= Self.commitDistance {
                    move(by: -1)
                }
                withAnimation(swap) { dragOffset = 0 }
            }
    }

    private func move(by step: Int) {
        let next = index + step
        guard formats.indices.contains(next) else { return }
        direction = CGFloat(step)
        withAnimation(swap) { index = next }
    }
}

private struct FormatHeading: View {
    let format: PracticeFormat
    let onAdjust: (Int) -> Void

    var body: some View {
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
            case .increment: onAdjust(1)
            case .decrement: onAdjust(-1)
            @unknown default: break
            }
        }
    }
}

/// Three dots. The user only ever sees one exercise, so something has to say there are more.
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

private extension PracticeFormat.Kind {
    /// The conversation plate's two heads sit level with the copy; the others clear it.
    var plateDrop: CGFloat {
        self == .conversation ? 0.12 : 0
    }
}

private extension Image {
    func speechGlassIcon() -> some View {
        font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

import SwiftUI
import SpeechAppKit

/// The three exercises as full screens rather than rows. Swipe between them; each one
/// carries its own figure, heading and start control.
struct FormatChooserView: View {
    @Environment(AppModel.self) private var model

    @State private var selection: PracticeFormat.Kind = .reading

    var body: some View {
        TabView(selection: $selection) {
            ForEach(PracticeFormat.all) { format in
                FormatPlateView(format: format, index: index(of: format.kind))
                    .tag(format.kind)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(EntryGreeting.kicker)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func index(of kind: PracticeFormat.Kind) -> Int {
        PracticeFormat.all.firstIndex { $0.kind == kind } ?? 0
    }
}

private struct FormatPlateView: View {
    let format: PracticeFormat
    let index: Int

    @Environment(AppModel.self) private var model

    private var control: PracticeFormat.StartControl {
        PracticeFormat.startControl(for: format.kind, budget: model.budget)
    }

    var body: some View {
        ZStack {
            DitherPlate(name: format.plateName)
            DitherPlateScrim()

            VStack(alignment: .leading, spacing: 0) {
                backButton
                heading
                Spacer(minLength: SpeechSpacing.section)
                footer
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, SpeechSpacing.related)
            .padding(.bottom, SpeechSpacing.page)
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
    }

    private var footer: some View {
        VStack(spacing: SpeechSpacing.related) {
            PageIndex(count: PracticeFormat.all.count, current: index)

            if let note = control.note {
                Text(note)
                    .speechType(.label)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            Button(control.title) {
                model.start(format.kind)
            }
            .buttonStyle(SpeechStartButtonStyle())
            .disabled(control.isEnabled == false)
        }
        .frame(maxWidth: .infinity)
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

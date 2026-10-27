import SwiftUI
import SpeechAppKit

/// Home progress. A glass panel while it is a card. Solid black only after the
/// gesture commits to a full screen. At rest the card runs to the bottom of the
/// screen, and Gallery sits in front of its lower edge.
struct ProgressSheet: View {
    var topInset: CGFloat
    var bottomInset: CGFloat
    /// Full screen height, including the areas outside the safe area.
    var containerHeight: CGFloat
    /// How open this sheet is, so the home stack can put it in front of Gallery.
    @Binding var lift: CGFloat
    /// How open Gallery is. Crossing into view closes this sheet.
    var otherLift: CGFloat

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Title band that stays visible above Gallery.
    static let lip: CGFloat = 56

    @State private var progress: CGFloat = 0
    @State private var dragOrigin: CGFloat?
    @State private var isDragging = false
    @State private var committedFullScreen = false
    @State private var manifests: [RecordingManifest] = []
    @State private var loadError: String?

    private var displayed: CGFloat { min(1, max(0, progress)) }
    private var showsSolid: Bool {
        reduceTransparency || (committedFullScreen && !isDragging)
    }
    private var cornerRadius: CGFloat { showsSolid ? 0 : 32 }
    private var motion: Animation? { reduceMotion ? nil : SpeechMotion.settle }

    private var snapshot: ProgressSnapshot {
        ProgressSnapshot(
            ledger: model.ledger,
            recordings: manifests,
            catalog: model.catalog
        )
    }

    /// Closed, the card reaches the screen bottom. Gallery covers all but `lip`.
    private var restingHeight: CGFloat { Self.lip + GallerySheet.peek }

    var body: some View {
        let panelHeight = restingHeight + displayed * (containerHeight - restingHeight)
        let topGap = max(0, containerHeight - panelHeight)
        let travel = max(1, containerHeight - restingHeight)
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topGap)
                .allowsHitTesting(false)
            panel(panelTop: topGap, travel: travel)
                .frame(height: panelHeight)
        }
        .frame(height: containerHeight, alignment: .top)
        .onChange(of: displayed, initial: true) { _, value in
            lift = value
        }
        .onChange(of: otherLift) { old, new in
            guard new > 0.05, old <= 0.05 else { return }
            guard displayed > 0.02 || isDragging else { return }
            settle(open: false)
        }
        .task { reload() }
    }

    private func panel(panelTop: CGFloat, travel: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(panelTop: panelTop, travel: travel)
            ProgressPages(
                snapshot: snapshot,
                bottomInset: bottomInset,
                loadError: loadError,
                allowsScroll: committedFullScreen
            )
            .opacity(displayed > 0.04 ? 1 : 0)
            .accessibilityHidden(!committedFullScreen)
        }
        .background { panelFill }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(motion, value: showsSolid)
    }

    private var panelFill: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(CeremonyPalette.background)
                .opacity(showsSolid ? 1 : 0)
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: max(cornerRadius, 1), style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: max(cornerRadius, 1), style: .continuous)
                    )
                    .opacity(showsSolid ? 0 : 1)
            }
        }
    }

    /// Keeps the title and the close button below the status bar once the
    /// card reaches the top. The peek uses a small inset.
    private func header(panelTop: CGFloat, travel: CGFloat) -> some View {
        let collapsed = displayed < 0.55
        let top = collapsed ? 14 : max(22, topInset - panelTop)
        return HStack(spacing: 8) {
            progressTitle
            Spacer(minLength: 0)
            if !collapsed {
                Button {
                    settle(open: false)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SpeechIconCircleStyle(diameter: SpeechIconCircleStyle.gallery))
                .accessibilityLabel("Close")
                .opacity(closeOpacity)
                .allowsHitTesting(displayed > 0.7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, top)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .simultaneousGesture(drag(travel: travel))
    }

    private var progressTitle: some View {
        let titleSize: CGFloat = committedFullScreen ? 36 : 24
        return Text("Progress")
            .font(.system(size: titleSize, weight: .semibold))
            .tracking(committedFullScreen ? -0.42 : -0.33)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            .accessibilityAction(.default) { settle(open: !committedFullScreen) }
    }

    private var closeOpacity: CGFloat {
        min(1, max(0, (displayed - 0.55) / 0.35))
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = progress }
                let raw = (dragOrigin ?? 0) + (-value.translation.height / travel)
                if !isDragging {
                    withAnimation(reduceMotion ? nil : SpeechMotion.swap) { isDragging = true }
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { progress = rubber(raw) }
            }
            .onEnded { value in
                let origin = dragOrigin ?? progress
                let projected = origin + (-value.predictedEndTranslation.height / travel)
                let flickUp = value.velocity.height < -650
                let flickDown = value.velocity.height > 650
                let commit = HomeSheetDrag.commitsOpen(
                    flickUp: flickUp,
                    flickDown: flickDown,
                    projected: Double(projected)
                )
                dragOrigin = nil
                settle(open: commit)
            }
    }

    private func settle(open: Bool) {
        dragOrigin = nil
        withAnimation(motion) {
            isDragging = false
            committedFullScreen = open
            progress = open ? 1 : 0
        }
    }

    private func reload() {
        do {
            manifests = try RecordingsService.store.list()
            loadError = nil
        } catch {
            UserFacingFailure.log(error, context: "progress list")
            loadError = UserFacingFailure.message(for: error)
            manifests = []
        }
    }

    private func rubber(_ value: CGFloat) -> CGFloat {
        if value < 0 { return value * 0.28 }
        if value > 1 { return 1 + (value - 1) * 0.28 }
        return value
    }
}

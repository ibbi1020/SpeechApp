import SwiftUI
import SpeechAppKit

/// Home gallery. A glass panel while it is a card. Solid black only after the
/// gesture commits to a full screen. The title grows at that same moment.
struct GallerySheet: View {
    /// Distance from the physical top of the screen to the bottom of the
    /// status bar, including the Dynamic Island. Controls start below this.
    var topInset: CGFloat
    var bottomInset: CGFloat
    /// Full screen height, including the areas outside the safe area.
    var containerHeight: CGFloat

    @Environment(AppModel.self) private var model
    /// How open this sheet is, so Progress can close when Gallery comes forward.
    @Binding var lift: CGFloat
    /// How open Progress is. Crossing into view closes this sheet.
    var otherLift: CGFloat

    static let peek: CGFloat = 88

    /// How much of the home column the collapsed card covers, plus a gap so
    /// Begin sits fully above the glass. The card is measured from the physical
    /// bottom; the home column ends at the safe area, one `bottomInset` higher.
    static func homeClearance(bottomInset: CGFloat) -> CGFloat {
        max(0, peek - bottomInset) + SpeechSpacing.section
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var progress: CGFloat = 0
    @State private var dragOrigin: CGFloat?
    @State private var isDragging = false
    @State private var committedFullScreen = false
    @State private var page: Page = .library
    @State private var pendingDelete: RecordingManifest?
    @State private var manifests: [RecordingManifest] = []
    @State private var formatFilter: RecordingManifest.Format?
    @State private var errorMessage: String?
    @State private var keepEnabled = RecordingsService.keepRecordings

    private enum Page: Equatable {
        case library
        case recording(RecordingManifest)
    }

    private var displayed: CGFloat { min(1, max(0, progress)) }
    private var showsSolid: Bool {
        reduceTransparency || (committedFullScreen && !isDragging)
    }
    private var cornerRadius: CGFloat { showsSolid ? 0 : 32 }
    private var motion: Animation? { reduceMotion ? nil : SpeechMotion.settle }

    var body: some View {
        let travel = max(1, containerHeight - Self.peek)
        let gap = (1 - displayed) * travel
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(0, gap))
                .allowsHitTesting(false)
            panel(panelTop: gap, travel: travel)
                .frame(height: Self.peek + displayed * travel)
        }
        .frame(height: containerHeight, alignment: .top)
        .confirmationDialog(
            "Delete this recording?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            if let item = pendingDelete {
                Button("Delete", role: .destructive) { delete(item) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { reload() }
        .onChange(of: displayed, initial: true) { _, value in
            lift = value
        }
        .onChange(of: otherLift) { old, new in
            guard new > 0.05, old <= 0.05 else { return }
            guard displayed > 0.02 || isDragging else { return }
            settle(open: false)
        }
        .onAppear {
            keepEnabled = RecordingsService.keepRecordings
            consumeGalleryRequest()
        }
        .onChange(of: model.presentGallery) { _, open in
            if open { consumeGalleryRequest() }
        }
    }

    init(
        topInset: CGFloat,
        bottomInset: CGFloat,
        containerHeight: CGFloat,
        lift: Binding<CGFloat>,
        otherLift: CGFloat,
        startOpen: Bool = false
    ) {
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.containerHeight = containerHeight
        _lift = lift
        self.otherLift = otherLift
        if startOpen {
            _progress = State(initialValue: 1)
            _committedFullScreen = State(initialValue: true)
        }
    }

    private func consumeGalleryRequest() {
        guard model.presentGallery else { return }
        model.presentGallery = false
        page = .library
        dragOrigin = nil
        isDragging = false
        committedFullScreen = true
        progress = 1
        reload()
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func panel(panelTop: CGFloat, travel: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(panelTop: panelTop, travel: travel)
            screenBody
        }
        .background { panelFill }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

    /// Keeps the title and the 44pt controls below the status bar.
    /// While the card is still low on the screen, the peek uses a small inset.
    /// As the card's top enters the status bar, the inset grows so nothing
    /// sits under the clock or the Dynamic Island.
    private func header(panelTop: CGFloat, travel: CGFloat) -> some View {
        let top = max(22, topInset - panelTop)
        return HStack(spacing: 8) {
            if showsBack {
                symbolButton("chevron.left", label: "Back") { leaveRecording() }
            }
            if case .library = page {
                galleryTitle
            }
            Spacer(minLength: 0)
            if case .recording(let item) = page {
                symbolButton("trash", label: "Delete recording") {
                    pendingDelete = item
                }
            }
            symbolButton("xmark", label: "Close") { settle(open: false) }
                .opacity(closeOpacity)
                .allowsHitTesting(displayed > 0.7)
        }
        .padding(.horizontal, 16)
        .padding(.top, top)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .simultaneousGesture(drag(travel: travel))
    }

    /// Full-screen library only. The peek stays title and count.
    private var showsKeepToggle: Bool {
        committedFullScreen && page == .library
    }

    /// Sits with the recordings it governs, under the title, not in the chrome.
    private var keepRecordingsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $keepEnabled) {
                Text("Keep recordings")
                    .font(.body.weight(.semibold))
            }
            .onChange(of: keepEnabled) { _, value in
                RecordingsService.keepRecordings = value
            }
            .accessibilityHint(RecordingsService.keepExplanation)
            Text(RecordingsService.keepExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }

    /// Total saved feedbacks, sat on the same baseline as the title.
    private var galleryTitle: some View {
        let titleSize: CGFloat = committedFullScreen ? 36 : 24
        let countSize: CGFloat = committedFullScreen ? 16 : 14
        return HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text("Gallery")
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(committedFullScreen ? -0.42 : -0.33)
                .foregroundStyle(.primary)
            Text(manifests.count, format: .number)
                .font(.system(size: countSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Gallery, \(manifests.count) recordings")
        .accessibilityAction(.default) { settle(open: !committedFullScreen) }
    }

    private var showsBack: Bool {
        if case .recording = page { return true }
        return false
    }

    private var closeOpacity: CGFloat {
        min(1, max(0, (displayed - 0.55) / 0.35))
    }

    @ViewBuilder
    private var screenBody: some View {
        switch page {
        case .library:
            libraryList
        case .recording(let item):
            recordingPage(item)
        }
    }

    private var libraryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeechSpacing.section) {
                if showsKeepToggle {
                    keepRecordingsRow
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if manifests.isEmpty {
                    Text("No recordings on this phone.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(alignment: .leading, spacing: SpeechSpacing.section) {
                        if committedFullScreen, !filters.isEmpty {
                            filterRow
                        }
                        ForEach(dayGroups) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(group.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, SpeechSpacing.cluster)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group.items) { item in
                                    recordingRow(item)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, SpeechSpacing.cluster)
            .padding(.bottom, bottomInset)
        }
    }

    /// All, then each kind that actually has a recording. Hidden when every
    /// recording is the same kind — the row would only repeat itself.
    private var filters: [GalleryFilter] {
        let present = GalleryFilter.order.filter { format in
            manifests.contains { $0.format == format }
        }
        guard present.count > 1 else { return [] }
        return [GalleryFilter(title: "All", format: nil, symbol: "tray.full")] + present.map {
            GalleryFilter(title: formatName($0), format: $0, symbol: formatSymbol($0))
        }
    }

    private var filterRow: some View {
        GalleryCategoryTabs(filters: filters, selection: $formatFilter)
            .padding(.horizontal, -16)
    }

    private var dayGroups: [GalleryDay] {
        let calendar = Calendar.current
        let source = manifests.filter { item in
            guard let formatFilter else { return true }
            return item.format == formatFilter
        }
        let grouped = Dictionary(grouping: source) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            let items = (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            return GalleryDay(day: day, title: dayTitle(day), items: items)
        }
    }

    private func recordingRow(_ item: RecordingManifest) -> some View {
        Button {
            guard committedFullScreen else { return }
            withAnimation(motion) { page = .recording(item) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.topic)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(rowDetail(for: item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.topic), \(identityLine(for: item))")
    }

    private func recordingPage(_ item: RecordingManifest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.topic)
                    .padding(.top, SpeechSpacing.section)
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.42)
                    .fixedSize(horizontal: false, vertical: true)
                Text(identityLine(for: item))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .padding(.bottom, item.reportLines.isEmpty || item.takes.isEmpty ? 18 : SpeechSpacing.related)
                if !item.takes.isEmpty {
                    FeedbackStatList(rows: FeedbackStatRows.stored(item.reportLines))
                        .padding(.bottom, item.reportLines.isEmpty ? 0 : 18)
                }
                TakeReviewSection(manifest: item, saveError: item.saveError)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, bottomInset + 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func symbolButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(SpeechIconCircleStyle(diameter: SpeechIconCircleStyle.gallery))
        .accessibilityLabel(label)
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
            if !open { page = .library }
        }
    }

    private func leaveRecording() {
        withAnimation(motion) { page = .library }
    }

    private func delete(_ item: RecordingManifest) {
        try? RecordingsService.store.delete(id: item.id)
        pendingDelete = nil
        withAnimation(motion) { page = .library }
        reload()
    }

    private func reload() {
        do {
            manifests = try RecordingsService.store.list()
            errorMessage = nil
            if let formatFilter, !manifests.contains(where: { $0.format == formatFilter }) {
                self.formatFilter = nil
            }
        } catch {
            UserFacingFailure.log(error, context: "gallery list")
            errorMessage = UserFacingFailure.message(for: error)
            manifests = []
        }
    }

    private func rowDetail(for item: RecordingManifest) -> String {
        "\(item.createdAt.formatted(date: .omitted, time: .shortened)) · \(formatName(item.format))"
    }

    private func identityLine(for item: RecordingManifest) -> String {
        "\(dayTitle(item.createdAt)), \(rowDetail(for: item))"
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func formatName(_ format: RecordingManifest.Format) -> String {
        switch format {
        case .monologue: "Talk"
        case .reading: "Reading"
        case .conversation: "Conversation"
        }
    }

    private func formatSymbol(_ format: RecordingManifest.Format) -> String {
        switch format {
        case .reading: "text.book.closed"
        case .monologue: "waveform"
        case .conversation: "bubble.left.and.bubble.right"
        }
    }

    private func rubber(_ value: CGFloat) -> CGFloat {
        if value < 0 { return value * 0.28 }
        if value > 1 { return 1 + (value - 1) * 0.28 }
        return value
    }
}

/// One calendar day in the gallery, newest day first.
private struct GalleryDay: Identifiable {
    var day: Date
    var title: String
    var items: [RecordingManifest]
    var id: Date { day }
}

/// A way to narrow the gallery. `format == nil` means every recording.
struct GalleryFilter: Identifiable {
    static let order: [RecordingManifest.Format] = [.reading, .monologue, .conversation]

    var title: String
    var format: RecordingManifest.Format?
    var symbol: String
    var id: String { title }
}

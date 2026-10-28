import SwiftUI
import SpeechAppKit

/// Calendar, then the five pictures. Month changes stay on the calendar.
/// Swiping the pictures does not change the month.
struct ProgressPages: View {
    var snapshot: ProgressSnapshot
    var bottomInset: CGFloat
    var loadError: String?
    /// The peek is clipped. Scrolling waits until the sheet is open.
    var allowsScroll: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month: Date
    @State private var pageID: Int? = 0
    @State private var selection: DaySelection?
    @State private var drag: DayDrag?
    /// Day frames in `daySpace`. The drag uses the same space, so a point lands on a cell.
    @State private var frames: [DayHit] = []
    /// A drag already claimed this touch, so the day's button does not start a new selection.
    @State private var swallowTap = false

    private let calendarGap: CGFloat = 72
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let dayNumberSize: CGFloat = 11
    /// The line box the digit is drawn in. Taller than the cap, so the bar does not treat it as ink.
    private let dayNumberHeight: CGFloat = 12
    /// Space between the day number and the mark under it.
    private let dayStackSpacing: CGFloat = 4
    /// The check and the dots live in this slot. The today ring is taller and is centered on it.
    private let dayMarkHeight: CGFloat = 16
    private let dayRing: CGFloat = 20
    /// The row holds the face. The face is the bar, with more air under the check than above the digit.
    private let dayRowHeight: CGFloat = 44
    private let dayRowGap: CGFloat = 10
    private let daySpace = "progress-day-grid"

    init(snapshot: ProgressSnapshot, bottomInset: CGFloat, loadError: String?, allowsScroll: Bool) {
        self.snapshot = snapshot
        self.bottomInset = bottomInset
        self.loadError = loadError
        self.allowsScroll = allowsScroll
        _month = State(initialValue: snapshot.latestMonth)
    }

    private var shownMonth: Date {
        let start = startOfMonth(month)
        if start < snapshot.firstMonth { return snapshot.firstMonth }
        if start > snapshot.latestMonth { return snapshot.latestMonth }
        return start
    }

    private var canGoBack: Bool { shownMonth > snapshot.firstMonth }
    private var canGoForward: Bool { shownMonth < snapshot.latestMonth }
    private var currentPage: Int { pageID ?? 0 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: calendarGap) {
                if let loadError {
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal, SpeechSpacing.page)
                }
                calendar
                VStack(spacing: SpeechSpacing.related) {
                    insightScroll
                    pager
                }
            }
            .padding(.bottom, bottomInset + SpeechSpacing.page)
        }
        .scrollDisabled(!allowsScroll)
        .onChange(of: allowsScroll) { _, canScroll in
            guard !canScroll else { return }
            drag = nil
            selection = nil
        }
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            HStack(spacing: 8) {
                monthButton("chevron.left", label: "Previous month", enabled: canGoBack) {
                    changeMonth(by: -1)
                }
                Text(shownMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(monthDrag)
                    .accessibilityAddTraits(.isHeader)
                monthButton("chevron.right", label: "Next month", enabled: canGoForward) {
                    changeMonth(by: 1)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: dayRowGap) {
                    HStack(spacing: 0) {
                        ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: dayRowGap) {
                        ForEach(0..<leadingBlanks, id: \.self) { _ in
                            daySlot {
                                Text("00")
                                    .font(.system(size: dayNumberSize))
                                    .frame(height: dayNumberHeight)
                                    .hidden()
                                Color.clear.frame(width: dayRing, height: dayMarkHeight)
                            }
                            .accessibilityHidden(true)
                        }
                        ForEach(1...daysInMonth, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                    .backgroundPreferenceValue(DayAnchorKey.self) { anchors in
                        GeometryReader { proxy in
                            let hits = anchors.map { item in
                                DayHit(
                                    day: item.day,
                                    week: item.week,
                                    index: item.index,
                                    rect: proxy[item.anchor]
                                )
                            }
                            DayHighlight(hits: hits, band: highlightBand)
                                .preference(key: DayFrameKey.self, value: hits)
                        }
                    }
                    .onPreferenceChange(DayFrameKey.self) { frames = $0 }
                    .simultaneousGesture(dayDrag)
                    .coordinateSpace(.named(daySpace))
                }
                if highlightSpan != nil {
                    HStack {
                        Spacer(minLength: 0)
                        Button("Clear", action: clearSelection)
                            .font(.body.weight(.semibold))
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .padding(.horizontal, SpeechSpacing.page)
        .padding(.top, SpeechSpacing.section)
    }

    private var weekdayLabels: [String] {
        Array(Calendar.current.veryShortStandaloneWeekdaySymbols.prefix(7))
    }

    private var leadingBlanks: Int {
        max(0, Calendar.current.component(.weekday, from: shownMonth) - 1)
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: shownMonth)?.count ?? 30
    }

    /// How far the today ring sticks out of the mark slot, above and below.
    private var dayRingOverflow: CGFloat { (dayRing - dayMarkHeight) / 2 }

    /// The ink of the digit. SF Pro's cap height is about 0.72 of the point size.
    private var dayCapHeight: CGFloat { (dayNumberSize * 0.72).rounded() }

    /// Gray above the number's line box. Just enough for the today ring.
    /// The cap already sits below the top of that box, so this is not the air above the ink.
    private var dayTopAir: CGFloat { dayRingOverflow }

    /// Gray under the mark.
    ///
    /// The digit is a thin cap. The check is a filled circle, and it sits at the bottom of the stack.
    /// The same pad above and below leaves that circle on the floor of the bar.
    /// The space under the circle is the space above the cap, plus half of how much taller the circle is.
    /// The heavier side gets the extra air, so the weight sits in the middle of the bar.
    private var dayBottomAir: CGFloat {
        let aboveCap = dayTopAir + (dayNumberHeight - dayCapHeight) / 2
        let extraWeight = (dayMarkHeight - dayCapHeight) / 2
        return aboveCap + extraWeight
    }

    /// The number and the mark. This frame is what the bar paints.
    private func dayFace<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: dayStackSpacing) {
            content()
        }
        .padding(.top, dayTopAir)
        .padding(.bottom, dayBottomAir)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// The row is taller than the face. The face stays centered in it.
    private func daySlot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        dayFace(content: content)
            .frame(maxWidth: .infinity, minHeight: dayRowHeight, alignment: .center)
    }

    private func dayCell(_ day: Int) -> some View {
        let date = dayDate(day)
        let mark = mark(for: date)
        let today = Calendar.current.isDate(date, inSameDayAs: snapshot.today)
        let highlighted = isHighlighted(date)
        let selectable = canSelect(date)
        let week = (leadingBlanks + day - 1) / 7
        let face = dayFace {
            Text(day, format: .number)
                .font(.system(size: dayNumberSize, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(dayNumberColor(mark: mark, highlighted: highlighted))
                .frame(height: dayNumberHeight)
            dayMark(mark, today: today)
        }
        .anchorPreference(key: DayAnchorKey.self, value: .bounds) { anchor in
            [
                DayAnchor(
                    day: date,
                    week: week,
                    index: ProgressCalendar.index(of: date),
                    anchor: anchor
                )
            ]
        }
        let label = face
            .frame(maxWidth: .infinity, minHeight: dayRowHeight, alignment: .center)
            .contentShape(Rectangle())

        return Group {
            if selectable {
                Button {
                    guard !swallowTap else { return }
                    handleTap(date)
                } label: {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
        .accessibilityValue(dayValue(mark: mark, highlighted: highlighted))
        .accessibilityAddTraits(selectable ? .isButton : [])
        .accessibilityAddTraits(highlighted ? .isSelected : [])
        .accessibilityAction(.default) {
            if selectable { handleTap(date) }
        }
    }

    private func dayNumberColor(mark: DayMark, highlighted: Bool) -> Color {
        if highlighted { return .white }
        if mark == .future { return Color.white.opacity(0.35) }
        return Color.white.opacity(0.72)
    }

    private func dayValue(mark: DayMark, highlighted: Bool) -> String {
        switch (highlighted, mark) {
        case (true, .done): "Selected, practiced"
        case (true, _): "Selected"
        case (false, .done): "Practiced"
        default: ""
        }
    }

    @ViewBuilder
    private func dayMark(_ mark: DayMark, today: Bool) -> some View {
        ZStack {
            switch mark {
            case .none:
                Color.clear
            case .future:
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 8, height: 8)
            case .empty:
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 8, height: 8)
            case .done:
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.black)
            }
            if today {
                Circle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: dayRing - 1, height: dayRing - 1)
            }
        }
        .frame(width: dayRing, height: dayMarkHeight)
    }

    private var monthDrag: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -40 { changeMonth(by: 1) }
                if value.translation.width > 40 { changeMonth(by: -1) }
            }
    }

    private var insightScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(InsightPage.allCases) { page in
                    BlurDissolve(value: chartFilter) { filter in
                        insight(page, filter: filter)
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(page.rawValue)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $pageID)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func insight(_ page: InsightPage, filter: ChartFilter) -> some View {
        let picture = picture(for: filter)
        let line = caption(for: page, picture: picture, filter: filter)
        return VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            Text(title(for: page, filter: filter))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            chart(page, picture: picture, filter: filter)
                .frame(height: 220)
            if !line.isEmpty {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SpeechSpacing.page)
    }

    @ViewBuilder
    private func chart(_ page: InsightPage, picture: ProgressSnapshot, filter: ChartFilter) -> some View {
        let empty = emptyCopy(for: page, filter: filter)
        switch page {
        case .turns:
            SeriesPlot(
                series: [picture.turns.map(\.secondsPerTurn)],
                fromZero: true,
                unit: "seconds",
                xLabels: [],
                dots: true,
                active: currentPage == page.rawValue,
                empty: empty
            )
        case .silences:
            SeriesPlot(
                series: picture.talks.map(\.pauseFrequency),
                fromZero: true,
                unit: "per min",
                xLabels: silenceLabels(for: picture),
                dots: false,
                active: currentPage == page.rawValue,
                empty: empty
            )
        case .sounds:
            BarPlot(
                bars: picture.sounds.map {
                    BarItem(label: $0.symbol, value: Double($0.misses), prominent: $0.highLoad)
                },
                unit: "misses",
                active: currentPage == page.rawValue,
                empty: empty
            )
        case .skips:
            BarPlot(
                bars: picture.skips.map {
                    BarItem(label: $0.word, value: Double($0.count), prominent: true)
                },
                unit: "skips",
                active: currentPage == page.rawValue,
                empty: empty
            )
        case .reading:
            SeriesPlot(
                series: [picture.readingRates],
                fromZero: false,
                unit: "syl/min",
                xLabels: [],
                dots: true,
                active: currentPage == page.rawValue,
                empty: empty
            )
        }
    }

    private func silenceLabels(for picture: ProgressSnapshot) -> [String] {
        let count = picture.talks.map(\.pauseFrequency.count).max() ?? 0
        guard count > 0 else { return [] }
        return (1...count).map(String.init)
    }

    private func picture(for filter: ChartFilter) -> ProgressSnapshot {
        guard let start = filter.start, let end = filter.end else { return snapshot }
        return snapshot.filtered(from: start, through: end)
    }

    private func title(for page: InsightPage, filter: ChartFilter) -> String {
        guard filter.isOn else { return page.title }
        switch page {
        case .turns: return "Turns"
        case .silences: return "Pause frequency"
        case .sounds, .skips, .reading: return page.title
        }
    }

    private func caption(for page: InsightPage, picture: ProgressSnapshot, filter: ChartFilter) -> String {
        guard filter.isOn else { return page.caption }
        guard hasRows(page, picture) else { return "" }
        let single = filter.isSingleDay
        switch page {
        case .turns:
            return single
                ? "Seconds you spoke in a turn on this day."
                : "Seconds you spoke in a turn on these days."
        case .silences:
            return single
                ? "Pauses per minute in each take saved this day."
                : "Pauses per minute in each talk saved on these days."
        case .sounds:
            return single ? "Sounds missed on this day." : "Sounds missed on these days."
        case .skips:
            return single ? "Words skipped on this day." : "Words skipped on these days."
        case .reading:
            return single
                ? "Reading speed on this day, in syllables per minute."
                : "Reading speeds on these days, in syllables per minute."
        }
    }

    private func hasRows(_ page: InsightPage, _ picture: ProgressSnapshot) -> Bool {
        switch page {
        case .turns: !picture.turns.isEmpty
        case .silences: !picture.talks.isEmpty
        case .sounds: !picture.sounds.isEmpty
        case .skips: !picture.skips.isEmpty
        case .reading: !picture.readingRates.isEmpty
        }
    }

    private func emptyCopy(for page: InsightPage, filter: ChartFilter) -> String {
        guard filter.isOn else { return "Not enough data." }
        let noun: String
        switch page {
        case .turns: noun = "conversations"
        case .silences: noun = "talks"
        case .sounds: noun = "missed sounds"
        case .skips: noun = "skipped words"
        case .reading: noun = "readings"
        }
        return filter.isSingleDay ? "No \(noun) this day." : "No \(noun) in this range."
    }

    private var pager: some View {
        HStack(spacing: 8) {
            ForEach(InsightPage.allCases) { page in
                Button {
                    move(to: page.rawValue)
                } label: {
                    Circle()
                        .fill(Color.white.opacity(currentPage == page.rawValue ? 1 : 0.28))
                        .frame(width: 6, height: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(for: page, filter: chartFilter))
                .accessibilityAddTraits(currentPage == page.rawValue ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func monthButton(
        _ systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(SpeechIconCircleStyle(diameter: SpeechIconCircleStyle.gallery))
        .opacity(enabled ? 1 : 0.28)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func changeMonth(by delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: shownMonth) else { return }
        let start = startOfMonth(next)
        guard start >= snapshot.firstMonth, start <= snapshot.latestMonth else { return }
        withAnimation(reduceMotion ? nil : SpeechMotion.settle) { month = start }
    }

    private func move(to page: Int) {
        withAnimation(reduceMotion ? nil : SpeechMotion.settle) { pageID = page }
    }

    private func startOfMonth(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private func mark(for date: Date) -> DayMark {
        let start = Calendar.current.startOfDay(for: date)
        if snapshot.practicedDays.contains(start) { return .done }
        if start > snapshot.today { return .future }
        if let earliest = snapshot.earliestDay, start >= earliest { return .empty }
        return .none
    }

    private var chartFilter: ChartFilter {
        guard let selection else { return ChartFilter() }
        return ChartFilter(start: selection.start, end: selection.end)
    }

    private var highlightSpan: DaySpan? {
        if let drag { return DaySpan(start: drag.start, end: drag.end) }
        if let selection { return DaySpan(start: selection.start, end: selection.end) }
        return nil
    }

    private var highlightBand: BandEnds? {
        guard let span = highlightSpan else { return nil }
        let start = min(span.start, span.end)
        let end = max(span.start, span.end)
        return BandEnds(
            lower: ProgressCalendar.index(of: start),
            upper: ProgressCalendar.index(of: end) + 1
        )
    }

    /// A drag paints the range. A still tap is left to the day's button.
    private var dayDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(daySpace))
            .onChanged { value in
                guard let origin = selectableDay(at: value.startLocation) else { return }
                var session: DayDrag
                if let drag, sameDay(drag.origin, origin) {
                    session = drag
                } else if drag == nil {
                    session = beginDrag(on: origin)
                } else {
                    return
                }
                swallowTap = true
                session.moved = true
                if let day = selectableDay(at: value.location) {
                    let span = ordered(session.anchor, day)
                    session.start = span.start
                    session.end = span.end
                }
                drag = session
            }
            .onEnded { _ in
                let session = drag
                drag = nil
                if let session, session.moved {
                    selection = DaySelection(start: session.start, end: session.end, pending: false)
                }
                Task { @MainActor in swallowTap = false }
            }
    }

    private func beginDrag(on origin: Date) -> DayDrag {
        let anchor: Date
        if let selection, selection.pending, !sameDay(selection.start, origin) {
            anchor = selection.start
        } else {
            anchor = origin
        }
        let span = ordered(anchor, origin)
        return DayDrag(origin: origin, anchor: anchor, start: span.start, end: span.end, moved: false)
    }

    private func handleTap(_ day: Date) {
        guard canSelect(day) else { return }
        if let selection, selection.pending {
            if sameDay(selection.start, day) { return }
            let span = ordered(selection.start, day)
            self.selection = DaySelection(start: span.start, end: span.end, pending: false)
            return
        }
        selection = DaySelection(start: day, end: day, pending: true)
    }

    private func clearSelection() {
        drag = nil
        selection = nil
    }

    private func ordered(_ first: Date, _ second: Date) -> DaySpan {
        first <= second ? DaySpan(start: first, end: second) : DaySpan(start: second, end: first)
    }

    private func sameDay(_ first: Date, _ second: Date) -> Bool {
        Calendar.current.isDate(first, inSameDayAs: second)
    }

    private func canSelect(_ date: Date) -> Bool {
        switch mark(for: date) {
        case .done, .empty: true
        case .none, .future: false
        }
    }

    private func dayDate(_ day: Int) -> Date {
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: day - 1, to: shownMonth) ?? shownMonth
        )
    }

    private func selectableDay(at point: CGPoint) -> Date? {
        frames.first { $0.rect.contains(point) && canSelect($0.day) }?.day
    }

    private func isHighlighted(_ date: Date) -> Bool {
        guard let span = highlightSpan else { return false }
        let day = Calendar.current.startOfDay(for: date)
        let start = Calendar.current.startOfDay(for: min(span.start, span.end))
        let end = Calendar.current.startOfDay(for: max(span.start, span.end))
        return day >= start && day <= end
    }
}

private enum DayMark {
    case none
    case empty
    case future
    case done
}

private enum InsightPage: Int, CaseIterable, Identifiable {
    case turns
    case silences
    case sounds
    case skips
    case reading

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .turns: "Turns got longer"
        case .silences: "Pause frequency"
        case .sounds: "Sounds you miss"
        case .skips: "Words you skip"
        case .reading: "Reading speed"
        }
    }

    var caption: String {
        switch self {
        case .turns:
            "Seconds you spoke in a turn, from your earliest saved conversation to the latest."
        case .silences:
            "Pauses per minute in each saved talk, from the first take to the last."
        case .sounds:
            "How many times you missed each sound."
        case .skips:
            "How many times you skipped each word while reading."
        case .reading:
            "Your last 10 reading speeds, in syllables per minute."
        }
    }
}

private struct BarItem: Identifiable {
    var label: String
    var value: Double
    var prominent: Bool
    var id: String { "\(label)-\(value)" }
}

/// Columns that grow from the baseline when the page is current.
private struct BarPlot: View {
    var bars: [BarItem]
    var unit: String
    var active: Bool
    var empty: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var drawToken = 0

    var body: some View {
        Group {
            if bars.isEmpty {
                emptyPlot(empty)
            } else {
                plot
            }
        }
        .onChange(of: active, initial: true) { _, on in
            syncDraw(on)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bars.isEmpty ? empty : summary)
    }

    private var summary: String {
        bars.map { "\($0.label), \(Int($0.value.rounded()))" }.joined(separator: ", ")
    }

    private var plot: some View {
        let top = max(bars.map(\.value).max() ?? 1, 1) * 1.15
        let range = 0...top
        return VStack(alignment: .leading, spacing: 4) {
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ZStack(alignment: .bottom) {
                tickMarks(range: range)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                        barColumn(bar, index: index, top: top)
                    }
                }
                .padding(.leading, 36)
            }
        }
    }

    private func barColumn(_ bar: BarItem, index: Int, top: Double) -> some View {
        let fraction = top > 0 ? bar.value / top : 0
        return VStack(spacing: 6) {
            Text(Int(bar.value.rounded()), format: .number)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .opacity(drawn)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bar.prominent ? Color.white : Color.white.opacity(0.38))
                .frame(height: max(2, 150 * fraction * drawn))
            Text(bar.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .animation(barAnimation(index: index), value: drawn)
    }

    private func tickMarks(range: ClosedRange<Double>) -> some View {
        let ticks = tickValues(range)
        return GeometryReader { geo in
            let plot = CGRect(x: 36, y: 0, width: geo.size.width - 36, height: geo.size.height - 38)
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                let y = yPosition(tick, in: plot, range: range)
                Path { path in
                    path.move(to: CGPoint(x: plot.minX, y: y))
                    path.addLine(to: CGPoint(x: plot.maxX, y: y))
                }
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                Text(axisLabel(tick))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .position(x: 16, y: y)
            }
        }
    }

    private func barAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: 0.55).delay(Double(index) * 0.06)
    }

    private func syncDraw(_ on: Bool) {
        drawToken += 1
        let token = drawToken
        guard on else {
            drawn = 0
            return
        }
        if reduceMotion {
            drawn = 1
            return
        }
        drawn = 0
        Task { @MainActor in
            guard token == drawToken else { return }
            drawn = 1
        }
    }
}

/// One or more lines. Reading speed scales to the values, with headroom.
private struct SeriesPlot: View {
    var series: [[Double]]
    var fromZero: Bool
    var unit: String
    var xLabels: [String]
    var dots: Bool
    var active: Bool
    var empty: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var drawToken = 0

    private var values: [Double] { series.flatMap { $0 } }

    var body: some View {
        Group {
            if values.isEmpty {
                emptyPlot(empty)
            } else {
                plot
            }
        }
        .onChange(of: active, initial: true) { _, on in
            syncDraw(on)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(values.isEmpty ? empty : summary)
    }

    private var summary: String {
        let numbers = values.map { axisLabel($0) }.joined(separator: ", ")
        return "\(unit): \(numbers)"
    }

    private var plot: some View {
        let range = paddedRange(values, fromZero: fromZero)
        return VStack(alignment: .leading, spacing: 4) {
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let plot = CGRect(x: 36, y: 4, width: max(1, geo.size.width - 44), height: max(1, geo.size.height - 24))
                tickLayer(in: plot, range: range)
                lines(in: plot, range: range)
                if !xLabels.isEmpty {
                    xAxis(in: plot)
                }
            }
        }
    }

    private func tickLayer(in plot: CGRect, range: ClosedRange<Double>) -> some View {
        let ticks = tickValues(range)
        return ZStack {
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                let y = yPosition(tick, in: plot, range: range)
                Path { path in
                    path.move(to: CGPoint(x: plot.minX, y: y))
                    path.addLine(to: CGPoint(x: plot.maxX, y: y))
                }
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                Text(axisLabel(tick))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .position(x: 16, y: y)
            }
        }
    }

    private func lines(in plot: CGRect, range: ClosedRange<Double>) -> some View {
        let slots = max(series.map(\.count).max() ?? 1, 1)
        return ZStack {
            ForEach(Array(series.enumerated()), id: \.offset) { index, values in
                let points = points(for: values, slots: slots, range: range)
                if points.count > 1 {
                    UnitLine(points: points)
                        .trim(from: 0, to: drawn)
                        .stroke(
                            Color.white.opacity(lineOpacity(index)),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: plot.width, height: plot.height)
                        .position(x: plot.midX, y: plot.midY)
                }
                if dots || points.count == 1 {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(Color.white.opacity(lineOpacity(index)))
                            .frame(width: 7, height: 7)
                            .position(
                                x: plot.minX + point.x * plot.width,
                                y: plot.minY + (1 - point.y) * plot.height
                            )
                            .opacity(drawn)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.76), value: drawn)
    }

    private func xAxis(in plot: CGRect) -> some View {
        let count = xLabels.count
        return ZStack {
            ForEach(Array(xLabels.enumerated()), id: \.offset) { index, label in
                let x = count == 1 ? plot.midX : plot.minX + CGFloat(index) / CGFloat(count - 1) * plot.width
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: x, y: plot.maxY + 12)
            }
        }
    }

    private func points(for values: [Double], slots: Int, range: ClosedRange<Double>) -> [CGPoint] {
        let span = range.upperBound - range.lowerBound
        return values.enumerated().map { index, value in
            let x: CGFloat = slots <= 1 ? 0.5 : CGFloat(index) / CGFloat(slots - 1)
            let y: CGFloat = span > 0 ? CGFloat((value - range.lowerBound) / span) : 0.5
            return CGPoint(x: x, y: min(1, max(0, y)))
        }
    }

    private func lineOpacity(_ index: Int) -> Double {
        let last = series.count - 1
        guard last > 0 else { return 1 }
        return 0.28 + 0.72 * (Double(index) / Double(last))
    }

    private func syncDraw(_ on: Bool) {
        drawToken += 1
        let token = drawToken
        guard on else {
            drawn = 0
            return
        }
        if reduceMotion {
            drawn = 1
            return
        }
        drawn = 0
        Task { @MainActor in
            guard token == drawToken else { return }
            drawn = 1
        }
    }
}

private struct UnitLine: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: place(first, in: rect))
        for point in points.dropFirst() {
            path.addLine(to: place(point, in: rect))
        }
        return path
    }

    private func place(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + (1 - point.y) * rect.height
        )
    }
}

private func emptyPlot(_ message: String) -> some View {
    Text(message)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

private func paddedRange(_ values: [Double], fromZero: Bool) -> ClosedRange<Double> {
    guard let low = values.min(), let high = values.max() else { return 0...1 }
    if fromZero {
        let top = high == 0 ? 1 : high * 1.15
        return 0...top
    }
    let pad = max((high - low) * 0.15, 8)
    let floor = low - pad
    let ceil = max(high + pad, floor + 1)
    return floor...ceil
}

private func tickValues(_ range: ClosedRange<Double>) -> [Double] {
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return [range.lowerBound] }
    return [range.lowerBound, range.lowerBound + span / 2, range.upperBound]
}

private func yPosition(_ value: Double, in plot: CGRect, range: ClosedRange<Double>) -> CGFloat {
    let span = range.upperBound - range.lowerBound
    let t = span > 0 ? (value - range.lowerBound) / span : 0.5
    return plot.maxY - CGFloat(t) * plot.height
}

private func axisLabel(_ value: Double) -> String {
    String(Int(value.rounded()))
}

private enum ProgressCalendar {
    static func index(of date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Double((parts.year ?? 0) * 372 + (parts.month ?? 0) * 31 + (parts.day ?? 0))
    }
}

private struct DaySelection: Equatable {
    var start: Date
    var end: Date
    var pending: Bool
}

private struct DaySpan: Equatable {
    var start: Date
    var end: Date
}

private struct DayDrag {
    var origin: Date
    var anchor: Date
    var start: Date
    var end: Date
    var moved: Bool
}

private struct ChartFilter: Equatable {
    var start: Date? = nil
    var end: Date? = nil

    var isOn: Bool { start != nil && end != nil }

    var isSingleDay: Bool {
        guard let start, let end else { return false }
        return Calendar.current.isDate(start, inSameDayAs: end)
    }
}

private struct BandEnds: Equatable {
    var lower: Double
    var upper: Double
}

private struct DayAnchor {
    var day: Date
    var week: Int
    var index: Double
    var anchor: Anchor<CGRect>
}

private struct DayAnchorKey: PreferenceKey {
    static var defaultValue: [DayAnchor] { [] }

    static func reduce(value: inout [DayAnchor], nextValue: () -> [DayAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

private struct DayHit: Equatable {
    var day: Date
    var week: Int
    var index: Double
    var rect: CGRect
}

private struct DayFrameKey: PreferenceKey {
    static var defaultValue: [DayHit] { [] }

    static func reduce(value: inout [DayHit], nextValue: () -> [DayHit]) {
        value.append(contentsOf: nextValue())
    }
}

/// One rounded bar per week row. The ends spring toward the stretch.
/// Response 0.2 and damping 1 settle without bouncing past the last day.
private struct DayHighlight: View {
    var hits: [DayHit]
    var band: BandEnds?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let band {
                SelectionBand(
                    lower: band.lower,
                    upper: band.upper,
                    trueLower: band.lower,
                    trueUpper: band.upper,
                    hits: hits,
                    canvas: proxy.size
                )
            }
        }
        .animation(motion, value: band)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 1)
    }
}

private struct WeekBar: Identifiable {
    var week: Int
    var rect: CGRect
    var cells: [DayHit]
    var id: Int { week }
}

private struct SelectionBand: View, Animatable {
    var lower: Double
    var upper: Double
    var trueLower: Double
    var trueUpper: Double
    var hits: [DayHit]
    var canvas: CGSize

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(lower, upper) }
        set {
            lower = newValue.first
            upper = newValue.second
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(weekBars) { bar in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(barFill(bar))
                    .frame(width: bar.rect.width, height: bar.rect.height, alignment: .topLeading)
                    .offset(x: bar.rect.minX, y: bar.rect.minY)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    private var weekBars: [WeekBar] {
        let grouped = Dictionary(grouping: hits, by: \.week)
        return grouped.keys.sorted().compactMap { week -> WeekBar? in
            guard let cells = grouped[week], let rect = barRect(cells) else { return nil }
            return WeekBar(week: week, rect: rect, cells: cells)
        }
    }

    /// Covers only the days inside the stretch. The gap between week rows stays empty.
    private func barRect(_ cells: [DayHit]) -> CGRect? {
        var minX: CGFloat?
        var maxX: CGFloat?
        var minY: CGFloat = 0
        var height: CGFloat = 0
        for cell in cells.sorted(by: { $0.index < $1.index }) {
            let start = max(lower, cell.index)
            let end = min(upper, cell.index + 1)
            guard end - start > 0.02 else { continue }
            let x0 = cell.rect.minX + cell.rect.width * CGFloat(start - cell.index)
            let x1 = cell.rect.minX + cell.rect.width * CGFloat(end - cell.index)
            minX = min(minX ?? x0, x0)
            maxX = max(maxX ?? x1, x1)
            minY = cell.rect.minY
            height = cell.rect.height
        }
        guard let minX, let maxX, maxX > minX + 0.5 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: height)
    }

    private func barFill(_ bar: WeekBar) -> AnyShapeStyle {
        let endColor = Color.white.opacity(0.24)
        let midColor = Color.white.opacity(0.14)
        let first = min(trueLower, trueUpper - 1)
        let last = max(trueLower, trueUpper - 1)
        if last - first < 1.5 || bar.rect.width <= 1 {
            return AnyShapeStyle(endColor)
        }
        let left = daySpan(first, in: bar)
        let right = daySpan(last, in: bar)
        if let left, left.0 <= bar.rect.minX + 0.5, left.1 >= bar.rect.maxX - 0.5 {
            return AnyShapeStyle(endColor)
        }
        if let right, right.0 <= bar.rect.minX + 0.5, right.1 >= bar.rect.maxX - 0.5 {
            return AnyShapeStyle(endColor)
        }
        let leftEnd = left.map { unit($0.1, in: bar.rect) } ?? 0
        let rightStart = right.map { unit($0.0, in: bar.rect) } ?? 1
        var stops: [Gradient.Stop] = []
        if leftEnd > 0.001 {
            stops.append(.init(color: endColor, location: 0))
            stops.append(.init(color: endColor, location: leftEnd))
        }
        if rightStart < 0.999, rightStart > leftEnd {
            stops.append(.init(color: midColor, location: leftEnd))
            stops.append(.init(color: midColor, location: rightStart))
            stops.append(.init(color: endColor, location: rightStart))
            stops.append(.init(color: endColor, location: 1))
        } else if leftEnd < 0.999 {
            stops.append(.init(color: midColor, location: leftEnd))
            stops.append(.init(color: midColor, location: 1))
        } else {
            return AnyShapeStyle(endColor)
        }
        return AnyShapeStyle(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
    }

    private func daySpan(_ index: Double, in bar: WeekBar) -> (CGFloat, CGFloat)? {
        guard let cell = bar.cells.first(where: { abs($0.index - index) < 0.01 }) else { return nil }
        let x0 = max(bar.rect.minX, cell.rect.minX)
        let x1 = min(bar.rect.maxX, cell.rect.maxX)
        guard x1 > x0 else { return nil }
        return (x0, x1)
    }

    private func unit(_ x: CGFloat, in rect: CGRect) -> CGFloat {
        guard rect.width > 0 else { return 0 }
        return min(1, max(0, (x - rect.minX) / rect.width))
    }
}

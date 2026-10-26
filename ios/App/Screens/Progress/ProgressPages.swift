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

    private let calendarGap: CGFloat = 72
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

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
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            HStack(spacing: 8) {
                monthButton("chevron.left", label: "Previous month", enabled: canGoBack) {
                    changeMonth(by: -1)
                }
                Spacer(minLength: 0)
                Text(shownMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                monthButton("chevron.right", label: "Next month", enabled: canGoForward) {
                    changeMonth(by: 1)
                }
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }
                ForEach(1...daysInMonth, id: \.self) { day in
                    dayCell(day)
                }
            }
            .gesture(monthDrag)
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

    private func dayCell(_ day: Int) -> some View {
        let date = Calendar.current.date(byAdding: .day, value: day - 1, to: shownMonth) ?? shownMonth
        let mark = mark(for: date)
        let today = Calendar.current.isDate(date, inSameDayAs: snapshot.today)
        return VStack(spacing: 4) {
            Text(day, format: .number)
                .font(.caption2)
                .foregroundStyle(mark == .future ? Color.white.opacity(0.35) : Color.white.opacity(0.72))
            dayMark(mark, today: today)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
        .accessibilityValue(mark == .done ? "Practiced" : "")
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
        }
        .frame(width: 20, height: 16)
        .overlay {
            if today {
                Circle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: 20, height: 20)
            }
        }
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
                    insight(page)
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

    private func insight(_ page: InsightPage) -> some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            Text(page.title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            chart(page)
                .frame(height: 220)
            Text(page.caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SpeechSpacing.page)
    }

    @ViewBuilder
    private func chart(_ page: InsightPage) -> some View {
        switch page {
        case .turns:
            SeriesPlot(
                series: [snapshot.turns.map(\.secondsPerTurn)],
                fromZero: true,
                unit: "seconds",
                xLabels: [],
                dots: true,
                active: currentPage == page.rawValue
            )
        case .silences:
            SeriesPlot(
                series: snapshot.talks.map { $0.longSilences.map(Double.init) },
                fromZero: true,
                unit: "gaps",
                xLabels: silenceLabels,
                dots: false,
                active: currentPage == page.rawValue
            )
        case .sounds:
            BarPlot(
                bars: snapshot.sounds.map {
                    BarItem(label: $0.symbol, value: Double($0.misses), prominent: $0.highLoad)
                },
                unit: "misses",
                active: currentPage == page.rawValue
            )
        case .skips:
            BarPlot(
                bars: snapshot.skips.map {
                    BarItem(label: $0.word, value: Double($0.count), prominent: true)
                },
                unit: "skips",
                active: currentPage == page.rawValue
            )
        case .reading:
            SeriesPlot(
                series: [snapshot.readingRates],
                fromZero: false,
                unit: "syl/min",
                xLabels: [],
                dots: true,
                active: currentPage == page.rawValue
            )
        }
    }

    private var silenceLabels: [String] {
        let count = snapshot.talks.map(\.longSilences.count).max() ?? 0
        guard count > 0 else { return [] }
        return (1...count).map(String.init)
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
                .accessibilityLabel(page.title)
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
        case .silences: "Fewer long silences"
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
            "Long silences in each saved talk, from the first take to the last."
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var drawToken = 0

    var body: some View {
        Group {
            if bars.isEmpty {
                emptyPlot
            } else {
                plot
            }
        }
        .onChange(of: active, initial: true) { _, on in
            syncDraw(on)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bars.isEmpty ? "Not enough data." : summary)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var drawToken = 0

    private var values: [Double] { series.flatMap { $0 } }

    var body: some View {
        Group {
            if values.isEmpty {
                emptyPlot
            } else {
                plot
            }
        }
        .onChange(of: active, initial: true) { _, on in
            syncDraw(on)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(values.isEmpty ? "Not enough data." : summary)
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

private var emptyPlot: some View {
    Text("Not enough data.")
        .font(.body)
        .foregroundStyle(.secondary)
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

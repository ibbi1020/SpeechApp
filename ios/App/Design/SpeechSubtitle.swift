import SwiftUI
import UIKit

/// Live caption above the speech orb. One line at a time.
/// A full line fades while the next line is already up, so speech is not held
/// for the fade. The row slides as one piece.
struct SpeechSubtitle: View {
    /// Quiet type on a flat screen. Full white type when a picture is behind the line.
    enum Legibility: Equatable {
        case quiet
        case caption
    }

    let text: String
    var legibility: Legibility = .quiet

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: SpeechReading.textStyle) private var fontSize: CGFloat = SpeechReading.size

    @State private var tokens: [Token] = []
    @State private var availableWidth: CGFloat = 0
    @State private var generation = 0
    @State private var sourceWords: [String] = []
    @State private var pageStart = 0
    @State private var isPaging = false
    /// Horizontal slide for the whole row. One value, so the words stay locked together.
    @State private var lineShift: CGFloat = 0
    @State private var outgoing: [Token] = []
    @State private var outgoingOpacity: Double = 0
    @State private var outgoingBlur: CGFloat = 0
    @State private var turnID = 0

    private var wordGap: CGFloat {
        SpeechReading.scaledGap(SpeechReading.wordGap, size: fontSize)
    }
    /// The line uses this share of the width the section offers. 0.85 is 15% narrower.
    private static let widthFraction: CGFloat = 0.85

    /// Quiet type stays faint. A caption on a picture is full white.
    private var inkOpacity: Double {
        legibility == .caption ? 1 : 0.62
    }

    private var inkColor: Color {
        switch legibility {
        case .quiet:
            Color.primary.opacity(0.62)
        case .caption:
            Color.white
        }
    }

    private static let enterBlur: CGFloat = 14
    private static let enterDuration = 0.45
    private static let fadeDuration = 0.2
    /// Crossfade when a line fills. Short enough that the next line is not already full.
    private static let pageTurnDuration = 0.12

    private var subtitleFont: Font {
        SpeechReading.font(
            size: fontSize,
            weight: legibility == .caption ? .semibold : .regular
        )
    }

    private var lineHeight: CGFloat {
        let weight: UIFont.Weight = legibility == .caption ? .semibold : .regular
        return SpeechReading.uiFont(size: fontSize, weight: weight).lineHeight
    }

    private var spokenLine: String {
        tokens.map(\.surface).joined(separator: " ")
    }

    var body: some View {
        SubtitleColumn(fraction: Self.widthFraction) {
            line
        }
    }

    private var line: some View {
        ZStack {
            wordRow(outgoing)
                .blur(radius: outgoingBlur)
                .opacity(outgoingOpacity)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)
            wordRow(tokens)
                .geometryGroup()
                .offset(x: lineShift)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: lineHeight)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        availableWidth = width
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLine)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            apply(text: text, animated: false)
        }
        .onChange(of: text) { _, newText in
            apply(text: newText, animated: true)
        }
        .onChange(of: availableWidth) { _, _ in
            apply(text: text, animated: false)
        }
        .onChange(of: legibility) { _, _ in
            apply(text: text, animated: false)
        }
    }

    // MARK: - Diff

    private func apply(text: String, animated: Bool) {
        if !animated {
            dropOutgoing()
        }

        let next = Self.splitWords(text)

        if next.isEmpty {
            sourceWords = []
            pageStart = 0
            dropOutgoing()
            clear(animated: animated)
            return
        }

        let extends = sourceWords.isEmpty
            || (next.count >= sourceWords.count && Array(next.prefix(sourceWords.count)) == sourceWords)
        if !extends {
            sourceWords = next
            pageStart = 0
            dropOutgoing()
            reveal(animated: animated && !tokens.isEmpty, replace: !tokens.isEmpty)
            return
        }

        sourceWords = next
        if isPaging {
            // The old line is fading. Keep painting words onto the line already on screen.
            syncVisiblePage(animated: animated)
            return
        }

        let page = fittedPage()
        let showing = tokens.map(\.surface)
        let overflow = pageStart + page.count < sourceWords.count

        if page == showing {
            if overflow { beginPageTurn(animated: animated) }
            return
        }

        if showing.isEmpty || page.starts(with: showing) {
            let additions = Array(page.dropFirst(showing.count))
            if !additions.isEmpty {
                appendWords(additions, onto: tokens, animated: animated && !showing.isEmpty)
            }
            if overflow {
                beginPageTurn(animated: animated)
            }
            return
        }

        reveal(animated: animated, replace: true)
    }

    private func appendWords(_ additions: [String], onto existing: [Token], animated: Bool) {
        guard !additions.isEmpty else { return }
        _ = bumpGeneration()

        var working = existing
        let growth = width(of: additions, leadingGap: !working.isEmpty)
        let entering = animated && !reduceMotion
        for surface in additions {
            working.append(
                Token(
                    surface: surface,
                    blur: entering ? Self.enterBlur : 0,
                    opacity: entering ? 0 : inkOpacity
                )
            )
        }

        let additionStart = working.count - additions.count
        commit(working, animated: false)
        if entering, !existing.isEmpty, growth > 0 {
            slideLine(by: growth)
        }

        if animated {
            settleEntrance(from: additionStart)
        }
    }

    /// The centered row jumps when a word lands. Shift the whole row by half that
    /// growth, then ease it back, so every word glides together.
    private func slideLine(by growth: CGFloat) {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            lineShift += growth / 2
        }
        withAnimation(SpeechMotion.settle) {
            lineShift = 0
        }
    }

    private func cancelSlide() {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            lineShift = 0
        }
    }

    /// Words from `pageStart` that fit on one line. A single oversized word still shows.
    private func fittedPage() -> [String] {
        guard pageStart < sourceWords.count else { return [] }
        if availableWidth <= 0 {
            return Array(sourceWords.dropFirst(pageStart))
        }

        var page: [String] = []
        var used: CGFloat = 0
        for word in sourceWords.dropFirst(pageStart) {
            let extra = page.isEmpty ? measure(word) : measure(word) + wordGap
            if !page.isEmpty, used + extra > availableWidth {
                break
            }
            page.append(word)
            used += extra
        }
        return page
    }

    private func presentPage(animated: Bool, replace: Bool) {
        let page = fittedPage()
        if page.isEmpty {
            commit([], animated: false)
            return
        }
        if replace, animated, !reduceMotion, !tokens.isEmpty {
            replaceAll(with: page, animated: true)
            return
        }
        cancelSlide()
        let entering = animated && !reduceMotion
        commit(
            makeTokens(
                from: page,
                blur: entering ? Self.enterBlur : 0,
                opacity: entering ? 0 : inkOpacity
            ),
            animated: false
        )
        if entering {
            settleEntrance(from: 0)
        }
    }

    /// Words that arrive while the previous line is fading, painted onto the line already up.
    private func syncVisiblePage(animated: Bool) {
        let page = fittedPage()
        let showing = tokens.map(\.surface)
        if page == showing { return }
        if showing.isEmpty || page.starts(with: showing) {
            appendWords(
                Array(page.dropFirst(showing.count)),
                onto: tokens,
                animated: animated && !showing.isEmpty
            )
            return
        }
        presentPage(animated: false, replace: false)
    }

    private func beginPageTurn(animated: Bool) {
        guard !isPaging else { return }
        let leaving = fittedPage()
        guard !leaving.isEmpty, pageStart + leaving.count < sourceWords.count else { return }

        if !animated || reduceMotion {
            cancelSlide()
            while true {
                let page = fittedPage()
                if page.isEmpty || pageStart + page.count >= sourceWords.count { break }
                pageStart += page.count
            }
            commit(makeTokens(from: fittedPage(), blur: 0, opacity: inkOpacity), animated: false)
            return
        }

        let snapshot = resting(tokens)
        pageStart += leaving.count
        let incoming = fittedPage()
        isPaging = true
        let gate = bumpTurn()
        _ = bumpGeneration()
        cancelSlide()

        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            outgoing = snapshot
            outgoingOpacity = 1
            outgoingBlur = 0
            tokens = makeTokens(from: incoming, blur: Self.enterBlur, opacity: 0)
        }
        withAnimation(.easeOut(duration: Self.pageTurnDuration)) {
            setAllTokens(blur: 0, opacity: inkOpacity)
            outgoingOpacity = 0
            outgoingBlur = Self.enterBlur
        }
        scheduleTurn(gate: gate, after: Self.pageTurnDuration) {
            outgoing = []
            outgoingOpacity = 0
            outgoingBlur = 0
            isPaging = false
            let page = fittedPage()
            if !page.isEmpty, pageStart + page.count < sourceWords.count {
                beginPageTurn(animated: true)
            }
        }
    }

    /// Show the current page. A page that is already full turns once it has been drawn.
    /// The turn itself does not wait out the word entrance.
    private func reveal(animated: Bool, replace: Bool) {
        let page = fittedPage()
        guard !page.isEmpty else {
            commit([], animated: false)
            return
        }

        let overflow = pageStart + page.count < sourceWords.count
        if !overflow {
            presentPage(animated: animated, replace: replace)
            return
        }

        presentPage(animated: false, replace: false)
        let delay: TimeInterval = animated && !reduceMotion ? Self.pageTurnDuration : 0
        let gate = generation
        scheduleIfCurrent(gate: gate, after: delay) {
            beginPageTurn(animated: animated)
        }
    }

    private func replaceAll(with next: [String], animated: Bool) {
        _ = bumpGeneration()
        let gate = bumpTurn()
        isPaging = false

        if !animated || reduceMotion {
            cancelSlide()
            outgoing = []
            outgoingOpacity = 0
            outgoingBlur = 0
            commit(makeTokens(from: next, blur: 0, opacity: inkOpacity), animated: false)
            if animated, reduceMotion {
                setAllTokens(opacity: 0)
                withAnimation(.easeOut(duration: Self.fadeDuration)) {
                    setAllTokens(opacity: inkOpacity)
                }
            }
            return
        }

        let snapshot = resting(tokens)
        cancelSlide()
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            outgoing = snapshot
            outgoingOpacity = 1
            outgoingBlur = 0
            tokens = makeTokens(from: next, blur: Self.enterBlur, opacity: 0)
        }
        withAnimation(.easeOut(duration: Self.pageTurnDuration)) {
            setAllTokens(blur: 0, opacity: inkOpacity)
            outgoingOpacity = 0
            outgoingBlur = Self.enterBlur
        }
        scheduleTurn(gate: gate, after: Self.pageTurnDuration) {
            outgoing = []
            outgoingOpacity = 0
            outgoingBlur = 0
        }
    }

    private func clear(animated: Bool) {
        guard !tokens.isEmpty else { return }
        let gate = bumpGeneration()

        switch (animated, reduceMotion) {
        case (true, false):
            fadeOutAll(blur: Self.enterBlur, duration: Self.enterDuration)
            scheduleIfCurrent(gate: gate, after: Self.enterDuration) {
                commit([], animated: false)
            }
        case (true, true):
            withAnimation(.easeOut(duration: Self.fadeDuration)) {
                setAllTokens(opacity: 0)
            }
            scheduleIfCurrent(gate: gate, after: Self.fadeDuration) {
                commit([], animated: false)
            }
        default:
            commit([], animated: false)
        }
    }

    private func settleEntrance(from startIndex: Int) {
        let duration = reduceMotion ? Self.fadeDuration : Self.enterDuration
        withAnimation(.easeOut(duration: duration)) {
            for index in tokens.indices where index >= startIndex {
                tokens[index].blur = 0
                tokens[index].opacity = inkOpacity
            }
        }
    }

    // MARK: - State helpers

    @discardableResult
    private func bumpGeneration() -> Int {
        generation += 1
        return generation
    }

    private func scheduleIfCurrent(gate: Int, after delay: TimeInterval, _ work: @MainActor @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard gate == generation else { return }
            work()
        }
    }

    @discardableResult
    private func bumpTurn() -> Int {
        turnID += 1
        return turnID
    }

    private func scheduleTurn(gate: Int, after delay: TimeInterval, _ work: @MainActor @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard gate == turnID else { return }
            work()
        }
    }

    /// Drop a line that is fading out. Cancels the turn so it cannot fire later.
    private func dropOutgoing() {
        _ = bumpTurn()
        isPaging = false
        outgoing = []
        outgoingOpacity = 0
        outgoingBlur = 0
        cancelSlide()
    }

    private func resting(_ source: [Token]) -> [Token] {
        source.map { token in
            Token(id: token.id, surface: token.surface, blur: 0, opacity: inkOpacity)
        }
    }

    private func wordRow(_ lineTokens: [Token]) -> some View {
        HStack(spacing: wordGap) {
            ForEach(lineTokens) { token in
                Text(token.surface)
                    .font(subtitleFont)
                    .foregroundStyle(inkColor)
                    .opacity(token.opacity)
                    .blur(radius: token.blur)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func makeTokens(from surfaces: [String], blur: CGFloat, opacity: Double) -> [Token] {
        surfaces.map { Token(surface: $0, blur: blur, opacity: opacity) }
    }

    private func commit(_ next: [Token], animated: Bool) {
        var transaction = Transaction()
        if !animated {
            transaction.disablesAnimations = true
        }
        withTransaction(transaction) {
            tokens = next
        }
    }

    private func fadeOutAll(blur: CGFloat, duration: TimeInterval) {
        withAnimation(.easeOut(duration: duration)) {
            setAllTokens(blur: blur, opacity: 0)
        }
    }

    private func setAllTokens(
        blur: CGFloat? = nil,
        opacity: Double? = nil
    ) {
        for index in tokens.indices {
            if let blur { tokens[index].blur = blur }
            if let opacity { tokens[index].opacity = opacity }
        }
    }

    // MARK: - Measure

    private func width(of surfaces: [String], leadingGap: Bool) -> CGFloat {
        guard !surfaces.isEmpty else { return 0 }
        let words = surfaces.reduce(CGFloat.zero) { $0 + measure($1) }
        let gaps = wordGap * CGFloat(surfaces.count - (leadingGap ? 0 : 1))
        return words + max(0, gaps)
    }

    private func measure(_ string: String) -> CGFloat {
        let weight: UIFont.Weight = legibility == .caption ? .semibold : .regular
        let font = SpeechReading.uiFont(size: fontSize, weight: weight)
        return (string as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: - Parse

    private static func splitWords(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

}

/// Centers the subtitle in the width it is offered, and gives the line a fraction of that width.
private struct SubtitleColumn: Layout {
    var fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = columnWidth(proposal.width)
        let child = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: width ?? child.width, height: child.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }

    private func columnWidth(_ offered: CGFloat?) -> CGFloat? {
        guard let offered else { return nil }
        return offered * fraction
    }
}

private struct Token: Identifiable, Equatable {
    let id: UUID
    var surface: String
    var blur: CGFloat
    var opacity: Double

    init(
        id: UUID = UUID(),
        surface: String,
        blur: CGFloat,
        opacity: Double
    ) {
        self.id = id
        self.surface = surface
        self.blur = blur
        self.opacity = opacity
    }
}

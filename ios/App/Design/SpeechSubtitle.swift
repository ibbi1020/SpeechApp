import SwiftUI
import UIKit

/// Live caption above the speech orb. One line at a time: when the line is full,
/// it fades out and the next words start on a fresh line.
struct SpeechSubtitle: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .callout) private var fontSize: CGFloat = 16

    @State private var tokens: [Token] = []
    @State private var availableWidth: CGFloat = 0
    @State private var generation = 0
    @State private var sourceWords: [String] = []
    @State private var pageStart = 0
    @State private var isPaging = false

    private static let wordGap: CGFloat = 5
    private static let inkOpacity = 0.62
    private static let enterBlur: CGFloat = 14
    private static let enterDuration = 0.45
    private static let fadeDuration = 0.2

    private var subtitleFont: Font {
        .system(size: fontSize, weight: .regular, design: .serif)
    }

    private var lineHeight: CGFloat {
        fontSize * 1.25
    }

    private var spokenLine: String {
        tokens.map(\.surface).joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: Self.wordGap) {
            ForEach(tokens) { token in
                Text(token.surface)
                    .font(subtitleFont)
                    .foregroundStyle(.primary.opacity(Self.inkOpacity))
                    .opacity(token.opacity)
                    .blur(radius: token.blur)
                    .offset(x: token.shiftX)
            }
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
    }

    // MARK: - Diff

    private func apply(text: String, animated: Bool) {
        let next = Self.splitWords(text)

        if next.isEmpty {
            sourceWords = []
            pageStart = 0
            isPaging = false
            clear(animated: animated)
            return
        }

        let extends = sourceWords.isEmpty
            || (next.count >= sourceWords.count && Array(next.prefix(sourceWords.count)) == sourceWords)
        if !extends {
            sourceWords = next
            pageStart = 0
            isPaging = false
            presentPage(animated: animated && !tokens.isEmpty, replace: !tokens.isEmpty)
            scheduleFollowUpPageIfNeeded()
            return
        }

        sourceWords = next
        if isPaging { return }

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
                holdThenTurnPage()
            }
            return
        }

        presentPage(animated: animated, replace: true)
        if overflow { holdThenTurnPage() }
    }

    private func appendWords(_ additions: [String], onto existing: [Token], animated: Bool) {
        guard !additions.isEmpty else { return }
        _ = bumpGeneration()

        var working = existing
        let growth = width(of: additions, leadingGap: !working.isEmpty)
        if animated, !reduceMotion, !working.isEmpty, growth > 0 {
            for index in working.indices {
                working[index].shiftX = growth / 2
            }
        }

        let entering = animated && !reduceMotion
        for surface in additions {
            working.append(
                Token(
                    surface: surface,
                    blur: entering ? Self.enterBlur : 0,
                    opacity: entering ? 0 : Self.inkOpacity,
                    shiftX: 0
                )
            )
        }

        let additionStart = working.count - additions.count
        commit(working, animated: false)

        if animated {
            settleEntrance(from: additionStart)
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
            let extra = page.isEmpty ? measure(word) : measure(word) + Self.wordGap
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
        let entering = animated && !reduceMotion
        commit(
            makeTokens(
                from: page,
                blur: entering ? Self.enterBlur : 0,
                opacity: entering ? 0 : Self.inkOpacity
            ),
            animated: false
        )
        if entering {
            settleEntrance(from: 0)
        }
    }

    private func beginPageTurn(animated: Bool) {
        guard !isPaging else { return }
        let leaving = fittedPage()
        guard !leaving.isEmpty, pageStart + leaving.count < sourceWords.count else { return }
        isPaging = true
        let gate = bumpGeneration()

        let finish: @MainActor @Sendable () -> Void = {
            pageStart += leaving.count
            commit([], animated: false)
            scheduleIfCurrent(gate: gate, after: 0.12) {
                isPaging = false
                presentPage(animated: animated, replace: false)
                scheduleFollowUpPageIfNeeded()
            }
        }

        if !animated || reduceMotion {
            finish()
            return
        }

        fadeOutAll(blur: Self.enterBlur, duration: Self.enterDuration)
        scheduleIfCurrent(gate: gate, after: Self.enterDuration, finish)
    }

    /// Let the finished line be readable, then fade it for the next line.
    private func holdThenTurnPage() {
        let gate = generation
        scheduleIfCurrent(gate: gate, after: 0.35) {
            beginPageTurn(animated: true)
        }
    }

    private func scheduleFollowUpPageIfNeeded() {
        let page = fittedPage()
        guard pageStart + page.count < sourceWords.count, !page.isEmpty else { return }
        let gate = generation
        scheduleIfCurrent(gate: gate, after: 0.7) {
            beginPageTurn(animated: true)
        }
    }

    private func replaceAll(with next: [String], animated: Bool) {
        let gate = bumpGeneration()

        if !animated || reduceMotion {
            commit(makeTokens(from: next, blur: 0, opacity: Self.inkOpacity), animated: false)
            if animated, reduceMotion {
                setAllTokens(opacity: 0)
                withAnimation(.easeOut(duration: Self.fadeDuration)) {
                    setAllTokens(opacity: Self.inkOpacity)
                }
            }
            return
        }

        fadeOutAll(blur: Self.enterBlur, duration: Self.enterDuration)

        let incoming = next
        scheduleIfCurrent(gate: gate, after: Self.enterDuration) {
            commit(
                makeTokens(from: incoming, blur: Self.enterBlur, opacity: 0),
                animated: false
            )
            withAnimation(.easeOut(duration: Self.enterDuration)) {
                setAllTokens(blur: 0, opacity: Self.inkOpacity)
            }
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
        if reduceMotion {
            withAnimation(.easeOut(duration: Self.fadeDuration)) {
                setAllTokens(blur: 0, opacity: Self.inkOpacity, shiftX: 0)
            }
            return
        }

        withAnimation(SpeechMotion.settle) {
            for index in tokens.indices where index < startIndex {
                tokens[index].shiftX = 0
            }
        }
        withAnimation(.easeOut(duration: Self.enterDuration)) {
            for index in tokens.indices where index >= startIndex {
                tokens[index].blur = 0
                tokens[index].opacity = Self.inkOpacity
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

    private func makeTokens(from surfaces: [String], blur: CGFloat, opacity: Double) -> [Token] {
        surfaces.map { Token(surface: $0, blur: blur, opacity: opacity, shiftX: 0) }
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
        opacity: Double? = nil,
        shiftX: CGFloat? = nil
    ) {
        for index in tokens.indices {
            if let blur { tokens[index].blur = blur }
            if let opacity { tokens[index].opacity = opacity }
            if let shiftX { tokens[index].shiftX = shiftX }
        }
    }

    // MARK: - Measure

    private func width(of surfaces: [String], leadingGap: Bool) -> CGFloat {
        guard !surfaces.isEmpty else { return 0 }
        let words = surfaces.reduce(CGFloat.zero) { $0 + measure($1) }
        let gaps = Self.wordGap * CGFloat(surfaces.count - (leadingGap ? 0 : 1))
        return words + max(0, gaps)
    }

    private func measure(_ string: String) -> CGFloat {
        let base = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: fontSize)
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

private struct Token: Identifiable, Equatable {
    let id: UUID
    var surface: String
    var blur: CGFloat
    var opacity: Double
    var shiftX: CGFloat

    init(
        id: UUID = UUID(),
        surface: String,
        blur: CGFloat,
        opacity: Double,
        shiftX: CGFloat
    ) {
        self.id = id
        self.surface = surface
        self.blur = blur
        self.opacity = opacity
        self.shiftX = shiftX
    }
}

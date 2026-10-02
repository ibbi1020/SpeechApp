import XCTest

/// Button-level QA walk. Every tap goes through `qaTap`, which records response time,
/// hit-test state, element size, and before/after screenshots. Soft checks only:
/// a failed tap is recorded, not fatal, so one bad button never hides the rest.
final class ButtonQATests: XCTestCase {
    private var app: XCUIApplication!
    private let ready = "I\u{2019}m ready"

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch() {
        app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "permissions") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        _ = app.buttons["Read a passage"].waitForExistence(timeout: 15)
    }

    // MARK: - Helpers

    @MainActor
    private var navBack: XCUIElement { app.navigationBars.buttons.element(boundBy: 0) }
    @MainActor
    private var homeVisible: Bool { app.buttons["Read a passage"].isHittable }

    @MainActor
    private func goHomeIfNeeded() {
        for _ in 0..<4 where !app.buttons["Read a passage"].exists {
            if app.buttons["Back to home"].exists {
                app.buttons["Back to home"].tap()
            } else if app.buttons["Back"].exists {
                app.buttons["Back"].firstMatch.tap()
                if app.buttons["Leave"].waitForExistence(timeout: 1) { app.buttons["Leave"].tap() }
            } else if navBack.exists {
                navBack.tap()
            }
            _ = app.buttons["Read a passage"].waitForExistence(timeout: 3)
        }
    }

    /// SessionStopModal carries `.isModal`, so XCUITest exposes it as an Alert.
    @MainActor
    private func modalButton(_ title: String) -> XCUIElement {
        let inAlert = app.alerts.buttons[title]
        if inAlert.exists { return inAlert }
        let all = app.buttons.matching(identifier: title).allElementsBoundByIndex
        return all.max(by: { $0.frame.width < $1.frame.width }) ?? app.buttons[title].firstMatch
    }

    @MainActor
    private func label(containing text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func anyText(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func firstPassageRow() -> XCUIElement {
        // Library rows are plain buttons labelled "<title>, <duration>".
        app.collectionViews.buttons.firstMatch.exists
            ? app.collectionViews.buttons.firstMatch
            : app.cells.buttons.firstMatch
    }

    // MARK: - 1. Home

    @MainActor
    func test01_HomeAndNavigation() {
        launch()
        let screen = "Home"
        for name in ["Read a passage", "Start a conversation", "Talk about something"] {
            qaNote(screen, name, app.buttons[name], note: "row size")
        }

        qaTap(screen, "Read a passage", app.buttons["Read a passage"]) {
            app.navigationBars["Passages"].exists
        }
        qaTap("Passages", "nav Back", navBack) { homeVisible }

        // Edge of the row (contentShape check): far right inside the glass row.
        qaTap(screen, "Read a passage (right edge)", app.buttons["Read a passage"], at: CGVector(dx: 0.95, dy: 0.5)) {
            app.navigationBars["Passages"].exists
        }
        qaTap("Passages", "nav Back", navBack) { homeVisible }

        qaTap(screen, "Talk about something", app.buttons["Talk about something"]) {
            app.buttons["Change topic"].exists || app.buttons[ready].exists
        }
        qaTap("Monologue", "custom Back (12pt right of glyph)", app.buttons["Back"].firstMatch,
              pointOffset: CGVector(dx: 12, dy: 0), timeout: 3) { homeVisible }
        if !homeVisible {
            qaTap("Monologue", "custom Back (planning, no takes)", app.buttons["Back"].firstMatch) { homeVisible }
        }

        qaTap(screen, "Start a conversation", app.buttons["Start a conversation"]) {
            app.navigationBars["Conversation"].exists
        }
        // Leave during the 3-2-1 (no controls are shown during the countdown).
        qaTap("Conversation", "nav Back during countdown", navBack, note: "countdown") { homeVisible }

        // Start again right away: must not hang on a half-torn-down session.
        qaTap(screen, "Start a conversation (again)", app.buttons["Start a conversation"]) {
            app.navigationBars["Conversation"].exists
        }
        qaTap("Conversation", "Stop visible after countdown", app.navigationBars["Conversation"], timeout: 12, note: "observe: no tap target, waiting for controls") {
            app.buttons["Stop"].exists
        }
        goHomeIfNeeded()
    }

    // MARK: - 2. Reading

    @MainActor
    func test02_ReadingFlow() {
        launch()
        qaTap("Home", "Read a passage", app.buttons["Read a passage"]) { app.navigationBars["Passages"].exists }
        let row = firstPassageRow()
        qaNote("Passages", "passage row", row, note: "row size")
        qaTap("Passages", "passage row (chevron edge)", row, at: CGVector(dx: 0.97, dy: 0.5)) {
            app.buttons["Start"].exists
        }
        qaTap("Reading", "nav Back", navBack) { app.navigationBars["Passages"].exists }
        qaTap("Passages", "passage row", firstPassageRow()) { app.buttons["Start"].exists }

        let start = app.buttons["Start"]
        qaNote("Reading", "Start", start, note: "size (text only; glass is wider)")
        qaTap("Reading", "Start (left glass edge)", start, pointOffset: CGVector(dx: -150, dy: 12), timeout: 3,
              note: "inside the tinted glass, outside the text") {
            anyText(containing: "Take a deep breath").exists
                || anyText(containing: "isn\u{2019}t set up").exists
                || anyText(containing: "permission").exists
                || app.buttons["Pause"].exists
        }
        // Wait out the countdown, then time how long Pause is visible but not hittable (fog still up).
        let live = app.buttons["Pause"].waitForExistence(timeout: 10)
        if live {
            let shownAt = Date()
            var hittableAt: Date?
            while Date().timeIntervalSince(shownAt) < 30 {
                if app.buttons["Pause"].isHittable { hittableAt = Date(); break }
                usleep(200_000)
            }
            let ms = hittableAt.map { Int($0.timeIntervalSince(shownAt) * 1000) }
            qaNote("Reading live", "Pause dead window", app.buttons["Pause"],
                   note: "visible-but-not-hittable for \(ms.map(String.init) ?? ">30000") ms after appearing")
            qa.shot("reading-pause-hittable", in: self)
        }
        qa.shot("reading-after-countdown-live-\(live)", in: self)
        if live {
            readingLiveControls()
        } else {
            qaNote("Reading", "Start outcome", anyText(containing: "."), note: "did not go live (no mic/key in simulator?)")
            if start.exists {
                qaTap("Reading", "Start (retry after error)", start, timeout: 3) {
                    anyText(containing: "Take a deep breath").exists || anyText(containing: "isn\u{2019}t set up").exists
                }
                _ = app.buttons["Pause"].waitForExistence(timeout: 8)
                if app.buttons["Pause"].exists { readingLiveControls() }
            }
        }
        goHomeIfNeeded()
    }

    @MainActor
    private func readingLiveControls() {
        let screen = "Reading live"
        qaNote(screen, "Pause", app.buttons["Pause"], note: "size")
        qaTap(screen, "Pause", app.buttons["Pause"]) { app.buttons["Resume"].exists }
        qaTap(screen, "Resume", app.buttons["Resume"]) { app.buttons["Pause"].exists }
        qaTap(screen, "Stop", app.buttons["Stop"].firstMatch) { app.buttons["Keep reading"].exists }
        qaTap("Reading stop modal", "Keep reading (left glass edge)", modalButton("Keep reading"),
              pointOffset: CGVector(dx: -120, dy: 12), timeout: 3, note: "inside the glass, outside the text") {
            !app.buttons["Keep reading"].exists && app.buttons["Pause"].exists
        }
        if app.buttons["Keep reading"].exists {
            qaTap("Reading stop modal", "Keep reading", modalButton("Keep reading")) {
                !app.buttons["Keep reading"].exists && app.buttons["Pause"].exists
            }
        }
        qaTap(screen, "Stop", app.buttons["Stop"].firstMatch) { app.buttons["Keep reading"].exists }
        qaTap("Reading stop modal", "Keep reading", modalButton("Keep reading")) {
            !app.buttons["Keep reading"].exists && app.buttons["Pause"].exists
        }
        qaTap(screen, "Stop", app.buttons["Stop"].firstMatch) { app.buttons["Keep reading"].exists }
        qaTap("Reading stop modal", "Stop (confirm)", modalButton("Stop"), timeout: 10) {
            app.buttons["Read this again"].exists
        }
        if app.buttons["Read this again"].exists { readingReport() }
    }

    @MainActor
    private func readingReport() {
        let screen = "Reading report"
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show '")).firstMatch
        if more.exists {
            let before = more.label
            qaTap(screen, "Show more", more) { more.exists && more.label != before }
        }
        qaTap(screen, "Read this again", app.buttons["Read this again"]) { app.buttons["Start"].exists }
        qaTap("Reading", "nav Back", navBack) { app.navigationBars["Passages"].exists }
    }

    // MARK: - 3. Conversation

    @MainActor
    func test03_ConversationFlow() {
        launch()
        qaTap("Home", "Start a conversation", app.buttons["Start a conversation"]) {
            app.navigationBars["Conversation"].exists
        }
        let screen = "Conversation"
        let stop = app.buttons["Stop"].firstMatch
        let gotControls = stop.waitForExistence(timeout: 15)
        qa.shot("conversation-controls-\(gotControls)", in: self)
        if !gotControls {
            if app.buttons["Try again"].exists {
                qaTap(screen, "Try again", app.buttons["Try again"], timeout: 15) { app.buttons["Stop"].exists }
            }
            if app.buttons["Back to home"].exists {
                qaTap(screen, "Back to home (failure view)", app.buttons["Back to home"]) { homeVisible }
            }
            return
        }
        let pause = app.buttons["Pause"]
        if pause.waitForExistence(timeout: 10) {
            qaNote(screen, "Pause", pause, note: "size")
            qaTap(screen, "Pause", pause) { app.buttons["Resume"].exists }
            qaTap(screen, "Resume (near circle edge)", app.buttons["Resume"], pointOffset: CGVector(dx: -20, dy: 0)) {
                app.buttons["Pause"].exists
            }
        } else {
            qaNote(screen, "Pause", pause, note: "pause never became available (phase not talking)")
        }
        qaTap(screen, "Stop", stop) { app.buttons["Keep talking"].exists }
        qaTap("Conversation stop modal", "Keep talking", modalButton("Keep talking")) {
            !app.buttons["Keep talking"].exists && app.buttons["Stop"].exists
        }
        // Let the debug loop run one fake user turn so the report has content.
        sleep(9)
        qaTap(screen, "Stop", app.buttons["Stop"].firstMatch) { app.buttons["Keep talking"].exists }
        qaTap("Conversation stop modal", "Stop (confirm)", modalButton("Stop"), timeout: 10) {
            app.buttons["Back to home"].exists
        }
        qa.shot("conversation-end-screen", in: self)
        if app.buttons["Try again"].exists {
            qaTap("Conversation failure", "Try again", app.buttons["Try again"], timeout: 15) {
                app.buttons["Stop"].exists || anyText(containing: "Take a deep breath").exists
            }
            goHomeIfNeeded()
            return
        }
        qaTap("Conversation report", "Back to home", app.buttons["Back to home"]) { homeVisible }
    }

    // MARK: - 4. Monologue

    @MainActor
    func test04_MonologueFlow() {
        launch()
        qaTap("Home", "Talk about something", app.buttons["Talk about something"]) {
            app.buttons["Change topic"].exists
        }
        let screen = "Monologue planning"
        let change = app.buttons["Change topic"]
        qaNote(screen, "Change topic", change, note: "size")
        let promptBefore = currentPromptText()
        qaTap(screen, "Change topic", change) { currentPromptText() != promptBefore }
        let promptMid = currentPromptText()
        // Right-hand side of the 44pt row the code reserves (frame is outside the Button).
        qaTap(screen, "Change topic (12pt below text, inside 44pt row)", change, pointOffset: CGVector(dx: 0, dy: 13), timeout: 2,
              note: ".frame(minHeight: 44) is applied outside the Button") {
            currentPromptText() != promptMid
        }
        let promptMid2 = currentPromptText()
        qaTap(screen, "Change topic (30pt right of text)", change, pointOffset: CGVector(dx: 77, dy: 0), timeout: 2) {
            currentPromptText() != promptMid2
        }

        let addNote = app.buttons["Add note"]
        qaNote(screen, "Add note", addNote, note: "size")
        qaTap(screen, "Add note (row, 150pt right of label)", addNote, pointOffset: CGVector(dx: 150, dy: 0), timeout: 2,
              note: "label has maxWidth frame but no contentShape") {
            app.textFields["Short note"].exists
        }
        if !app.textFields["Short note"].exists {
            qaTap(screen, "Add note (on label)", addNote, at: CGVector(dx: 0.08, dy: 0.5)) {
                app.textFields["Short note"].exists
            }
        }
        let field = app.textFields["Short note"]
        if field.waitForExistence(timeout: 2) {
            field.typeText("first idea")
            qaTap(screen, "Add", app.buttons["Add"]) { anyText(containing: "first idea").exists }
        }
        qaTap(screen, "Add note", addNote, at: CGVector(dx: 0.08, dy: 0.5)) { app.textFields["Short note"].exists }
        if field.waitForExistence(timeout: 2) {
            field.typeText("second idea\n")
            _ = anyText(containing: "second idea").waitForExistence(timeout: 2)
        }
        let remove = app.buttons["Remove note"].firstMatch
        qaNote(screen, "Remove note", remove, note: "size")
        let count = app.buttons.matching(identifier: "Remove note").count
        qaTap(screen, "Remove note (14pt left of glyph, inside 44pt frame)", remove, pointOffset: CGVector(dx: -14, dy: 0), timeout: 2,
              note: "frame(44x44) inside label, no contentShape") {
            app.buttons.matching(identifier: "Remove note").count < count
        }
        let count2 = app.buttons.matching(identifier: "Remove note").count
        if count2 > 0 {
            qaTap(screen, "Remove note (center)", app.buttons["Remove note"].firstMatch) {
                app.buttons.matching(identifier: "Remove note").count < count2
            }
        }

        let readyButton = app.buttons[ready]
        qaNote(screen, ready, readyButton, note: "size (text only; glass is wider)")
        qaTap(screen, ready + " (left glass edge)", readyButton, pointOffset: CGVector(dx: -150, dy: 12), timeout: 4) {
            app.otherElements.matching(NSPredicate(format: "label == '3' OR label == '2'")).firstMatch.exists
                || anyText(containing: "isn\u{2019}t set up").exists
                || anyText(containing: "permission").exists
                || app.buttons["Done"].exists
        }
        let live = app.buttons["Done"].waitForExistence(timeout: 10)
        qa.shot("monologue-after-ready-live-\(live)", in: self)
        if live {
            let liveScreen = "Monologue live"
            qaTap(liveScreen, "Pause", app.buttons["Pause"]) { app.buttons["Resume"].exists }
            qaTap(liveScreen, "Resume", app.buttons["Resume"]) { app.buttons["Pause"].exists }
            sleep(2)
            qaTap(liveScreen, "Done", app.buttons["Done"], timeout: 8) {
                app.buttons[ready].exists || app.buttons["Back to home"].exists
            }
            if app.buttons["Back"].exists {
                qaTap("Monologue between", "custom Back (has takes)", app.buttons["Back"].firstMatch) {
                    app.buttons["Keep going"].exists
                }
                qaTap("Monologue leave modal", "Keep going", modalButton("Keep going")) { !app.buttons["Keep going"].exists }
                qaTap("Monologue between", "custom Back (has takes)", app.buttons["Back"].firstMatch) {
                    app.buttons["Leave"].exists
                }
                qaTap("Monologue leave modal", "Leave", modalButton("Leave"), timeout: 8) {
                    app.buttons["Back to home"].exists || homeVisible
                }
            }
            if app.buttons["Back to home"].exists {
                qaTap("Monologue report", "Back to home", app.buttons["Back to home"]) { homeVisible }
            }
        }
        goHomeIfNeeded()
    }

    @MainActor
    private func currentPromptText() -> String {
        // The prompt is the longest static text on the planning screen.
        let texts = app.scrollViews.staticTexts.allElementsBoundByIndex.map(\.label)
        return texts.max(by: { $0.count < $1.count }) ?? ""
    }

    // MARK: - 5. Double taps and rapid taps

    @MainActor
    func test05_DoubleTapGuards() {
        launch()
        qaTap("Home", "Read a passage", app.buttons["Read a passage"], action: "doubleTap") {
            app.navigationBars["Passages"].exists
        }
        sleep(1)
        qaTap("Passages", "nav Back (once after double tap)", navBack) { homeVisible }

        qaTap("Home", "Read a passage", app.buttons["Read a passage"]) { app.navigationBars["Passages"].exists }
        qaTap("Passages", "passage row", firstPassageRow(), action: "doubleTap") { app.buttons["Start"].exists }
        sleep(1)
        qaTap("Reading", "nav Back (once after double tap)", navBack) { app.navigationBars["Passages"].exists }

        qaTap("Passages", "passage row", firstPassageRow()) { app.buttons["Start"].exists }
        qaTap("Reading", "Start", app.buttons["Start"], action: "doubleTap", timeout: 3, note: "double tap Start") {
            anyText(containing: "Take a deep breath").exists || anyText(containing: "isn\u{2019}t set up").exists
        }
        // Sample the screen a few times to catch fog/countdown flicker from two start tasks.
        for i in 0..<6 {
            qa.shot(String(format: "reading-doubletap-start-%02d", i), in: self)
            usleep(250_000)
        }
        goHomeIfNeeded()

        qaTap("Home", "Talk about something", app.buttons["Talk about something"], action: "doubleTap") {
            app.buttons["Change topic"].exists
        }
        let promptBefore = currentPromptText()
        qaTap("Monologue planning", "Change topic", app.buttons["Change topic"], action: "doubleTap",
              note: "double tap skips two topics?") { currentPromptText() != promptBefore }
        goHomeIfNeeded()

        qaTap("Home", "Start a conversation", app.buttons["Start a conversation"]) { app.navigationBars["Conversation"].exists }
        if app.buttons["Stop"].firstMatch.waitForExistence(timeout: 15) {
            let pause = app.buttons["Pause"]
            if pause.waitForExistence(timeout: 8) {
                qaTap("Conversation", "Pause", pause, action: "doubleTap", note: "double tap pause = pause+resume") {
                    app.buttons["Pause"].exists || app.buttons["Resume"].exists
                }
                qa.shot("conversation-after-double-pause", in: self)
            }
            qaTap("Conversation", "Stop", app.buttons["Stop"].firstMatch, action: "doubleTap") {
                app.buttons["Keep talking"].exists
            }
            qaTap("Conversation stop modal", "Stop (confirm)", modalButton("Stop"), action: "doubleTap", timeout: 10) {
                app.buttons["Back to home"].exists
            }
            qa.shot("conversation-after-double-confirm", in: self)
        }
        goHomeIfNeeded()
    }
}

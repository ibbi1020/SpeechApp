import XCTest

/// One row per tap. Written as JSON lines to $QA_OUT/taps.jsonl and attached to the xcresult.
struct TapRecord: Codable {
    var seq: Int
    var screen: String
    var element: String
    var action: String
    var exists: Bool
    var hittable: Bool
    var frame: String
    var widthPt: Double
    var heightPt: Double
    var responded: Bool
    /// Wall time of the XCUITest tap call itself (includes XCUITest's wait-for-idle before and after).
    var tapCallMs: Double
    /// Time from just before the tap until the expected UI state was observed.
    var responseMs: Double?
    var note: String
    var before: String
    var after: String
}

@MainActor
final class QARecorder {
    static let shared = QARecorder()
    let outDir: URL?
    private var seq = 0
    private(set) var records: [TapRecord] = []

    init() {
        if let path = ProcessInfo.processInfo.environment["QA_OUT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(
                at: url.appendingPathComponent("screens"), withIntermediateDirectories: true
            )
            outDir = url
        } else {
            outDir = nil
        }
    }

    func nextSeq() -> Int {
        seq += 1
        return seq
    }

    /// Saves a screenshot to disk (if QA_OUT is set) and attaches it to the test. Returns the file name.
    @discardableResult
    func shot(_ name: String, in testCase: XCTestCase) -> String {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
        let file = "\(name).png"
        if let outDir {
            try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("screens").appendingPathComponent(file))
        }
        return file
    }

    func append(_ record: TapRecord, in testCase: XCTestCase) {
        records.append(record)
        guard let data = try? JSONEncoder().encode(record) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = String(format: "tap-%03d", record.seq)
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
        if let outDir {
            let url = outDir.appendingPathComponent("taps.jsonl")
            var line = data
            line.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line)
                try? handle.close()
            } else {
                try? line.write(to: url)
            }
        }
        let resp = record.responseMs.map { String(format: "%.0f ms", $0) } ?? "NO RESPONSE"
        print("QA_TAP #\(record.seq) [\(record.screen)] \(record.element) (\(record.action)) -> \(resp) | tapCall \(Int(record.tapCallMs)) ms | \(Int(record.widthPt))x\(Int(record.heightPt))pt hittable=\(record.hittable) \(record.note)")
    }
}

@MainActor
extension XCTestCase {
    var qa: QARecorder { QARecorder.shared }

    /// Taps `element` (or a normalized point inside it), then polls `expect` until it is true.
    @discardableResult
    func qaTap(
        _ screen: String,
        _ name: String,
        _ element: XCUIElement,
        action: String = "tap",
        at offset: CGVector? = nil,
        timeout: TimeInterval = 6,
        note: String = "",
        expect: () -> Bool
    ) -> Bool {
        let seq = qa.nextSeq()
        let slug = "\(String(format: "%03d", seq))-\(screen)-\(name)"
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let exists = element.waitForExistence(timeout: 3)
        var record = TapRecord(
            seq: seq, screen: screen, element: name, action: action, exists: exists,
            hittable: false, frame: "", widthPt: 0, heightPt: 0, responded: false,
            tapCallMs: 0, responseMs: nil, note: note, before: "", after: ""
        )
        guard exists else {
            record.note = (note.isEmpty ? "" : note + "; ") + "element not found"
            record.before = qa.shot("\(slug)-missing", in: self)
            qa.append(record, in: self)
            return false
        }
        record.hittable = element.isHittable
        let frame = element.frame
        record.frame = "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
        record.widthPt = Double(frame.width)
        record.heightPt = Double(frame.height)
        record.before = qa.shot("\(slug)-before", in: self)

        let start = CFAbsoluteTimeGetCurrent()
        switch action {
        case "doubleTap":
            if let offset {
                element.coordinate(withNormalizedOffset: offset).doubleTap()
            } else {
                element.doubleTap()
            }
        default:
            if let offset {
                element.coordinate(withNormalizedOffset: offset).tap()
            } else {
                element.tap()
            }
        }
        let afterTap = CFAbsoluteTimeGetCurrent()
        record.tapCallMs = (afterTap - start) * 1000

        let deadline = start + timeout
        var responded = expect()
        while !responded && CFAbsoluteTimeGetCurrent() < deadline {
            usleep(30_000)
            responded = expect()
        }
        if responded {
            record.responded = true
            record.responseMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        }
        record.after = qa.shot("\(slug)-after", in: self)
        qa.append(record, in: self)
        return responded
    }

    /// Records a non-tap observation (e.g. sizes of an element that is not tapped in this pass).
    func qaNote(_ screen: String, _ name: String, _ element: XCUIElement, note: String) {
        let seq = qa.nextSeq()
        let exists = element.exists
        let frame = exists ? element.frame : .zero
        let record = TapRecord(
            seq: seq, screen: screen, element: name, action: "observe", exists: exists,
            hittable: exists && element.isHittable,
            frame: "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))",
            widthPt: Double(frame.width), heightPt: Double(frame.height), responded: exists,
            tapCallMs: 0, responseMs: nil, note: note, before: "", after: ""
        )
        qa.append(record, in: self)
    }
}

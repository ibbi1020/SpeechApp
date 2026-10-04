import Foundation
import os

/// Live session JSONL diagnostics for caret lag / freeze-then-burst analysis.
///
/// Tiny payloads only — no PCM or full transcripts.
public final class SessionDiagnostics: @unchecked Sendable {
    public static let freezeSpeakingSeconds: TimeInterval = 0.8
    public static let freezeFillThreshold: Double = 0.9
    public static let burstWindowSeconds: TimeInterval = 0.45
    public static let burstMinTokens: Int = 4
    public static let chunkSampleInterval: TimeInterval = 0.1

    public private(set) var logFileURL: URL?
    public private(set) var freezeCount: Int = 0
    public private(set) var maxFreezeDuration: TimeInterval = 0
    public private(set) var burstCount: Int = 0

    private let lock = NSLock()
    private let fileHandle: FileHandle?
    private let sessionStartUptime: TimeInterval
    private let logger = Logger(subsystem: "com.speechapp.prototype", category: "SessionDiagnostics")

    private var lastChunkSampleAt: TimeInterval = 0
    private var caretStuckSince: TimeInterval?
    private var lastCaretWordID: String?
    private var freezeEmittedForCaret: String?
    private var asrTokenTimestamps: [TimeInterval] = []
    private var lastWasSpeaking: Bool = false
    private var caretAdvanceGaps: [TimeInterval] = []
    private var lastCaretAdvanceAt: TimeInterval?
    private var handleChunkDurations: [TimeInterval] = []

    public init(passageID: String, fileManager: FileManager = .default) {
        sessionStartUptime = ProcessInfo.processInfo.systemUptime
        let dir = Self.logsDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let unique = UUID().uuidString.prefix(8)
        let url = dir.appendingPathComponent("session-\(stamp)-\(unique).jsonl")
        fileManager.createFile(atPath: url.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: url)
        logFileURL = url

        emit(
            "session_start",
            [
                "passageID": passageID,
                "logPath": url.path,
            ]
        )
    }

    public static func logsDirectory(fileManager: FileManager = .default) -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return docs.appendingPathComponent("SpeechAppLogs", isDirectory: true)
    }

    // MARK: - Freeze / burst detectors (testable)

    /// Speaking continuously ≥800ms with fill ≥0.9 and no caret change.
    public static func shouldEmitFreeze(
        speakingDuration: TimeInterval,
        fill: Double,
        alreadyEmittedForThisCaret: Bool
    ) -> Bool {
        guard !alreadyEmittedForThisCaret else { return false }
        return speakingDuration >= freezeSpeakingSeconds && fill >= freezeFillThreshold
    }

    /// ≥N ASR tokens (volatile or final) arrived within a short window after silence.
    public static func shouldEmitBurst(
        tokenTimestampsInWindow: Int,
        wasSilentBeforeBurst: Bool
    ) -> Bool {
        wasSilentBeforeBurst && tokenTimestampsInWindow >= burstMinTokens
    }

    // MARK: - Emit API

    public func noteChunk(
        handleDuration: TimeInterval,
        speaking: Bool,
        rmsEnergy: Float,
        fill: Double,
        currentWordID: String?
    ) {
        lock.lock()
        defer { lock.unlock() }

        let now = ProcessInfo.processInfo.systemUptime
        handleChunkDurations.append(handleDuration)
        if handleChunkDurations.count > 200 {
            handleChunkDurations.removeFirst(handleChunkDurations.count - 200)
        }

        if speaking {
            if caretStuckSince == nil || currentWordID != lastCaretWordID {
                if currentWordID != lastCaretWordID {
                    caretStuckSince = now
                    freezeEmittedForCaret = nil
                } else if caretStuckSince == nil {
                    caretStuckSince = now
                }
            }
            lastCaretWordID = currentWordID
            let stuckFor = now - (caretStuckSince ?? now)
            if Self.shouldEmitFreeze(
                speakingDuration: stuckFor,
                fill: fill,
                alreadyEmittedForThisCaret: freezeEmittedForCaret == currentWordID
            ) {
                freezeCount += 1
                maxFreezeDuration = max(maxFreezeDuration, stuckFor)
                freezeEmittedForCaret = currentWordID
                emitUnlocked(
                    "caret_freeze",
                    [
                        "wordID": currentWordID ?? "",
                        "duration": String(format: "%.3f", stuckFor),
                        "fill": String(format: "%.2f", fill),
                        "energy": String(format: "%.2f", rmsEnergy),
                    ]
                )
            }
        } else {
            caretStuckSince = nil
        }

        let crossedToSilence = lastWasSpeaking && !speaking
        lastWasSpeaking = speaking

        if now - lastChunkSampleAt >= Self.chunkSampleInterval {
            lastChunkSampleAt = now
            emitUnlocked(
                "chunk",
                [
                    "handleMs": String(format: "%.1f", handleDuration * 1000),
                    "speaking": speaking ? "1" : "0",
                    "energy": String(format: "%.2f", rmsEnergy),
                    "fill": String(format: "%.2f", fill),
                    "wordID": currentWordID ?? "",
                ]
            )
        }

        // Burst detection uses recent ASR stamps when we just went silent.
        if crossedToSilence {
            evaluateBurstUnlocked(now: now, afterSilence: true)
        }
    }

    public func noteASRUpdate(
        engineKind: String,
        finalCount: Int,
        volatileCount: Int,
        caretBefore: String?,
        caretAfter: String?,
        wasSpeaking: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }

        let now = ProcessInfo.processInfo.systemUptime
        let tokenCount = finalCount + volatileCount
        for _ in 0..<tokenCount {
            asrTokenTimestamps.append(now)
        }
        if asrTokenTimestamps.count > 80 {
            asrTokenTimestamps.removeFirst(asrTokenTimestamps.count - 80)
        }

        emitUnlocked(
            "asr_update",
            [
                "engine": engineKind,
                "finals": "\(finalCount)",
                "volatiles": "\(volatileCount)",
                "caretBefore": caretBefore ?? "",
                "caretAfter": caretAfter ?? "",
                "speaking": wasSpeaking ? "1" : "0",
            ]
        )

        // Catch-up burst while not speaking (pause flush).
        if !wasSpeaking {
            evaluateBurstUnlocked(now: now, afterSilence: true)
        }
    }

    public func noteCaret(
        wordID: String,
        surface: String,
        trigger: String,
        latency: TimeInterval?
    ) {
        lock.lock()
        defer { lock.unlock() }

        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastCaretAdvanceAt {
            caretAdvanceGaps.append(now - previous)
        }
        lastCaretAdvanceAt = now
        caretStuckSince = now
        freezeEmittedForCaret = nil
        lastCaretWordID = wordID

        var fields: [String: String] = [
            "wordID": wordID,
            "surface": surface,
            "trigger": trigger,
        ]
        if let latency {
            fields["latency"] = String(format: "%.3f", latency)
        }
        emitUnlocked("caret", fields)
    }

    public func noteHint(stuckWordID: String?, nextWordID: String?) {
        emit(
            "hint",
            [
                "stuck": stuckWordID ?? "",
                "next": nextWordID ?? "",
            ]
        )
    }

    public func noteSkip(wordIDs: [String]) {
        guard !wordIDs.isEmpty else { return }
        emit(
            "skip",
            [
                "count": "\(wordIDs.count)",
                "ids": wordIDs.prefix(8).joined(separator: ","),
            ]
        )
    }

    public func noteScroll(wordID: String, reason: String) {
        emit(
            "scroll",
            [
                "wordID": wordID,
                "reason": reason,
            ]
        )
    }

    public func notePresenceAdvance(from: String, to: String) {
        emit(
            "presence_advance",
            [
                "from": from,
                "to": to,
            ]
        )
    }

    public func notePresenceSnap(to wordID: String) {
        emit(
            "presence_snap",
            [
                "to": wordID,
            ]
        )
    }

    public func noteSpanAdvance(from: Int, to: Int) {
        emit(
            "span_advance",
            [
                "from": String(from),
                "to": String(to),
            ]
        )
    }

    public func noteSpanSnap(to index: Int) {
        emit(
            "span_snap",
            [
                "to": String(index),
            ]
        )
    }

    public func finishSummary(
        volatileLatencies: [TimeInterval],
        finalLatencies: [TimeInterval]
    ) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        let allLatencies = volatileLatencies + finalLatencies
        let recentASR = asrTokenTimestamps.filter {
            ProcessInfo.processInfo.systemUptime - $0 <= Self.burstWindowSeconds
        }

        emitUnlocked(
            "summary",
            [
                "freezeCount": "\(freezeCount)",
                "maxFreezeSec": String(format: "%.3f", maxFreezeDuration),
                "burstCount": "\(burstCount)",
                "caretSamples": "\(allLatencies.count)",
                "volatileP50": fmtPercentile(volatileLatencies, 0.50),
                "volatileP95": fmtPercentile(volatileLatencies, 0.95),
                "volatileP99": fmtPercentile(volatileLatencies, 0.99),
                "finalP50": fmtPercentile(finalLatencies, 0.50),
                "finalP95": fmtPercentile(finalLatencies, 0.95),
                "finalP99": fmtPercentile(finalLatencies, 0.99),
                "maxCaretGap": fmtMax(caretAdvanceGaps),
                "p95ChunkHandleMs": fmtPercentile(handleChunkDurations.map { $0 * 1000 }, 0.95),
                "recentAsrInBurstWindow": "\(recentASR.count)",
            ]
        )

        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        return logFileURL
    }

    // MARK: - Private

    private func evaluateBurstUnlocked(now: TimeInterval, afterSilence: Bool) {
        let inWindow = asrTokenTimestamps.filter { now - $0 <= Self.burstWindowSeconds }.count
        if Self.shouldEmitBurst(tokenTimestampsInWindow: inWindow, wasSilentBeforeBurst: afterSilence) {
            burstCount += 1
            emitUnlocked(
                "asr_burst",
                [
                    "tokensInWindow": "\(inWindow)",
                    "windowSec": String(format: "%.2f", Self.burstWindowSeconds),
                ]
            )
            // Prevent immediate re-fire: clear window stamps.
            asrTokenTimestamps.removeAll()
        }
    }

    private func emit(_ type: String, _ fields: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        emitUnlocked(type, fields)
    }

    private func emitUnlocked(_ type: String, _ fields: [String: String]) {
        let uptime = ProcessInfo.processInfo.systemUptime - sessionStartUptime
        var line = "{\"t\":\(String(format: "%.3f", uptime)),\"event\":\"\(type)\""
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            line += ",\"\(key)\":\"\(escaped)\""
        }
        line += "}\n"

        if let data = line.data(using: .utf8) {
            try? fileHandle?.write(contentsOf: data)
        }
        // Console mirror for Xcode.
        print("[Diag] \(line.trimmingCharacters(in: .newlines))")
        logger.debug("\(line, privacy: .public)")
    }

    private func fmtPercentile(_ values: [TimeInterval], _ p: Double) -> String {
        guard let v = ReadingSession.percentile(values, p) else { return "-1" }
        return String(format: "%.3f", v)
    }

    private func fmtMax(_ values: [TimeInterval]) -> String {
        guard let v = values.max() else { return "-1" }
        return String(format: "%.3f", v)
    }
}

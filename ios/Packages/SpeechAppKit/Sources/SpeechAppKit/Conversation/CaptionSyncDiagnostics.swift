import Foundation
import os

/// Conversation caption↔audio sync JSONL. Share after a hang-up to diagnose lag.
///
/// Tiny payloads — frame/word counts and a short preview, never PCM.
public final class CaptionSyncDiagnostics: @unchecked Sendable {
    public static let sampleRate: Double = 24_000

    public private(set) var logFileURL: URL?
    public private(set) var responseIndex = 0
    public private(set) var yieldCount = 0
    public private(set) var maxLagWords = 0
    public private(set) var maxLagSec: Double = 0
    public private(set) var audioCompleteWithEmptyPending = 0

    private let lock = NSLock()
    private let fileHandle: FileHandle?
    private let sessionStartUptime: TimeInterval
    private let logger = Logger(subsystem: "com.speechapp", category: "CaptionSync")
    private var finished = false

    public init(conversationID: String, fileManager: FileManager = .default) {
        sessionStartUptime = ProcessInfo.processInfo.systemUptime
        let dir = SessionDiagnostics.logsDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let unique = UUID().uuidString.prefix(8)
        let url = dir.appendingPathComponent("caption-sync-\(stamp)-\(unique).jsonl")
        fileManager.createFile(atPath: url.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: url)
        logFileURL = url

        emit(
            "session_start",
            [
                "conversationID": conversationID,
                "logPath": url.path,
            ]
        )
    }

    // MARK: - Events

    public func noteResponseCreated() {
        lock.lock()
        responseIndex += 1
        let resp = responseIndex
        lock.unlock()
        emit("response_created", ["resp": "\(resp)"])
    }

    public func noteAudioDelta(
        deltaFrames: Int,
        queuedFrames: Int,
        completedFrames: Int,
        pendingWords: Int,
        revealedWords: Int
    ) {
        emitLedger(
            "audio_delta",
            deltaFrames: deltaFrames,
            deltaChars: nil,
            queuedFrames: queuedFrames,
            completedFrames: completedFrames,
            pendingWords: pendingWords,
            revealedWords: revealedWords,
            yielded: nil,
            preview: nil
        )
    }

    public func noteTranscriptDelta(
        deltaChars: Int,
        queuedFrames: Int,
        completedFrames: Int,
        pendingWords: Int,
        revealedWords: Int
    ) {
        emitLedger(
            "transcript_delta",
            deltaFrames: nil,
            deltaChars: deltaChars,
            queuedFrames: queuedFrames,
            completedFrames: completedFrames,
            pendingWords: pendingWords,
            revealedWords: revealedWords,
            yielded: nil,
            preview: nil
        )
    }

    public func noteTranscriptDone(
        queuedFrames: Int,
        completedFrames: Int,
        pendingWords: Int,
        revealedWords: Int
    ) {
        emitLedger(
            "transcript_done",
            deltaFrames: nil,
            deltaChars: nil,
            queuedFrames: queuedFrames,
            completedFrames: completedFrames,
            pendingWords: pendingWords,
            revealedWords: revealedWords,
            yielded: nil,
            preview: nil
        )
    }

    public func noteAudioComplete(
        deltaFrames: Int,
        queuedFrames: Int,
        completedFrames: Int,
        pendingWords: Int,
        revealedWordsBefore: Int,
        revealedWordsAfter: Int,
        yielded: Bool,
        preview: String
    ) {
        if pendingWords == 0 {
            lock.lock()
            audioCompleteWithEmptyPending += 1
            lock.unlock()
        }
        emitLedger(
            "audio_complete",
            deltaFrames: deltaFrames,
            deltaChars: nil,
            queuedFrames: queuedFrames,
            completedFrames: completedFrames,
            pendingWords: pendingWords,
            revealedWords: revealedWordsAfter,
            yielded: yielded,
            preview: preview,
            extra: ["revealedBefore": "\(revealedWordsBefore)"]
        )
    }

    public func noteCaptionYield(
        revealedWords: Int,
        pendingWords: Int,
        queuedFrames: Int,
        completedFrames: Int,
        preview: String
    ) {
        lock.lock()
        yieldCount += 1
        lock.unlock()
        emitLedger(
            "caption_yield",
            deltaFrames: nil,
            deltaChars: nil,
            queuedFrames: queuedFrames,
            completedFrames: completedFrames,
            pendingWords: pendingWords,
            revealedWords: revealedWords,
            yielded: true,
            preview: preview
        )
    }

    public func noteResponseDone(
        queuedFrames: Int,
        completedFrames: Int,
        pendingWords: Int,
        revealedWords: Int,
        draining: Bool
    ) {
        emitLedger(
            "response_done",
            deltaFrames: nil,
            deltaChars: nil,
            queuedFrames: queuedFrames,
            completedFrames: completedFrames,
            pendingWords: pendingWords,
            revealedWords: revealedWords,
            yielded: nil,
            preview: nil,
            extra: ["draining": draining ? "1" : "0"]
        )
    }

    public func noteCancel(
        queuedFrames: Int,
        completedFrames: Int,
        pendingWords: Int,
        revealedWords: Int
    ) {
        emitLedger(
            "cancel",
            deltaFrames: nil,
            deltaChars: nil,
            queuedFrames: queuedFrames,
            completedFrames: completedFrames,
            pendingWords: pendingWords,
            revealedWords: revealedWords,
            yielded: nil,
            preview: nil
        )
    }

    @discardableResult
    public func finish() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return logFileURL }
        finished = true
        emitUnlocked(
            "session_end",
            [
                "resp": "\(responseIndex)",
                "yields": "\(yieldCount)",
                "maxLagWords": "\(maxLagWords)",
                "maxLagSec": String(format: "%.3f", maxLagSec),
                "audioCompleteEmptyPending": "\(audioCompleteWithEmptyPending)",
            ]
        )
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        return logFileURL
    }

    // MARK: - Helpers

    public static func preview(_ text: String, limit: Int = 40) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let start = trimmed.index(trimmed.endIndex, offsetBy: -limit)
        return String(trimmed[start...])
    }

    public static func seconds(frames: Int) -> Double {
        Double(frames) / sampleRate
    }

    private func emitLedger(
        _ event: String,
        deltaFrames: Int?,
        deltaChars: Int?,
        queuedFrames: Int,
        completedFrames: Int,
        pendingWords: Int,
        revealedWords: Int,
        yielded: Bool?,
        preview: String?,
        extra: [String: String] = [:]
    ) {
        let lagWords = max(0, pendingWords - revealedWords)
        let lagFrames = max(0, queuedFrames - completedFrames)
        let lagSec = Self.seconds(frames: lagFrames)

        lock.lock()
        maxLagWords = max(maxLagWords, lagWords)
        maxLagSec = max(maxLagSec, lagSec)
        let resp = responseIndex
        lock.unlock()

        var fields: [String: String] = [
            "resp": "\(resp)",
            "queuedFrames": "\(queuedFrames)",
            "completedFrames": "\(completedFrames)",
            "queuedSec": String(format: "%.3f", Self.seconds(frames: queuedFrames)),
            "completedSec": String(format: "%.3f", Self.seconds(frames: completedFrames)),
            "pendingWords": "\(pendingWords)",
            "revealedWords": "\(revealedWords)",
            "lagWords": "\(lagWords)",
            "lagSec": String(format: "%.3f", lagSec),
        ]
        if let deltaFrames {
            fields["deltaFrames"] = "\(deltaFrames)"
        }
        if let deltaChars {
            fields["deltaChars"] = "\(deltaChars)"
        }
        if let yielded {
            fields["yielded"] = yielded ? "1" : "0"
        }
        if let preview, !preview.isEmpty {
            fields["preview"] = preview
        }
        for (key, value) in extra {
            fields[key] = value
        }
        emit(event, fields)
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
        print("[CaptionSync] \(line.trimmingCharacters(in: .newlines))")
        logger.debug("\(line, privacy: .public)")
    }
}

import Foundation

public struct MissedPhoneTag: Equatable, Sendable, Codable {
    public let phone: String
    public let flBand: FunctionalLoadBand

    public init(phone: String, flBand: FunctionalLoadBand) {
        self.phone = phone
        self.flBand = flBand
    }
}

/// Per-word analysis row for the end report.
public struct WordAnalysis: Equatable, Sendable, Codable, Identifiable {
    public var id: String { scriptWordID }
    public let scriptWordID: String
    public let surface: String
    public let canonicalPhones: [String]
    public let occupancy: String
    public let soundAssessment: String
    public let pcmSampleCount: Int

    public init(
        scriptWordID: String,
        surface: String,
        canonicalPhones: [String],
        occupancy: String,
        soundAssessment: String,
        pcmSampleCount: Int
    ) {
        self.scriptWordID = scriptWordID
        self.surface = surface
        self.canonicalPhones = canonicalPhones
        self.occupancy = occupancy
        self.soundAssessment = soundAssessment
        self.pcmSampleCount = pcmSampleCount
    }
}

public struct SessionReport: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let passageID: String
    public let passageTitle: String
    public let passageLength: String
    public let contrastFocus: [String]
    public let marks: [LiveMarkCodable]
    public let matchCount: Int
    public let skipCount: Int
    public let extraCount: Int
    public let substituteCount: Int
    public let scriptWordCount: Int
    public let completenessRatio: Double
    public let stallEventCount: Int
    public let speechRateSyllablesPerMinute: Double
    public let averageSpeechRateSyllablesPerMinute: Double?
    public let durationSeconds: TimeInterval
    public let pcmCapturedSeconds: TimeInterval
    public let missedPhoneTags: [MissedPhoneTag]
    public let wordAnalyses: [WordAnalysis]
    public let engineKind: String
    public let followAlongNote: String
    public let gopNote: String
    /// On-device JSONL path for caret-lag diagnostics (share from report screen).
    public let diagnosticsLogPath: String?

    public init(
        id: UUID = UUID(),
        passageID: String,
        passageTitle: String,
        passageLength: String = PassageLength.short.rawValue,
        contrastFocus: [String] = [],
        marks: [LiveMarkCodable],
        matchCount: Int,
        skipCount: Int,
        extraCount: Int,
        substituteCount: Int,
        scriptWordCount: Int = 0,
        completenessRatio: Double = 0,
        stallEventCount: Int = 0,
        speechRateSyllablesPerMinute: Double,
        averageSpeechRateSyllablesPerMinute: Double?,
        durationSeconds: TimeInterval,
        pcmCapturedSeconds: TimeInterval = 0,
        missedPhoneTags: [MissedPhoneTag],
        wordAnalyses: [WordAnalysis] = [],
        engineKind: String,
        followAlongNote: String = "Follow-along counts words we heard against the passage. It is not a pronunciation grade.",
        gopNote: String = "Sound-by-sound scoring is not on yet. Audio used for that is discarded after this report.",
        diagnosticsLogPath: String? = nil
    ) {
        self.id = id
        self.passageID = passageID
        self.passageTitle = passageTitle
        self.passageLength = passageLength
        self.contrastFocus = contrastFocus
        self.marks = marks
        self.matchCount = matchCount
        self.skipCount = skipCount
        self.extraCount = extraCount
        self.substituteCount = substituteCount
        self.scriptWordCount = scriptWordCount
        self.completenessRatio = completenessRatio
        self.stallEventCount = stallEventCount
        self.speechRateSyllablesPerMinute = speechRateSyllablesPerMinute
        self.averageSpeechRateSyllablesPerMinute = averageSpeechRateSyllablesPerMinute
        self.durationSeconds = durationSeconds
        self.pcmCapturedSeconds = pcmCapturedSeconds
        self.missedPhoneTags = missedPhoneTags
        self.wordAnalyses = wordAnalyses
        self.engineKind = engineKind
        self.followAlongNote = followAlongNote
        self.gopNote = gopNote
        self.diagnosticsLogPath = diagnosticsLogPath
    }
}

/// Codable mirror of LiveMark for persistence in reports.
public struct LiveMarkCodable: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let kind: LiveMark.Kind
    public let scriptWordID: String?
    public let spokenSurface: String?
    public let message: String

    public init(from mark: LiveMark) {
        self.id = mark.id
        self.kind = mark.kind
        self.scriptWordID = mark.scriptWordID
        self.spokenSurface = mark.spokenSurface
        self.message = mark.message
    }

    public init(
        id: UUID = UUID(),
        kind: LiveMark.Kind,
        scriptWordID: String? = nil,
        spokenSurface: String? = nil,
        message: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.scriptWordID = scriptWordID
        self.spokenSurface = spokenSurface
        self.message = message
    }
}

extension LiveMark.Kind: Codable {}

/// Builds the end-of-session analysis from alignment + PCM + specialized scorer.
public enum SessionAnalyzer {
    public static func buildReport(
        passage: Passage,
        events: [AlignmentEvent],
        marks: [LiveMark],
        matchedSyllables: Int,
        duration: TimeInterval,
        stallEventCount: Int,
        pcm: PCMStore,
        gopScorer: any GOPScorer,
        ledgerAverageRate: Double?,
        engineKind: String,
        diagnosticsLogPath: String? = nil
    ) async -> SessionReport {
        let matchCount = events.filter { $0.op == .match }.count
        let skipCount = events.filter { $0.op == .skipScript }.count
        let extraCount = events.filter { $0.op == .insertSpoken }.count
        let substituteCount = events.filter { $0.op == .substitute }.count
        let scriptCount = max(1, passage.words.count)
        let completeness = Double(matchCount) / Double(scriptCount)

        let rate: Double
        if duration > 0.5 {
            rate = Double(matchedSyllables) / (duration / 60.0)
        } else {
            rate = 0
        }

        var occupancyByID: [String: AlignmentOperator] = [:]
        for event in events {
            if let id = event.scriptWordID {
                occupancyByID[id] = event.op
            }
        }

        var missedTags: [MissedPhoneTag] = []
        var wordAnalyses: [WordAnalysis] = []
        let wordCount = max(1, passage.words.count)

        for (index, word) in passage.words.enumerated() {
            let start = Double(index) / Double(wordCount)
            let end = Double(index + 1) / Double(wordCount)
            let slice = pcm.slice(startFraction: start, endFraction: end)
            let assessment = await gopScorer.score(scriptWord: word, pcmSlice: slice)
            let op = occupancyByID[word.id]
            let occupancyLabel: String
            switch op {
            case .match: occupancyLabel = "matched"
            case .skipScript: occupancyLabel = "skipped"
            case .substitute: occupancyLabel = "swapped"
            case .none: occupancyLabel = "unscored"
            default: occupancyLabel = op?.rawValue ?? "other"
            }

            if op == .skipScript || op == .substitute {
                for phone in word.phoneTags {
                    missedTags.append(MissedPhoneTag(phone: phone, flBand: word.flBand))
                }
            }

            wordAnalyses.append(
                WordAnalysis(
                    scriptWordID: word.id,
                    surface: word.surface,
                    canonicalPhones: word.resolvedPhones,
                    occupancy: occupancyLabel,
                    soundAssessment: Self.label(assessment),
                    pcmSampleCount: slice.count
                )
            )
        }

        return SessionReport(
            passageID: passage.id,
            passageTitle: passage.title,
            passageLength: passage.length.rawValue,
            contrastFocus: passage.contrastTags,
            marks: marks.map(LiveMarkCodable.init(from:)),
            matchCount: matchCount,
            skipCount: skipCount,
            extraCount: extraCount,
            substituteCount: substituteCount,
            scriptWordCount: passage.words.count,
            completenessRatio: completeness,
            stallEventCount: stallEventCount,
            speechRateSyllablesPerMinute: rate,
            averageSpeechRateSyllablesPerMinute: ledgerAverageRate,
            durationSeconds: duration,
            pcmCapturedSeconds: pcm.durationSeconds,
            missedPhoneTags: missedTags,
            wordAnalyses: wordAnalyses,
            engineKind: engineKind,
            diagnosticsLogPath: diagnosticsLogPath
        )
    }

    private static func label(_ assessment: GOPAssessment) -> String {
        switch assessment {
        case .notAssessed: return "not assessed"
        case .poorSound: return "needs attention"
        case .ok: return "ok"
        }
    }
}

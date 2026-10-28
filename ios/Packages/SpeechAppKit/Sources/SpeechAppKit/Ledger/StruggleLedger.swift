import Foundation

public struct PhoneStruggle: Codable, Equatable, Sendable {
    public var phone: String
    public var flBand: FunctionalLoadBand
    public var missCount: Int
    public var lastSession: Date

    public init(phone: String, flBand: FunctionalLoadBand, missCount: Int, lastSession: Date = Date()) {
        self.phone = phone
        self.flBand = flBand
        self.missCount = missCount
        self.lastSession = lastSession
    }
}

public struct SkipWordStruggle: Codable, Equatable, Sendable {
    public var wordId: String
    public var surface: String
    public var count: Int

    public init(wordId: String, surface: String, count: Int) {
        self.wordId = wordId
        self.surface = surface
        self.count = count
    }
}

/// One missed sound from a saved reading. The dated log is never trimmed.
public struct PhoneMissEvent: Codable, Equatable, Sendable {
    public var phone: String
    public var flBand: FunctionalLoadBand
    public var date: Date

    public init(phone: String, flBand: FunctionalLoadBand, date: Date) {
        self.phone = phone
        self.flBand = flBand
        self.date = date
    }
}

/// One skipped word from a saved reading. The dated log is never trimmed.
public struct SkipEvent: Codable, Equatable, Sendable {
    public var wordId: String
    public var surface: String
    public var date: Date

    public init(wordId: String, surface: String, date: Date) {
        self.wordId = wordId
        self.surface = surface
        self.date = date
    }
}

/// One reading speed from a saved reading. The dated log is never trimmed.
public struct SpeechRateEvent: Codable, Equatable, Sendable {
    public var syllablesPerMinute: Double
    public var date: Date

    public init(syllablesPerMinute: Double, date: Date) {
        self.syllablesPerMinute = syllablesPerMinute
        self.date = date
    }
}

public struct StruggleLedger: Equatable, Sendable {
    public var phones: [PhoneStruggle]
    public var skipWords: [SkipWordStruggle]
    public var extras: [String: Int]
    public var recentSpeechRates: [Double]
    public var seenPassageIDs: [String]
    public var missEvents: [PhoneMissEvent]
    public var skipEvents: [SkipEvent]
    public var speechRateEvents: [SpeechRateEvent]

    public init(
        phones: [PhoneStruggle] = [],
        skipWords: [SkipWordStruggle] = [],
        extras: [String: Int] = [:],
        recentSpeechRates: [Double] = [],
        seenPassageIDs: [String] = [],
        missEvents: [PhoneMissEvent] = [],
        skipEvents: [SkipEvent] = [],
        speechRateEvents: [SpeechRateEvent] = []
    ) {
        self.phones = phones
        self.skipWords = skipWords
        self.extras = extras
        self.recentSpeechRates = recentSpeechRates
        self.seenPassageIDs = seenPassageIDs
        self.missEvents = missEvents
        self.skipEvents = skipEvents
        self.speechRateEvents = speechRateEvents
    }

    public var averageSpeechRate: Double? {
        guard !recentSpeechRates.isEmpty else { return nil }
        return recentSpeechRates.reduce(0, +) / Double(recentSpeechRates.count)
    }

    /// Updates the running totals, keeps the last 10 speeds, and appends one dated
    /// event per miss, skip, and reading speed. `date` is the session save time.
    /// The dated log is never trimmed. Pass a fixed date from tests.
    public mutating func record(report: SessionReport, at date: Date = Date()) {
        if !seenPassageIDs.contains(report.passageID) {
            seenPassageIDs.append(report.passageID)
        }
        recentSpeechRates.append(report.speechRateSyllablesPerMinute)
        if recentSpeechRates.count > 10 {
            recentSpeechRates.removeFirst(recentSpeechRates.count - 10)
        }
        speechRateEvents.append(
            SpeechRateEvent(
                syllablesPerMinute: report.speechRateSyllablesPerMinute,
                date: date
            )
        )

        for mark in report.marks where mark.kind == .skip {
            guard let wordID = mark.scriptWordID else { continue }
            if let index = skipWords.firstIndex(where: { $0.wordId == wordID }) {
                skipWords[index].count += 1
            } else {
                skipWords.append(
                    SkipWordStruggle(
                        wordId: wordID,
                        surface: mark.message,
                        count: 1
                    )
                )
            }
            skipEvents.append(SkipEvent(wordId: wordID, surface: mark.message, date: date))
        }

        for mark in report.marks where mark.kind == .extra {
            let key = (mark.spokenSurface ?? "extra").lowercased()
            extras[key, default: 0] += 1
        }

        for tag in report.missedPhoneTags {
            if let index = phones.firstIndex(where: { $0.phone == tag.phone }) {
                phones[index].missCount += 1
                phones[index].lastSession = date
                if tag.flBand > phones[index].flBand {
                    phones[index].flBand = tag.flBand
                }
            } else {
                phones.append(
                    PhoneStruggle(
                        phone: tag.phone,
                        flBand: tag.flBand,
                        missCount: 1,
                        lastSession: date
                    )
                )
            }
            missEvents.append(PhoneMissEvent(phone: tag.phone, flBand: tag.flBand, date: date))
        }
    }
}

extension StruggleLedger: Codable {
    private enum CodingKeys: String, CodingKey {
        case phones
        case skipWords
        case extras
        case recentSpeechRates
        case seenPassageIDs
        case missEvents
        case skipEvents
        case speechRateEvents
    }

    /// Missing event arrays are empty. A synthesized `Codable` would fail on a
    /// ledger saved before those keys existed, and `loadOrCreate` would replace it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phones = try container.decode([PhoneStruggle].self, forKey: .phones)
        skipWords = try container.decode([SkipWordStruggle].self, forKey: .skipWords)
        extras = try container.decode([String: Int].self, forKey: .extras)
        recentSpeechRates = try container.decode([Double].self, forKey: .recentSpeechRates)
        seenPassageIDs = try container.decode([String].self, forKey: .seenPassageIDs)
        missEvents = try container.decodeIfPresent([PhoneMissEvent].self, forKey: .missEvents) ?? []
        skipEvents = try container.decodeIfPresent([SkipEvent].self, forKey: .skipEvents) ?? []
        speechRateEvents = try container.decodeIfPresent([SpeechRateEvent].self, forKey: .speechRateEvents) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phones, forKey: .phones)
        try container.encode(skipWords, forKey: .skipWords)
        try container.encode(extras, forKey: .extras)
        try container.encode(recentSpeechRates, forKey: .recentSpeechRates)
        try container.encode(seenPassageIDs, forKey: .seenPassageIDs)
        try container.encode(missEvents, forKey: .missEvents)
        try container.encode(skipEvents, forKey: .skipEvents)
        try container.encode(speechRateEvents, forKey: .speechRateEvents)
    }
}

public enum StruggleLedgerStore {
    public static let fileName = "struggle_ledger.json"

    public static func storageURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = root.appendingPathComponent("SpeechApp", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }

    public static func loadOrCreate(fileManager: FileManager = .default) -> StruggleLedger {
        do {
            let url = try storageURL(fileManager: fileManager)
            guard fileManager.fileExists(atPath: url.path) else {
                return StruggleLedger()
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(StruggleLedger.self, from: data)
        } catch {
            return StruggleLedger()
        }
    }

    public static func save(_ ledger: StruggleLedger, fileManager: FileManager = .default) {
        do {
            let url = try storageURL(fileManager: fileManager)
            let data = try JSONEncoder().encode(ledger)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Prototype: swallow persistence errors; session still works in-memory.
        }
    }
}

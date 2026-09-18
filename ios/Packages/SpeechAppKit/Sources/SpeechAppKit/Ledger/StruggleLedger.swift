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

public struct StruggleLedger: Codable, Equatable, Sendable {
    public var phones: [PhoneStruggle]
    public var skipWords: [SkipWordStruggle]
    public var extras: [String: Int]
    public var recentSpeechRates: [Double]
    public var seenPassageIDs: [String]

    public init(
        phones: [PhoneStruggle] = [],
        skipWords: [SkipWordStruggle] = [],
        extras: [String: Int] = [:],
        recentSpeechRates: [Double] = [],
        seenPassageIDs: [String] = []
    ) {
        self.phones = phones
        self.skipWords = skipWords
        self.extras = extras
        self.recentSpeechRates = recentSpeechRates
        self.seenPassageIDs = seenPassageIDs
    }

    public var averageSpeechRate: Double? {
        guard !recentSpeechRates.isEmpty else { return nil }
        return recentSpeechRates.reduce(0, +) / Double(recentSpeechRates.count)
    }

    public mutating func record(report: SessionReport) {
        if !seenPassageIDs.contains(report.passageID) {
            seenPassageIDs.append(report.passageID)
        }
        recentSpeechRates.append(report.speechRateSyllablesPerMinute)
        if recentSpeechRates.count > 10 {
            recentSpeechRates.removeFirst(recentSpeechRates.count - 10)
        }

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
        }

        for mark in report.marks where mark.kind == .extra {
            let key = (mark.spokenSurface ?? "extra").lowercased()
            extras[key, default: 0] += 1
        }

        for tag in report.missedPhoneTags {
            if let index = phones.firstIndex(where: { $0.phone == tag.phone }) {
                phones[index].missCount += 1
                phones[index].lastSession = Date()
                if tag.flBand > phones[index].flBand {
                    phones[index].flBand = tag.flBand
                }
            } else {
                phones.append(
                    PhoneStruggle(
                        phone: tag.phone,
                        flBand: tag.flBand,
                        missCount: 1
                    )
                )
            }
        }
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

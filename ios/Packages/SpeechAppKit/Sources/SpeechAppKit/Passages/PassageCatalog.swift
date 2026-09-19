import Foundation

public struct PassageCatalog: Equatable, Sendable {
    public let passages: [Passage]

    public init(passages: [Passage]) {
        self.passages = passages
    }

    public func passage(id: String) -> Passage? {
        passages.first { $0.id == id }
    }

    public var families: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for p in passages {
            if seen.insert(p.family).inserted {
                ordered.append(p.family)
            }
        }
        return ordered
    }

    public func passages(inFamily family: String) -> [Passage] {
        passages.filter { $0.family == family }
            .sorted { lhs, rhs in
                lengthRank(lhs.length) < lengthRank(rhs.length)
            }
    }

    /// Full passages only. Short variants stay in the bundle for later work.
    public var pickerPassages: [Passage] {
        passages.filter { $0.length == .long }
    }

    private func lengthRank(_ length: PassageLength) -> Int {
        switch length {
        case .short: return 0
        case .medium: return 1
        case .long: return 2
        }
    }

    public static func loadBundled(
        bundle: Bundle? = nil
    ) -> PassageCatalog {
        let bundle = bundle ?? .module
        if let url = bundle.url(forResource: "passages", withExtension: "json", subdirectory: "Passages")
            ?? bundle.url(forResource: "passages", withExtension: "json")
        {
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(PassageCatalogDTO.self, from: data)
                return PassageCatalog(passages: decoded.passages.map(\.asPassage))
            } catch {
                return PassageCatalog(passages: Self.fallbackPassages)
            }
        }
        return PassageCatalog(passages: Self.fallbackPassages)
    }

    /// In-code fallback so the app runs even if the resource copy fails.
    public static var fallbackPassages: [Passage] {
        [
            makePassage(
                id: "ship-sheep-1",
                family: "ship-sheep",
                length: .short,
                title: "Harbor Morning",
                text: "The ship and the sheep share the same shore this morning",
                tags: ["ɪ-i", "ʃ"],
                phones: ["ɪ", "i", "ʃ"],
                balanced: true
            ),
            makePassage(
                id: "l-r-1",
                family: "l-r",
                length: .short,
                title: "River Light",
                text: "A light rain ran along the long river road",
                tags: ["l-r"],
                phones: ["l", "r"],
                balanced: false
            ),
            makePassage(
                id: "mixed-1",
                family: "mixed",
                length: .long,
                title: "Evening Walk",
                text: "On an evening walk by the river we view vivid lights while a light rain runs along the long road",
                tags: ["ɪ-i", "l-r"],
                phones: ["ɪ", "i", "l", "r"],
                balanced: true
            ),
        ]
    }

    static func makePassage(
        id: String,
        family: String,
        length: PassageLength,
        title: String,
        text: String,
        tags: [String],
        phones: [String],
        balanced: Bool,
        flBand: FunctionalLoadBand = .high
    ) -> Passage {
        let surfaces = text.split(separator: " ").map(String.init)
        let words = surfaces.enumerated().map { index, surface in
            ScriptWord(
                id: "\(id)-\(index)",
                surface: surface,
                syllableCount: estimateSyllables(surface),
                phoneTags: phones,
                canonicalPhones: PhoneLexicon.phones(for: surface),
                flBand: flBand
            )
        }
        return Passage(
            id: id,
            title: title,
            words: words,
            contrastTags: tags,
            isBalancedDefault: balanced,
            family: family,
            length: length
        )
    }

    private static func estimateSyllables(_ word: String) -> Int {
        estimateSyllablesPublic(word)
    }
}

private struct PassageCatalogDTO: Codable {
    let passages: [PassageDTO]
}

private struct PassageDTO: Codable {
    let id: String
    let title: String
    let text: String
    let contrastTags: [String]
    let phoneTags: [String]
    let isBalancedDefault: Bool
    let flBand: String?
    let family: String?
    let length: String?
    /// Optional per-word phone overrides, parallel to whitespace-split text.
    let wordPhones: [[String]]?

    var asPassage: Passage {
        let band = FunctionalLoadBand(rawValue: flBand ?? "high") ?? .high
        let length = PassageLength(rawValue: length ?? "short") ?? .short
        let family = family ?? id
        let surfaces = text.split(separator: " ").map(String.init)
        let words = surfaces.enumerated().map { index, surface in
            let authored: [String]
            if let wordPhones, wordPhones.indices.contains(index) {
                authored = wordPhones[index]
            } else {
                authored = []
            }
            let canonical = authored.isEmpty ? PhoneLexicon.phones(for: surface) : authored
            return ScriptWord(
                id: "\(id)-\(index)",
                surface: surface,
                syllableCount: PassageCatalog.estimateSyllablesPublic(surface),
                phoneTags: phoneTags,
                canonicalPhones: canonical,
                flBand: band
            )
        }
        return Passage(
            id: id,
            title: title,
            words: words,
            contrastTags: contrastTags,
            isBalancedDefault: isBalancedDefault,
            family: family,
            length: length
        )
    }
}

extension PassageCatalog {
    /// Exposed for DTO decoding syllable estimates.
    static func estimateSyllablesPublic(_ word: String) -> Int {
        let vowels = CharacterSet(charactersIn: "aeiouyAEIOUY")
        var count = 0
        var previousWasVowel = false
        for scalar in word.unicodeScalars {
            let isVowel = vowels.contains(scalar)
            if isVowel && !previousWasVowel {
                count += 1
            }
            previousWasVowel = isVowel
        }
        return max(1, count)
    }
}

public enum NextPassagePicker {
    public static func pick(catalog: PassageCatalog, ledger: StruggleLedger) -> Passage? {
        let pool = catalog.pickerPassages
        guard !pool.isEmpty else { return nil }

        if ledger.phones.isEmpty && ledger.skipWords.isEmpty {
            if let balanced = catalog.passages.first(where: \.isBalancedDefault) {
                return pool.first { $0.family == balanced.family } ?? pool.first
            }
            return pool.first
        }

        let highFL = Set(ledger.phones.filter { $0.flBand == .high }.map(\.phone))
        let allMissed = Set(ledger.phones.map(\.phone))

        func score(_ passage: Passage) -> (Int, Int, Int) {
            let tags = Set(passage.words.flatMap(\.phoneTags) + passage.contrastTags)
            let highHits = tags.intersection(highFL).count
            let otherHits = tags.intersection(allMissed).count
            let unseenBoost = ledger.seenPassageIDs.contains(passage.id) ? 0 : 1
            return (highHits, otherHits, unseenBoost)
        }

        return pool.max { lhs, rhs in
            let a = score(lhs)
            let b = score(rhs)
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            if a.2 != b.2 { return a.2 < b.2 }
            return lhs.id > rhs.id
        }
    }
}

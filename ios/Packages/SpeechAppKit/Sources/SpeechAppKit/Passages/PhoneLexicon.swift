import Foundation

/// Approximate IPA-style phones for script words. Used by specialized sound scoring —
/// never by Apple's transcript. Prefer authored overrides in passage JSON when present.
public enum PhoneLexicon {
    /// Hand lexicon for common Reading practice words (IPA-ish symbols).
    private static let table: [String: [String]] = [
        "the": ["ð", "ə"], "a": ["ə"], "an": ["ə", "n"], "and": ["æ", "n", "d"],
        "to": ["t", "u"], "of": ["ə", "v"], "for": ["f", "ɔ", "ɹ"], "in": ["ɪ", "n"],
        "on": ["ɑ", "n"], "is": ["ɪ", "z"], "as": ["æ", "z"], "at": ["æ", "t"],
        "by": ["b", "aɪ"], "with": ["w", "ɪ", "θ"], "that": ["ð", "æ", "t"],
        "this": ["ð", "ɪ", "s"], "they": ["ð", "eɪ"], "them": ["ð", "ɛ", "m"],
        "then": ["ð", "ɛ", "n"], "than": ["ð", "æ", "n"], "those": ["ð", "oʊ", "z"],
        "these": ["ð", "i", "z"], "their": ["ð", "ɛ", "ɹ"], "there": ["ð", "ɛ", "ɹ"],
        "ship": ["ʃ", "ɪ", "p"], "sheep": ["ʃ", "i", "p"], "shore": ["ʃ", "ɔ", "ɹ"],
        "share": ["ʃ", "ɛ", "ɹ"], "same": ["s", "eɪ", "m"], "morning": ["m", "ɔ", "ɹ", "n", "ɪ", "ŋ"],
        "harbor": ["h", "ɑ", "ɹ", "b", "ɚ"], "harbour": ["h", "ɑ", "ɹ", "b", "ɚ"],
        "light": ["l", "aɪ", "t"], "right": ["ɹ", "aɪ", "t"], "rain": ["ɹ", "eɪ", "n"],
        "ran": ["ɹ", "æ", "n"], "along": ["ə", "l", "ɔ", "ŋ"], "long": ["l", "ɔ", "ŋ"],
        "wrong": ["ɹ", "ɔ", "ŋ"], "river": ["ɹ", "ɪ", "v", "ɚ"], "road": ["ɹ", "oʊ", "d"],
        "think": ["θ", "ɪ", "ŋ", "k"], "thank": ["θ", "æ", "ŋ", "k"], "thanks": ["θ", "æ", "ŋ", "k", "s"],
        "thick": ["θ", "ɪ", "k"], "thin": ["θ", "ɪ", "n"], "thinner": ["θ", "ɪ", "n", "ɚ"],
        "thread": ["θ", "ɹ", "ɛ", "d"], "cloth": ["k", "l", "ɔ", "θ"], "breath": ["b", "ɹ", "ɛ", "θ"],
        "breathe": ["b", "ɹ", "i", "ð"], "view": ["v", "ju"], "vivid": ["v", "ɪ", "v", "ɪ", "d"],
        "waves": ["w", "eɪ", "v", "z"], "very": ["v", "ɛ", "ɹ", "i"], "wide": ["w", "aɪ", "d"],
        "west": ["w", "ɛ", "s", "t"], "wind": ["w", "ɪ", "n", "d"], "wine": ["w", "aɪ", "n"],
        "vine": ["v", "aɪ", "n"], "please": ["p", "l", "i", "z"], "put": ["p", "ʊ", "t"],
        "big": ["b", "ɪ", "ɡ"], "bag": ["b", "æ", "ɡ"], "park": ["p", "ɑ", "ɹ", "k"],
        "bench": ["b", "ɛ", "n", "tʃ"], "people": ["p", "i", "p", "əl"], "paper": ["p", "eɪ", "p", "ɚ"],
        "record": ["ɹ", "ɛ", "k", "ɚ", "d"], "present": ["p", "ɹ", "ɛ", "z", "ə", "n", "t"],
        "protest": ["p", "ɹ", "oʊ", "t", "ɛ", "s", "t"], "object": ["ɑ", "b", "dʒ", "ɛ", "k", "t"],
        "make": ["m", "eɪ", "k"], "decision": ["d", "ɪ", "s", "ɪ", "ʒ", "ən"],
        "take": ["t", "eɪ", "k"], "break": ["b", "ɹ", "eɪ", "k"], "work": ["w", "ɝ", "k"],
        "busy": ["b", "ɪ", "z", "i"], "cities": ["s", "ɪ", "t", "i", "z"],
        "buzz": ["b", "ʌ", "z"], "buses": ["b", "ʌ", "s", "ɪ", "z"], "zip": ["z", "ɪ", "p"],
        "shops": ["ʃ", "ɑ", "p", "s"], "bad": ["b", "æ", "d"], "bed": ["b", "ɛ", "d"],
        "red": ["ɹ", "ɛ", "d"], "blanket": ["b", "l", "æ", "ŋ", "k", "ɪ", "t"],
        "black": ["b", "l", "æ", "k"], "singing": ["s", "ɪ", "ŋ", "ɪ", "ŋ"],
        "green": ["ɡ", "ɹ", "i", "n"], "hanging": ["h", "æ", "ŋ", "ɪ", "ŋ"],
        "vines": ["v", "aɪ", "n", "z"], "sin": ["s", "ɪ", "n"], "sing": ["s", "ɪ", "ŋ"],
        "evening": ["i", "v", "n", "ɪ", "ŋ"], "walk": ["w", "ɔ", "k"], "meeting": ["m", "i", "t", "ɪ", "ŋ"],
        "office": ["ɔ", "f", "ɪ", "s"], "clear": ["k", "l", "ɪ", "ɹ"], "speech": ["s", "p", "i", "tʃ"],
        "listener": ["l", "ɪ", "s", "ə", "n", "ɚ"], "practice": ["p", "ɹ", "æ", "k", "t", "ɪ", "s"],
        "before": ["b", "ɪ", "f", "ɔ", "ɹ"], "after": ["æ", "f", "t", "ɚ"],
        "while": ["w", "aɪ", "l"], "when": ["w", "ɛ", "n"], "where": ["w", "ɛ", "ɹ"],
        "what": ["w", "ʌ", "t"], "who": ["h", "u"], "how": ["h", "aʊ"],
        "can": ["k", "æ", "n"], "could": ["k", "ʊ", "d"], "would": ["w", "ʊ", "d"],
        "should": ["ʃ", "ʊ", "d"], "will": ["w", "ɪ", "l"], "was": ["w", "ʌ", "z"],
        "were": ["w", "ɝ"], "been": ["b", "ɪ", "n"], "have": ["h", "æ", "v"],
        "has": ["h", "æ", "z"], "had": ["h", "æ", "d"], "do": ["d", "u"],
        "does": ["d", "ʌ", "z"], "did": ["d", "ɪ", "d"], "not": ["n", "ɑ", "t"],
        "no": ["n", "oʊ"], "yes": ["j", "ɛ", "s"], "or": ["ɔ", "ɹ"],
        "if": ["ɪ", "f"], "from": ["f", "ɹ", "ʌ", "m"], "into": ["ɪ", "n", "t", "u"],
        "over": ["oʊ", "v", "ɚ"], "under": ["ʌ", "n", "d", "ɚ"], "about": ["ə", "b", "aʊ", "t"],
        "between": ["b", "ɪ", "t", "w", "i", "n"], "without": ["w", "ɪ", "ð", "aʊ", "t"],
        "through": ["θ", "ɹ", "u"], "throughout": ["θ", "ɹ", "u", "aʊ", "t"],
        "every": ["ɛ", "v", "ɹ", "i"], "each": ["i", "tʃ"], "other": ["ʌ", "ð", "ɚ"],
        "another": ["ə", "n", "ʌ", "ð", "ɚ"], "something": ["s", "ʌ", "m", "θ", "ɪ", "ŋ"],
        "someone": ["s", "ʌ", "m", "w", "ʌ", "n"], "mother": ["m", "ʌ", "ð", "ɚ"],
        "brother": ["b", "ɹ", "ʌ", "ð", "ɚ"], "friends": ["f", "ɹ", "ɛ", "n", "d", "z"],
        "child": ["tʃ", "aɪ", "l", "d"], "children": ["tʃ", "ɪ", "l", "d", "ɹ", "ə", "n"],
        "story": ["s", "t", "ɔ", "ɹ", "i"], "words": ["w", "ɝ", "d", "z"],
        "word": ["w", "ɝ", "d"], "sound": ["s", "aʊ", "n", "d"], "sounds": ["s", "aʊ", "n", "d", "z"],
        "vowel": ["v", "aʊ", "ə", "l"], "reader": ["ɹ", "i", "d", "ɚ"], "reading": ["ɹ", "i", "d", "ɪ", "ŋ"],
        "read": ["ɹ", "i", "d"], "forward": ["f", "ɔ", "ɹ", "w", "ɚ", "d"],
        "still": ["s", "t", "ɪ", "l"], "feel": ["f", "i", "l"], "feels": ["f", "i", "l", "z"],
        "easy": ["i", "z", "i"], "hard": ["h", "ɑ", "ɹ", "d"], "calm": ["k", "ɑ", "m"],
        "pace": ["p", "eɪ", "s"], "whole": ["h", "oʊ", "l"], "passage": ["p", "æ", "s", "ɪ", "dʒ"],
        "paragraph": ["p", "æ", "ɹ", "ə", "ɡ", "ɹ", "æ", "f"], "scene": ["s", "i", "n"],
        "mixed": ["m", "ɪ", "k", "s", "t"],
    ]

    public static func phones(for surface: String) -> [String] {
        let key = ScriptWord.normalize(surface)
        if let known = table[key] { return known }
        return approximate(from: key)
    }

    /// Last-resort letter→phone sketch so every word has a sequence for Slice B wiring.
    /// Marked approximate in analysis — not a substitute for a real G2P lexicon.
    public static func approximate(from normalized: String) -> [String] {
        guard !normalized.isEmpty else { return [] }
        var phones: [String] = []
        let chars = Array(normalized)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            switch (c, next) {
            case ("t", "h"):
                phones.append("θ"); i += 2
            case ("s", "h"):
                phones.append("ʃ"); i += 2
            case ("c", "h"):
                phones.append("tʃ"); i += 2
            case ("n", "g"):
                phones.append("ŋ"); i += 2
            case ("o", "o"), ("e", "e"):
                phones.append("u"); i += 2
            default:
                phones.append(String(c))
                i += 1
            }
        }
        return phones
    }
}

import Foundation

// MARK: - WakePhrase
// Pure functions — no Speech or AVFoundation dependencies.
// Compiled into both the app and standalone test scripts.

enum WakePhrase {

    // MARK: - Public API

    struct SplitResult {
        let matched: Bool
        /// Words after the LAST wake phrase occurrence, extracted from the **original** transcript
        /// (original casing, apostrophes, hyphens, accents preserved).
        /// Leading punctuation on the first word is stripped.
        let command: String
    }

    /// Scans `raw` for a wake phrase at a word boundary (anywhere in the transcript,
    /// not just the start). Returns the text following the **last** occurrence as the command,
    /// preserving the original casing and punctuation of the command portion.
    ///
    /// Accepted patterns (case-insensitive, after phonetic normalisation):
    /// - "ei <nome>", "oi <nome>", "ok <nome>", "hey <nome>", for every name in `names`
    /// - Default names cover how the recognizer writes "Cloud" in Portuguese (Claude, Claudio, iCloud).
    ///
    /// Word-boundary search means "é ei cloud abre" matches and returns "abre".
    /// A name alone never matches: talking about Claude must not wake Cloud.
    static func split(_ raw: String) -> SplitResult {
        // Split original into whitespace-separated tokens (punctuation stays attached to words)
        let originalWords = raw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !originalWords.isEmpty else { return SplitResult(matched: false, command: "") }

        // Normalise each word independently for wake-phrase matching only
        let normWords = originalWords.map(normWord)

        // Wake phrase patterns (normalised).
        // "ok cou cou" handled as a 3-token pattern in case the STT splits it.
        let patterns: [[String]] = ["ei", "oi", "ok", "hey"].flatMap { p in names.map { [p] + $0 } }

        // Find LAST occurrence of any pattern
        var lastMatchEnd: Int? = nil   // word index immediately after the matched pattern

        for pattern in patterns {
            guard normWords.count >= pattern.count else { continue }
            var i = 0
            while i <= normWords.count - pattern.count {
                if matches(Array(normWords[i ..< i + pattern.count]), pattern) {
                    let end = i + pattern.count
                    if lastMatchEnd == nil || end > lastMatchEnd! { lastMatchEnd = end }
                    i = end   // resume search after this match
                } else {
                    i += 1
                }
            }
        }

        guard let end = lastMatchEnd else { return SplitResult(matched: false, command: "") }

        let tail = Array(originalWords[end...])
        guard !tail.isEmpty else { return SplitResult(matched: true, command: "") }

        // Strip leading punctuation from the first command word
        var first = tail[0]
        while let c = first.first, !c.isLetter && !c.isNumber { first = String(first.dropFirst()) }

        let parts = ([first] + Array(tail.dropFirst())).filter { !$0.isEmpty }
        return SplitResult(matched: true, command: parts.joined(separator: " "))
    }

    /// The names Cloud answers to (Settings → Voz → Nome), each split into normalised words.
    /// Set by the app; the default covers how "Cloud" comes out of the recognizer in Portuguese.
    nonisolated(unsafe) static var names: [[String]] = parseNames(defaultNames)
    static let defaultNames = "Cloud, Claude, Claudio, iCloud, Claud, Clouds, Clawd"

    static func parseNames(_ csv: String) -> [[String]] {
        let list = csv.split(separator: ",")
            .map { $0.split(whereSeparator: \.isWhitespace).map { normWord(String($0)) }.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
        return list.isEmpty ? parseNames(defaultNames) : list
    }

    /// The prefix ("ei", "oi"…) must match exactly; a name word may be off by a letter or two
    /// ("Claudia", "Klaud" for "Claudio", "Cloud"), since the recognizer guesses at names.
    static func matches(_ words: [String], _ pattern: [String]) -> Bool {
        guard words.count == pattern.count, words.first == pattern.first else { return false }
        for (w, p) in zip(words.dropFirst(), pattern.dropFirst()) where w != p {
            let allowed = p.count >= 6 ? 2 : (p.count >= 4 ? 1 : 0)
            guard allowed > 0, abs(w.count - p.count) <= allowed, distance(w, p) <= allowed else { return false }
        }
        return true
    }

    /// Levenshtein distance, small strings only.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var prev = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return a.isEmpty ? b.count : (b.isEmpty ? a.count : prev[b.count])
    }

    /// Normalise a string for cancel-phrase comparison: lowercase + strip punctuation.
    static func normalise(_ s: String) -> String {
        s.lowercased()
         .components(separatedBy: .punctuationCharacters)
         .joined()
         .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Private

    /// Normalise a single word token for wake-phrase matching.
    private static func normWord(_ w: String) -> String {
        var t = normalise(w)
        if ["okay", "okey"].contains(t) { t = "ok" }
        if ["hei", "ey", "eí", "ê", "é", "eii", "êi"].contains(t) { t = "ei" }
        // Accents don't count: "Cláudio" = "claudio".
        return t.folding(options: .diacriticInsensitive, locale: nil)
    }
}

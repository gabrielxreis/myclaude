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
        // Greeting + name: "ei/hey/oi/ok/olá/alô/fala/opa/e aí <nome>".
        let patterns: [[String]] = prefixes.flatMap { p in names.map { p + $0 } }

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
    /// The same names as typed (for the recognizer's hints), set with `names`.
    nonisolated(unsafe) static var hintNames: [String] = defaultNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    static let defaultNames = "Cloud, Claude, Claudio, iCloud, Claud, Clouds, Clawd"

    static func parseNames(_ csv: String) -> [[String]] {
        let list = csv.split(separator: ",")
            .map { $0.split(whereSeparator: \.isWhitespace).map { normWord(String($0)) }.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
        return list.isEmpty ? parseNames(defaultNames) : list
    }

    /// The prefix ("ei", "oi"…) must match exactly; a name word may be off by a letter or two
    /// ("Claudia", "Klaud" for "Claudio", "Cloud"), since the recognizer guesses at names.
    /// The greetings that come before the name (normalised; "e aí" is two words).
    static let prefixes: [[String]] = [["ei"], ["oi"], ["ok"], ["hey"], ["ola"], ["alo"], ["fala"], ["opa"], ["ei", "ai"], ["eai"]]

    static func matches(_ words: [String], _ pattern: [String]) -> Bool {
        guard words.count == pattern.count else { return false }
        // The greeting words must match exactly; the name may be off by a letter or two.
        let greeting = prefixes.first { Array(pattern.prefix($0.count)) == $0 }?.count ?? 1
        guard Array(words.prefix(greeting)) == Array(pattern.prefix(greeting)) else { return false }
        for (w, p) in zip(words.dropFirst(greeting), pattern.dropFirst(greeting)) where w != p {
            let allowed = p.count >= 6 ? 2 : (p.count >= 4 ? 1 : 0)
            let closeSpelling = allowed > 0 && abs(w.count - p.count) <= allowed && distance(w, p) <= allowed
            // Different letters, same sound ("tasque" for "task"): also a match.
            guard closeSpelling || soundsLike(w, p) else { return false }
        }
        return true
    }

    // MARK: - Sound of a name (pt-BR)

    /// A rough pronunciation key, so different spellings of the same sound match:
    /// "task" = "tasque" = "tasqui" = "tasc", "cloud" = "claud", "kiko" = "quico".
    static func soundKey(_ w: String) -> String {
        var s = w.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter }
        let pairs: [(String, String)] = [
            ("sch", "x"), ("sh", "x"), ("ch", "x"), ("ph", "f"), ("th", "t"), ("ck", "k"),
            ("qu", "k"), ("gue", "ge"), ("gui", "gi"), ("lh", "l"), ("nh", "n"), ("ss", "s"),
            ("ou", "o"), ("ow", "o"), ("au", "o"), ("oo", "u"), ("ee", "i"), ("ea", "i"),
            ("w", "u"), ("y", "i"), ("z", "s"), ("q", "k"),
        ]
        for (a, b) in pairs { s = s.replacingOccurrences(of: a, with: b) }
        // c: "s" before e/i, else "k"; h is silent.
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if c == "h" { continue }
            if c == "c" {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                out.append(next == "e" || next == "i" ? "s" : "k")
                continue
            }
            // Unstressed Portuguese vowels: e sounds like i, o like u.
            out.append(c == "e" ? "i" : c == "o" ? "u" : c)
        }
        // Doubled letters count once; a final vowel after a consonant is how Portuguese ends
        // a foreign word ("task" said "tasqui"), so it is dropped.
        var dedup = ""
        for c in out where dedup.last != c { dedup.append(c) }
        if dedup.count > 3, let last = dedup.last, "iu".contains(last),
           let prev = dedup.dropLast().last, !"aiu".contains(prev) { dedup.removeLast() }
        return dedup
    }

    /// Same sound, give or take one letter (names of 4+ sounds).
    static func soundsLike(_ heard: String, _ name: String) -> Bool {
        let a = soundKey(heard), b = soundKey(name)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return b.count >= 4 && abs(a.count - b.count) <= 1 && distance(a, b) <= 1
    }

    /// Spellings the recognizer may write for `name` in Portuguese (hints and extra names).
    static func spellingVariants(_ name: String) -> [String] {
        let base = name.trimmingCharacters(in: .whitespaces)
        guard base.count >= 3, !base.contains(" ") else { return [] }
        let n = base.lowercased()
        var out = Set<String>()
        func add(_ s: String) { if s != n && s.count >= 3 { out.insert(s) } }
        // Final consonant gets a vowel ("task" → "tasque", "tasqui", "taske").
        if let last = n.last, !"aeiou".contains(last) {
            if last == "k" || last == "c" {
                let stem = String(n.dropLast())
                ["que", "qui", "ke", "ky", "c"].forEach { add(stem + $0) }
            } else {
                add(n + "e"); add(n + "i")
            }
        }
        // English vowels the way they are said ("task" → "tesk", "cloud" → "claud", "clau").
        let swaps: [(String, String)] = [("a", "e"), ("ou", "au"), ("oo", "u"), ("ee", "i"),
                                          ("k", "c"), ("c", "k"), ("w", "u"), ("y", "i"), ("ph", "f"),
                                          ("th", "t"), ("i", "e"), ("o", "u")]
        for (a, b) in swaps where n.contains(a) {
            add(n.replacingOccurrences(of: a, with: b))
        }
        if n.hasSuffix("oud") { add(String(n.dropLast(3)) + "audio"); add(String(n.dropLast(3)) + "au") }
        // Plural and diminutive the recognizer likes to add.
        add(n + "s")
        if (n.hasSuffix("o") || n.hasSuffix("a")) && !n.hasSuffix("inho") && !n.hasSuffix("inha") { add(String(n.dropLast()) + "inho") }
        return out.sorted().prefix(12).map { $0.prefix(1).uppercased() + $0.dropFirst() }
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
        // The recognizer often writes "Ei" as "Em", "Hein" or "Eis" ("Ei Task" → "Em teste"):
        // only a greeting when the name follows, so "em casa" never wakes it.
        if ["hei", "ey", "eí", "ê", "é", "eii", "êi", "em", "hein", "eis", "ein", "e"].contains(t) { t = "ei" }
        if ["hi", "hello", "hay"].contains(t) { t = "hey" }
        // Accents don't count: "Cláudio" = "claudio".
        return t.folding(options: .diacriticInsensitive, locale: nil)
    }
}

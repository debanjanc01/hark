import AppKit

/// Fixes developer terms the speech model mishears, like "cube cuttle" for kubectl.
///
/// Biasing the model towards these words also changes what it hears in ordinary speech
/// ("the docker did stop" became "the Docker Desktop"), so this works on the finished text
/// instead. A run of words becomes a term only when it sounds like one and the rest agrees:
/// the words around it fit, it isn't a dictionary word, or the model itself wasn't sure.
public struct DeveloperWords: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let term: String
        /// How it's said. Anything beyond the built-in forms came from the person, and is
        /// always swapped when heard word for word.
        public let soundsLike: [String]
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// One entry per line: `term: sounds like, sounds like`.
    public init(list: String) {
        entries = list.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let term = parts.first?.trimmingCharacters(in: .whitespaces), !term.isEmpty else { return nil }
            let forms = parts.count > 1 ? parts[1].split(separator: ",") : []
            return Entry(term: term, soundsLike: forms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
    }

    public var list: String {
        entries.map { $0.soundsLike.isEmpty ? $0.term : "\($0.term): \($0.soundsLike.joined(separator: ", "))" }
            .joined(separator: "\n")
    }

    public static let defaults = DeveloperWords(entries: builtIn.map { Entry(term: $0.term, soundsLike: $0.says) })

    /// What to paste for a transcript. Only English is corrected: the sounds are matched as English.
    /// - Parameter keeping: the person's Custom Words. Those are never replaced, and their
    ///   spelling of a term wins.
    @MainActor
    public func correct(_ transcript: Transcript, keeping customWords: [String] = []) -> String {
        guard transcript.language == "en", !entries.isEmpty else { return transcript.text }
        let words = transcript.words.flatMap { $0.isEmpty ? nil : $0 }
            ?? transcript.text.split(separator: " ").map { Transcript.Word(word: String($0), probability: nil) }
        return correct(words, keeping: customWords) ?? transcript.text
    }

    /// The corrected text, or nil when nothing changed.
    @MainActor
    private func correct(_ words: [Transcript.Word], keeping customWords: [String]) -> String? {
        let cleaned = words.map { Self.clean($0.word) }
        let lowered = cleaned.map { $0.lowercased() }
        var checked: [String: Bool] = [:]
        let rules = entries.map(Rule.init)
        // A custom word that is itself a term only sets its spelling.
        let kept = Set(customWords.map { $0.lowercased() }.filter { word in !rules.contains { $0.term.lowercased() == word } }
            .map { $0.filter { !$0.isWhitespace } })

        // Spell checking is the slowest step here, so only ask about words that sound like a term.
        func isOdd(_ index: Int) -> Bool {
            if cleaned[index].dropFirst().contains(where: \.isUppercase) { return true }
            let word = lowered[index]
            if let known = checked[word] { return !known }
            let known = Self.isKnownWord(word)
            checked[word] = known
            return !known
        }

        var matches: [(score: Double, start: Int, count: Int, term: String)] = []
        let longest = max(4, rules.flatMap(\.aliases).map(\.count).max() ?? 0)
        for count in 1...longest where count <= words.count {
            for start in 0...(words.count - count) {
                let span = start..<(start + count)
                // A sentence boundary inside the span means it isn't one term.
                if words[start..<(span.upperBound - 1)].contains(where: { $0.word.last.map(Self.endsClause) == true }) { continue }
                if span.contains(where: { cleaned[$0].isEmpty }) { continue }

                let said = Array(lowered[span])
                for rule in rules where rule.aliases.contains(said) {
                    matches.append((2, start, count, rule.term))
                }
                guard count <= 4,
                      !said.contains(where: kept.contains), !kept.contains(said.joined()) else { continue }

                let whole = count == words.count
                if !whole, said.contains(where: Self.commonWords.contains) { continue }

                let sound = Self.key(cleaned[span].joined(separator: " "))
                let joined = said.joined()
                let before = lowered[max(0, start - 4)..<start]
                let after = lowered[span.upperBound..<min(words.count, span.upperBound + 4)]
                let unsure = words[span].contains { ($0.probability ?? 0) < Self.unsureBelow }

                for rule in rules {
                    let exact = rule.spellings.contains(joined)
                    // Too few sounds to compare ("email" and YAML): only a listed spelling counts.
                    if !exact, sound.count < 3 || rule.shortestSound < 3 { continue }
                    if count > rule.wordsSaid + 1 { continue }
                    if !rule.sounds.contains(where: { $0.first == sound.first }) { continue }
                    let similarity = rule.similarity(to: sound, exact: exact)
                    if similarity < 0.62 { continue }

                    let inContext = !rule.context.isDisjoint(with: before) || !rule.context.isDisjoint(with: after)
                    let accepted: Bool
                    if span.upperBound < words.count, rule.notBefore.contains(lowered[span.upperBound]) {
                        accepted = false  // "Jason sent me the file" is a person
                    } else if rule.risky {
                        accepted = inContext && similarity >= 0.85
                    } else {
                        let odd = span.contains { isOdd($0) }
                        accepted = (inContext && (odd || unsure))
                            || (whole && similarity >= 0.70 && (odd || unsure))
                            || (odd && similarity >= 0.85 && unsure)
                            || (similarity >= 0.95 && span.allSatisfy { isOdd($0) })
                    }
                    if accepted { matches.append((similarity, start, count, rule.term)) }
                }
            }
        }

        var used = Set<Int>()
        var edits: [(start: Int, count: Int, term: String)] = []
        let ranked = matches.enumerated().sorted { a, b in
            (-a.element.score, -a.element.count, a.offset) < (-b.element.score, -b.element.count, b.offset)
        }
        for (_, match) in ranked {
            let span = match.start..<(match.start + match.count)
            if span.contains(where: used.contains) { continue }
            used.formUnion(span)
            edits.append((match.start, match.count, match.term))
        }
        guard !edits.isEmpty else { return nil }

        var output = words.map(\.word)
        for edit in edits.sorted(by: { $0.start > $1.start }) {
            let spelled = customWords.first { $0.lowercased() == edit.term.lowercased() } ?? edit.term
            let last = output[edit.start + edit.count - 1]
            let tail = last.reversed().prefix { !Self.isWordCharacter($0) && $0 != "'" }.reversed()
            output.replaceSubrange(edit.start..<(edit.start + edit.count), with: [spelled + String(tail)])
        }
        return output.joined(separator: " ")
    }

    // MARK: Rules

    private static let unsureBelow = 0.75
    private static let commonWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "to", "in", "on", "of", "for", "and", "or", "at", "it",
        "that", "this", "we", "you", "i", "my", "your", "our", "with", "from", "by", "as", "be",
    ]

    /// An entry, ready for matching.
    private struct Rule {
        let term: String
        let sounds: [String]
        let spellings: Set<String>
        let shortestSound: Int
        let wordsSaid: Int
        let aliases: [[String]]
        let context: Set<String>
        let risky: Bool
        let notBefore: Set<String>

        init(_ entry: Entry) {
            term = entry.term
            let builtIn = DeveloperWords.builtIn.first { $0.term.lowercased() == entry.term.lowercased() }
            let builtInForms = Set(builtIn?.says.map { $0.lowercased() } ?? [])
            let forms = entry.soundsLike.filter { builtInForms.contains($0.lowercased()) || $0.lowercased() == entry.term.lowercased() }
            let said = forms.isEmpty ? [entry.term] : forms
            sounds = said.map(DeveloperWords.key)
            spellings = Set((said + [entry.term]).map { $0.lowercased().filter { $0.isLetter || $0.isNumber } })
            shortestSound = sounds.map(\.count).min() ?? 0
            wordsSaid = said[0].split(separator: " ").count
            aliases = entry.soundsLike.filter { !forms.contains($0) }.map { alias in
                alias.split(separator: " ").map { DeveloperWords.clean(String($0)).lowercased() }
            }
            context = builtIn?.context ?? []
            risky = builtIn?.risky ?? false
            notBefore = builtIn?.notBefore ?? []
        }

        func similarity(to sound: String, exact: Bool) -> Double {
            if exact { return 1 }
            return sounds.map { 1 - Double(DeveloperWords.distance(sound, $0)) / Double(max(sound.count, $0.count)) }.max() ?? 0
        }
    }

    private struct BuiltIn: Sendable {
        let term: String
        let says: [String]
        let context: Set<String>
        var risky = false
        var notBefore: Set<String> = []
    }

    /// `says` is how a term is spoken, written the way the model tends to spell it.
    /// `context` holds words that only make sense near the term; `risky` terms also sound
    /// like everyday words ("sequel", "Jason"), so they aren't changed without one.
    private static let builtIn: [BuiltIn] = [
        BuiltIn(term: "kubectl", says: ["kube C T L", "kube control", "kube cuttle", "kube cuddle"],
                context: ["pods", "pod", "logs", "namespace", "deployment", "cluster", "describe", "exec", "rollout", "container", "apply"]),
        BuiltIn(term: "k8s", says: ["K eights", "K eight S", "K8s"],
                context: ["cluster", "node", "pod", "deployment", "helm"], risky: true),
        BuiltIn(term: "Docker Desktop", says: ["Docker Desktop"],
                context: ["open", "restart", "install", "installed", "launch", "quit", "running"]),
        BuiltIn(term: "Kubernetes", says: ["Kubernetes", "kuber netes", "cuber nettys"],
                context: ["cluster", "deploy", "dashboard", "pod"]),
        BuiltIn(term: "nginx", says: ["engine X"], context: ["restart", "reload", "config", "proxy", "server"]),
        BuiltIn(term: "Postgres", says: ["Postgres", "post gres", "PostgreSQL"], context: ["database", "table", "migrate", "port"]),
        BuiltIn(term: "Redis", says: ["Redis", "red iss"], context: ["cache", "session", "flush", "memory"]),
        BuiltIn(term: "JSON", says: ["Jason", "J son"], context: ["parse", "endpoint", "api", "schema", "validate", "convert"], risky: true,
                notBefore: ["sent", "said", "told", "called", "asked", "wrote", "is", "was", "and"]),
        BuiltIn(term: "YAML", says: ["yamel", "Yaml", "yammel"], context: ["indentation", "config", "workflow", "file"]),
        BuiltIn(term: "npm", says: ["N P M"], context: ["install", "publish", "packages", "build"]),
        BuiltIn(term: "SQL", says: ["sequel", "S Q L"], context: ["query", "migration", "database", "index", "join", "table"], risky: true),
        BuiltIn(term: "sudo", says: ["sue doe", "sudo"], context: ["command", "reboot", "apt"]),
        BuiltIn(term: "chmod", says: ["C H mod", "change mod", "chmod"], context: ["script", "executable", "seven"]),
        BuiltIn(term: "regex", says: ["reg ex", "regex"], context: ["emails", "greedy"]),
        BuiltIn(term: "GitHub", says: ["git hub", "github"], context: ["push", "pull", "action", "issue"]),
        BuiltIn(term: "OAuth", says: ["oh auth", "o auth"], context: ["login", "token", "callback"]),
        BuiltIn(term: "localhost", says: ["local host"], context: ["port", "bind", "curl"], risky: true),
        BuiltIn(term: "Terraform", says: ["terra form", "terraform"], context: ["plan", "state", "module", "locked"]),
        BuiltIn(term: "Homebrew", says: ["home brew", "homebrew"], context: ["install", "formula", "update"], risky: true),
        BuiltIn(term: "Claude Code", says: ["Claude Code"], context: ["terminal", "tests"]),
    ]

    // MARK: Text

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func endsClause(_ character: Character) -> Bool {
        ".,;:!?".contains(character)
    }

    /// The word without the punctuation around it.
    private static func clean(_ word: String) -> String {
        var text = Substring(word)
        text = text.drop { !isWordCharacter($0) }
        while let last = text.last, !isWordCharacter(last), last != "'" { text.removeLast() }
        return String(text)
    }

    /// Asks the Mac's English spell checker, which knows modern words and plurals.
    @MainActor
    private static func isKnownWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false,
                                            inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }

    /// A rough spelling of the consonants: "cube cuttle" and "kube cuddle" come out the same.
    static func key(_ text: String) -> String {
        var sounds: [UInt8] = []
        for word in text.utf8.split(whereSeparator: { !isASCIIAlphanumeric($0) && $0 != apostrophe }) {
            var spelled = spellOut(Array(word)).filter { $0 != apostrophe }
            for (from, to) in [("ph", "f"), ("ck", "k"), ("gh", ""), ("sh", "s"), ("ch", "k")] {
                spelled = replacing(Array(from.utf8), with: Array(to.utf8), in: spelled)
            }
            for (index, letter) in spelled.enumerated() {
                let next = index + 1 < spelled.count ? spelled[index + 1] : 0
                let soft = letter == ascii("c") && [ascii("e"), ascii("i"), ascii("y")].contains(next)
                let startsWord = letter == ascii("x") && (index == 0 || spelled[index - 1] == ascii(" "))
                let classes = soft || startsWord ? [ascii("s")] : soundClasses[letter] ?? [letter]
                for sound in classes where !silentLetters.contains(sound) && sounds.last != sound {
                    sounds.append(sound)
                }
            }
        }
        return String(decoding: sounds, as: UTF8.self)
    }

    private static let apostrophe = ascii("'")
    private static let silentLetters = Set("aeiouywh ".utf8)

    private static func ascii(_ character: Character) -> UInt8 {
        character.asciiValue ?? 0
    }

    private static func isUpper(_ byte: UInt8) -> Bool { (65...90).contains(byte) }
    private static func isLower(_ byte: UInt8) -> Bool { (97...122).contains(byte) }
    private static func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool { isUpper(byte) || isLower(byte) || isDigit(byte) }

    private static func replacing(_ from: [UInt8], with to: [UInt8], in bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index...].starts(with: from) {
                output += to
                index += from.count
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return output
    }

    private static let soundClasses: [UInt8: [UInt8]] = [
        ascii("c"): [ascii("k")], ascii("q"): [ascii("k")], ascii("g"): [ascii("k")], ascii("j"): [ascii("k")],
        ascii("b"): [ascii("p")], ascii("d"): [ascii("t")], ascii("z"): [ascii("s")], ascii("v"): [ascii("f")],
        ascii("x"): [ascii("k"), ascii("s")],
    ]

    private static let letterNames: [UInt8: [UInt8]] = Dictionary(uniqueKeysWithValues: [
        "ay", "bee", "see", "dee", "ee", "ef", "jee", "aych", "eye", "jay", "kay", "el", "em",
        "en", "oh", "pee", "kyu", "ar", "es", "tee", "yu", "vee", "dub", "ex", "wy", "zee",
    ].enumerated().map { (UInt8(97 + $0.offset), Array($0.element.utf8)) })

    /// Short all-caps parts are said letter by letter: "CubeCTL" is "cube see tee el".
    private static func spellOut(_ word: [UInt8]) -> [UInt8] {
        var parts: [[UInt8]] = []
        var index = 0
        while index < word.count {
            let start = index
            if isUpper(word[index]) {
                while index < word.count, isUpper(word[index]) { index += 1 }
                // The last capital of "HTTPServer" starts the next part.
                if index - start >= 2, index < word.count, isLower(word[index]) { index -= 1 }
                if index - start >= 2 {
                    if index - start <= 4 {
                        parts += word[start..<index].compactMap { letterNames[$0 + 32] }
                    } else {
                        parts.append(word[start..<index].map { $0 + 32 })
                    }
                    continue
                }
                index = start
                if index + 1 < word.count, isLower(word[index + 1]) {
                    index += 1
                    while index < word.count, isLower(word[index]) { index += 1 }
                    parts.append([word[start] + 32] + word[(start + 1)..<index])
                } else {
                    index += 1
                    if let name = letterNames[word[start] + 32] { parts.append(name) }
                }
            } else if isLower(word[index]) {
                while index < word.count, isLower(word[index]) { index += 1 }
                parts.append(Array(word[start..<index]))
            } else if isDigit(word[index]) {
                while index < word.count, isDigit(word[index]) { index += 1 }
                parts.append(Array(word[start..<index]))
            } else {
                index += 1
            }
        }
        return Array(parts.joined(separator: [ascii(" ")]))
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let b = Array(b.utf8)
        var previous = Array(0...b.count)
        var current = previous
        for (i, x) in a.utf8.enumerated() {
            current[0] = i + 1
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

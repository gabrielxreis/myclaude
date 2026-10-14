#if !APPSTORE
import AVFoundation
import Speech

// MARK: - Teaching the name (Settings → Assistente → Ensinar o nome)
//
// The recognizer writes a name its own way ("Task" comes out "teste" in Portuguese). Here I say
// "Ei <nome>" a few times; each take is transcribed on this Mac with the chosen microphone, and
// the word after the greeting becomes one of the other spellings, so the next call wakes it.

@MainActor
final class NameTrainer: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var heard: [String] = []      // full transcripts, for display
    @Published private(set) var learned: [String] = []    // spellings found

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var last = ""

    /// One take of about 3 seconds.
    func record() {
        guard !listening,
              let r = SFSpeechRecognizer(locale: Locale(identifier: VoiceSettings.listenLanguage == "en" ? "en-US" : "pt-BR")),
              r.isAvailable else { return }
        let e = AVAudioEngine()
        let input = e.inputNode
        AudioInputDevices.apply(to: input.audioUnit)
        let hw = input.inputFormat(forBus: 0)
        let fmt = hw.sampleRate > 0 ? hw : input.outputFormat(forBus: 0)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = r.supportsOnDeviceRecognition
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in req.append(buf) }
        do { e.prepare(); try e.start() } catch { return }
        engine = e; request = req; last = ""; listening = true
        task = r.recognitionTask(with: req) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in self?.last = text }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in self?.stop() }
    }

    private func stop() {
        guard listening else { return }
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // The last words arrive just after the audio ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.task?.cancel()
            self.engine = nil; self.request = nil; self.task = nil
            self.listening = false
            let text = self.last.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { self.heard.append("(não ouvi nada)"); return }
            self.heard.append(text)
            if let word = Self.nameWord(in: text), !self.learned.contains(word) { self.learned.append(word) }
        }
    }

    /// The word(s) after the greeting: "E aí teste" → "teste", "Ei Tasque" → "Tasque".
    static func nameWord(in text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
        let norm = words.map { $0.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
        for p in WakePhrase.prefixes {
            for i in 0..<max(0, norm.count - p.count) where Array(norm[i..<(i + p.count)]) == p {
                return words[i + p.count]
            }
        }
        // No greeting heard: the take was probably just the name.
        return words.count == 1 ? words[0] : nil
    }

    /// Adds what was learned to the other spellings.
    func save() {
        var list = VoiceSettings.wakeNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for w in learned where !list.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) { list.append(w) }
        VoiceSettings.wakeNames = list.joined(separator: ", ")
        appendAppLog("nb.log", "[Voice] name taught: \(learned)")
    }

    func clear() { heard = []; learned = [] }
}
#endif

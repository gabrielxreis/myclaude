#if !APPSTORE
import Foundation
import Speech

// MARK: - Transcribing a file on this Mac
//
// Apple's on-device recognizer (pt-BR, falls back to the Mac's language): no upload, no credits.

enum FileTranscriber {
    static func transcribe(_ audio: URL) async -> String? {
        let locale = Locale(identifier: VoiceSettings.listenLanguage == "en" ? "en-US" : "pt-BR")
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else { return nil }
        let req = SFSpeechURLRecognitionRequest(url: audio)
        req.requiresOnDeviceRecognition = r.supportsOnDeviceRecognition
        // The on-device recognizer restarts after each pause: keep every segment, not only the last.
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            var finished = false
            var committed = "", current = ""
            func finish() {
                guard !finished else { return }
                finished = true
                let text = (committed + " " + current).trimmingCharacters(in: .whitespaces)
                cont.resume(returning: text.isEmpty ? nil : text)
            }
            r.recognitionTask(with: req) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    // A new segment: the text no longer continues the previous one.
                    if !current.isEmpty && !text.hasPrefix(String(current.prefix(max(1, min(current.count, text.count) / 2)))) {
                        committed += (committed.isEmpty ? "" : " ") + current
                    }
                    current = text
                    if result.isFinal { finish() }
                } else if error != nil {
                    finish()
                }
            }
        }
    }
}
#endif

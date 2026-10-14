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
            // The recognizer calls back on its own queue: the state is behind a lock, and a
            // time limit ends it even if the recognizer never answers (the card job would hang).
            final class State: @unchecked Sendable {
                let lock = NSLock()
                var finished = false
                var committed = "", current = ""
            }
            let st = State()
            let finish: @Sendable () -> Void = {
                st.lock.lock()
                guard !st.finished else { st.lock.unlock(); return }
                st.finished = true
                let text = (st.committed + " " + st.current).trimmingCharacters(in: .whitespaces)
                st.lock.unlock()
                cont.resume(returning: text.isEmpty ? nil : text)
            }
            let task = r.recognitionTask(with: req) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    st.lock.lock()
                    // A new segment: the text no longer continues the previous one.
                    let cur = st.current
                    if !cur.isEmpty && !text.hasPrefix(String(cur.prefix(max(1, min(cur.count, text.count) / 2)))) {
                        st.committed += (st.committed.isEmpty ? "" : " ") + cur
                    }
                    st.current = text
                    st.lock.unlock()
                    if result.isFinal { finish() }
                } else if error != nil {
                    finish()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 900) {
                task.cancel()
                finish()
            }
        }
    }
}
#endif

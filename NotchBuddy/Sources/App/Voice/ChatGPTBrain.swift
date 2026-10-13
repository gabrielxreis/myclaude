#if !APPSTORE
import Foundation

// MARK: - ChatGPT for questions
//
// Questions and research go to ChatGPT through the Codex CLI (`codex exec`), signed in with
// the user's ChatGPT account: it runs on the ChatGPT plan, no API key, no credits. Read-only
// sandbox with web search. Anything to *do* stays with Claude (ClaudeCLIBrain).

@MainActor
enum ChatGPTBrain {

    static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static var isAvailable: Bool { executable != nil }

    /// Settings → Voz: who answers questions, "chatgpt" (default when Codex is installed) or "claude".
    static var answersQuestions: Bool {
        isAvailable && (UserDefaults.standard.string(forKey: "cloudQuestionsProvider") ?? "chatgpt") == "chatgpt"
    }

    /// A question or a lookup, not something to do: "quem ganhou…", "o que é…", "quanto custa…?".
    static func isQuestion(_ text: String) -> Bool {
        let n = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("/") { return false }   // a skill
        let doing = ["abre", "abrir", "cria", "criar", "faz ", "fazer", "edita", "editar", "roda ", "rodar",
                     "manda", "mandar", "legenda", "coloca", "apaga", "instala", "salva", "escreve",
                     "renderiza", "exporta", "corta", "monta", "gera ", "gerar", "skill", "ogab", "ojhon"]
        if doing.contains(where: { n.hasPrefix($0) || n.contains(" " + $0) }) { return false }
        let asks = ["o que", "oque", "quem", "quanto", "quantos", "quantas", "qual", "quais", "como ", "por que",
                    "porque", "quando", "onde", "me explica", "me fala", "me diz", "explica", "sabe ",
                    "voce sabe", "pesquisa sobre", "pesquise sobre", "noticias", "previsao", "cotacao"]
        return n.hasSuffix("?") || asks.contains { n.hasPrefix($0) || n.contains(" " + $0) }
    }

    /// Asks ChatGPT. nil on failure (logged).
    static func ask(_ question: String, voice: Bool) async -> String? {
        guard let exe = executable else { return nil }
        let style = voice
            ? "Responda em português do Brasil em uma ou duas frases curtas, sem markdown, sem links e sem travessão."
            : "Responda em português do Brasil, direto ao ponto, sem travessão. Pode usar markdown."
        let prompt = "\(style) Pesquise na web quando a resposta puder ter mudado.\n\nPergunta: \(question)"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("mycloud-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: out) }
        let args = ["exec", "--skip-git-repo-check", "--sandbox", "read-only",
                    "-c", "tools.web_search=true", "-c", "model_reasoning_effort=low",
                    "-o", out.path, prompt]
        let t0 = Date()
        let ok = await Task.detached { () -> Bool in
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return false }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 180, execute: killer)
            p.waitUntilExit()
            killer.cancel()
            return p.terminationReason == .exit && p.terminationStatus == 0
        }.value
        let text = (try? String(contentsOf: out, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        appendAppLog("nb.log", "[Cloud] ChatGPT \(Int(Date().timeIntervalSince(t0)))s ok=\(ok)")
        return ok && !text.isEmpty ? text : nil
    }
}
#endif

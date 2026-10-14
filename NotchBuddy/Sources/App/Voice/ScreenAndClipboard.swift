#if !APPSTORE
import AppKit

// MARK: - Looking at the screen, recording it, and the clipboard
//
// "que erro é esse?", "olha minha tela"   → a screenshot Claude reads and explains
// "grava a tela" / "para de gravar"        → macOS's own screen recording, saved in Movies/My Cloud
// "traduz / resume / corrige o que eu copiei" → done by Claude, the result goes back to the clipboard
// "traduz essa página"                     → the open page through Google Translate

@MainActor
final class ScreenTools: ObservableObject {
    static let shared = ScreenTools()

    @Published private(set) var recordingSince: Date?
    private var recorder: Process?
    private var recordingURL: URL?

    /// The line the notch shows while recording.
    var recordingLine: String? {
        guard let since = recordingSince else { return nil }
        let s = Int(Date().timeIntervalSince(since))
        return String(format: "Gravando a tela: %d:%02d", s / 60, s % 60)
    }

    // MARK: Reading the screen

    static func isLookRequest(_ n: String) -> Bool {
        ["que erro e esse", "olha minha tela", "olha a minha tela", "olha a tela", "le a tela", "le minha tela",
         "analisa a tela", "analisa minha tela", "o que ta na tela", "o que esta na tela", "o que e isso na tela",
         "o que aparece na tela", "ve minha tela", "ve a tela", "que mensagem e essa", "o que significa isso na tela"]
            .contains { n.contains($0) }
    }

    /// A screenshot of the main display, and the request for Claude to read it ([tela] keeps it with Claude).
    static func lookRequest(_ question: String) -> (reply: String, rest: String?) {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("mycloud-tela-\(Int(Date().timeIntervalSince1970)).png").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-m", path]
        do { try p.run() } catch { return ("Não consegui ver a tela.", nil) }
        p.waitUntilExit()
        guard FileManager.default.fileExists(atPath: path) else {
            return ("Não consegui ver a tela. Libere o My Cloud em Ajustes do Sistema, Privacidade, Gravação de Tela.", nil)
        }
        CloudMissions.shared.record(.tela)
        // The screenshot is only for Claude to read: gone after 10 minutes (it may show private things).
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { try? FileManager.default.removeItem(atPath: path) }
        return ("Deixa eu ver…",
                "[tela] Leia a imagem da tela do usuário em \(path) com a ferramenta Read e responda ao que ele perguntou: \"\(question)\". Se for um erro, diga o que significa e como resolver, em passos curtos.")
    }

    // MARK: Recording the screen

    static func isRecordRequest(_ n: String) -> Bool {
        let aboutRecording = n.contains("grava") || n.contains("gravar") || n.contains("gravacao")
        // While recording, "para de gravar" (no "tela") must reach it too: it's what Cloud tells me to say.
        return aboutRecording && (n.contains("tela") || shared.recorder != nil)
    }

    func record(_ n: String) -> String {
        // "grava a tela para mim" starts; only an explicit stop stops.
        let stop = ["para de gravar", "parar de gravar", "pare de gravar", "para a gravacao", "parar a gravacao",
                    "termina", "terminar", "encerra", "finaliza", "stop"].contains { n.contains($0) }
        if stop {
            guard let rec = recorder, let url = recordingURL else { return "Não estou gravando a tela." }
            rec.interrupt()          // screencapture -v stops and writes the movie on SIGINT
            recorder = nil; recordingSince = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            appendAppLog("nb.log", "[Cloud] screen recording stop \(url.path)")
            return "Parei. A gravação está em Filmes, My Cloud."
        }
        guard recorder == nil else { return "Já estou gravando. Diz \"para de gravar\" quando quiser." }
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("My Cloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = dir.appendingPathComponent("Gravação \(f.string(from: Date())).mov")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-v", "-x"] + (n.contains("audio") || n.contains("som") ? ["-g"] : []) + [url.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "Não consegui começar a gravar." }
        recorder = p; recordingURL = url; recordingSince = Date()
        CloudMissions.shared.record(.tela)
        appendAppLog("nb.log", "[Cloud] screen recording start \(url.path)")
        return "Gravando a tela. Diz \"para de gravar\" quando terminar."
    }

    func stopRecordingOnQuit() {
        guard let rec = recorder else { return }
        rec.interrupt()   // screencapture writes the movie on SIGINT
        recorder = nil; recordingSince = nil
    }

    // MARK: Clipboard

    static func isClipboardRequest(_ n: String) -> Bool {
        let acts = ["traduz", "resume", "resumir", "corrige", "corrigir", "melhora", "melhorar", "explica", "explicar"]
        let what = ["que eu copiei", "que copiei", "o copiado", "area de transferencia", "clipboard", "que ta copiado", "que esta copiado"]
        return acts.contains { n.contains($0) } && what.contains { n.contains($0) }
    }

    func clipboard(_ text: String, _ n: String) -> String {
        guard let copied = NSPasteboard.general.string(forType: .string),
              !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Não tem texto copiado agora. Copia o texto e me pede de novo."
        }
        let task: String
        if n.contains("traduz") {
            let langs = ["ingles": "inglês", "espanhol": "espanhol", "frances": "francês", "italiano": "italiano", "alemao": "alemão"]
            task = langs.first { n.contains($0.key) }.map { "Traduza para \($0.value)" }
                ?? "Traduza para português do Brasil (se já estiver em português, traduza para inglês)"
        } else if n.contains("resum") {
            task = "Resuma em poucas linhas, em português"
        } else if n.contains("explica") {
            task = "Explique de forma simples, em português"
        } else {
            task = "Corrija e melhore o texto, mantendo o idioma e o tom"
        }
        let prompt = "\(task). Responda SÓ com o resultado, sem comentários.\n\n\(copied)"
        Task { @MainActor in
            // Haiku: a quick text job, it should come back in seconds.
            guard let r = await ClaudeCLIBrain.ask(prompt, sessionId: nil, voice: false, model: "haiku", timeout: 90) else { return }
            let out = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(out, forType: .string)
            SoundEngine.shared.play("approve")
            if let id = CloudChatStore.shared.voiceConversationId ?? CloudChatStore.shared.conversations.first?.id {
                CloudChatStore.shared.record(user: "(o que eu copiei) \(text)", cloud: out, in: id)
            }
            let esc = "Pronto, está copiado: \(out.prefix(120))".replacingOccurrences(of: "\"", with: "'")
            NSAppleScript(source: "display notification \"\(esc)\" with title \"My Cloud\"")?.executeAndReturnError(nil)
        }
        return "Já faço, e deixo o resultado copiado para você colar."
    }

    // MARK: Translating the page

    static func isPageTranslation(_ n: String) -> Bool {
        n.contains("traduz") && (n.contains("pagina") || n.contains("site") || n.contains("essa aba"))
    }

    func translatePage() -> String {
        guard let (url, _) = VideoIdea.currentBrowserPage(),
              let enc = CloudLocalActions.queryEncoded(url),
              let t = URL(string: "https://translate.google.com/translate?sl=auto&tl=pt&u=\(enc)") else {
            return "Não achei a página: abre ela no navegador e me pede de novo."
        }
        NSWorkspace.shared.open(t)
        return "Abrindo a página traduzida."
    }
}

// MARK: - Routines and triggers by voice (local, instant)

@MainActor
enum VoiceSetup {
    private static let days: [(String, Set<Int>)] = [
        ("todo dia", Set(1...7)), ("todos os dias", Set(1...7)), ("dias uteis", Set(2...6)), ("dia util", Set(2...6)),
        ("dias de semana", Set(2...6)), ("fim de semana", [1, 7]), ("fins de semana", [1, 7]),
        ("toda segunda", [2]), ("toda terca", [3]), ("toda quarta", [4]), ("toda quinta", [5]), ("toda sexta", [6]),
        ("todo sabado", [7]), ("todo domingo", [1]),
    ]

    /// "todo dia às 8h me dá o resumo", "toda segunda às 9 e meia, ideias de reels" → a routine.
    static func routine(_ text: String) -> String? {
        let n = CloudTimers.norm(text)
        guard let (key, set) = days.first(where: { n.hasPrefix($0.0) || n.contains(" " + $0.0) }),
              let r = n.range(of: #"\bas (\d{1,2})(?:h|:)?(\d{2})?( e meia)?"#, options: .regularExpression) else { return nil }
        let digits = n[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard var h = digits.first, h < 24 else { return nil }
        var m = digits.count > 1 ? digits[1] : 0
        if n[r].hasSuffix("e meia") { m = 30 }
        if (n.contains("da tarde") || n.contains("da noite")) && h < 12 { h += 12 }
        // The request: what comes after the time, in the original words.
        let afterIndex = n.distance(from: n.startIndex, to: r.upperBound)
        var pedido = String(text.dropFirst(min(afterIndex, text.count)))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for filler in ["da tarde", "da noite", "da manha", "me ", ",", "e "] where pedido.lowercased().hasPrefix(filler) {
            pedido = String(pedido.dropFirst(filler.count)).trimmingCharacters(in: .whitespaces)
        }
        guard pedido.count > 2 else { return nil }
        let nome = String(pedido.prefix(40))
        RoutineStore.shared.routines.append(CloudRoutine(nome: nome.prefix(1).uppercased() + nome.dropFirst(), hora: h, minuto: m, dias: set, pedido: pedido))
        return String(format: "Rotina criada: %@, às %02d:%02d, %@. Está no painel de rotinas.", pedido, h, m, key)
    }

    /// "quando eu disser modo edição, fecha o WhatsApp e abre o DaVinci" → a trigger.
    static func trigger(_ text: String) -> String? {
        let n = CloudTimers.norm(text)
        guard let r = n.range(of: #"quando eu (disser|falar) "#, options: .regularExpression) else { return nil }
        let rest = String(n[r.upperBound...])
        let seps = [", ", " faz ", " faca ", " voce ", " entao "]
        guard let sep = seps.compactMap({ rest.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let frase = String(rest[..<sep.lowerBound]).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            .replacingOccurrences(of: "\"", with: "")
        // The request in the original words (offset in n = start of rest + position in rest).
        let offset = n.distance(from: n.startIndex, to: r.upperBound) + rest.distance(from: rest.startIndex, to: sep.upperBound)
        let pedido = String(text.dropFirst(min(offset, text.count))).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !frase.isEmpty, pedido.count > 2 else { return nil }
        TriggerStore.shared.triggers.append(CloudTrigger(frase: frase, pedido: pedido))
        return "Gatilho criado: quando você disser \"\(frase)\", eu \(pedido)."
    }
}
#endif

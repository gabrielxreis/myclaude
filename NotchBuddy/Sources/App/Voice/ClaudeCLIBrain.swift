#if !APPSTORE
import Foundation

// MARK: - ClaudeCLIBrain
//
// Cloud's brain: the Claude Code CLI (`claude -p`) on the user's own Claude plan, no API key.
// Every exchange, spoken ("Ei Cloud, …") or typed in the chat window, lives in a
// CloudChatStore conversation, which keeps the CLI session id (`--resume`) so an old chat
// picks up with its full context.
//
// Phase 1: Cloud only looks things up (files, web). Tools that change anything are not in
// `allowedTools`, so `claude -p` denies them on its own and Cloud says it can't yet.
@MainActor
final class ClaudeCLIBrain {
    static let shared = ClaudeCLIBrain()

    /// Settings → Assistente: model for spoken answers (Haiku by default, the fastest).
    static var voiceModel: String { UserDefaults.standard.string(forKey: "cloudVoiceModel").flatMap { $0.isEmpty ? nil : $0 } ?? "haiku" }
    /// Settings → Assistente: model for the chat window; nil keeps Claude Code's default.
    static var chatModel: String? { UserDefaults.standard.string(forKey: "cloudChatModel").flatMap { $0.isEmpty ? nil : $0 } }
    /// Settings → Assistente: how long a spoken question may wait (actions get at least 5 min).
    static var voiceTimeout: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "cloudVoiceTimeout")
        return v > 0 ? v : 90
    }

    /// Read-only for now: nothing is edited, run or sent.
    static let allowedTools = ["Read", "Glob", "Grep", "WebSearch", "WebFetch"]

    /// The one file Cloud may write: its own quick actions.
    static var quickActionTools: [String] {
        ["acoes-rapidas.json", "rotinas.json", "gatilhos.json"].flatMap { f -> [String] in
            let p = "~/Library/Application Support/MyCloud/" + f
            return ["Edit(\(p))", "Write(\(p))"]
        }
    }

    /// A GUI app doesn't get the shell's PATH: look where the installers put `claude`.
    static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                     "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static var isAvailable: Bool { executable != nil }

    /// One spoken turn at a time: a second "Ei Cloud" during the wait must not interleave.
    private var busy = false

    /// The spoken conversation is forgotten (a new one starts next time); it stays in the history.
    func reset() { CloudChatStore.shared.voiceConversationId = nil }

    /// A spoken turn, recorded in the current voice conversation.
    func respond(to transcript: String) async -> ClaudeVoiceBrain.Reply? {
        guard Self.isAvailable else { return nil }
        // Claude still on the last request: what runs here (apps, sites, clicks, keys) runs now
        // anyway; only a part that needs Claude waits. Dropping the whole command made Cloud
        // look deaf while it was busy.
        if busy {
            let early = VoiceEngine.shared.takeEarly()
            let local = CloudLocalActions.process(transcript, early: early.status)
            let done = early.replies + local.replies
            let text = local.rest == nil
                ? (done.isEmpty ? "Pronto." : done.joined(separator: " "))
                : (done + ["Ainda estou terminando o pedido anterior; me pede o resto daqui a pouco."]).joined(separator: " ")
            appendAppLog("nb.log", "[Cloud] busy: ran locally \(done.count), rest \(local.rest == nil ? "none" : "waits")")
            return ClaudeVoiceBrain.Reply(text: text, acted: !done.isEmpty, failed: false)
        }
        busy = true
        defer { busy = false }
        let store = CloudChatStore.shared
        let id = store.voiceConversationId.flatMap { store.conversation($0)?.id }
            ?? store.newConversation(fromVoice: true)
        store.voiceConversationId = id
        // Local requests (open/quit an app, search) run here, instantly; some may already have
        // run while I was talking. Only what's left goes to Claude.
        let early = VoiceEngine.shared.takeEarly()
        let local = CloudLocalActions.process(transcript, early: early.status)
        let done = early.replies + local.replies
        guard let rest = local.rest else {
            let text = done.isEmpty ? "Pronto." : done.joined(separator: " ")
            store.record(user: transcript, cloud: text, in: id)
            return ClaudeVoiceBrain.Reply(text: text, acted: true, failed: false)
        }
        if !done.isEmpty { VoiceCaptionManager.shared.appendResponse(done.joined(separator: " ")) }
        let toChatGPT = ChatGPTBrain.answersQuestions && ChatGPTBrain.isQuestion(rest)
        if toChatGPT { VoiceCaptionManager.shared.appendResponse("Pesquisando no ChatGPT…") }
        guard let answer = await store.send(rest, in: id, voice: true) else { return nil }
        if toChatGPT { VoiceCaptionManager.shared.clearResponse() }
        let text = (done + [VoiceQuery.spokenText(answer)]).joined(separator: " ")
        return ClaudeVoiceBrain.Reply(text: text, acted: !done.isEmpty, failed: text.isEmpty)
    }

    // MARK: One call

    struct Answer { let text: String; let sessionId: String? }

    /// Asks Claude, resuming `sessionId` when given. nil on failure (logged).
    static func ask(_ prompt: String, sessionId: String?, voice: Bool, model: String? = nil,
                    timeout: TimeInterval? = nil) async -> Answer? {
        guard let exe = executable else { return nil }
        let mode = VoiceSettings.executionMode
        var args = ["-p", prompt,
                    "--output-format", "json",
                    "--append-system-prompt", systemPrompt(voice: voice, mode: mode)]
        if let m = model ?? (voice ? voiceModel : chatModel) { args += ["--model", m] }
        if let sessionId { args += ["--resume", sessionId] }
        // Only the MCP tools Cloud uses (Peekaboo, when "usar qualquer app" is on): every MCP
        // server of mine was loaded into each call (~35k tokens of tool descriptions). Skills,
        // CLAUDE.md and settings stay as they are (/ogab and /ojhon need them).
        let mcp = CloudComputerUse.active
            ? #"{"mcpServers":{"peekaboo":{"command":"npx","args":["-y","@steipete/peekaboo","mcp"]}}}"#
            : #"{"mcpServers":{}}"#
        args += ["--strict-mcp-config", "--mcp-config", mcp]
        // Settings → Assistente → "O que o Cloud pode fazer". The variadic --allowedTools goes last:
        // each rule is its own argument (rules may contain spaces).
        let screen = CloudComputerUse.allowedTools(mode: mode)   // Peekaboo, when turned on
        switch mode {
        case "automatico":   // chosen by the user in Settings, with the warning shown there
            args += ["--permission-mode", "auto"]
            if !screen.isEmpty { args += ["--allowedTools"] + screen }
        case "consultar":
            args += ["--allowedTools"] + allowedTools + quickActionTools + screen
        default:
            args += ["--allowedTools"] + VoiceSettings.allowedRules + quickActionTools + screen
        }

        let acting = mode != "consultar"
        guard let data = await run(exe, args, timeout: timeout ?? (voice ? (acting ? max(300, voiceTimeout) : voiceTimeout) : 1800)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            appendAppLog("nb.log", "[Cloud] claude -p gave no JSON")
            return nil
        }
        let result = json["result"] as? String ?? ""
        if json["is_error"] as? Bool == true {
            appendAppLog("nb.log", "[Cloud] claude -p error: \(result)")
            // "Not logged in": say it, the user can't guess it otherwise.
            if result.localizedCaseInsensitiveContains("log") {
                return Answer(text: "Preciso que você faça login no Claude pelo terminal primeiro.", sessionId: nil)
            }
            return nil
        }
        return Answer(text: result, sessionId: json["session_id"] as? String)
    }

    // MARK: Process

    /// Runs the CLI off the main thread; nil on launch failure or timeout.
    private static func run(_ exe: URL, _ args: [String], timeout: TimeInterval) async -> Data? {
        await Task.detached {
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            // Same order as the terminal: the /ogab's Python packages live in python.org's Python.
            env["PATH"] = "\(home)/.local/bin:/Library/Frameworks/Python.framework/Versions/Current/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            return p.terminationReason == .exit ? data : nil
        }.value
    }

    // MARK: Prompt

    private static func modeRules(_ mode: String) -> String {
        switch mode {
        case "consultar":
            return "Você só consulta: lê arquivos e pesquisa na web. Se pedirem para executar algo, diga em uma frase que o modo do Cloud está em Só consultar nos Ajustes."
        case "automatico":
            let live = HookServer.shared.liveSessions()
            let list = live.isEmpty ? "nenhuma" : live.map {
                "\($0.project) (pasta \($0.cwd), sessão \($0.id)\($0.working ? ", trabalhando agora" : ""))"
            }.joined(separator: "; ")
            return """
            Você executa no Mac do usuário: faça a tarefa, não descreva como fazer. Nunca apague nada, \
            não publique e não envie mensagem ou e-mail sem o usuário confirmar antes. \
            Sessões do Claude Code abertas agora: \(list). Para mandar uma instrução a uma delas: \
            `cd "<pasta>" && claude -p --resume <sessão> "<instrução>"`, e resuma o que ela respondeu.
            """
        default:
            return """
            Você executa no Mac do usuário, mas só com as ferramentas liberadas na lista de ações do \
            Cloud: faça a tarefa, não descreva como fazer. Se o pedido precisa de algo fora da lista \
            (a ferramenta for negada), diga em uma frase o que faltou e que dá para liberar em \
            Ajustes → Assistente → O que o Cloud pode fazer. Nunca apague nada, não publique e não envie \
            mensagem sem o usuário confirmar.
            """
        }
    }

    private static func systemPrompt(voice: Bool, mode: String) -> String {
        let today = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()
            .locale(Locale(identifier: "pt_BR")))
        let common = """
        Você é o \(CloudIdentity.name), o assistente (o app se chama My Cloud) que mora no notch do Mac do usuário, tipo Jarvis: \
        rápido, caloroso, um pouco brincalhão. Agora é \(today). Responda em português do Brasil, \
        sem travessão.
        \(modeRules(mode))
        \(CloudComputerUse.promptRules)
        Nunca invente dados do usuário.
        Rotinas ficam em \(RoutineStore.file.path): array JSON de {"nome", "hora" (0-23), "minuto", \
        "dias" (1=domingo...7=sábado), "pedido"}. Gatilhos ficam em \(TriggerStore.file.path): array de \
        {"frase", "pedido"}. Quando pedirem "todo dia às 8h faz X" ou "quando eu disser Y faz Z", edite o arquivo \
        (mantenha o JSON válido) e confirme em uma frase.
        Vídeo: qualquer pedido de vídeo (criar, editar, DaVinci, reels, legenda, motion, roteiro) é \
        trabalho da skill /ogab, se ela estiver instalada em ~/.claude/skills: use a skill. Anúncio, \
        tráfego pago, campanha, Meta ou Google Ads, CPA, ROAS, criativo de anúncio ou relatório de \
        campanha é trabalho da skill /ojhon, se estiver instalada: use a skill.
        Ações rápidas: são botões no notch do usuário, guardados em \(CloudQuickActions.fileURL.path), \
        um array JSON de objetos {"titulo": curto, "pedido": o que você deve fazer quando ele tocar, \
        "icone": nome de SF Symbol}, ou um atalho de skill {"titulo": "/nome", "skill": "nome", \
        "icone": "sparkles"} (as skills ficam em ~/.claude/skills). Além das rotinas e dos gatilhos, é o único arquivo do Cloud que você pode editar. Quando o usuário pedir \
        para criar, mudar ou remover uma ação rápida, leia o arquivo, edite mantendo o JSON válido e \
        confirme em uma frase. O "pedido" é reutilizado em outros dias: nunca coloque data, dia da \
        semana ou horário fixos nele (escreva "hoje", "agora").
        """
        return voice
            ? common + """

            A resposta aparece numa legenda pequena no notch: uma ou duas frases curtas, sem markdown, \
            sem listas, sem emojis, sem links. Quando precisar de uma resposta do usuário, termine com \
            uma pergunta curta; caso contrário, nunca termine com pergunta.
            """
            : common + """

            Esta conversa é na janela de chat: pode usar markdown e listas quando ajudar a leitura, \
            sem enrolar.
            """
    }
}
#endif

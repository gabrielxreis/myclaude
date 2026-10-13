#if !APPSTORE
import AppKit

// MARK: - "Gostei desse vídeo, cria uma ideia em cima dele"
//
// Takes the link of the video open in the browser (front tab of Chrome, Safari, Arc, Brave, Edge),
// and in the background the /ogab downloads it or takes YouTube's captions, transcribes it,
// studies the hook and the structure, and writes a new script based on it (in a client's style
// when one is named). The script lands in a conversation of the history, with a notification.

@MainActor
enum VideoIdea {

    static func isRequest(_ text: String) -> Bool {
        let n = CloudTimers.norm(text)
        let video = ["esse video", "desse video", "este video", "deste video", "esse reels", "desse reels",
                     "esse post", "desse post", "esse aqui", "desse aqui"].contains { n.contains($0) }
        let wants = ["gostei", "ideia", "roteiro", "inspira", "baseado", "em cima", "faz um", "cria um"].contains { n.contains($0) }
        return video && wants
    }

    /// Starts the work; returns what Cloud says right away.
    static func start(_ request: String) -> String {
        guard let (url, title) = currentBrowserPage() else {
            return "Não achei o vídeo: abre ele no navegador (Chrome, Safari, Arc, Brave ou Edge) e me pede de novo."
        }
        let store = CloudChatStore.shared
        let id = store.newConversation()
        let prompt = """
        /ogab Quero um roteiro novo inspirado neste vídeo: \(url)
        Pedido original: "\(request)"
        1. Pegue o conteúdo do vídeo: se for YouTube, a legenda/transcrição; senão, baixe (baixar_video.py ou yt-dlp) \
        e transcreva com o transcritor da /ogab.
        2. Analise: gancho dos primeiros segundos, estrutura, ritmo, formato e por que funciona.
        3. Escreva um roteiro NOVO (não copie o texto), no estilo do cliente se eu citei um, com gancho, \
        desenvolvimento e CTA, pronto para eu aprovar.
        Responda com: resumo do vídeo em 2 linhas, o que faz ele funcionar, e o roteiro.
        """
        Task { @MainActor in
            CloudPet.shared.interacted(xpGain: 8)
            let answer = await store.send(prompt, in: id, voice: false)
            let ok = answer != nil
            SoundEngine.shared.play(ok ? "finish" : "error")
            let msg = ok ? "Seu roteiro baseado em \(title) está pronto. Abre o histórico do Cloud." : "Não consegui montar o roteiro desse vídeo agora."
            NSAppleScript(source: "display notification \"\(msg.replacingOccurrences(of: "\"", with: "'"))\" with title \"My Cloud\" sound name \"Glass\"")?
                .executeAndReturnError(nil)
            if ok { CloudChatWindow.shared.show(conversation: id) }
        }
        appendAppLog("nb.log", "[Cloud] video idea from \(url)")
        CloudMissions.shared.record(.video)
        return "Peguei o vídeo \(title). Vou estudar e montar o roteiro em segundo plano, te aviso quando estiver pronto."
    }

    /// URL and title of the front tab of the browser in front (or the last one used).
    static func currentBrowserPage() -> (String, String)? {
        let browsers: [(id: String, name: String, chromium: Bool)] = [
            ("com.google.Chrome", "Google Chrome", true), ("com.apple.Safari", "Safari", false),
            ("company.thebrowser.Browser", "Arc", true), ("com.brave.Browser", "Brave Browser", true),
            ("com.microsoft.edgemac", "Microsoft Edge", true),
        ]
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let lastFront = CloudPet.shared.frontApp?.bundleId
        let ordered = browsers.sorted { a, _ in a.id == front || a.id == lastFront }.filter { running.contains($0.id) }
        for b in ordered {
            let src = b.chromium
                ? "tell application \"\(b.name)\" to return (URL of active tab of front window) & \"\\n\" & (title of active tab of front window)"
                : "tell application \"Safari\" to return (URL of current tab of front window) & \"\\n\" & (name of current tab of front window)"
            var err: NSDictionary?
            guard let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue else { continue }
            let parts = out.components(separatedBy: "\n")
            if let url = parts.first, url.hasPrefix("http") {
                return (url, parts.count > 1 && !parts[1].isEmpty ? "\"\(parts[1])\"" : "da aba aberta")
            }
        }
        return nil
    }
}
#endif

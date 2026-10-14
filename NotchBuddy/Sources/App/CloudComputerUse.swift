#if !APPSTORE
import AppKit

// MARK: - Using any app (Peekaboo)
//
// With this on, Cloud's Claude may see the screen and click, type and use menus in any app,
// through Peekaboo (github.com/openclaw/Peekaboo, MIT), an MCP server added to Claude Code
// (`claude mcp add --scope user peekaboo -- npx -y @steipete/peekaboo mcp`). Off by default
// (Settings → Assistente). "Só consultar" only lets it look; deleting, sending, publishing,
// buying or changing settings always waits for my confirmation (system prompt).

@MainActor
enum CloudComputerUse {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "cloudComputerUse") }
        set { UserDefaults.standard.set(newValue, forKey: "cloudComputerUse") }
    }

    /// Peekaboo is set up in Claude Code (user scope in ~/.claude.json).
    static var installed: Bool {
        let f = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: f),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = j["mcpServers"] as? [String: Any] else { return false }
        return servers["peekaboo"] != nil
    }

    static var active: Bool { enabled && installed }

    /// Claude Code permission rules for the current mode.
    static func allowedTools(mode: String) -> [String] {
        guard active else { return [] }
        return mode == "consultar" ? ["mcp__peekaboo__see", "mcp__peekaboo__image", "mcp__peekaboo__inspect_ui"]
                                   : ["mcp__peekaboo"]
    }

    static var promptRules: String {
        guard active else { return "" }
        return """
        Você pode ver e usar qualquer app do Mac pelas ferramentas do peekaboo: primeiro olhe \
        (see, ou image do app), depois aja (app para abrir ou trazer para frente, click, type, press, \
        menu, scroll, window) e olhe de novo para conferir. Prefira clicar pelo nome do botão ou \
        elemento. Antes de qualquer ação que apague, envie, publique, compre, pague ou mude uma \
        configuração do sistema, pare e pergunte ao usuário. No fim, diga em uma frase o que fez.
        """
    }

    /// Adds Peekaboo to Claude Code (after a dated backup of ~/.claude.json). nil = ok.
    static func install() async -> String? {
        guard let exe = ClaudeCLIBrain.executable else { return "Instale o Claude Code primeiro (Ajustes → Claude)." }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cfg = home.appendingPathComponent(".claude.json")
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        try? FileManager.default.copyItem(at: cfg, to: home.appendingPathComponent(".claude.json.bak-" + f.string(from: Date())))
        let ok = await Task.detached { () -> Bool in
            let p = Process()
            p.executableURL = exe
            p.arguments = ["mcp", "add", "--scope", "user", "peekaboo", "--", "npx", "-y", "@steipete/peekaboo", "mcp"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\(home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }.value
        appendAppLog("nb.log", "[Cloud] peekaboo install ok=\(ok)")
        return ok ? nil : "Não consegui adicionar o Peekaboo. Ele precisa do Node 22 ou mais novo (brew install node)."
    }
}
#endif

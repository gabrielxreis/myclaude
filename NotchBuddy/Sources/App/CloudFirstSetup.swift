#if !APPSTORE
import AppKit

// MARK: - Setting everything up at once
//
// The first time (after the egg) and from Settings → Permissões → "Configurar tudo agora":
// asks macOS for every permission that is still missing, one after the other (each prompt
// waits for the previous answer), turns on "usar qualquer app" when Peekaboo is there, and
// ends with what only I can do by hand (Accessibility / Screen Recording switches, the
// browser's JavaScript menu item, which browsers refuse to let an app tick).

@MainActor
enum CloudFirstSetup {
    static var done: Bool {
        get { UserDefaults.standard.bool(forKey: "myCloudSetupDone") }
        set { UserDefaults.standard.set(newValue, forKey: "myCloudSetupDone") }
    }

    /// Once, after the egg has hatched.
    static func runIfNeeded() {
        guard CloudIdentity.hatched, !done else { return }
        done = true
        Task { await run() }
    }

    static func run() async {
        appendAppLog("nb.log", "[Cloud] setup: start")
        // Prompts macOS shows by itself, one at a time.
        for p in [CloudPermission.microfone, .fala, .contatos, .agenda] where p.status == .notAsked {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in p.request { c.resume() } }
        }
        // Control of other apps: only for the ones installed.
        for p in [CloudPermission.chrome, .safari, .terminal] where p.status != .granted && p.status != .denied {
            let id = p == .chrome ? "com.google.Chrome" : p == .safari ? "com.apple.Safari" : "com.apple.Terminal"
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil else { continue }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in p.request { c.resume() } }
        }
        if CloudComputerUse.installed && !CloudComputerUse.enabled { CloudComputerUse.enabled = true }

        // What is left for me, with the System Settings pane opened for the first one.
        var left: [String] = []
        if CloudPermission.acessibilidade.status != .granted { left.append("• Acessibilidade: ligue o My Cloud (para clicar e digitar em qualquer app).") }
        if CloudPermission.tela.status != .granted { left.append("• Gravação de tela: ligue o My Cloud (para ver a tela).") }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil, CloudPermission.jsChrome.status != .granted {
            left.append("• Chrome: menu Visualização → Desenvolvedor → Permitir o JavaScript do Eventos da Apple (para clicar dentro dos sites).")
        }
        appendAppLog("nb.log", "[Cloud] setup: done, \(left.count) left by hand")
        guard !left.isEmpty else { return }
        if CloudPermission.acessibilidade.status != .granted {
            CloudPermission.acessibilidade.request { }
        } else if CloudPermission.tela.status != .granted {
            CloudPermission.tela.request { }
        }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Quase pronto: falta o que só você pode ligar"
        a.informativeText = left.joined(separator: "\n\n") + "\n\nDepois de ligar Acessibilidade ou Gravação de tela, reabra o My Cloud. Tudo isso fica em Ajustes → Permissões."
        a.addButton(withTitle: "Abrir Permissões")
        a.addButton(withTitle: "Depois")
        if a.runModal() == .alertFirstButtonReturn {
            NotificationCenter.default.post(name: .openFullSettings, object: "permissoes")
        }
    }
}
#endif

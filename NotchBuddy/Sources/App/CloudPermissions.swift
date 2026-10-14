#if !APPSTORE
import AppKit
import AVFoundation
import Speech
import Contacts
import EventKit
import SwiftUI

// MARK: - Permissions (Settings → Permissões)
//
// Every macOS permission My Cloud uses, what it is for, whether it is granted, and one button:
// "Permitir" asks for it (when macOS still can), "Abrir Ajustes" goes to the right pane.

enum CloudPermission: String, CaseIterable, Identifiable {
    case microfone, fala, acessibilidade, tela, contatos, agenda, terminal, chrome, safari, jsChrome, jsSafari
    var id: String { rawValue }
    /// What the Permissions tab shows: Safari's JavaScript is out (the web goes to Chrome).
    static var shown: [CloudPermission] { allCases.filter { $0 != .jsSafari } }

    var title: String {
        switch self {
        case .microfone: "Microfone"
        case .fala: "Reconhecimento de fala"
        case .acessibilidade: "Acessibilidade"
        case .tela: "Gravação de tela"
        case .contatos: "Contatos"
        case .agenda: "Calendário"
        case .terminal: "Automação: Terminal"
        case .chrome: "Automação: Google Chrome"
        case .safari: "Automação: Safari"
        case .jsChrome: "JavaScript no Chrome"
        case .jsSafari: "JavaScript no Safari"
        }
    }

    var purpose: String {
        switch self {
        case .microfone: "Ouvir quando você chama o Cloud."
        case .fala: "Entender o que você fala, no próprio Mac."
        case .acessibilidade: "Usar qualquer app pelo Peekaboo (clicar, digitar, menus)."
        case .tela: "\u{201C}Olha minha tela\u{201D}, gravar a tela e o Peekaboo enxergar os apps."
        case .contatos: "Achar o telefone para abrir a conversa no WhatsApp."
        case .agenda: "O widget de agenda no notch."
        case .terminal: "O botão Conectar ao Claude (instalar e entrar na conta)."
        case .chrome: "Pegar o link do vídeo aberto (roteiro a partir de um vídeo)."
        case .safari: "Pegar o link do vídeo aberto (roteiro a partir de um vídeo)."
        case .jsChrome, .jsSafari: "Clicar em botões e links dentro dos sites (\u{201C}clica em…\u{201D}, \u{201C}coloca o primeiro vídeo\u{201D})."
        }
    }

    enum Status { case granted, denied, notAsked, unknown }

    @MainActor var status: Status {
        switch self {
        case .microfone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .fala:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .acessibilidade:
            return AXIsProcessTrusted() ? .granted : .notAsked
        case .tela:
            return CGPreflightScreenCaptureAccess() ? .granted : .notAsked
        case .contatos:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            case .denied, .restricted: return .denied
            default: return .granted   // limited access still finds the contacts it was given
            }
        case .agenda:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .terminal, .chrome, .safari:
            return Self.automationStatus(bundleID)
        case .jsChrome, .jsSafari:
            let id = self == .jsChrome ? "com.google.Chrome" : "com.apple.Safari"
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) else { return .unknown }
            return ScreenActions.runJS("1", in: app) != nil ? .granted : .notAsked
        }
    }

    private var bundleID: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .chrome, .jsChrome: "com.google.Chrome"
        default: "com.apple.Safari"
        }
    }

    /// Shows macOS's "My Cloud wants to control …" prompt (blocks until answered).
    nonisolated private static func askAutomation(_ id: String) -> OSStatus {
        var target = AEAddressDesc()
        let err = id.withCString { ptr -> OSStatus in
            OSStatus(AECreateDesc(typeApplicationBundleID, ptr, strlen(ptr), &target))
        }
        guard err == noErr else { return err }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true)
    }

    /// Apple Events permission for one app, without asking (only known while that app is open).
    private static func automationStatus(_ id: String) -> Status {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }) else { return .unknown }
        var target = AEAddressDesc()
        let err = id.withCString { ptr -> OSStatus in
            OSStatus(AECreateDesc(typeApplicationBundleID, ptr, strlen(ptr), &target))
        }
        guard err == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default: return .unknown
        }
    }

    private var pane: String {
        switch self {
        case .microfone: "Privacy_Microphone"
        case .fala: "Privacy_SpeechRecognition"
        case .acessibilidade: "Privacy_Accessibility"
        case .tela: "Privacy_ScreenCapture"
        case .contatos: "Privacy_Contacts"
        case .agenda: "Privacy_Calendars"
        case .terminal, .chrome, .safari, .jsChrome, .jsSafari: "Privacy_Automation"
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Kept alive while macOS shows its prompt: a store freed right after asking cancels it.
    @MainActor private static let eventStore = EKEventStore()
    @MainActor private static let contactStore = CNContactStore()

    /// Screen Recording and Accessibility are only seen after My Cloud reopens.
    var needsRelaunch: Bool { self == .tela || self == .acessibilidade || self == .agenda }

    /// Asks macOS for it when it still can; else opens the right pane of System Settings.
    @MainActor func request(done: @escaping @MainActor () -> Void) {
        // An accessory app: come to the front first, or the prompt may open behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        let back: @Sendable (Bool) -> Void = { _ in Task { @MainActor in done() } }
        switch (self, status) {
        case (.microfone, .notAsked): AVCaptureDevice.requestAccess(for: .audio, completionHandler: back)
        case (.fala, .notAsked): SFSpeechRecognizer.requestAuthorization { @Sendable _ in Task { @MainActor in done() } }
        case (.contatos, .notAsked): Self.contactStore.requestAccess(for: .contacts) { ok, _ in back(ok) }
        case (.agenda, .notAsked), (.agenda, .denied):
            Self.eventStore.requestFullAccessToEvents { ok, err in
                appendAppLog("nb.log", "[Cloud] calendar request ok=\(ok) err=\(String(describing: err)) status=\(EKEventStore.authorizationStatus(for: .event).rawValue)")
                Task { @MainActor in
                    if !ok { CloudPermission.agenda.openSettings() }
                    done()
                }
            }
        case (.acessibilidade, .notAsked):
            let key = "AXTrustedCheckOptionPrompt" as CFString
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            openSettings(); done()
        case (.tela, .notAsked):
            // macOS shows its prompt only the first time; after that the switch is in Settings.
            if !CGRequestScreenCaptureAccess() { openSettings() }
            done()
        case (.jsChrome, _):
            // Chrome: View → Developer → Allow JavaScript from Apple Events, pressed for me.
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) {
                if !Self.pressChromeJSMenu(app) {
                    let a = NSAlert()
                    a.messageText = "Ligue no Chrome"
                    a.informativeText = "No Chrome: menu Ver → Desenvolvedor → Permitir o JavaScript do Eventos da Apple."
                    a.runModal()
                }
            } else {
                let a = NSAlert(); a.messageText = "Abra o Chrome primeiro"
                a.informativeText = "Depois toque em Permitir de novo."; a.runModal()
            }
            done()
        case (.jsSafari, _):
            let a = NSAlert()
            a.messageText = "Ligue no Safari (uma vez)"
            a.informativeText = "1. Safari → Ajustes → Avançado → marque \u{201C}Mostrar recursos para desenvolvedores web\u{201D}.\n2. Menu Desenvolvedor → \u{201C}Permitir JavaScript de Eventos da Apple\u{201D}."
            a.runModal()
            done()
        case (.terminal, _), (.chrome, _), (.safari, _):
            if status == .denied { openSettings(); done(); return }
            // My Cloud itself asks (the official prompt names My Cloud): the app must be running,
            // so a closed one is opened in the background first. Off the main thread: it waits for me.
            let id = bundleID
            Task {
                if !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }),
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.activates = false
                    cfg.hides = true
                    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                let result = await Task.detached { Self.askAutomation(id) }.value
                if result == OSStatus(errAEEventNotPermitted) { openSettings() }
                done()
            }
        default:
            openSettings(); done()
        }
    }
}

extension CloudPermission {
    /// Finds Chrome's "Allow JavaScript from Apple Events" menu item (any language) and presses it.
    @MainActor static func pressChromeJSMenu(_ app: NSRunningApplication) -> Bool {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXMenuBarAttribute as CFString, &bar) == .success, let bar else { return false }
        var queue = [bar as! AXUIElement], i = 0
        while i < queue.count, i < 4000 {
            let el = queue[i]; i += 1
            let t = ScreenActions.title(el).lowercased()
            if t.contains("javascript") && (t.contains("apple") || t.contains("eventos")) {
                return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
            }
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success,
               let arr = kids as? [AXUIElement] { queue.append(contentsOf: arr) }
        }
        return false
    }
}

/// Quits and opens My Cloud again (Screen Recording and Accessibility need it).
@MainActor func relaunchMyCloud() {
    let path = Bundle.main.bundleURL.path
    let pid = ProcessInfo.processInfo.processIdentifier
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$1\"", "--", path]
    try? task.run()
    NSApp.terminate(nil)
}

/// One line in the log with every status (diagnostics).
@MainActor func logPermissions() {
    let line = CloudPermission.allCases.map { "\($0.rawValue)=\($0.status)" }.joined(separator: " ")
    appendAppLog("nb.log", "[Cloud] permissions \(line) calendarRaw=\(EKEventStore.authorizationStatus(for: .event).rawValue)")
}

struct CloudPermissionsView: View {
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let all = CloudPermission.shown
        let missing = all.filter { $0.status != .granted }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: missing == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(missing == 0 ? .green : .orange)
                Text(missing == 0 ? "Tudo o que o My Cloud usa está permitido."
                                  : "Falta permitir \(missing) \(missing == 1 ? "item" : "itens").")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if missing > 0 {
                    Button("Configurar tudo agora") { Task { await CloudFirstSetup.run(); tick += 1 } }
                        .buttonStyle(.borderedProminent)
                }
                Button("Atualizar") { tick += 1 }.buttonStyle(.bordered)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(all.enumerated()), id: \.element) { i, p in
                        row(p)
                        if i < all.count - 1 { Divider().padding(.vertical, 6) }
                    }
                }
                .padding(6)
            }
            if all.contains(where: { $0.needsRelaunch && $0.status != .granted }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundColor(.orange)
                    Text("Ligou Gravação de tela, Acessibilidade ou Calendário nos Ajustes do Sistema? O macOS só mostra a mudança depois que o My Cloud abre de novo.")
                        .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reabrir o My Cloud") { relaunchMyCloud() }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            Text("Automação: \u{201C}Permitir\u{201D} abre o app (se estiver fechado) e o Mac pergunta se o My Cloud pode controlá-lo. Se algo foi negado sem querer, \u{201C}Abrir Ajustes\u{201D} leva direto ao lugar certo nos Ajustes do Sistema.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in tick += 1 }
        .onAppear { logPermissions() }
    }

    private func row(_ p: CloudPermission) -> some View {
        let st = p.status
        let (icon, color, label): (String, Color, String) = {
            switch st {
            case .granted: return ("checkmark.circle.fill", .green, "Permitido")
            case .denied: return ("xmark.circle.fill", .red, "Negado")
            case .notAsked: return ("circle.dashed", .orange, "Falta permitir")
            case .unknown: return ("circle.dashed", .orange, "Ainda não pedido")
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.system(size: 12, weight: .semibold))
                Text(p.purpose).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(label).font(.system(size: 11)).foregroundColor(color)
            if st != .granted {
                Button(st == .denied ? "Abrir Ajustes" : "Permitir") { p.request { tick += 1 } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}
#endif

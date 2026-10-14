#if !APPSTORE
import AppKit

// MARK: - Connection to Claude (Settings → Claude)
//
// Reads, without changing anything, what is already set up: the Claude Code CLI, the signed-in
// account (`claude auth status`), the notch hooks and the plan-usage status line. "Conectar ao
// Claude" then does the next missing step: install the CLI (official installer, in Terminal),
// sign in (in Terminal), or write the hooks / status line (shown first, written after a click).

@MainActor
final class ClaudeConnection: ObservableObject {
    static let shared = ClaudeConnection()

    @Published private(set) var cliPath: String?
    @Published private(set) var version: String?
    @Published private(set) var loggedIn = false
    @Published private(set) var email: String?
    @Published private(set) var plan: String?
    @Published private(set) var hooks = false
    @Published private(set) var statusLine = false
    @Published private(set) var checking = false
    @Published private(set) var lastCheck: Date?

    enum Step { case installCLI, login, hooks, statusLine, done }

    var nextStep: Step {
        if cliPath == nil { return .installCLI }
        if !loggedIn { return .login }
        if !hooks { return .hooks }
        if !statusLine { return .statusLine }
        return .done
    }

    /// Settings → Claude: read the integration by itself when the app opens.
    static var autoRead: Bool {
        get { UserDefaults.standard.object(forKey: "cloudClaudeAutoRead") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "cloudClaudeAutoRead") }
    }

    func refresh() async {
        checking = true
        defer { checking = false; lastCheck = Date() }
        hooks = HookServer.claudeHooksInstalled()
        statusLine = HookServer.statusLineInstalled()
        guard let exe = ClaudeCLIBrain.executable else {
            cliPath = nil; version = nil; loggedIn = false; email = nil; plan = nil
            return
        }
        cliPath = exe.path
        let v = await Self.run(exe, ["--version"])
        version = v.flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " (Claude Code)", with: "")
        if let data = await Self.run(exe, ["auth", "status"]),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            loggedIn = j["loggedIn"] as? Bool ?? false
            email = j["email"] as? String
            plan = (j["subscriptionType"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        } else {
            loggedIn = false; email = nil; plan = nil
        }
        appendAppLog("nb.log", "[Cloud] claude connection cli=\(cliPath != nil) login=\(loggedIn) hooks=\(hooks) statusline=\(statusLine)")
    }

    /// Opens Terminal with a command the user can see run (install or sign in).
    func runInTerminal(_ command: String) {
        let esc = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(esc)"
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err { appendAppLog("nb.log", "[Cloud] terminal: \(err)") }
    }

    func installCLI() { runInTerminal("curl -fsSL https://claude.ai/install.sh | bash") }

    func login() {
        guard let exe = cliPath else { return }
        runInTerminal("'\(exe)' auth login")
    }

    /// Runs the CLI off the main thread (10 s max).
    private static func run(_ exe: URL, _ args: [String]) async -> Data? {
        await Task.detached { () -> Data? in
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: killer)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            return data
        }.value
    }

    /// At launch: read the integration; if something is missing, open Settings → Claude once.
    func checkAtLaunch() {
        guard Self.autoRead else { return }
        Task {
            await refresh()
            let key = "cloudClaudeConnectPrompted"
            if nextStep == .done { UserDefaults.standard.removeObject(forKey: key); return }
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)
            NotificationCenter.default.post(name: .openFullSettings, object: "claude")
        }
    }
}
#endif

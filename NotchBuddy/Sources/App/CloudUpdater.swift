#if !APPSTORE
import AppKit

// MARK: - Auto-update (once a day)
//
// Checks github.com/gabrielxreis/myclaude: when its newest commit is newer than this build
// (Info.plist MyCloudBuildDate, stamped by scripts/build-mycloud.sh), it downloads the source to
// ~/Library/Application Support/MyCloud/src, builds it in the background, replaces
// /Applications/My Cloud.app and reopens it. The /ogab and /ojhon skills are updated the same day.
// A build newer than GitHub (a development build) is never replaced by an older one.

@MainActor
final class CloudUpdater: ObservableObject {
    static let shared = CloudUpdater()
    static let repo = "gabrielxreis/myclaude"

    @Published private(set) var status = ""
    private var timer: Timer?

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "cloudAutoUpdate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "cloudAutoUpdate") }
    }
    static var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: "cloudLastUpdateCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "cloudLastUpdateCheck") }
    }
    static var buildDate: Date? {
        (Bundle.main.object(forInfoDictionaryKey: "MyCloudBuildDate") as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// Called at launch: a check now if the last one is over a day old, then every hour.
    func start() {
        dailyCheck()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in CloudUpdater.shared.dailyCheck() }
        }
    }

    private func dailyCheck() {
        guard Self.enabled else { return }
        if let last = Self.lastCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        Task { await check(manual: false) }
    }

    /// "Verificar agora" in Settings, or the daily check.
    func check(manual: Bool) async {
        Self.lastCheck = Date()
        status = "Verificando…"
        updateSkills()
        guard let remote = await Self.latestCommitDate() else {
            status = "Não consegui falar com o GitHub agora."
            return
        }
        let mine = Self.buildDate ?? .distantPast
        guard remote > mine.addingTimeInterval(60) else {
            status = "Você está na versão mais nova."
            appendAppLog("nb.log", "[Cloud] update: up to date (remote \(remote), build \(mine))")
            return
        }
        guard Self.canBuild else {
            status = "Tem versão nova, mas precisa do Xcode e do xcodegen para instalar."
            if manual { Self.notify("Tem versão nova do My Cloud. Instale o Xcode para ela entrar sozinha.") }
            return
        }
        status = "Baixando e instalando a versão nova…"
        appendAppLog("nb.log", "[Cloud] update: installing \(remote)")
        runInstaller()
    }

    /// The newest commit on GitHub (public API, no token).
    static func latestCommitDate() async -> Date? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/commits/main") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commit = json["commit"] as? [String: Any],
              let committer = commit["committer"] as? [String: Any],
              let date = committer["date"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: date)
    }

    static var canBuild: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/xcodebuild")
            && ["/opt/homebrew/bin/xcodegen", "/usr/local/bin/xcodegen"].contains { FileManager.default.isExecutableFile(atPath: $0) }
            && FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
    }

    /// The update runs detached from this app (the build closes and reopens My Cloud).
    private func runInstaller() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyCloud", isDirectory: true)
        let src = dir.appendingPathComponent("src").path
        let log = dir.appendingPathComponent("atualizacao.log").path
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        {
          echo "== $(date) =="
          if [ -d "\(src)/.git" ]; then git -C "\(src)" fetch -q --depth 1 origin main && git -C "\(src)" reset -q --hard origin/main
          else rm -rf "\(src)"; git clone -q --depth 1 https://github.com/\(Self.repo).git "\(src)"; fi
          "\(src)/scripts/build-mycloud.sh" && osascript -e 'display notification "Atualizei o My Cloud para a versão mais nova." with title "My Cloud" sound name "Glass"'
        } >> "\(log)" 2>&1
        """
        let path = dir.appendingPathComponent("atualizar.sh")
        try? script.write(to: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        p.arguments = ["/bin/zsh", path.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// /ogab and /ojhon: a quiet git pull (their install.sh stays for the big updates).
    private func updateSkills() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for skill in ["ogab", "ojhon"] {
            let dir = "\(home)/.claude/skills/\(skill)"
            guard FileManager.default.fileExists(atPath: dir + "/.git") else { continue }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", dir, "pull", "--ff-only", "-q"]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run()
        }
    }

    static func notify(_ text: String) {
        let esc = text.replacingOccurrences(of: "\"", with: "'")
        NSAppleScript(source: "display notification \"\(esc)\" with title \"My Cloud\"")?.executeAndReturnError(nil)
    }
}
#endif

#if !APPSTORE
import AppKit

// MARK: - Auto-update (once a day)
//
// Checks the latest release of github.com/gabrielxreis/myclaude: when it is newer than this build
// (Info.plist MyCloudBuildDate), it downloads the ready-made MyCloud.zip (no Xcode needed),
// replaces /Applications/My Cloud.app and reopens it. Without a release, a Mac with Xcode builds
// the source instead. Only the app: skills such as /ogab and /ojhon update on their own.
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
    static var isPersonalBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "MyCloudPersonal") as? Bool ?? false
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
        let release = await Self.latestRelease()
        var remoteDate = release?.date
        if remoteDate == nil { remoteDate = await Self.latestCommitDate() }
        guard let remote = remoteDate else {
            status = "Não consegui falar com o GitHub agora."
            return
        }
        let mine = Self.buildDate ?? .distantPast
        // My own build from the private fork: the public release (no Mochi, no Coucou sounds)
        // must not replace it. I update it with scripts/build-mycloud.sh.
        if Self.isPersonalBuild {
            status = remote > mine.addingTimeInterval(60)
                ? "Build pessoal: tem versão pública mais nova, mas esta não é trocada (atualize com o build-mycloud.sh)."
                : "Build pessoal, em dia."
            appendAppLog("nb.log", "[Cloud] update: personal build, not replaced")
            return
        }
        guard remote > mine.addingTimeInterval(60) else {
            status = "Você está na versão mais nova."
            appendAppLog("nb.log", "[Cloud] update: up to date (remote \(remote), build \(mine))")
            return
        }
        status = "Baixando e instalando a versão nova…"
        appendAppLog("nb.log", "[Cloud] update: installing \(remote)")
        if let zip = release?.zip {
            runInstaller(zip: zip)
        } else if Self.canBuild {
            runInstaller(zip: nil)
        } else {
            status = "Tem versão nova, mas ainda sem app pronto para baixar."
        }
    }

    /// The latest release: its date and the MyCloud.zip to download.
    static func latestRelease() async -> (date: Date, zip: URL)? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let published = (json["published_at"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }),
              let assets = json["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String) == "MyCloud.zip" })?["browser_download_url"] as? String,
              let zipURL = URL(string: zip) else { return nil }
        return (published, zipURL)
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

    /// The update runs detached from this app (it closes and reopens My Cloud).
    private func runInstaller(zip: URL?) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyCloud", isDirectory: true)
        let src = dir.appendingPathComponent("src").path
        let log = dir.appendingPathComponent("atualizacao.log").path
        let done = "osascript -e 'display notification \"Atualizei o My Cloud para a versão mais nova.\" with title \"My Cloud\" sound name \"Glass\"'"
        let script: String
        if let zip {
            // Ready-made app: download, swap, reopen. No Xcode.
            script = """
            #!/bin/zsh
            {
              echo "== $(date) =="
              T=$(mktemp -d)
              curl -fsSL "\(zip.absoluteString)" -o "$T/MyCloud.zip" && ditto -x -k "$T/MyCloud.zip" "$T" && [ -d "$T/My Cloud.app" ] || exit 1
              pkill -f "My Cloud.app/Contents/MacOS" 2>/dev/null; sleep 1
              rm -rf "/Applications/My Cloud.app" && ditto "$T/My Cloud.app" "/Applications/My Cloud.app"
              xattr -dr com.apple.quarantine "/Applications/My Cloud.app" 2>/dev/null
              rm -rf "$T"
              open "/Applications/My Cloud.app" && \(done)
            } >> "\(log)" 2>&1
            """
        } else {
            script = """
            #!/bin/zsh
            export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            {
              echo "== $(date) =="
              if [ -d "\(src)/.git" ]; then git -C "\(src)" fetch -q --depth 1 origin main && git -C "\(src)" reset -q --hard origin/main
              else rm -rf "\(src)"; git clone -q --depth 1 https://github.com/\(Self.repo).git "\(src)"; fi
              "\(src)/scripts/build-mycloud.sh" && \(done)
            } >> "\(log)" 2>&1
            """
        }
        let path = dir.appendingPathComponent("atualizar.sh")
        try? script.write(to: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        p.arguments = ["/bin/zsh", path.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    static func notify(_ text: String) {
        let esc = text.replacingOccurrences(of: "\"", with: "'")
        NSAppleScript(source: "display notification \"\(esc)\" with title \"My Cloud\"")?.executeAndReturnError(nil)
    }
}
#endif

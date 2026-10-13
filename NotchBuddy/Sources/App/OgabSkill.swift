#if !APPSTORE
import AppKit

// MARK: - Skills My Cloud ships with
//
// /ogab (video, github.com/gabrielxreis/ogab) and /ojhon (paid traffic,
// github.com/gabrielxreis/ojhon), both public. Each one's own install.sh installs or updates
// the skill and what it needs; it may ask for the Mac password, so it runs in Terminal.

struct BundledSkill: Identifiable {
    let id: String          // folder in ~/.claude/skills
    let title: String
    let summary: String

    static let all: [BundledSkill] = [
        BundledSkill(id: "ogab", title: "/ogab (vídeo)",
                     summary: "Pedidos de vídeo (criar, editar no DaVinci, reels, legenda, motions, roteiro) passam pela /ogab."),
        BundledSkill(id: "ojhon", title: "/ojhon (tráfego pago)",
                     summary: "Anúncios, campanhas, Meta e Google Ads, CPA, ROAS, criativos e relatórios passam pela /ojhon."),
    ]

    var installCommand: String {
        "curl -fsSL https://raw.githubusercontent.com/gabrielxreis/\(id)/main/install.sh | bash"
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills/\(id)/SKILL.md").path)
    }

    func runInstallerInTerminal() {
        let script = """
        tell application "Terminal"
            activate
            do script "\(installCommand)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { appendAppLog("nb.log", "[Cloud] \(id) installer: \(error)") }
    }
}
#endif

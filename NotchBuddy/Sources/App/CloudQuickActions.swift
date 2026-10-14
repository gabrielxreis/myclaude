#if !APPSTORE
import Foundation
import SwiftUI

// MARK: - Quick actions
//
// Buttons at the top of the island's right card. Each one sends its request to Cloud, as if
// spoken after "Ei Cloud". They live in ~/Library/Application Support/MyCloud/acoes-rapidas.json,
// a file Cloud itself may edit (its only write permission), so "Ei Cloud, cria uma ação rápida
// que…" works, and so does writing it in the chat.

struct CloudQuickAction: Codable, Identifiable, Equatable {
    var id: String { titulo + "|" + pedido + "|" + (skill ?? "") }
    let titulo: String
    /// What Cloud does on tap (a ready request). Empty for a skill shortcut.
    var pedido: String = ""
    var icone: String?
    /// A skill shortcut ("ogab"): the tap opens the chat with "/ogab " to finish the request.
    var skill: String?

    init(titulo: String, pedido: String = "", icone: String? = nil, skill: String? = nil) {
        self.titulo = titulo; self.pedido = pedido; self.icone = icone; self.skill = skill
    }

    // Cloud edits this file by hand: a missing field must not make the whole list unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titulo = try c.decode(String.self, forKey: .titulo)
        pedido = try c.decodeIfPresent(String.self, forKey: .pedido) ?? ""
        icone  = try c.decodeIfPresent(String.self, forKey: .icone)
        skill  = try c.decodeIfPresent(String.self, forKey: .skill)
    }
}

/// A skill installed in ~/.claude/skills (name and one-line description from SKILL.md).
struct InstalledSkill: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let summary: String

    static func all() -> [InstalledSkill] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().compactMap { n in
            let md = dir.appendingPathComponent(n).appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: md, encoding: .utf8) else { return nil }
            let desc = text.split(separator: "\n").first { $0.hasPrefix("description:") }
                .map { String($0.dropFirst("description:".count)).trimmingCharacters(in: .whitespaces) } ?? ""
            return InstalledSkill(name: n, summary: String(desc.prefix(140)))
        }
    }
}

@MainActor
final class CloudQuickActions: ObservableObject {
    static let shared = CloudQuickActions()

    @Published private(set) var actions: [CloudQuickAction] = []
    private var lastModified: Date?

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyCloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("acoes-rapidas.json")
    }

    /// The path as Claude Code permission rules write it.
    static var permissionPath: String { "~/Library/Application Support/MyCloud/acoes-rapidas.json" }

    private init() {
        if !FileManager.default.fileExists(atPath: Self.fileURL.path) {
            let starter = [CloudQuickAction(titulo: "Notícias de IA",
                                            pedido: "Quais as 3 notícias mais importantes de IA hoje?",
                                            icone: "newspaper")]
            if let data = try? JSONEncoder.pretty.encode(starter) { try? data.write(to: Self.fileURL) }
        }
        reload()
        pinOgabOnce()
    }

    /// Re-reads the file when it changed (Cloud may have edited it).
    func reload() {
        let mod = (try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path))?[.modificationDate] as? Date
        guard mod != lastModified else { return }
        lastModified = mod
        guard let data = try? Data(contentsOf: Self.fileURL),
              let list = try? JSONDecoder().decode([CloudQuickAction].self, from: data) else {
            appendAppLog("nb.log", "[Cloud] acoes-rapidas.json unreadable")
            return
        }
        actions = list
    }

    /// Runs an action: a skill opens the chat with "/skill "; a request goes to Cloud as if spoken.
    func run(_ action: CloudQuickAction) {
        if let skill = action.skill {
            CloudChatWindow.shared.show(conversation: CloudChatStore.shared.newConversation(), draft: "/\(skill) ")
            return
        }
        NotificationCenter.default.post(name: .voiceWoke, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(name: .voiceFinished, object: action.pedido as NSString)
        }
    }

    /// Pins a skill as a shortcut (the "+" menu).
    func pin(_ skill: InstalledSkill) {
        guard !actions.contains(where: { $0.skill == skill.name }) else { return }
        write(actions + [CloudQuickAction(titulo: "/" + skill.name, icone: "sparkles", skill: skill.name)])
    }

    func remove(_ action: CloudQuickAction) {
        write(actions.filter { $0 != action })
    }

    private func write(_ list: [CloudQuickAction]) {
        guard let data = try? JSONEncoder.pretty.encode(list) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        reload()
    }

    /// /ogab and /ojhon get pinned once each, only when the skill is installed (My Cloud doesn't
    /// install them); the user may remove them. Checked again at each launch until installed.
    private func pinOgabOnce() {
        let skills = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
        for (skill, icon) in [("ogab", "film"), ("ojhon", "chart.line.uptrend.xyaxis")] {
            let key = skill == "ogab" ? "myCloudOgabPinned" : "myCloudOjhonPinned"
            guard !UserDefaults.standard.bool(forKey: key),
                  FileManager.default.fileExists(atPath: skills.appendingPathComponent(skill).appendingPathComponent("SKILL.md").path)
            else { continue }
            UserDefaults.standard.set(true, forKey: key)
            if !actions.contains(where: { $0.skill == skill }) {
                write(actions + [CloudQuickAction(titulo: "/" + skill, icone: icon, skill: skill)])
            }
        }
    }

    /// The "+" menu's "Pedido pronto…": a chat that asks Cloud to create the action.
    func openCreator() {
        CloudChatWindow.shared.show(conversation: CloudChatStore.shared.newConversation(), draft: "Cria uma ação rápida que ")
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return e
    }
}

// MARK: - View

struct CloudQuickActionsRow: View {
    @ObservedObject var store = CloudQuickActions.shared
    /// Inside a widget tile: two tight columns, no outer padding.
    var compact = false

    private var columns: [GridItem] {
        compact ? [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
                : [GridItem(.adaptive(minimum: 84), spacing: 6)]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(store.actions) { a in
                    chip(icon: a.icone ?? (a.skill != nil ? "sparkles" : "bolt.fill"), title: a.titulo) { store.run(a) }
                        .help(a.skill != nil ? "Abrir o chat com /\(a.skill!)" : a.pedido)
                        .contextMenu { Button("Remover atalho", role: .destructive) { store.remove(a) } }
                }
                Menu {
                    Menu("Fixar skill") {
                        ForEach(InstalledSkill.all()) { s in
                            Button("/" + s.name) { store.pin(s) }.help(s.summary)
                        }
                    }
                    Button("Pedido pronto (criar com o Cloud)…") { store.openCreator() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                        Text("Nova").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "#D7DAE0"))
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Fixar uma skill ou criar um pedido pronto")
            }
            .padding(compact ? 0 : 10)
        }
        .onAppear { store.reload() }
    }

    private func chip(icon: String, title: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                if let title { Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1) }
            }
            .foregroundColor(Color(hex: "#D7DAE0"))
            .padding(.horizontal, compact ? 6 : 9)
            .frame(maxWidth: .infinity, minHeight: compact ? 20 : 24, alignment: .leading)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif

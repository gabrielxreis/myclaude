#if !APPSTORE
import AppKit

// MARK: - Local actions
//
// Simple commands Cloud runs itself, instantly, without asking Claude (which takes seconds):
// open or quit an app, search the web, several in a row ("abre o Chrome e pesquisa…"). "abre o DaVinci", "consegue abrir o Safari pra mim", "preciso que você
// abra o Finder", "fecha o Spotify". Anything else goes to Claude.

@MainActor
enum CloudLocalActions {

    // MARK: Requests in a row

    /// "abre o Chrome e pesquisa animais da Antártida" → ["abre o Chrome", "pesquisa animais da
    /// Antártida"]. Splits on "e / depois / e depois / aí" only when a new command follows, so
    /// "pesquisa gatos e cachorros" stays one request.
    static func clauses(_ text: String) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [[String]] = [[]]
        var i = 0
        while i < words.count {
            let n = normalise(words[i])
            let joiner = ["e", "depois", "ai", "entao"].contains(n)
            // "e depois abre…": skip every joiner word before the verb.
            var j = i
            while j < words.count, ["e", "depois", "ai", "entao"].contains(normalise(words[j])) { j += 1 }
            if joiner, j < words.count, !out[out.count - 1].isEmpty, isVerb(normalise(words[j])) {
                out.append([])
                i = j
                continue
            }
            out[out.count - 1].append(words[i])
            i += 1
        }
        return out.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }
    }

    /// Runs the clauses from `skip` on, in order, until one needs Claude. Returns what Cloud
    /// says for each local one and the rest of the request for Claude (nil when all were local).
    static func process(_ text: String, skip: Int = 0, expanded: Bool = false) -> (replies: [String], rest: String?) {
        // Defining a routine or a trigger comes first ("quando eu disser X, ..." contains X).
        if let r = VoiceSetup.trigger(text) ?? VoiceSetup.routine(text) { return ([r], nil) }
        // A trigger of mine ("modo edição") stands for its request, once (no chains).
        if skip == 0, !expanded, let e = TriggerStore.shared.expand(text) { return process(e, expanded: true) }
        if let r = openPanel(text) { return ([r], nil) }
        let nn = normalise(text)
        if ScreenTools.isPageTranslation(nn) { return ([ScreenTools.shared.translatePage()], nil) }
        if ScreenTools.isClipboardRequest(nn) { return ([ScreenTools.shared.clipboard(text, nn)], nil) }
        if ScreenTools.isRecordRequest(nn) { return ([ScreenTools.shared.record(nn)], nil) }
        if ScreenTools.isLookRequest(nn) {
            let look = ScreenTools.lookRequest(text)
            return ([look.reply], look.rest)
        }
        if text.trimmingCharacters(in: .whitespaces).hasPrefix("/") { CloudMissions.shared.record(.skill) }
        // A card offload in progress: this is the answer to its question. Or a new offload.
        if CardOffload.shared.awaiting { return ([CardOffload.shared.answer(text)], nil) }
        if CardOffload.isRequest(text) { return ([CardOffload.shared.begin(text)], nil) }
        if CloudTimers.isRequest(text) { return ([CloudTimers.shared.handle(text)], nil) }
        if VideoIdea.isRequest(text) { return ([VideoIdea.start(text)], nil) }
        let cls = clauses(text)
        var replies: [String] = []
        var i = skip
        while i < cls.count, let r = handle(cls[i]) { replies.append(r); i += 1 }
        let rest = i < cls.count ? cls[i...].joined(separator: " e ") : nil
        return (replies, rest)
    }

    /// One request, when it is local (open/quit an app, search the web, a WhatsApp chat); nil otherwise.
    static func handle(_ text: String) -> String? {
        if let r = whatsApp(text) { return r }
        let words = normalise(text).split(separator: " ").map(String.init)
        guard let (verb, rest) = findVerb(words) else { return nil }
        if verb == .search { return search(text) }
        let query = stripFiller(rest).joined(separator: " ")
        guard !query.isEmpty else { return nil }
        if verb == .open, let r = openFolder(rest) ?? openSiteIfNamed(rest) { return r }
        guard let app = findApp(query) else {
            if verb == .open, let r = openSite(query) { return r }
            return verb == .open ? nil : "Não achei nenhum app aberto com esse nome."   // Claude may know better
        }
        switch verb {
        case .open:
            NSWorkspace.shared.openApplication(at: app.url, configuration: .init(), completionHandler: nil)
            if isBrowser(app.url) { lastBrowser = app.url }
            lastOpenedApp = squash(app.name)
            CloudMissions.shared.record(.app)
            appendAppLog("nb.log", "[Cloud] local open \(app.name)")
            return "Abrindo o \(app.name)."
        case .quit:
            guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == app.url })
            else { return "O \(app.name) não está aberto." }
            running.terminate()   // the app asks to save unsaved work itself
            appendAppLog("nb.log", "[Cloud] local quit \(app.name)")
            return "Fechando o \(app.name)."
        case .search:
            return nil
        }
    }

    // MARK: Panel

    /// "abre as rotinas", "mostra minhas conquistas", "abre o painel".
    private static func openPanel(_ text: String) -> String? {
        let n = normalise(text)
        guard ["abre", "abrir", "mostra", "mostrar", "ver", "quero ver"].contains(where: { n.hasPrefix($0) || n.contains(" " + $0 + " ") }) else { return nil }
        let map: [(String, CloudPanelWindow.Tab)] = [("rotina", .rotinas), ("gatilho", .gatilhos), ("missoes", .missoes), ("missao", .missoes),
                                                     ("conquista", .conquistas), ("painel", .rotinas)]
        guard let hit = map.first(where: { n.contains($0.0) }) else { return nil }
        CloudPanelWindow.shared.show(hit.1)
        return "Abrindo \(hit.1.rawValue.lowercased())."
    }

    // MARK: Folders and sites

    /// "abre a pasta Downloads", "abre a área de trabalho", "abre a pasta Clientes".
    private static func openFolder(_ words: [String]) -> String? {
        let w = words.filter { !["o", "a", "minha", "meu", "de", "do", "da"].contains($0) }
        let saidFolder = w.first == "pasta" || w.first == "diretorio"
        let name = (saidFolder ? Array(w.dropFirst()) : w).joined(separator: " ")
        guard !name.isEmpty else { return nil }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let known: [String: String] = [
            "downloads": "Downloads", "download": "Downloads", "documentos": "Documents", "documents": "Documents",
            "area trabalho": "Desktop", "mesa": "Desktop", "desktop": "Desktop", "imagens": "Pictures",
            "fotos": "Pictures", "musicas": "Music", "musica": "Music", "filmes": "Movies", "videos": "Movies",
            "aplicativos": "/Applications", "home": "", "inicio": "",
        ]
        var url: URL?
        if let k = known[name] { url = k.hasPrefix("/") ? URL(fileURLWithPath: k) : home.appendingPathComponent(k) }
        else if saidFolder {
            // A folder with that name in the usual places (one level down).
            let q = squash(name)
            for base in ["Desktop", "Documents", "Downloads", "Movies", "Pictures", "Music"] {
                let dir = home.appendingPathComponent(base)
                let items = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                if let hit = items.first(where: { squash($0) == q }) ?? items.first(where: { squash($0).contains(q) }) {
                    var isDir: ObjCBool = false
                    let u = dir.appendingPathComponent(hit)
                    if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue { url = u; break }
                }
            }
            if url == nil { return "Não achei uma pasta chamada \(name)." }
        }
        guard let url else { return nil }
        NSWorkspace.shared.open(url)
        appendAppLog("nb.log", "[Cloud] local folder \(url.path)")
        return "Abrindo a pasta \(url.lastPathComponent)."
    }

    private static let sites: [String: String] = [
        "youtube": "https://www.youtube.com", "instagram": "https://www.instagram.com",
        "gmail": "https://mail.google.com", "email": "https://mail.google.com",
        "drive": "https://drive.google.com", "google drive": "https://drive.google.com",
        "agenda": "https://calendar.google.com", "google agenda": "https://calendar.google.com",
        "facebook": "https://www.facebook.com", "tiktok": "https://www.tiktok.com",
        "linkedin": "https://www.linkedin.com", "netflix": "https://www.netflix.com",
        "chatgpt": "https://chatgpt.com", "claude": "https://claude.ai", "github": "https://github.com",
        "x": "https://x.com", "twitter": "https://x.com", "canva": "https://www.canva.com",
    ]

    /// "abre o site globo.com".
    private static func openSiteIfNamed(_ words: [String]) -> String? {
        guard let i = words.firstIndex(of: "site") else { return nil }
        return openSite(words[(i + 1)...].joined(separator: " "))
    }

    /// A known site ("youtube") or something that looks like a domain ("globo com").
    private static func openSite(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        var link = sites[n]
        if link == nil, n.hasSuffix(" com") || n.hasSuffix(" com br") || n.hasSuffix(" ai") || n.hasSuffix(" io") {
            link = "https://" + n.replacingOccurrences(of: " ", with: ".")
        }
        guard let link, let url = URL(string: link) else { return nil }
        if let browser = lastBrowser {
            NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: .init(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
        appendAppLog("nb.log", "[Cloud] local site \(link)")
        return "Abrindo \(url.host ?? n)."
    }

    // MARK: WhatsApp

    private static var lastOpenedApp: String?

    /// "abre a conversa com a Maria no WhatsApp", "manda mensagem pro João no zap dizendo oi",
    /// or "vê a conversa do João" right after opening WhatsApp. Opens the chat; a message is
    /// only typed in, never sent: I press Enter myself.
    private static func whatsApp(_ text: String) -> String? {
        let original = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let norm = original.map(normalise)
        let saysApp = norm.contains { ["whatsapp", "whats", "zap", "zapzap", "wpp"].contains($0) }
        let chatWords: Set<String> = ["conversa", "mensagem", "chat", "msg", "fala", "falar", "escreve", "escrever"]
        guard norm.contains(where: chatWords.contains),
              saysApp || lastOpenedApp == "whatsapp" else { return nil }

        // The name: after "com/do/da/pro/pra/para (o/a)", until "no/na/whatsapp/dizendo/falando/que".
        let intro: Set<String> = ["com", "do", "da", "pro", "pra", "para", "pa"]
        let stop: Set<String> = ["no", "na", "pelo", "pelo", "whatsapp", "zap", "wpp", "dizendo", "falando", "que", "e"]
        guard let start = norm.firstIndex(where: intro.contains) else { return nil }
        var i = start + 1
        while i < norm.count, ["o", "a", "meu", "minha"].contains(norm[i]) { i += 1 }
        var nameWords: [String] = []
        while i < norm.count, !stop.contains(norm[i]) { nameWords.append(original[i]); i += 1 }
        let name = nameWords.joined(separator: " ")
        guard !name.isEmpty else { return nil }

        // Optional message: after "dizendo / falando / que".
        var message: String?
        if let m = norm.firstIndex(where: { ["dizendo", "falando"].contains($0) }), m + 1 < original.count {
            var rest = Array(original[(m + 1)...])
            if let f = rest.first, normalise(f) == "que" { rest.removeFirst() }
            message = rest.joined(separator: " ")
        }

        switch ContactLookup.phoneNow(for: name) {
        case .needsAccess:
            return "Preciso de acesso aos seus Contatos para achar o \(name). Aceita o pedido e me pede de novo."
        case .notFound:
            return "Não achei o telefone de \(name) nos seus Contatos."
        case .found(let contact, let phone):
            var link = "whatsapp://send?phone=\(phone)"
            if let message, let enc = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                link += "&text=\(enc)"
            }
            guard let url = URL(string: link) else { return nil }
            NSWorkspace.shared.open(url)
            lastOpenedApp = "whatsapp"
            appendAppLog("nb.log", "[Cloud] local whatsapp \(contact)")
            return message == nil ? "Abrindo a conversa com \(contact) no WhatsApp."
                                  : "Escrevi a mensagem pra \(contact) no WhatsApp. É só apertar Enter."
        }
    }

    // MARK: Web search

    /// The browser opened by voice last ("abre o Chrome e pesquisa…" searches in Chrome).
    private static var lastBrowser: URL?

    private static func isBrowser(_ url: URL) -> Bool {
        guard let id = Bundle(url: url)?.bundleIdentifier?.lowercased() else { return false }
        return ["chrome", "safari", "firefox", "arc", "brave", "edge", "opera", "vivaldi", "orion"]
            .contains { id.contains($0) }
    }

    /// "pesquisa animais da Antártida" → Google, in the browser just opened, the front one, or
    /// the default. The query keeps its accents and capitals.
    private static func search(_ text: String) -> String? {
        let original = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let v = original.firstIndex(where: { searchVerbs.contains(normalise($0)) }) else { return nil }
        var q = Array(original[(v + 1)...])
        let filler: Set<String> = ["por", "sobre", "pra", "para", "mim", "no", "na", "google", "internet", "web"]
        while let f = q.first, filler.contains(normalise(f)) { q.removeFirst() }
        while let l = q.last, ["mim", "favor", "google", "internet"].contains(normalise(l)) { q.removeLast() }
        let query = q.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return nil }
        let front = NSWorkspace.shared.frontmostApplication?.bundleURL
        let browser = lastBrowser ?? front.flatMap { isBrowser($0) ? $0 : nil }
        if let browser {
            NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: .init(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
        appendAppLog("nb.log", "[Cloud] local search \(query)")
        CloudMissions.shared.record(.pesquisa)
        return "Pesquisando \(query)."
    }

    /// True while I'm still talking when the command can only mean one app: the name matches
    /// exactly, or only one installed app contains what was said (4+ letters).
    static func isSureEarly(_ text: String) -> Bool {
        let words = normalise(text).split(separator: " ").map(String.init)
        guard let (verb, rest) = findVerb(words), verb != .search else { return false }   // a search ends with the sentence
        let q = squash(stripFiller(rest).joined(separator: " "))
        guard q.count >= 4 else { return false }
        let apps = installedApps()
        if apps.contains(where: { squash($0.name) == q }) { return true }
        return Set(apps.filter { squash($0.name).contains(q) }.map(\.url)).count == 1
    }

    // MARK: Parsing

    private enum Verb { case open, quit, search }

    private static let searchVerbs: Set<String> = ["pesquisa", "pesquise", "pesquisar", "procura", "procure",
                                                   "procurar", "busca", "busque", "buscar", "googla", "search"]

    /// Words that start a new request after "e" ("…e vê a conversa do João").
    private static let chatVerbs: Set<String> = ["ve", "ver", "olha", "manda", "mande", "mandar",
                                                 "envia", "escreve", "chama"]

    private static func isVerb(_ w: String) -> Bool {
        openVerbs.contains(w) || quitVerbs.contains(w) || searchVerbs.contains(w) || chatVerbs.contains(w)
    }

    private static let openVerbs: Set<String> = ["abre", "abra", "abrir", "abri", "abrindo", "open", "inicia", "iniciar"]
    private static let quitVerbs: Set<String> = ["fecha", "feche", "fechar", "encerra", "encerrar", "quit"]

    /// The first open/quit verb and the words after it, only when the phrase starts like a
    /// request (no long sentence before the verb: "o vídeo que eu abri ontem" is not one).
    private static func findVerb(_ words: [String]) -> (Verb, [String])? {
        for (i, w) in words.enumerated() where i <= 5 {
            if openVerbs.contains(w) { return (.open, Array(words[(i + 1)...])) }
            if searchVerbs.contains(w) { return (.search, Array(words[(i + 1)...])) }
            if quitVerbs.contains(w) { return (.quit, Array(words[(i + 1)...])) }
        }
        return nil
    }

    private static let leading: Set<String> = ["o", "a", "os", "as", "um", "uma", "meu", "minha", "app", "aplicativo", "programa", "pra", "para", "mim", "me"]
    private static let trailingPhrases: [[String]] = [["pra", "mim"], ["para", "mim"], ["por", "favor"], ["agora"], ["ai"], ["aí"]]

    private static func stripFiller(_ words: [String]) -> [String] {
        var w = words
        while let f = w.first, leading.contains(f) { w.removeFirst() }
        var changed = true
        while changed {
            changed = false
            for p in trailingPhrases where w.count > p.count && Array(w.suffix(p.count)) == p {
                w.removeLast(p.count); changed = true
            }
        }
        return w
    }

    private static func normalise(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: Apps

    struct App { let name: String; let url: URL }

    /// Installed apps, matched ignoring case, accents and spaces ("da vinci" → DaVinci Resolve).
    private static func findApp(_ query: String) -> App? {
        let q = squash(query)
        guard q.count >= 2 else { return nil }
        let apps = installedApps()
        if let exact = apps.first(where: { squash($0.name) == q }) { return exact }
        // Shortest name that contains the query: "safari" → Safari, not "Safari Technology Preview".
        return apps.filter { squash($0.name).contains(q) }.min { $0.name.count < $1.name.count }
            ?? apps.filter { q.contains(squash($0.name)) && $0.name.count >= 3 }.max { $0.name.count < $1.name.count }
    }

    private static func squash(_ s: String) -> String {
        normalise(s).replacingOccurrences(of: " ", with: "")
    }

    /// The file name and, when different, the name the Mac shows (Calculator → Calculadora).
    private static func entries(_ url: URL) -> [App] {
        let file = url.deletingPathExtension().lastPathComponent
        var shown = FileManager.default.displayName(atPath: url.path)
        if shown.hasSuffix(".app") { shown = String(shown.dropLast(4)) }
        return shown == file ? [App(name: file, url: url)] : [App(name: shown, url: url), App(name: file, url: url)]
    }

    private static func installedApps() -> [App] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                    "/System/Applications/Utilities", fm.homeDirectoryForCurrentUser.path + "/Applications"]
        var out: [App] = []
        for d in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: d) else { continue }
            for item in items where item.hasSuffix(".app") {
                out += entries(URL(fileURLWithPath: d).appendingPathComponent(item))
            }
            // One level of folders ("/Applications/DaVinci Resolve/DaVinci Resolve.app").
            for item in items where !item.hasSuffix(".app") {
                let sub = (d as NSString).appendingPathComponent(item)
                guard let inner = try? fm.contentsOfDirectory(atPath: sub) else { continue }
                for i in inner where i.hasSuffix(".app") {
                    out += entries(URL(fileURLWithPath: sub).appendingPathComponent(i))
                }
            }
        }
        return out
    }
}
#endif

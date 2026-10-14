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

    // MARK: Commands inside natural speech

    /// Verbs that start a command wherever they are ("eu quero que você pesquise…").
    static let commandVerbs: Set<String> = [
        "abre", "abra", "abrir", "fecha", "feche", "fechar", "entra", "entre", "entrar", "acessa", "acesse", "acessar",
        "pesquisa", "pesquise", "pesquisar", "procura", "procure", "procurar", "busca", "busque", "buscar",
        "clica", "clique", "clicar", "aperta", "aperte", "apertar", "digita", "digite", "digitar", "escreve", "escreva",
        "coloca", "coloque", "colocar", "bota", "bote", "toca", "toque", "tocar", "poe", "rola", "role", "rolar",
        "volta", "volte", "voltar", "recarrega", "recarregue", "copia", "copie", "cola", "cole", "pausa", "pause",
        "seleciona", "selecione", "manda", "mande", "inicia", "inicie", "minimiza", "assiste", "vai",
    ]
    private static let joiners: Set<String> = ["e", "depois", "entao", "ai", "que", "voce", "tambem", "e", "dai"]
    private static let fillers: [String] = [
        "eu quero que voce", "quero que voce", "eu queria que voce", "queria que voce", "preciso que voce",
        "eu preciso que voce", "faz o seguinte", "faca o seguinte", "voce pode", "voce consegue", "pode", "consegue",
        "por favor", "pra mim", "para mim", "agora", "la", "ai", "entao", "depois", "e", "tambem", "dai",
    ]

    /// Splits natural speech into commands: each starts at a command verb and runs until the next
    /// one. Inside a search, a typed text or a message, a verb only starts a new command after
    /// "e / depois / que / você" (the query may contain verbs). Leading filler is dropped.
    static func commands(_ text: String) -> [String] { commandsWithStart(text).map(\.text) }

    /// The same, each with the word index where it starts (-1 for what came before the first verb):
    /// a stable key while the sentence is still growing.
    static func commandsWithStart(_ text: String) -> [(start: Int, text: String)] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let norms = words.map { normalise($0) }
        var starts: [Int] = []
        var freeText = false   // the current command takes any words (search, typing, message)
        for (i, w) in norms.enumerated() where commandVerbs.contains(w) {
            if w == "vai", !(i + 1 < norms.count && ["no", "na", "pro", "pra", "para", "ao"].contains(norms[i + 1])) { continue }
            let prev = i > 0 ? norms[i - 1] : ""
            let afterPause = i > 0 && words[i - 1].last.map { ",.;!?".contains($0) } == true
            if starts.isEmpty || !freeText || joiners.contains(prev) || afterPause {
                starts.append(i)
                freeText = searchVerbs.contains(w) || ["digita", "digite", "escreve", "escreva", "manda", "mande"].contains(w)
            } else if ["dizendo", "falando"].contains(prev) { continue }
        }
        guard let first = starts.first else { return [(-1, text)] }
        var out: [(start: Int, text: String)] = []
        // What came before the first verb, when it says something (not just "faz o seguinte").
        let pre = clean(Array(words[..<first]))
        if pre.split(separator: " ").count >= 3 { out.append((-1, pre)) }
        for (k, st) in starts.enumerated() {
            let end = k + 1 < starts.count ? starts[k + 1] : words.count
            let c = clean(Array(words[st..<end]))
            if !c.isEmpty { out.append((st, c)) }
        }
        return out
    }

    /// Without filler at the ends ("…e eu quero que você" → "…").
    private static func clean(_ ws: [String]) -> String {
        var w = ws
        var changed = true
        while changed && !w.isEmpty {
            changed = false
            for f in fillers {
                let fw = f.split(separator: " ").map(String.init)
                if w.count >= fw.count, w.prefix(fw.count).map(normalise) == fw { w.removeFirst(fw.count); changed = true }
                if w.count >= fw.count, w.suffix(fw.count).map(normalise) == fw { w.removeLast(fw.count); changed = true }
            }
        }
        return w.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    /// Runs the clauses from `skip` on, in order, until one needs Claude. Returns what Cloud
    /// says for each local one and the rest of the request for Claude (nil when all were local).
    static func process(_ text: String, early: [Int: Bool] = [:], expanded: Bool = false) -> (replies: [String], rest: String?) {
        let skip = early.isEmpty ? 0 : 1
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
        // Every command that runs here runs now (some already did while I was talking); only
        // the others go to Claude, together. One that needs Claude no longer holds the rest.
        let cmds = commandsWithStart(text)
        var replies: [String] = []
        var forClaude: [String] = []
        for (start, c) in cmds {
            if early[start] == true { continue }
            if let r = handle(c) { replies.append(r) } else { forClaude.append(c) }
        }
        _ = skip
        return (replies, forClaude.isEmpty ? nil : forClaude.joined(separator: " e "))
    }

    /// One request, when it is local (open/quit an app, search the web, a WhatsApp chat); nil otherwise.
    static func handle(_ text: String) -> String? {
        if let r = whatsApp(text) { return r }
        // On the screen and on the web: click, type, keys, scroll, "entra no YouTube e pesquisa…".
        if let r = ScreenActions.handle(text) { return r }
        let words = normalise(text).split(separator: " ").map(String.init)
        guard let (verb, rest) = findVerb(words) else { return nil }
        if verb == .search { return search(text) }
        let query = stripFiller(rest).joined(separator: " ")
        guard !query.isEmpty else { return nil }
        if verb == .open, let r = openFolder(rest) ?? openSiteIfNamed(rest) { return r }
        guard var app = findApp(query) else {
            if verb == .open, let r = openSite(query) { return r }
            return verb == .open ? nil : "Não achei nenhum app aberto com esse nome."   // Claude may know better
        }
        var swapped = false
        if verb == .open, Bundle(url: app.url)?.bundleIdentifier == "com.apple.Safari", let c = chromiumBrowser {
            app = App(name: FileManager.default.displayName(atPath: c.path).replacingOccurrences(of: ".app", with: ""), url: c)
            swapped = true
        }
        switch verb {
        case .open:
            NSWorkspace.shared.openApplication(at: app.url, configuration: .init(), completionHandler: nil)
            if isBrowser(app.url) { lastBrowser = app.url }
            lastOpenedApp = squash(app.name)
            CloudMissions.shared.record(.app)
            appendAppLog("nb.log", "[Cloud] local open \(app.name)")
            return swapped ? "Abrindo o \(app.name) no lugar do Safari, que tem limitações." : "Abrindo o \(app.name)."
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
        if let browser = webBrowser {
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
            if let message, let enc = Self.queryEncoded(message) {
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
              let encoded = Self.queryEncoded(query),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return nil }
        if let browser = webBrowser {
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
        if ScreenActions.isSure(text) { return true }
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
            || ScreenActions.verbs.contains(w)
    }

    /// Chrome or one of its family, first one installed: Safari blocks too much (pages hidden from
    /// automation, JavaScript locked), so the web always goes to a Chromium browser when there is one.
    static let chromiumIDs = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
                              "company.thebrowser.Browser", "org.chromium.Chromium", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]

    static var chromiumBrowser: URL? {
        // The one already running first, then the first installed.
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        for id in chromiumIDs where running.contains(id) {
            if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return u }
        }
        return chromiumIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    /// The browser for the web: the last Chromium one I used, else any Chromium, else what I had.
    static var webBrowser: URL? {
        if let l = lastBrowser, let id = Bundle(url: l)?.bundleIdentifier, chromiumIDs.contains(id) { return l }
        if let c = chromiumBrowser { return c }
        let front = NSWorkspace.shared.frontmostApplication?.bundleURL
        return lastBrowser ?? front.flatMap { isBrowser($0) ? $0 : nil }
    }

    /// Opens a link in the web browser (Chrome family first), or the default.
    static func openInBrowser(_ url: URL) {
        if let browser = webBrowser {
            NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: .init(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    static func isBrowserApp(_ url: URL?) -> Bool { url.map(isBrowser) ?? false }

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

    /// Words the recognizer should expect (it runs in Portuguese): the apps installed here, the
    /// sites Cloud knows and common English words of apps and sites, so "abre o Final Cut" or
    /// "clica em Download" come out as said instead of a Portuguese look-alike.
    static func recognizerHints() -> [String] {
        let apps = installedApps().map(\.name)
            .filter { $0.count >= 3 && $0.split(separator: " ").count <= 3 && !$0.lowercased().contains("uninstall") }
        let sites = ScreenActions.sites.values.map(\.name)
        let english = ["YouTube", "Chrome", "Google", "Spotify", "WhatsApp", "Instagram", "TikTok", "Netflix", "Gmail",
                       "play", "pause", "download", "upload", "login", "logout", "settings", "share", "like", "subscribe",
                       "filter", "filters", "search", "home", "next", "skip", "shorts", "reels", "story", "stories",
                       "feed", "post", "link", "email", "save", "export", "render", "timeline", "preset", "template"]
        var seen = Set<String>(), out: [String] = []
        for w in english + sites + apps where seen.insert(w.lowercased()).inserted { out.append(w) }
        return Array(out.prefix(160))
    }

    /// A value for a URL query: everything but letters, digits and -._~ is escaped, so "&", "+",
    /// "=" and "#" in what was said can't cut the query short.
    static func queryEncoded(_ s: String) -> String? {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~")))
    }

    /// Cached for a minute: while I'm talking, every partial result asks for the app list.
    private static var appsCache: (list: [App], at: Date)?

    private static func installedApps() -> [App] {
        if let c = appsCache, Date().timeIntervalSince(c.at) < 60 { return c.list }
        let list = scanInstalledApps()
        appsCache = (list, Date())
        return list
    }

    private static func scanInstalledApps() -> [App] {
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

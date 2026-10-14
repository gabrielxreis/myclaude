#if !APPSTORE
import AppKit
import ApplicationServices

// MARK: - Acting on the screen, instantly, in any app
//
// What I say while using an app runs right here (Accessibility and synthetic keys), in a
// fraction of a second, without asking Claude: "clica em Inscrever-se", "digita bom dia",
// "aperta enter", "volta", "rola pra baixo", "nova aba", "pausa"… and on the web
// "entra no YouTube e pesquisa X", "pesquisa X na Amazon", "coloca o vídeo mais assistido de X".
// Anything else still goes to Claude (with Peekaboo when it is on).

@MainActor
enum ScreenActions {

    // MARK: Sites and their search pages

    struct Site { let name: String; let home: String; let search: String }   // search: "%@" = query

    static let sites: [String: Site] = [
        "youtube": Site(name: "YouTube", home: "https://www.youtube.com", search: "https://www.youtube.com/results?search_query=%@"),
        "google": Site(name: "Google", home: "https://www.google.com", search: "https://www.google.com/search?q=%@"),
        "amazon": Site(name: "Amazon", home: "https://www.amazon.com.br", search: "https://www.amazon.com.br/s?k=%@"),
        "mercado livre": Site(name: "Mercado Livre", home: "https://www.mercadolivre.com.br", search: "https://lista.mercadolivre.com.br/%@"),
        "wikipedia": Site(name: "Wikipédia", home: "https://pt.wikipedia.org", search: "https://pt.wikipedia.org/w/index.php?search=%@"),
        "github": Site(name: "GitHub", home: "https://github.com", search: "https://github.com/search?q=%@"),
        "maps": Site(name: "Google Maps", home: "https://maps.google.com", search: "https://www.google.com/maps/search/%@"),
        "google maps": Site(name: "Google Maps", home: "https://maps.google.com", search: "https://www.google.com/maps/search/%@"),
        "spotify": Site(name: "Spotify", home: "https://open.spotify.com", search: "https://open.spotify.com/search/%@"),
        "instagram": Site(name: "Instagram", home: "https://www.instagram.com", search: "https://www.instagram.com/explore/search/keyword/?q=%@"),
        "tiktok": Site(name: "TikTok", home: "https://www.tiktok.com", search: "https://www.tiktok.com/search?q=%@"),
        "pinterest": Site(name: "Pinterest", home: "https://br.pinterest.com", search: "https://br.pinterest.com/search/pins/?q=%@"),
        "netflix": Site(name: "Netflix", home: "https://www.netflix.com", search: "https://www.netflix.com/search?q=%@"),
        "imagens": Site(name: "Google Imagens", home: "https://images.google.com", search: "https://www.google.com/search?tbm=isch&q=%@"),
    ]

    /// The site I entered last ("entra no YouTube"), so "pesquisa X" right after searches there.
    private static var lastSite: (key: String, at: Date)?
    /// The last thing searched, so "coloca o mais assistido" right after uses it.
    private static var lastQuery: (q: String, at: Date)?

    // MARK: Entry point

    /// Handles `text` when it is a screen or web action; nil otherwise (it goes on).
    static func handle(_ text: String) -> String? {
        let n = norm(text)
        if let r = webAction(text, n) { return r }
        if let r = keyAction(n) { return r }
        if let r = typeAction(text, n) { return r }
        if let r = clickAction(text, n) { return r }
        return nil
    }

    /// Complete as soon as heard (safe to run while I'm still talking): entering a known site.
    static func isSure(_ text: String) -> Bool {
        let n = norm(text)
        guard let first = n.split(separator: " ").first.map(String.init),
              ["entra", "entre", "entrar", "acessa", "acesse", "abre", "abra", "vai"].contains(first),
              siteKey(in: n) != nil else { return false }
        return !["pesquisa", "pesquise", "procura", "busca", "coloca", "toca"].contains(where: n.contains)
    }

    /// Verbs that start a new request inside a sentence ("…e clica em…").
    static let verbs: Set<String> = ["entra", "entrar", "acessa", "acessar", "vai", "clica", "clique", "clicar", "aperta",
                                     "aperte", "digita", "digite", "escreve", "rola", "role", "volta", "avanca", "recarrega",
                                     "atualiza", "coloca", "coloque", "bota", "toca", "toque", "poe", "assiste", "pausa",
                                     "pause", "continua", "seleciona", "copia", "cola", "minimiza", "maximiza"]

    // MARK: Web

    private static func webAction(_ text: String, _ n: String) -> String? {
        let words = n.split(separator: " ").map(String.init)
        guard let first = words.first else { return nil }

        // "entra no YouTube", "vai no site da Amazon", "acessa o Mercado Livre"
        if ["entra", "entre", "entrar", "acessa", "acesse", "acessar", "vai", "abre", "abra", "abrir"].contains(first),
           let key = siteKey(in: n), !n.contains("pesquisa"), !n.contains("procura"), !n.contains("busca") {
            lastSite = (key, Date())
            open(sites[key]!.home)
            return "Entrando no \(sites[key]!.name)."
        }

        // "clica no primeiro vídeo", "abre o primeiro resultado"
        if (n.contains("primeiro") || n.contains("primeira")) && ["video", "resultado", "link", "musica"].contains(where: n.contains),
           ["clica", "clique", "abre", "abrir", "toca", "coloca", "entra"].contains(first) {
            return pressFirstResult() ? "Abrindo o primeiro." : "Não achei o primeiro resultado na tela."
        }
        // "coloca / toca / bota o vídeo mais assistido de carros" → YouTube (or Spotify), plays the first.
        if ["coloca", "coloque", "bota", "toca", "toque", "poe", "assiste", "assistir"].contains(first) {
            let mostViewed = ["mais assistido", "mais visto", "mais visualizado", "mais popular", "mais famoso"].contains { n.contains($0) }
            let spotify = n.contains("spotify")
            var q = stripQuery(text, drop: ["coloca", "coloque", "bota", "toca", "toque", "poe", "põe", "assiste", "assistir", "pra", "para",
                                             "mim", "um", "uma", "o", "a", "os", "as", "video", "vídeo", "videos", "vídeos", "musica",
                                             "música", "clipe", "mais", "assistido", "visto", "visualizado", "popular", "famoso",
                                             "de", "do", "da", "sobre", "no", "na", "youtube", "spotify", "aí", "ai"])
            q = q.trimmingCharacters(in: .whitespaces)
            if q.isEmpty, let l = lastQuery, Date().timeIntervalSince(l.at) < 180 { q = l.q }
            guard !q.isEmpty else { return nil }
            lastQuery = (q, Date())
            let key = spotify ? "spotify" : "youtube"
            var url = String(format: sites[key]!.search, encode(q))
            if key == "youtube" && mostViewed { url += "&sp=CAM%253D" }   // sorted by view count
            open(url)
            lastSite = (key, Date())
            if key == "youtube" { playFirstResult() }
            return mostViewed ? "Colocando o vídeo mais assistido de \(q)." : "Colocando \(q) no \(sites[key]!.name)."
        }

        // "pesquisa X no YouTube" / "pesquisa X" right after entering a site.
        if ["pesquisa", "pesquise", "pesquisar", "procura", "procure", "busca", "busque", "buscar"].contains(first) {
            var key = siteKey(in: n)
            if key == nil, let l = lastSite, Date().timeIntervalSince(l.at) < 120, l.key != "google" { key = l.key }
            guard let k = key else { return nil }   // plain search: Google, as before
            let q = stripQuery(text, drop: ["pesquisa", "pesquise", "pesquisar", "procura", "procure", "busca", "busque", "buscar",
                                             "por", "sobre", "pra", "para", "mim", "no", "na", "site", "do", "da", "o", "a"]
                                + sites[k]!.name.lowercased().split(separator: " ").map(String.init) + [k])
            guard !q.isEmpty else { return nil }
            lastQuery = (q, Date())
            open(String(format: sites[k]!.search, encode(q)))
            lastSite = (k, Date())
            CloudMissions.shared.record(.pesquisa)
            return "Pesquisando \(q) no \(sites[k]!.name)."
        }

        return nil
    }

    private static func siteKey(in n: String) -> String? {
        sites.keys.sorted { $0.count > $1.count }.first { k in
            n.range(of: "(^|\\s)\(k)($|\\s)", options: .regularExpression) != nil
        }
    }

    /// The query in the original words, without the command words.
    private static func stripQuery(_ text: String, drop: [String]) -> String {
        let dropSet = Set(drop.map(norm))
        var words = text.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: .punctuationCharacters) }
        while let f = words.first, dropSet.contains(norm(f)) { words.removeFirst() }
        while let l = words.last, dropSet.contains(norm(l)) { words.removeLast() }
        // "… no YouTube" in the middle: cut from the site name on.
        if let i = words.firstIndex(where: { sites[norm($0)] != nil }), i > 0 {
            words = Array(words[..<i])
            while let l = words.last, dropSet.contains(norm(l)) { words.removeLast() }
        }
        return words.joined(separator: " ")
    }

    private static func encode(_ s: String) -> String { CloudLocalActions.queryEncoded(s) ?? s }

    private static var lastWebOpen = Date.distantPast

    /// Opens a page. Right after another one (one sentence: "entra no YouTube e pesquisa…"),
    /// the same tab is used in Safari or Chrome instead of piling up new tabs.
    private static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        let recent = Date().timeIntervalSince(lastWebOpen) < 45
        lastWebOpen = Date()
        if recent, navigateFrontTab(link) {
            appendAppLog("nb.log", "[Cloud] screen web (same tab) \(link)")
            return
        }
        CloudLocalActions.openInBrowser(url)
        appendAppLog("nb.log", "[Cloud] screen web \(link)")
    }

    private static func navigateFrontTab(_ link: String) -> Bool {
        let esc = link.replacingOccurrences(of: "\"", with: "%22")
        // Chrome family only (Safari is never the web browser when one of them is there).
        guard let browser = CloudLocalActions.webBrowser, let id = Bundle(url: browser)?.bundleIdentifier,
              let name = chromiumBrowsers[id],
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }) else { return false }
        let script = "tell application \"\(name)\" to set URL of active tab of front window to \"\(esc)\""
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        return err == nil
    }

    /// After a YouTube search opens: press the first video as soon as the results are there.
    private static func playFirstResult() {
        var tries = 0
        func attempt() {
            tries += 1
            if pressFirstResult() { return }
            if tries < 12 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { attempt() } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { attempt() }
    }

    /// The first result link of the page in front (a long title, highest on the page).
    @discardableResult
    static func pressFirstResult() -> Bool {
        targets().contains { pressFirstResult(in: $0) }
    }

    private static func pressFirstResult(in app: NSRunningApplication) -> Bool {
        if isBrowser(app), firstResultInPage(app: app) {
            appendAppLog("nb.log", "[Cloud] screen first result (page)")
            return true
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.6)
        var best: (el: AXUIElement, y: CGFloat)?
        walk(window(of: ax), limit: 9000, deadline: Date().addingTimeInterval(1.5)) { el, role in
            guard role == "AXLink" || role == "AXHeading" else { return }
            let t = title(el)
            guard t.count >= 18, let f = frame(el), f.minY > 140, f.width > 60 else { return }
            let lower = t.lowercased()
            if ["inscrever", "shorts", "início", "inicio", "explorar", "biblioteca", "histórico", "pular"].contains(where: lower.contains) { return }
            if best == nil || f.minY < best!.y - 4 { best = (el, f.minY) }
        }
        guard let b = best else { return false }
        press(b.el)
        appendAppLog("nb.log", "[Cloud] screen first result \(title(b.el).prefix(60))")
        return true
    }

    // MARK: Keys

    private static func keyAction(_ n: String) -> String? {
        let cmd = CGEventFlags.maskCommand, shift = CGEventFlags.maskShift
        let table: [(phrases: [String], key: CGKeyCode, flags: CGEventFlags, say: String)] = [
            (["aperta enter", "aperte enter", "da enter", "da um enter", "aperta o enter"], 36, [], "Enter."),
            (["aperta esc", "aperte esc", "escape"], 53, [], "Esc."),
            (["aperta tab", "proximo campo"], 48, [], "Tab."),
            (["aperta espaco", "barra de espaco"], 49, [], "Espaço."),
            (["apaga a ultima palavra"], 51, .maskAlternate, "Apaguei a última palavra."),
            (["volta a pagina", "volta pagina", "pagina anterior", "voltar a pagina"], 33, cmd, "Voltando."),
            (["avanca a pagina", "proxima pagina", "avanca"], 30, cmd, "Avançando."),
            (["recarrega", "atualiza a pagina", "recarregar"], 15, cmd, "Recarregando."),
            (["nova aba", "abre uma aba", "abre outra aba"], 17, cmd, "Nova aba."),
            (["fecha a aba", "fecha essa aba", "fechar a aba"], 13, cmd, "Fechei a aba."),
            (["reabre a aba", "abre a aba que fechei"], 17, [cmd, shift], "Reabrindo a aba."),
            (["copia", "copiar isso"], 8, cmd, "Copiado."),
            (["cola", "colar"], 9, cmd, "Colado."),
            (["seleciona tudo", "selecionar tudo"], 0, cmd, "Tudo selecionado."),
            (["desfaz", "desfazer"], 6, cmd, "Desfeito."),
            (["salva", "salvar"], 1, cmd, "Salvo."),
            (["tela cheia"], 3, [cmd, .maskControl], "Tela cheia."),
            (["minimiza"], 46, cmd, "Minimizado."),
            (["proxima aba"], 30, [cmd, shift], "Próxima aba."),
            (["aba anterior"], 33, [cmd, shift], "Aba anterior."),
            (["vai pro endereco", "barra de endereco"], 37, cmd, "Na barra de endereço."),
        ]
        for row in table where row.phrases.contains(where: { n == $0 || n.hasPrefix($0 + " ") || n.hasSuffix(" " + $0) }) {
            key(row.key, row.flags)
            return row.say
        }
        // "volta" alone: back in a browser.
        if n == "volta" || n == "voltar" { key(33, cmd); return "Voltando." }
        // Scroll
        if n.hasPrefix("rola") || n.hasPrefix("role") || n.hasPrefix("desce") || n.hasPrefix("sobe") || n.hasPrefix("rolar") {
            let up = n.contains("cima") || n.hasPrefix("sobe")
            let lots = n.contains("muito") || n.contains("bastante") || n.contains("tudo")
            if n.contains("tudo") { key(up ? 126 : 125, cmd); return up ? "No topo." : "No fim." }
            scroll(up ? (lots ? 25 : 10) : (lots ? -25 : -10))
            return up ? "Subindo." : "Descendo."
        }
        // Play / pause: YouTube uses "k"; elsewhere the space bar.
        if ["pausa", "pause", "pausar", "play", "continua o video", "da play", "solta o video", "despausa"].contains(where: { n == $0 || n.hasPrefix($0 + " ") }) {
            let browser = NSWorkspace.shared.frontmostApplication.map { CloudLocalActions.isBrowserApp($0.bundleURL) } ?? false
            key(browser ? 40 : 49, [])
            return n.contains("pausa") || n.contains("pause") ? "Pausado." : "Play."
        }
        return nil
    }

    // MARK: Typing

    private static func typeAction(_ text: String, _ n: String) -> String? {
        for verb in ["digita", "digite", "escreve", "escreva", "digitar", "escrever"] where n.hasPrefix(verb + " ") {
            var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            words.removeFirst()
            if let f = words.first, ["ai", "aí", "isso", "assim", "o", "a"].contains(norm(f)), words.count > 1 { words.removeFirst() }
            let content = words.joined(separator: " ")
            guard !content.isEmpty else { return nil }
            typeText(content)
            let andEnter = n.hasSuffix(" e aperta enter") || n.hasSuffix(" e da enter")
            if andEnter { key(36, []) }
            return "Digitei."
        }
        return nil
    }

    // MARK: Clicking by name

    private static func clickAction(_ text: String, _ n: String) -> String? {
        let starts = ["clica em ", "clica no ", "clica na ", "clica ", "clique em ", "clique no ", "clique na ", "aperta o botao ",
                      "aperta no botao ", "aperta em ", "aperta o ", "aperta a ", "seleciona o ", "seleciona a ", "marca o ", "marca a "]
        guard let s = starts.first(where: { n.hasPrefix($0) }) else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let skip = s.split(separator: " ").count
        guard words.count > skip else { return nil }
        let label = words[skip...].joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        guard !label.isEmpty else { return nil }
        if pressLabel(label) { return "Cliquei em \(label)." }
        if let f = NSWorkspace.shared.frontmostApplication, let id = f.bundleIdentifier, jsBlocked.contains(id) {
            return "Para eu clicar dentro de sites no \(f.localizedName ?? "navegador"), libere o JavaScript em Ajustes do My Cloud, Permissões."
        }
        return nil   // not found on screen: Claude (and Peekaboo) may do better
    }

    /// Finds a control named like `label` in the app in front and presses it.
    static func pressLabel(_ label: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        return targets().contains { pressLabel(label, in: $0) }
    }

    private static func pressLabel(_ label: String, in app: NSRunningApplication) -> Bool {
        if isBrowser(app), clickInPage(label, app: app) {
            appendAppLog("nb.log", "[Cloud] screen click (page) \(label)")
            return true
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.6)
        let q = norm(label)
        let pressable: Set<String> = ["AXButton", "AXLink", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton",
                                      "AXTab", "AXPopUpButton", "AXMenuButton", "AXCell", "AXRow", "AXDisclosureTriangle", "AXImage"]
        var best: (el: AXUIElement, score: Int)?
        walk(window(of: ax), limit: 9000, deadline: Date().addingTimeInterval(1.5)) { el, role in
            let t = norm(title(el))
            guard !t.isEmpty else { return }
            var score = t == q ? 100 : t.hasPrefix(q) ? 70 : t.contains(q) ? 40 : 0
            if score == 0, q.count >= 4, WakePhrase.distance(t, q) <= max(1, q.count / 5) { score = 30 }
            guard score > 0 else { return }
            if pressable.contains(role) { score += 20 }
            if t.count > q.count * 4 { score -= 25 }   // a long text that just mentions the word
            if best == nil || score > best!.score { best = (el, score) }
        }
        guard let b = best, b.score >= 40 else { return false }
        press(b.el)
        appendAppLog("nb.log", "[Cloud] screen click \(label) (\(b.score))")
        return true
    }

    // MARK: Inside web pages (browsers hide their pages from Accessibility)

    static let chromiumBrowsers: [String: String] = [
        "com.google.Chrome": "Google Chrome", "com.brave.Browser": "Brave Browser",
        "com.microsoft.edgemac": "Microsoft Edge", "company.thebrowser.Browser": "Arc",
    ]

    /// Set when a browser refuses JavaScript from Apple Events (Settings → Permissões explains).
    static var jsBlocked: Set<String> = []

    /// Runs `js` in the front tab of `app` (a browser); its result, or nil.
    static func runJS(_ js: String, in app: NSRunningApplication) -> String? {
        guard let id = app.bundleIdentifier else { return nil }
        let esc = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        if let name = chromiumBrowsers[id] {
            script = "tell application \"\(name)\" to execute active tab of front window javascript \"\(esc)\""
        } else if id == "com.apple.Safari" {
            script = "tell application \"Safari\" to do JavaScript \"\(esc)\" in current tab of front window"
        } else { return nil }
        var err: NSDictionary?
        let out = NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            let msg = (err[NSAppleScript.errorMessage] as? String ?? "").lowercased()
            if msg.contains("javascript") { jsBlocked.insert(id) }
            appendAppLog("nb.log", "[Cloud] screen js error \(id): \(msg.prefix(120))")
            return nil
        }
        jsBlocked.remove(id)
        return out?.stringValue ?? ""
    }

    static func isBrowser(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return chromiumBrowsers[id] != nil || id == "com.apple.Safari"
    }

    /// Clicks the visible link/button whose text (or aria-label) matches, like a person would.
    private static func clickInPage(_ label: String, app: NSRunningApplication) -> Bool {
        let q = label.replacingOccurrences(of: "'", with: " ")
        let js = """
        (function(q){const n=s=>(s||'').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase().replace(/\\s+/g,' ').trim();q=n(q);
        const els=[...document.querySelectorAll('a,button,[role=button],[role=link],[role=tab],[role=menuitem],[role=option],input[type=submit],input[type=button],summary,label,yt-chip-cloud-chip-renderer')];
        let best=null,sc=0;for(const e of els){const r=e.getBoundingClientRect();if(r.width<2||r.height<2||r.bottom<0||r.top>innerHeight*2)continue;
        const t=n((e.getAttribute('aria-label')||'')+' '+(e.innerText||e.value||''));if(!t)continue;
        let s=t===q?100:t.startsWith(q)?70:t.includes(q)?40:0;if(t.length>q.length*4)s-=25;if(s>sc){sc=s;best=e;}}
        if(best&&sc>=40){best.scrollIntoView({block:'center'});best.click();return 'ok';}return 'none';})('\(q)')
        """
        return runJS(js, in: app) == "ok"
    }

    /// The first result of the page: a YouTube video, a Google result, else the first big link.
    private static func firstResultInPage(app: NSRunningApplication) -> Bool {
        let js = """
        (function(){const pick=document.querySelector('ytd-video-renderer a#video-title, ytd-rich-item-renderer a#video-title-link, a#video-title')
        ||document.querySelector('#search a h3')?.closest('a')||[...document.querySelectorAll('main a, a')].find(a=>(a.innerText||'').trim().length>18&&a.getBoundingClientRect().top>100);
        if(pick){pick.click();return 'ok';}return 'none';})()
        """
        return runJS(js, in: app) == "ok"
    }

    // MARK: Accessibility helpers

    /// Where to look: the app in front, then (right after a web action) the browser just used.
    private static func targets() -> [NSRunningApplication] {
        var out: [NSRunningApplication] = []
        if let f = NSWorkspace.shared.frontmostApplication, f.bundleIdentifier != Bundle.main.bundleIdentifier { out.append(f) }
        if Date().timeIntervalSince(lastWebOpen) < 180 {
            let ids = ["com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac", "com.apple.Safari"]
            if let b = NSWorkspace.shared.runningApplications.first(where: { ids.contains($0.bundleIdentifier ?? "") && !out.contains($0) }) {
                out.append(b)
            }
        }
        return out
    }

    private static func window(of app: AXUIElement) -> AXUIElement {
        var w: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success, let w {
            return (w as! AXUIElement)
        }
        return app
    }

    /// Breadth-first over the tree, with a node and time budget.
    private static func walk(_ root: AXUIElement, limit: Int, deadline: Date, _ visit: (AXUIElement, String) -> Void) {
        var queue = [root], i = 0
        while i < queue.count, i < limit, Date() < deadline {
            let el = queue[i]; i += 1
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
            visit(el, roleRef as? String ?? "")
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success,
               let arr = kids as? [AXUIElement] { queue.append(contentsOf: arr) }
        }
    }

    static func title(_ el: AXUIElement) -> String {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let s = v as? String,
               !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
        }
        return ""
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    /// AXPress, else a real click in its middle.
    private static func press(_ el: AXUIElement) {
        if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success { return }
        guard let f = frame(el) else { return }
        let c = CGPoint(x: f.midX, y: f.midY)
        for t in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Synthetic input

    static func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    static func typeText(_ s: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        let units = Array(s.utf16)
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + 16, units.count)])
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                chunk.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                e?.post(tap: .cghidEventTap)
            }
            i += 16
        }
    }

    private static func scroll(_ lines: Int32) {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    static func norm(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
    }
}
#endif

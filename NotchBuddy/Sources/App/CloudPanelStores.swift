#if !APPSTORE
import Foundation

// MARK: - Routines, triggers, missions and achievements
//
// Saved as JSON in ~/Library/Application Support/MyCloud (Cloud itself may edit routines.json and
// gatilhos.json when asked by voice). The Cloud panel (CloudPanel.swift) shows and edits them.

private func myCloudFile(_ name: String) -> URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MyCloud", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

private func load<T: Decodable>(_ file: URL, _ fallback: T) -> T {
    guard let d = try? Data(contentsOf: file), let v = try? JSONDecoder().decode(T.self, from: d) else { return fallback }
    return v
}

private func store<T: Encodable>(_ v: T, _ file: URL) {
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    if let d = try? e.encode(v) { try? d.write(to: file, options: .atomic) }
}

// MARK: Routines ("todo dia às 8h, faz tal coisa")

struct CloudRoutine: Codable, Identifiable, Equatable {
    var id = UUID()
    var nome: String
    var hora: Int            // 0–23
    var minuto: Int          // 0–59
    var dias: Set<Int>       // 1 = domingo … 7 = sábado (Calendar.weekday)
    var pedido: String
    var ativa = true
    var ultimaVez: Date?

    init(nome: String, hora: Int, minuto: Int, dias: Set<Int>, pedido: String) {
        self.nome = nome; self.hora = hora; self.minuto = minuto; self.dias = dias; self.pedido = pedido
    }
    // Cloud writes this file by voice: missing fields get defaults instead of breaking the list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        nome = (try? c.decode(String.self, forKey: .nome)) ?? "Rotina"
        hora = (try? c.decode(Int.self, forKey: .hora)) ?? 9
        minuto = (try? c.decode(Int.self, forKey: .minuto)) ?? 0
        dias = (try? c.decode(Set<Int>.self, forKey: .dias)) ?? Set(1...7)
        pedido = (try? c.decode(String.self, forKey: .pedido)) ?? ""
        ativa = (try? c.decode(Bool.self, forKey: .ativa)) ?? true
        ultimaVez = try? c.decode(Date.self, forKey: .ultimaVez)
    }
}

@MainActor
final class RoutineStore: ObservableObject {
    static let shared = RoutineStore()
    static var file: URL { myCloudFile("rotinas.json") }
    @Published var routines: [CloudRoutine] = [] { didSet { store(routines, Self.file) } }
    private var timer: Timer?
    private var lastModified: Date?

    static let templates: [CloudRoutine] = [
        CloudRoutine(nome: "Bom dia", hora: 8, minuto: 0, dias: Set(2...6), pedido: "bom dia"),
        CloudRoutine(nome: "Backup noturno", hora: 23, minuto: 30, dias: Set(1...7),
                     pedido: "Copie com rsync a pasta ~/Documents/Projetos para o SSD conectado, na pasta Backup, e me diga se deu certo."),
        CloudRoutine(nome: "Resumo do dia", hora: 18, minuto: 30, dias: Set(2...6),
                     pedido: "Me dê um resumo curto do que as sessões do Claude Code fizeram hoje."),
        CloudRoutine(nome: "Ideias de conteúdo", hora: 9, minuto: 30, dias: [2],
                     pedido: "/ogab pauta: 5 ideias de Reels para esta semana"),
    ]

    private init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in RoutineStore.shared.tick() }
        }
    }

    func reload() {
        let mod = (try? FileManager.default.attributesOfItem(atPath: Self.file.path))?[.modificationDate] as? Date
        guard mod != lastModified else { return }
        lastModified = mod
        let list: [CloudRoutine] = load(Self.file, [])
        if list != routines { routines = list }
    }

    /// Every 20 s: a routine whose minute has come (once per day) runs.
    private func tick() {
        reload()
        let now = Date(), cal = Calendar.current
        let c = cal.dateComponents([.weekday, .hour, .minute], from: now)
        for i in routines.indices where routines[i].ativa {
            let r = routines[i]
            guard r.dias.contains(c.weekday ?? 0), r.hora == c.hour, r.minuto == c.minute else { continue }
            if let last = r.ultimaVez, cal.isDate(last, inSameDayAs: now) { continue }
            routines[i].ultimaVez = now
            run(r)
        }
    }

    func run(_ r: CloudRoutine) {
        appendAppLog("nb.log", "[Cloud] routine \(r.nome)")
        CloudMissions.shared.record(.rotina)
        Task { @MainActor in
            let id = CloudChatStore.shared.newConversation()
            let answer = await CloudChatStore.shared.send(r.pedido, in: id, voice: false) ?? "não consegui rodar agora"
            let short = answer.count > 160 ? String(answer.prefix(157)) + "…" : answer
            let esc = "\(r.nome): \(short)".replacingOccurrences(of: "\"", with: "'")
            NSAppleScript(source: "display notification \"\(esc)\" with title \"My Cloud · Rotina\" sound name \"Glass\"")?
                .executeAndReturnError(nil)
        }
    }
}

// MARK: Triggers ("modo edição" → a request)

struct CloudTrigger: Codable, Identifiable, Equatable {
    var id = UUID()
    var frase: String
    var pedido: String
    var ativo = true

    init(frase: String, pedido: String) { self.frase = frase; self.pedido = pedido }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        frase = (try? c.decode(String.self, forKey: .frase)) ?? ""
        pedido = (try? c.decode(String.self, forKey: .pedido)) ?? ""
        ativo = (try? c.decode(Bool.self, forKey: .ativo)) ?? true
    }
}

@MainActor
final class TriggerStore: ObservableObject {
    static let shared = TriggerStore()
    static var file: URL { myCloudFile("gatilhos.json") }
    @Published var triggers: [CloudTrigger] = [] { didSet { store(triggers, Self.file) } }
    private var lastModified: Date?

    static let templates: [CloudTrigger] = [
        CloudTrigger(frase: "modo edição", pedido: "fecha o WhatsApp e fecha o Mail e abre o DaVinci"),
        CloudTrigger(frase: "fim do dia", pedido: "fecha o DaVinci e abre o WhatsApp"),
        CloudTrigger(frase: "hora do café", pedido: "timer de 15 minutos de café"),
    ]

    private init() { reload() }

    func reload() {
        let mod = (try? FileManager.default.attributesOfItem(atPath: Self.file.path))?[.modificationDate] as? Date
        guard mod != lastModified else { return }
        lastModified = mod
        let list: [CloudTrigger] = load(Self.file, [])
        if list != triggers { triggers = list }
    }

    /// The request a phrase stands for, when it is one of my triggers.
    func expand(_ text: String) -> String? {
        reload()
        // Whole words only: the trigger "foco" must not fire on "focou" or "desfoco".
        let words = { (s: String) in " " + CloudTimers.norm(s).components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ") + " " }
        let n = words(text)
        return triggers.first { t in
            let f = words(t.frase)
            return t.ativo && f.count > 2 && n.contains(f)
        }?.pedido
    }
}

// MARK: Daily missions and achievements

enum CloudEvent: String, Codable, CaseIterable {
    case conversa, cartao, timer, skill, tarefaClaude, rotina, pesquisa, app, video, tela
}

struct CloudMission: Codable, Identifiable, Equatable {
    var id: String { evento.rawValue + "\(meta)" }
    let titulo: String
    let evento: CloudEvent
    let meta: Int
    var feito = 0
    let xp: Int
}

struct CloudAchievement: Identifiable {
    let id: String
    let titulo: String
    let detalhe: String
    let icone: String
    let ok: (CloudMissions) -> Bool
}

@MainActor
final class CloudMissions: ObservableObject {
    static let shared = CloudMissions()
    static var file: URL { myCloudFile("missoes.json") }

    struct State: Codable {
        var dia = ""
        var missoes: [CloudMission] = []
        var totais: [String: Int] = [:]
        var diasSeguidos = 0
        var ultimoDia = ""
        var conquistas: [String: Date] = [:]
    }

    @Published private(set) var state: State { didSet { store(state, Self.file) } }

    private static let pool: [CloudMission] = [
        CloudMission(titulo: "Converse 3 vezes com o Cloud", evento: .conversa, meta: 3, xp: 15),
        CloudMission(titulo: "Use uma skill (/ogab, /ojhon...)", evento: .skill, meta: 1, xp: 20),
        CloudMission(titulo: "Marque um timer", evento: .timer, meta: 1, xp: 10),
        CloudMission(titulo: "Descarregue um cartão", evento: .cartao, meta: 1, xp: 30),
        CloudMission(titulo: "Abra 3 apps pela voz", evento: .app, meta: 3, xp: 10),
        CloudMission(titulo: "Faça 2 pesquisas", evento: .pesquisa, meta: 2, xp: 10),
        CloudMission(titulo: "Deixe o Claude terminar 2 tarefas", evento: .tarefaClaude, meta: 2, xp: 20),
        CloudMission(titulo: "Crie um roteiro a partir de um vídeo", evento: .video, meta: 1, xp: 25),
        CloudMission(titulo: "Peça para o Cloud olhar a tela", evento: .tela, meta: 1, xp: 15),
    ]

    static let achievements: [CloudAchievement] = [
        .init(id: "primeira", titulo: "Primeiro papo", detalhe: "Conversou com o Cloud pela primeira vez", icone: "bubble.left.fill") { $0.total(.conversa) >= 1 },
        .init(id: "falante", titulo: "Falante", detalhe: "100 conversas", icone: "text.bubble.fill") { $0.total(.conversa) >= 100 },
        .init(id: "cartao1", titulo: "Primeiro backup", detalhe: "Descarregou um cartão", icone: "sdcard.fill") { $0.total(.cartao) >= 1 },
        .init(id: "cartao25", titulo: "Rato de set", detalhe: "25 cartões descarregados", icone: "film.stack.fill") { $0.total(.cartao) >= 25 },
        .init(id: "skill10", titulo: "Mestre das skills", detalhe: "Usou skills 10 vezes", icone: "sparkles") { $0.total(.skill) >= 10 },
        .init(id: "pontual", titulo: "Pontual", detalhe: "10 timers e lembretes", icone: "timer") { $0.total(.timer) >= 10 },
        .init(id: "rotina", titulo: "No piloto automático", detalhe: "Uma rotina rodou sozinha", icone: "repeat") { $0.total(.rotina) >= 1 },
        .init(id: "semana", titulo: "Semana inteira", detalhe: "7 dias seguidos com o Cloud", icone: "flame.fill") { $0.state.diasSeguidos >= 7 },
        .init(id: "mes", titulo: "Melhores amigos", detalhe: "30 dias seguidos", icone: "heart.fill") { $0.state.diasSeguidos >= 30 },
        .init(id: "roteirista", titulo: "Roteirista", detalhe: "5 roteiros a partir de vídeos", icone: "doc.text.fill") { $0.total(.video) >= 5 },
        .init(id: "missoes", titulo: "Caçador de missões", detalhe: "Completou todas as missões de um dia", icone: "checkmark.seal.fill") { _ in false },
    ]

    private init() {
        state = load(Self.file, State())
        rollDay()
    }

    func total(_ e: CloudEvent) -> Int { state.totais[e.rawValue] ?? 0 }

    /// Something happened: missions advance, achievements unlock, XP goes to the pet.
    func record(_ e: CloudEvent) {
        rollDay()
        var s = state
        s.totais[e.rawValue, default: 0] += 1
        var gained = 0
        for i in s.missoes.indices where s.missoes[i].evento == e && s.missoes[i].feito < s.missoes[i].meta {
            s.missoes[i].feito += 1
            if s.missoes[i].feito == s.missoes[i].meta { gained += s.missoes[i].xp }
        }
        if !s.missoes.isEmpty, s.missoes.allSatisfy({ $0.feito >= $0.meta }), s.conquistas["missoes"] == nil {
            s.conquistas["missoes"] = Date()
        }
        state = s
        if gained > 0 {
            CloudPet.shared.interacted(xpGain: gained)
            SoundEngine.shared.play("proud")
        }
        for a in Self.achievements where state.conquistas[a.id] == nil && a.ok(self) {
            state.conquistas[a.id] = Date()
            SoundEngine.shared.play("finish")
            let esc = "Conquista: \(a.titulo)! \(a.detalhe)".replacingOccurrences(of: "\"", with: "'")
            NSAppleScript(source: "display notification \"\(esc)\" with title \"My Cloud\" sound name \"Glass\"")?.executeAndReturnError(nil)
        }
    }

    /// A new day: three missions drawn from the pool, the streak goes on (or restarts).
    private func rollDay() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        guard state.dia != today else { return }
        var s = state
        let yesterday = f.string(from: Date().addingTimeInterval(-86400))
        s.diasSeguidos = s.ultimoDia == yesterday ? s.diasSeguidos + 1 : 1
        s.ultimoDia = today
        s.dia = today
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(today.hashValue)))   // abs(Int.min) would crash
        s.missoes = Array(Self.pool.shuffled(using: &rng).prefix(3))
        state = s
    }
}

private struct SeededRandom: RandomNumberGenerator {
    var x: UInt64
    init(seed: UInt64) { x = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return x }
}
#endif

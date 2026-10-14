#if !APPSTORE
import AppKit

// MARK: - Timers and reminders
//
// "timer de 10 minutos", "cronômetro de meia hora", "me avisa em 20 minutos" → a countdown in the
// notch, an alarm sound at the end. "me lembra às 15h de exportar o vídeo" → at that time.
// "quanto falta?", "cancela o timer". Saved to disk: they survive a restart of the app.

@MainActor
final class CloudTimers: ObservableObject {
    static let shared = CloudTimers()

    struct Item: Codable, Identifiable, Equatable {
        var id = UUID()
        let end: Date
        let label: String      // "" for a plain timer
        let isReminder: Bool
    }

    @Published private(set) var items: [Item] = []
    private var ticker: Timer?

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyCloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("timers.json")
    }

    private init() {
        if let d = try? Data(contentsOf: Self.file), let list = try? JSONDecoder().decode([Item].self, from: d) { items = list }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in CloudTimers.shared.tick() }
        }
    }

    /// What the notch shows: the next one to ring.
    var nextLine: String? {
        guard let n = items.min(by: { $0.end < $1.end }) else { return nil }
        let left = max(0, n.end.timeIntervalSinceNow)
        if n.isReminder && left > 3600 {
            return "Lembrete às \(n.end.formatted(date: .omitted, time: .shortened)): \(n.label)"
        }
        let m = Int(left) / 60, s = Int(left) % 60
        let clock = m >= 60 ? String(format: "%d:%02d:%02d", m / 60, m % 60, s) : String(format: "%d:%02d", m, s)
        return n.label.isEmpty ? "Timer: \(clock)" : "\(n.label): \(clock)"
    }

    private func tick() {
        let now = Date()
        guard !items.isEmpty else { return }   // nothing running: no redraw every second
        let due = items.filter { $0.end <= now }
        guard !due.isEmpty else { objectWillChange.send(); return }
        items.removeAll { $0.end <= now }
        save()
        for d in due { ring(d) }
    }

    private func ring(_ item: Item) {
        let text = item.isReminder ? "Lembrete: \(item.label)" : (item.label.isEmpty ? "Acabou o timer!" : "Acabou o timer: \(item.label)")
        // A little alarm: three chimes.
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.45) { SoundEngine.shared.play("finish") }
        }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        CloudPet.shared.interacted(xpGain: 2)
        let esc = text.replacingOccurrences(of: "\"", with: "'")
        NSAppleScript(source: "display notification \"\(esc)\" with title \"My Cloud\" sound name \"Glass\"")?.executeAndReturnError(nil)
        appendAppLog("nb.log", "[Cloud] timer rang: \(text)")
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: Self.file, options: .atomic) }
    }

    // MARK: Understanding requests

    static func isRequest(_ text: String) -> Bool {
        let n = norm(text)
        return ["timer", "cronometro", "temporizador", "me lembra", "me lembre", "lembrete", "me avisa em", "me avise em",
                "quanto falta", "cancela o timer", "cancelar o timer", "para o timer", "cancela o lembrete"].contains { n.contains($0) }
    }

    func handle(_ text: String) -> String {
        let n = Self.norm(text)
        if n.contains("quanto falta") {
            return nextLine.map { "Falta: \($0)." } ?? "Não tem nenhum timer rodando."
        }
        // Explicit only: "timer de 40 minutos para o bolo" is a new timer, not "para o timer".
        let stops = ["cancela", "cancelar", "para o timer", "parar o timer", "pare o timer", "para o lembrete",
                     "desliga o timer", "desligar o timer", "apaga o timer", "apaga o lembrete"]
        if stops.contains(where: { n.contains($0) }) {
            let wasReminder = n.contains("lembrete")
            let before = items.count
            if let i = items.indices.filter({ items[$0].isReminder == wasReminder }).min(by: { items[$0].end < items[$1].end }) {
                items.remove(at: i)
            }
            save()
            return before == items.count ? "Não tinha nenhum para cancelar." : "Cancelei."
        }
        let label = Self.label(from: text)
        let reminder = n.contains("lembra") || n.contains("lembrete")
        if let at = Self.clockTime(n) {
            add(Item(end: at, label: label.isEmpty ? "hora marcada" : label, isReminder: true))
            return "Combinado, te lembro às \(at.formatted(date: .omitted, time: .shortened))" + (label.isEmpty ? "." : " de \(label).")
        }
        if let secs = Self.duration(n) {
            add(Item(end: Date().addingTimeInterval(secs), label: label, isReminder: reminder))
            return "Timer de \(Self.spoken(secs)) começou" + (label.isEmpty ? "." : " para \(label).") + " Te aviso com um barulhinho."
        }
        return "Não entendi o tempo. Diz assim: timer de 10 minutos, ou me lembra às 15h de exportar o vídeo."
    }

    private func add(_ item: Item) {
        CloudMissions.shared.record(.timer)
        items.append(item)
        save()
        CloudPet.shared.interacted()
    }

    // MARK: Parsing

    static func norm(_ s: String) -> String { s.lowercased().folding(options: .diacriticInsensitive, locale: nil) }

    private static let numbers: [String: Double] = [
        "um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7, "oito": 8,
        "nove": 9, "dez": 10, "onze": 11, "doze": 12, "quinze": 15, "vinte": 20, "trinta": 30, "quarenta": 40,
        "quarenta e cinco": 45, "cinquenta": 50, "noventa": 90,
    ]

    /// "10 minutos", "meia hora", "1 hora e meia", "30 segundos", "dez minutos".
    static func duration(_ n: String) -> TimeInterval? {
        if n.contains("meia hora") && !n.contains("hora e meia") { return 1800 }
        var total = 0.0
        let units: [(String, Double)] = [("hora", 3600), ("min", 60), ("seg", 1)]
        let words = n.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        for (i, w) in words.enumerated() {
            guard let unit = units.first(where: { w.hasPrefix($0.0) }) else { continue }
            guard i > 0 else { continue }
            let prev = words[i - 1]
            let value = Double(prev.replacingOccurrences(of: "h", with: "")) ?? numbers[prev]
                ?? (i > 2 ? numbers[words[(i - 3)..<i].joined(separator: " ")] : nil)
            if let v = value { total += v * unit.1 }
        }
        if n.contains("hora e meia") { total += 1800 }
        // "timer de 10" with no unit: minutes.
        if total == 0, let num = words.compactMap({ Double($0) }).first { total = num * 60 }
        return total > 0 ? total : nil
    }

    /// "às 15h", "as 15:30", "às 3 da tarde".
    static func clockTime(_ n: String) -> Date? {
        guard let r = n.range(of: #"\bas (\d{1,2})(?:h|:)?(\d{2})?"#, options: .regularExpression) else { return nil }
        let digits = n[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard var h = digits.first, h < 24 else { return nil }
        let m = digits.count > 1 ? digits[1] : 0
        if (n.contains("da tarde") || n.contains("da noite")) && h < 12 { h += 12 }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = h; c.minute = m
        guard var d = Calendar.current.date(from: c) else { return nil }
        if n.contains("amanha") { d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d }
        else if d < Date() { d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }

    /// What the timer is for: "…de exportar o vídeo", "…pra tirar o bolo".
    static func label(from text: String) -> String {
        let n = norm(text)
        for key in [" de ", " pra ", " para "] {
            // The part after the time, when it reads like a task.
            let parts = n.components(separatedBy: key)
            guard parts.count > 1, let last = parts.last, last.count > 3,
                  !["minuto", "segundo", "hora", "timer", "cronometro"].contains(where: { last.hasPrefix($0) || last.contains(" " + $0) }),
                  last.range(of: #"^\d"#, options: .regularExpression) == nil else { continue }
            let start = text.count - last.count
            return String(text.suffix(text.count - start)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return ""
    }

    static func spoken(_ secs: TimeInterval) -> String {
        let s = Int(secs)
        if s % 3600 == 0 { return s == 3600 ? "1 hora" : "\(s / 3600) horas" }
        if s >= 3600 { return "\(s / 3600)h\(String(format: "%02d", (s % 3600) / 60))" }
        if s % 60 == 0 { return s == 60 ? "1 minuto" : "\(s / 60) minutos" }
        return s < 60 ? "\(s) segundos" : "\(s / 60) min e \(s % 60) s"
    }
}
#endif

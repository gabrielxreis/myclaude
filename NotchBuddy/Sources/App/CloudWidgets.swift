#if !APPSTORE
import AppKit
import EventKit
import SwiftUI

// MARK: - Widgets of the notch's right card
//
// The user picks and orders them (Settings → Geral → Widgets do notch): shortcuts, SSDs, headphones,
// weather, timer, Claude plan, missions, agenda, card copy. Only shortcuts: the card is the
// shortcuts grid, as before; more than one: tiles side by side, scrolling sideways.

enum CloudWidget: String, CaseIterable, Identifiable {
    case atalhos, ssds, fones, clima, timer, plano, missoes, agenda, copia
    var id: String { rawValue }
    var title: String {
        switch self {
        case .atalhos: "Atalhos"
        case .ssds: "SSDs"
        case .fones: "Fones"
        case .clima: "Clima"
        case .timer: "Timer e lembretes"
        case .plano: "Plano do Claude"
        case .missoes: "Missões do dia"
        case .agenda: "Agenda"
        case .copia: "Cópia de cartão"
        }
    }
    var icon: String {
        switch self {
        case .atalhos: "square.grid.2x2.fill"
        case .ssds: "externaldrive.fill"
        case .fones: "airpodspro"
        case .clima: "cloud.sun.fill"
        case .timer: "timer"
        case .plano: "gauge.medium"
        case .missoes: "target"
        case .agenda: "calendar"
        case .copia: "sdcard.fill"
        }
    }

    /// The chosen widgets, in order.
    static var selected: [CloudWidget] {
        get {
            let raw = (UserDefaults.standard.string(forKey: "cloudWidgets") ?? defaultCSV).split(separator: ",").map(String.init)
            let list = raw.compactMap(CloudWidget.init(rawValue:))
            return list.isEmpty ? [.atalhos] : list
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).joined(separator: ","), forKey: "cloudWidgets") }
    }
    static let defaultCSV = "atalhos,ssds,timer,clima"
}

// MARK: Data (refreshed every minute while the app runs)

@MainActor
final class CloudWidgetData: ObservableObject {
    static let shared = CloudWidgetData()

    struct Volume: Identifiable { let id: String; let name: String; let free: Int64; let total: Int64 }
    struct Headphone: Identifiable { let id: String; let name: String; let levels: [(String, Int)] }

    @Published private(set) var volumes: [Volume] = []
    @Published private(set) var headphones: [Headphone] = []
    @Published private(set) var nextEvent: (title: String, date: Date)?
    @Published var calendarDenied = false
    private var timer: Timer?
    private let events = EKEventStore()

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in CloudWidgetData.shared.refresh() }
        }
    }

    func refresh() {
        refreshVolumes()
        if CloudWidget.selected.contains(.fones) { refreshHeadphones() }
        if CloudWidget.selected.contains(.agenda) { refreshAgenda() }
    }

    private func refreshVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityKey]
        volumes = CardOffload.externalVolumes().compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity else { return nil }
            let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            return Volume(id: u.path, name: v.volumeName ?? u.lastPathComponent, free: free, total: Int64(total))
        }
    }

    /// AirPods and other Bluetooth headphones: left, right and case when the system reports them.
    private func refreshHeadphones() {
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            var found: [Headphone] = []
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["SPBluetoothDataType"] as? [[String: Any]] {
                for item in items {
                    for (key, value) in item where key.contains("device_connected") {
                        for dev in (value as? [[String: Any]]) ?? [] {
                            for (name, info) in dev {
                                guard let d = info as? [String: Any] else { continue }
                                let map = [("device_batteryLevelLeft", "E"), ("device_batteryLevelRight", "D"),
                                           ("device_batteryLevelCase", "Estojo"), ("device_batteryLevelMain", "")]
                                let levels = map.compactMap { k, label -> (String, Int)? in
                                    guard let s = d[k] as? String, let v = Int(s.replacingOccurrences(of: "%", with: "")) else { return nil }
                                    return (label, v)
                                }
                                if !levels.isEmpty { found.append(Headphone(id: name, name: name, levels: levels)) }
                            }
                        }
                    }
                }
            }
            let result = found
            await MainActor.run { CloudWidgetData.shared.headphones = result }
        }
    }

    private func refreshAgenda() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            events.requestFullAccessToEvents { _, _ in Task { @MainActor in CloudWidgetData.shared.refreshAgenda() } }
            return
        }
        guard status == .fullAccess else { calendarDenied = true; return }
        let now = Date()
        let pred = events.predicateForEvents(withStart: now, end: now.addingTimeInterval(36 * 3600), calendars: nil)
        let next = events.events(matching: pred).filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }.first
        nextEvent = next.map { ($0.title ?? "Compromisso", $0.startDate) }
    }

    /// Today's events (for "bom dia").
    func todayEvents() -> [EKEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date()), end = start.addingTimeInterval(86400)
        return events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
    }
}

// MARK: The card

struct CloudWidgetsCard: View {
    @AppStorage("cloudWidgets") private var csv: String = CloudWidget.defaultCSV

    var body: some View {
        let list = csv.split(separator: ",").compactMap { CloudWidget(rawValue: String($0)) }
        if list.count <= 1 && (list.first ?? .atalhos) == .atalhos {
            CloudQuickActionsRow()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(list) { w in
                        CloudWidgetTile(widget: w)
                            .frame(width: w == .atalhos ? 196 : 132)
                    }
                }
                .padding(8)
            }
        }
    }
}

struct CloudWidgetTile: View {
    let widget: CloudWidget
    @ObservedObject private var data = CloudWidgetData.shared
    @ObservedObject private var weather = CloudWeather.shared
    @ObservedObject private var timers = CloudTimers.shared
    @ObservedObject private var missions = CloudMissions.shared
    @ObservedObject private var offload = CardOffload.shared
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: widget.icon).font(.system(size: 9, weight: .semibold))
                Text(widget.title.uppercased()).font(.system(size: 8.5, weight: .bold))
            }
            .foregroundColor(Color(hex: "#6B7079"))
            content
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func line(_ text: String, _ color: String = "#D7DAE0", size: CGFloat = 11, bold: Bool = false) -> some View {
        Text(text).font(.system(size: size, weight: bold ? .semibold : .regular)).foregroundColor(Color(hex: color)).lineLimit(1)
    }

    private func bar(_ v: Double, _ color: String) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(Color(hex: color)).frame(width: g.size.width * CGFloat(max(0, min(1, v))))
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder private var content: some View {
        switch widget {
        case .atalhos:
            CloudQuickActionsRow(compact: true)
        case .ssds:
            if data.volumes.isEmpty { line("Nenhum SSD conectado", "#8E939C") }
            ForEach(data.volumes.prefix(3)) { v in
                VStack(alignment: .leading, spacing: 2) {
                    line("\(v.name)  \(Self.gb(v.free)) livres", size: 10)
                    let used = 1 - Double(v.free) / Double(max(v.total, 1))
                    bar(used, used > 0.9 ? "#F87171" : "#60A5FA")
                }
            }
        case .fones:
            if data.headphones.isEmpty { line("Nenhum fone conectado", "#8E939C") }
            ForEach(data.headphones.prefix(2)) { h in
                line(h.name, size: 10, bold: true)
                line(h.levels.map { ($0.0.isEmpty ? "" : $0.0 + " ") + "\($0.1)%" }.joined(separator: "  "), size: 10)
            }
        case .clima:
            if let t = weather.temperature {
                line(String(format: "%.0f°C", t), "#F5F6F8", size: 20, bold: true)
                line(CloudWeather.city + (weather.raining ? " · chovendo" : ""), "#8E939C", size: 10)
            } else { line("Carregando…", "#8E939C") }
        case .timer:
            line(timers.nextLine ?? "Nenhum timer", timers.nextLine == nil ? "#8E939C" : "#FBBF24", size: 11, bold: timers.nextLine != nil)
            if timers.nextLine == nil { line("\"timer de 10 minutos\"", "#6B7079", size: 9.5) }
        case .plano:
            if let u = state.claudePlanUsage, let pct = ClaudePlanGauge.dominantPct(u) {
                line(String(format: "%.0f%% usado", pct), "#F5F6F8", size: 15, bold: true)
                bar(pct / 100, pct > 85 ? "#F87171" : "#34D399")
                if let r = u.fiveHour?.resetsAt { line("volta às \(r.formatted(date: .omitted, time: .shortened))", "#8E939C", size: 9.5) }
            } else { line("Sem dados ainda", "#8E939C") }
        case .missoes:
            ForEach(missions.state.missoes.prefix(3)) { m in
                HStack(spacing: 4) {
                    Image(systemName: m.feito >= m.meta ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9)).foregroundColor(Color(hex: m.feito >= m.meta ? "#34D399" : "#6B7079"))
                    line(m.titulo, size: 9.5)
                }
            }
        case .agenda:
            if let e = data.nextEvent {
                line(e.title, "#F5F6F8", size: 11, bold: true)
                line(e.date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "pt_BR"))), "#8E939C", size: 10)
            } else { line(data.calendarDenied ? "Libere o Calendário nos Ajustes do Mac" : "Nada nas próximas horas", "#8E939C", size: 10) }
        case .copia:
            line(offload.status ?? "Nenhum cartão copiando", offload.status == nil ? "#8E939C" : "#7CC4FF", size: 10.5)
        }
    }

    static func gb(_ bytes: Int64) -> String {
        let g = Double(bytes) / 1_000_000_000
        return g >= 1000 ? String(format: "%.1f TB", g / 1000) : String(format: "%.0f GB", g)
    }
}

// MARK: Settings

struct CloudWidgetsSettings: View {
    @AppStorage("cloudWidgets") private var csv: String = CloudWidget.defaultCSV
    private var raw: [String] {
        get { csv.split(separator: ",").map(String.init) }
        nonmutating set { csv = newValue.joined(separator: ",") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Escolha e ordene o que aparece no card da direita quando o notch abre.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            ForEach(CloudWidget.allCases) { w in
                let on = raw.contains(w.rawValue)
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { on }, set: { v in
                        if v { raw.append(w.rawValue) } else { raw.removeAll { $0 == w.rawValue } }
                        if raw.isEmpty { raw = ["atalhos"] }
                    })) {
                        Label(w.title, systemImage: w.icon)
                    }
                    Spacer()
                    if on, let i = raw.firstIndex(of: w.rawValue) {
                        Button { if i > 0 { raw.swapAt(i, i - 1) } } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(i == 0)
                        Button { if i < raw.count - 1 { raw.swapAt(i, i + 1) } } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(i == raw.count - 1)
                        Text("\(i + 1)º").font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary).frame(width: 24)
                    }
                }
            }
        }
    }
}
#endif

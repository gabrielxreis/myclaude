#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - Cloud's panel: Rotinas, Gatilhos, Missões, Conquistas
//
// Same look as the chat window (dark, rounded cards). Opened from the menu bar, Settings, the
// pet card or by voice ("abre as rotinas").

@MainActor
final class CloudPanelWindow: NSObject, NSWindowDelegate {
    static let shared = CloudPanelWindow()
    private var window: NSWindow?
    private let tab = CloudPanelTab()

    enum Tab: String, CaseIterable, Identifiable {
        case rotinas = "Rotinas", gatilhos = "Gatilhos", missoes = "Missões", conquistas = "Conquistas"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .rotinas: "repeat"
            case .gatilhos: "bolt.fill"
            case .missoes: "target"
            case .conquistas: "rosette"
            }
        }
    }

    func show(_ t: Tab = .rotinas) {
        tab.current = t
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Cloud"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 680, height: 460)
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: CloudPanelView(tab: tab))
            w.center()
            w.setFrameAutosaveName("CloudPanelWindow")
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class CloudPanelTab: ObservableObject {
    @Published var current: CloudPanelWindow.Tab = .rotinas
}

private enum P {   // palette shared with the chat window
    static let bg = Color(hex: "#1B1C20"), side = Color(hex: "#141518"), card = Color(hex: "#23252B")
    static let line = Color.white.opacity(0.07), text = Color(hex: "#EDEFF3"), muted = Color(hex: "#8E939C")
    static let accent = Color(hex: "#7CC4FF")
}

struct CloudPanelView: View {
    @ObservedObject var tab: CloudPanelTab
    @ObservedObject private var pet = CloudPet.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Canvas { ctx, size in
                        CloudPainter(kind: CloudCharacterKind.current, face: .feliz, skin: .padrao, t: 1, faceT: 2, hopT: 9,
                                     blinking: false, look: .zero, cold: false, hot: false, raining: false).draw(in: &ctx, size: size)
                    }
                    .frame(width: 44, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(CloudIdentity.name).font(.system(size: 14, weight: .bold)).foregroundColor(P.text)
                        Text("\(pet.stage) · nv \(pet.level)").font(.system(size: 11)).foregroundColor(P.muted)
                    }
                }
                .padding(.bottom, 14).padding(.top, 30)
                ForEach(CloudPanelWindow.Tab.allCases) { t in
                    Button { tab.current = t } label: {
                        HStack(spacing: 9) {
                            Image(systemName: t.icon).frame(width: 18)
                            Text(t.rawValue)
                            Spacer()
                        }
                        .font(.system(size: 13, weight: tab.current == t ? .semibold : .regular))
                        .foregroundColor(tab.current == t ? P.text : P.muted)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(tab.current == t ? Color.white.opacity(0.08) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(width: 200)
            .background(P.side)
            Divider()
            ScrollView {
                Group {
                    switch tab.current {
                    case .rotinas: RoutinesPane()
                    case .gatilhos: TriggersPane()
                    case .missoes: MissionsPane()
                    case .conquistas: AchievementsPane()
                    }
                }
                .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(P.bg)
        .environment(\.colorScheme, .dark)
    }
}

private struct PaneHeader: View {
    let title: String, subtitle: String
    var action: (String, () -> Void)? = nil
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundColor(P.text)
                Text(subtitle).font(.system(size: 12)).foregroundColor(P.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let action {
                Button(action: action.1) {
                    Label(action.0, systemImage: "plus").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(P.accent)).foregroundColor(Color(hex: "#06121F"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 18)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(P.line))
    }
}

// MARK: Rotinas

private let weekdayLetters = ["D", "S", "T", "Q", "Q", "S", "S"]

private struct RoutinesPane: View {
    @ObservedObject private var store = RoutineStore.shared
    @State private var editing: CloudRoutine?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneHeader(title: "Rotinas", subtitle: "Coisas que o Cloud faz sozinho, no dia e na hora que você escolher. Também dá para pedir por voz: \"todo dia às 8h me dá o resumo\".",
                       action: ("Nova rotina", { editing = CloudRoutine(nome: "", hora: 9, minuto: 0, dias: Set(2...6), pedido: "") }))
            if store.routines.isEmpty {
                Text("Comece por um modelo:").font(.system(size: 12, weight: .semibold)).foregroundColor(P.muted)
            }
            HStack(spacing: 8) {
                ForEach(RoutineStore.templates) { t in
                    Button { var c = t; c.id = UUID(); store.routines.append(c) } label: {
                        Text("+ " + t.nome).font(.system(size: 11, weight: .medium)).foregroundColor(P.text)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
            ForEach(store.routines) { r in routineCard(r) }
        }
        .sheet(item: $editing) { r in
            RoutineEditor(routine: r) { saved in
                if let i = store.routines.firstIndex(where: { $0.id == saved.id }) { store.routines[i] = saved }
                else { store.routines.append(saved) }
                editing = nil
            } cancel: { editing = nil }
        }
    }

    private func routineCard(_ r: CloudRoutine) -> some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                Text(String(format: "%02d:%02d", r.hora, r.minuto))
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(r.ativa ? P.text : P.muted)
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.nome.isEmpty ? "Rotina" : r.nome).font(.system(size: 14, weight: .semibold)).foregroundColor(P.text)
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { d in
                            Text(weekdayLetters[d - 1])
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(r.dias.contains(d) ? P.accent.opacity(0.9) : Color.white.opacity(0.06)))
                                .foregroundColor(r.dias.contains(d) ? Color(hex: "#06121F") : P.muted)
                        }
                    }
                    Text(r.pedido).font(.system(size: 12)).foregroundColor(P.muted).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("", isOn: Binding(get: { r.ativa }, set: { v in
                        if let i = store.routines.firstIndex(where: { $0.id == r.id }) { store.routines[i].ativa = v }
                    })).toggleStyle(.switch).labelsHidden()
                    HStack(spacing: 6) {
                        iconButton("play.fill", "Rodar agora") { store.run(r) }
                        iconButton("pencil", "Editar") { editing = r }
                        iconButton("trash", "Apagar") { store.routines.removeAll { $0.id == r.id } }
                    }
                }
            }
        }
    }
}

private func iconButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: icon).font(.system(size: 11)).foregroundColor(P.muted)
            .frame(width: 26, height: 24).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
    }
    .buttonStyle(.plain).help(help)
}

private struct RoutineEditor: View {
    @State var routine: CloudRoutine
    let save: (CloudRoutine) -> Void
    let cancel: () -> Void
    @State private var time = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(routine.nome.isEmpty ? "Nova rotina" : "Editar rotina").font(.system(size: 18, weight: .bold))
            TextField("Nome (ex.: Bom dia)", text: $routine.nome).textFieldStyle(.roundedBorder)
            HStack {
                Text("Horário").foregroundColor(.secondary)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Dias").foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { d in
                        let on = routine.dias.contains(d)
                        Button {
                            if on { routine.dias.remove(d) } else { routine.dias.insert(d) }
                        } label: {
                            Text(weekdayLetters[d - 1]).font(.system(size: 12, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(on ? P.accent : Color.white.opacity(0.08)))
                                .foregroundColor(on ? Color(hex: "#06121F") : P.text)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Todo dia") { routine.dias = Set(1...7) }.buttonStyle(.link).padding(.leading, 6)
                    Button("Dias úteis") { routine.dias = Set(2...6) }.buttonStyle(.link)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("O que o Cloud faz").foregroundColor(.secondary)
                TextEditor(text: $routine.pedido)
                    .font(.system(size: 13)).frame(height: 90)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                Text("Escreva como falaria com ele: \"bom dia\", \"abre o DaVinci\", \"/ogab pauta da semana\"...")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar", action: cancel).keyboardShortcut(.cancelAction)
                Button("Salvar") {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    routine.hora = c.hour ?? 9; routine.minuto = c.minute ?? 0
                    save(routine)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(routine.pedido.trimmingCharacters(in: .whitespaces).isEmpty || routine.dias.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            c.hour = routine.hora; c.minute = routine.minuto
            time = Calendar.current.date(from: c) ?? Date()
        }
    }
}

// MARK: Gatilhos

private struct TriggersPane: View {
    @ObservedObject private var store = TriggerStore.shared
    @State private var frase = ""
    @State private var pedido = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneHeader(title: "Gatilhos", subtitle: "Uma frase sua que dispara um pedido. Diga \"Ei Cloud, modo edição\" e ele faz tudo o que você definiu.")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Novo gatilho").font(.system(size: 13, weight: .semibold)).foregroundColor(P.text)
                    HStack(spacing: 10) {
                        TextField("Quando eu disser (ex.: modo edição)", text: $frase).textFieldStyle(.roundedBorder).frame(width: 220)
                        Image(systemName: "arrow.right").foregroundColor(P.muted)
                        TextField("O Cloud faz (ex.: fecha o WhatsApp e abre o DaVinci)", text: $pedido).textFieldStyle(.roundedBorder)
                        Button("Adicionar") {
                            store.triggers.append(CloudTrigger(frase: frase, pedido: pedido)); frase = ""; pedido = ""
                        }
                        .disabled(frase.isEmpty || pedido.isEmpty)
                    }
                    HStack(spacing: 8) {
                        ForEach(TriggerStore.templates) { t in
                            Button { var c = t; c.id = UUID(); store.triggers.append(c) } label: {
                                Text("+ " + t.frase).font(.system(size: 11, weight: .medium)).foregroundColor(P.text)
                                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.07)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            ForEach(store.triggers) { t in
                Card {
                    HStack(spacing: 12) {
                        Text("“\(t.frase)”").font(.system(size: 14, weight: .semibold)).foregroundColor(P.text)
                        Image(systemName: "arrow.right").foregroundColor(P.accent)
                        Text(t.pedido).font(.system(size: 12)).foregroundColor(P.muted).lineLimit(2)
                        Spacer()
                        Toggle("", isOn: Binding(get: { t.ativo }, set: { v in
                            if let i = store.triggers.firstIndex(where: { $0.id == t.id }) { store.triggers[i].ativo = v }
                        })).toggleStyle(.switch).labelsHidden()
                        iconButton("trash", "Apagar") { store.triggers.removeAll { $0.id == t.id } }
                    }
                }
            }
        }
    }
}

// MARK: Missões

private struct MissionsPane: View {
    @ObservedObject private var m = CloudMissions.shared
    @ObservedObject private var pet = CloudPet.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneHeader(title: "Missões do dia", subtitle: "Três missões novas todo dia. Completar dá experiência para o Cloud subir de nível.")
            HStack(spacing: 12) {
                stat("flame.fill", "\(m.state.diasSeguidos)", m.state.diasSeguidos == 1 ? "dia seguido" : "dias seguidos", "#FB923C")
                stat("star.fill", "\(pet.xp)", "de experiência", "#FBBF24")
                stat("crown.fill", pet.stage, "nível \(pet.level)", "#A78BFA")
            }
            .padding(.bottom, 4)
            ForEach(m.state.missoes) { mi in
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: mi.feito >= mi.meta ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundColor(mi.feito >= mi.meta ? Color(hex: "#34D399") : P.muted)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mi.titulo).font(.system(size: 13, weight: .semibold)).foregroundColor(P.text)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.08))
                                    Capsule().fill(LinearGradient(colors: [P.accent, Color(hex: "#A78BFA")], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: g.size.width * CGFloat(min(mi.feito, mi.meta)) / CGFloat(mi.meta))
                                }
                            }
                            .frame(height: 6)
                        }
                        Text("\(min(mi.feito, mi.meta))/\(mi.meta)").font(.system(size: 12).monospacedDigit()).foregroundColor(P.muted)
                        Text("+\(mi.xp) XP").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#FBBF24"))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color(hex: "#FBBF24").opacity(0.12)))
                    }
                }
            }
        }
    }

    private func stat(_ icon: String, _ value: String, _ label: String, _ color: String) -> some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20)).foregroundColor(Color(hex: color))
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(P.text)
                    Text(label).font(.system(size: 11)).foregroundColor(P.muted)
                }
            }
        }
    }
}

// MARK: Conquistas

private struct AchievementsPane: View {
    @ObservedObject private var m = CloudMissions.shared
    private let cols = [GridItem(.adaptive(minimum: 170), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let got = CloudMissions.achievements.filter { m.state.conquistas[$0.id] != nil }.count
            PaneHeader(title: "Conquistas", subtitle: "\(got) de \(CloudMissions.achievements.count) desbloqueadas.")
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(CloudMissions.achievements) { a in
                    let date = m.state.conquistas[a.id]
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(date != nil
                                          ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#FBBF24"), Color(hex: "#F472B6")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                          : AnyShapeStyle(Color.white.opacity(0.06)))
                                .frame(width: 58, height: 58)
                            Image(systemName: date != nil ? a.icone : "lock.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(date != nil ? .white : P.muted)
                        }
                        Text(a.titulo).font(.system(size: 13, weight: .semibold)).foregroundColor(date != nil ? P.text : P.muted)
                        Text(a.detalhe).font(.system(size: 11)).foregroundColor(P.muted).multilineTextAlignment(.center)
                        if let date {
                            Text(date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundColor(Color(hex: "#FBBF24"))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 170)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.card))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(P.line))
                }
            }
        }
    }
}
#endif

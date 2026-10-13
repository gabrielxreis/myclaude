#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - Cloud, the pet
//
// A Tamagotchi for work (inspired by github.com/usik/tamagotchi, without the dying part):
// – Energia: what is left of the Claude plan (5 h / weekly window, whichever is fuller).
// – Humor: goes up when I talk to Cloud, use a shortcut or it acts; drifts down when ignored.
// – Foco: Claude Code agents working right now.
// – XP and stages (Ovo → Filhote → Jovem → Adulto → Mestre): tasks done and conversations.
// It also watches which app I'm in and suggests something it can actually do there.

@MainActor
final class CloudPet: ObservableObject {
    static let shared = CloudPet()

    enum Mood: String {
        case preocupado, cansado, focado, sonolento, carente, animado, feliz
        var label: String {
            switch self {
            case .preocupado: "preocupado"
            case .cansado:    "cansado"
            case .focado:     "focado"
            case .sonolento:  "com sono"
            case .carente:    "carente"
            case .animado:    "animado"
            case .feliz:      "feliz"
            }
        }
        var emoji: String {
            switch self {
            case .preocupado: "😟"
            case .cansado:    "🥱"
            case .focado:     "🧐"
            case .sonolento:  "😴"
            case .carente:    "🥺"
            case .animado:    "🤩"
            case .feliz:      "😊"
            }
        }
    }

    struct Suggestion: Equatable {
        let text: String
        /// Draft for the chat window ("/ogab …"); nil when `request` is set.
        var chatDraft: String? = nil
        /// A request Cloud runs as if spoken.
        var request: String? = nil
    }

    @Published private(set) var humorStored: Double
    @Published private(set) var xp: Int
    @Published private(set) var lastInteraction: Date
    @Published private(set) var frontApp: (name: String, bundleId: String)? = nil

    private let d = UserDefaults.standard

    private init() {
        humorStored = d.object(forKey: "petHumor") as? Double ?? 70
        xp = d.integer(forKey: "petXP")
        lastInteraction = d.object(forKey: "petLastInteraction") as? Date ?? Date()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
            let name = app.localizedName ?? id
            Task { @MainActor in CloudPet.shared.frontApp = (name, id) }
        }
    }

    // MARK: Events

    /// I talked to Cloud, used a shortcut, or it did something for me.
    func interacted(xpGain: Int = 5) {
        humorStored = min(100, humor + 10)
        xp += xpGain
        lastInteraction = Date()
        save()
    }

    /// A Claude Code agent finished a task.
    func taskFinished() {
        CloudMissions.shared.record(.tarefaClaude)
        xp += 10
        humorStored = min(100, humor + 3)
        save()
    }

    private func save() {
        d.set(humorStored, forKey: "petHumor")
        d.set(xp, forKey: "petXP")
        d.set(lastInteraction, forKey: "petLastInteraction")
    }

    // MARK: Stats

    /// Humor drifts down 3 points per hour without contact, never below 10.
    var humor: Double {
        let hours = Date().timeIntervalSince(lastInteraction) / 3600
        return max(10, humorStored - hours * 3)
    }

    func energia(_ state: AppState) -> Double {
        guard let u = state.claudePlanUsage, let pct = ClaudePlanGauge.dominantPct(u) else { return 100 }
        return max(0, 100 - pct)
    }

    func foco(_ state: AppState) -> Double {
        let working = state.tasks.filter { [.working, .thinking, .searching].contains($0.state) }.count
        return min(100, Double(working) * 60)
    }

    static let stages: [(name: String, xp: Int)] = [("Ovo", 0), ("Filhote", 50), ("Jovem", 200), ("Adulto", 600), ("Mestre", 1500)]
    var stage: String { Self.stages.last { xp >= $0.xp }?.name ?? "Ovo" }
    var level: Int { 1 + Int(sqrt(Double(xp) / 10)) }

    func mood(_ state: AppState) -> Mood {
        if state.pendingApproval != nil { return .preocupado }
        if energia(state) < 15 { return .cansado }
        if foco(state) > 0 || CardOffload.shared.status != nil { return .focado }
        let hour = Calendar.current.component(.hour, from: Date())
        let idle = Date().timeIntervalSince(lastInteraction)
        if hour < 6 || idle > 3 * 3600 { return .sonolento }
        if humor < 30 { return .carente }
        if idle < 120 { return .animado }
        return .feliz
    }

    // MARK: Suggestions

    /// What Cloud offers given what I'm doing. Only things it can really do.
    func suggestion(_ state: AppState) -> Suggestion? {
        if let done = state.tasks.first(where: { $0.state == .finished && $0.finalLine != nil }) {
            return Suggestion(text: "\(done.name) terminou. Quer ver o resultado?", chatDraft: nil,
                              request: nil)
        }
        let e = energia(state)
        if e < 20, let reset = state.claudePlanUsage?.fiveHour?.resetsAt {
            let h = reset.formatted(.dateTime.hour().minute())
            return Suggestion(text: "Seu plano está quase no fim, volta às \(h). Pega leve comigo.")
        }
        guard let app = frontApp else { return nil }
        let id = app.bundleId.lowercased()
        if id.contains("davinci") || id.contains("resolve") {
            return Suggestion(text: "No DaVinci? Quer que eu legende a timeline com a /ogab?",
                              chatDraft: "/ogab legenda a timeline atual")
        }
        if id.contains("premiere") || id.contains("finalcut") || id.contains("aftereffects") {
            return Suggestion(text: "Editando no \(app.name)? Chama a /ogab que eu ajudo.",
                              chatDraft: "/ogab ")
        }
        if id.contains("instagram") || id.contains("photos") || id.contains("photoshop") {
            return Suggestion(text: "Quer uma legenda pronta pro Instagram?", chatDraft: "/ogab legenda do post: ")
        }
        return nil
    }

    /// The tap on a suggestion.
    func act(on s: Suggestion, state: AppState) {
        interacted()
        if let draft = s.chatDraft {
            CloudChatWindow.shared.show(conversation: CloudChatStore.shared.newConversation(), draft: draft)
        } else if let request = s.request {
            CloudQuickActions.shared.run(CloudQuickAction(titulo: "", pedido: request))
        } else if let done = state.tasks.first(where: { $0.state == .finished }) {
            if !ClaudeHost.activate(done.hostApp) { ClaudeHost.openClaudeApp() }
        }
    }
}

// MARK: - Left card

struct CloudPetCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var pet = CloudPet.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let mood = pet.mood(state)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Button { CloudPanelWindow.shared.show(.missoes) } label: {
                        Text(CloudIdentity.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                    }
                    .buttonStyle(.plain)
                    .help("Missões, conquistas, rotinas e gatilhos")
                    Text("\(mood.emoji) \(mood.label)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#B0B5BE"))
                    Spacer(minLength: 2)
                    Text("\(pet.stage) · nv \(pet.level)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                HStack(spacing: 8) {
                    bar("Humor", pet.humor, "#F472B6")
                    bar("Energia", pet.energia(state), "#34D399")
                    bar("Foco", pet.foco(state), "#60A5FA")
                }
                bottomLine
            }
            .padding(.top, 9)
            .padding(.leading, 108)
            .padding(.trailing, 34)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onChange(of: state.tasks.filter { $0.state == .finished }.count) { old, new in
            if new > old { pet.taskFinished() }
        }
    }

    @ObservedObject private var offload = CardOffload.shared
    @ObservedObject private var timers = CloudTimers.shared
    @ObservedObject private var screen = ScreenTools.shared

    /// A card being copied, else what the agent is doing right now, else Cloud's suggestion.
    @ViewBuilder private var bottomLine: some View {
        if let status = offload.status {
            HStack(spacing: 5) {
                Image(systemName: "sdcard.fill").font(.system(size: 10)).foregroundColor(Color(hex: "#7CC4FF"))
                Text(status).font(.system(size: 11)).foregroundColor(Color(hex: "#D7DAE0")).lineLimit(2)
            }
        } else if let rec = screen.recordingLine {
            HStack(spacing: 5) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text(rec).font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: "#D7DAE0"))
            }
        } else if let line = timers.nextLine {
            HStack(spacing: 5) {
                Image(systemName: "timer").font(.system(size: 10)).foregroundColor(Color(hex: "#FBBF24"))
                Text(line).font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: "#D7DAE0")).lineLimit(2)
            }
        } else if let t = state.tasks.first(where: { [.working, .thinking, .searching].contains($0.state) }) {
            let step = t.steps.indices.contains(t.stepIndex) ? t.steps[t.stepIndex] : "trabalhando…"
            Text("\(t.name): \(step)")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
                .lineLimit(2)
        } else if let s = pet.suggestion(state) {
            Button { pet.act(on: s, state: state) } label: {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "lightbulb.fill").font(.system(size: 9)).foregroundColor(.yellow.opacity(0.8))
                    Text(s.text).font(.system(size: 11)).foregroundColor(Color(hex: "#D7DAE0")).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
        } else {
            Text("Diga \u{201C}Ei Cloud\u{201D} ou toque num atalho.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
        }
    }

    private func bar(_ label: String, _ value: Double, _ color: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundColor(Color(hex: "#6B7079"))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color(hex: color)).frame(width: g.size.width * CGFloat(value / 100))
                }
            }
            .frame(height: 4)
        }
    }
}
#endif

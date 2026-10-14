#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - Cloud up close (tap the left card in the notch)
//
// A window with the character big and animated, its stats and Tamagotchi-style care:
// snack (Fome), play, pet, sleep / wake up, chat and missions. Tapping the character is a pet;
// three quick taps make it dizzy. Everything feeds the same CloudPet as the notch card.

extension CloudPet {
    /// Fome (0 = starving, 100 = full): drops 8 points an hour after the last snack.
    var saciedade: Double {
        let last = UserDefaults.standard.object(forKey: "petLastFed") as? Date ?? Date().addingTimeInterval(-3 * 3600)
        return max(0, 100 - Date().timeIntervalSince(last) / 3600 * 8)
    }

    func feed() {
        UserDefaults.standard.set(Date(), forKey: "petLastFed")
        interacted(xpGain: 3)
        objectWillChange.send()
    }

    /// Put to bed by hand (until woken up or for 2 h): the notch shows it sleeping too.
    var sleepingByHand: Bool {
        guard let until = UserDefaults.standard.object(forKey: "petSleepUntil") as? Date else { return false }
        return until > Date()
    }

    func setSleeping(_ on: Bool) {
        if on { UserDefaults.standard.set(Date().addingTimeInterval(2 * 3600), forKey: "petSleepUntil") }
        else { UserDefaults.standard.removeObject(forKey: "petSleepUntil"); interacted(xpGain: 1) }
        objectWillChange.send()
    }

    var nextStage: (name: String, xp: Int)? { Self.stages.first { $0.xp > xp } }
}

@MainActor
final class CloudPetWindow: NSObject, NSWindowDelegate {
    static let shared = CloudPetWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            // Opens on the Space I am on, even over a full-screen app.
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.backgroundColor = NSColor(red: 0.055, green: 0.06, blue: 0.075, alpha: 1)
            w.contentView = NSHostingView(rootView: CloudPetView(state: AppState.shared))
            w.delegate = self
            w.center()
            window = w
        }
        if AppState.shared.mode == .expanded {
            NotificationCenter.default.post(name: .collapseIsland, object: nil)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        SoundEngine.shared.play("pop")
    }

    /// Closed: the window goes away with its view, so the character's animation stops ticking.
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}

extension Notification.Name {
    static let collapseIsland = Notification.Name("myCloud.collapseIsland")
}

// MARK: - View

private enum Reaction { case carinho, lanche, brincar, tonto }

struct CloudPetView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var pet = CloudPet.shared
    @ObservedObject private var weather = CloudWeather.shared
    @State private var reaction: Reaction?
    @State private var reactionAt = Date.distantPast
    @State private var faceStart = Date()
    @State private var lastFace: CloudFace = .parado
    @State private var blinkAt = Date().addingTimeInterval(1.5)
    @State private var blinkUntil = Date.distantPast
    @State private var taps: [Date] = []
    @State private var tick = 0

    var body: some View {
        VStack(spacing: 14) {
            header
            stage
            stats
            actions
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(width: 440, height: 620)
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .preferredColorScheme(.dark)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }

    // MARK: Header

    private var header: some View {
        let mood = pet.sleepingByHand ? CloudPet.Mood.sonolento : pet.mood(state)
        return VStack(spacing: 4) {
            Text(CloudIdentity.name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("\(mood.emoji) \(mood.label) · \(pet.stage) · nível \(pet.level)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#9CA3AF"))
            if let next = pet.nextStage {
                let prev = CloudPet.stages.last { pet.xp >= $0.xp }?.xp ?? 0
                let p = Double(pet.xp - prev) / Double(max(1, next.xp - prev))
                VStack(spacing: 3) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(LinearGradient(colors: [Color(hex: "#A78BFA"), Color(hex: "#60A5FA")],
                                                          startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * CGFloat(min(1, p)))
                        }
                    }
                    .frame(width: 180, height: 5)
                    Text("\(pet.xp) XP · faltam \(next.xp - pet.xp) para \(next.name)")
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: The character, big

    private var currentFace: CloudFace {
        let since = Date().timeIntervalSince(reactionAt)
        switch reaction {
        case .tonto where since < 2.2: return .tonto
        case .lanche where since < 1.8: return since < 0.6 ? .surpreso : .falando
        case .brincar where since < 2.4: return .feliz
        case .carinho where since < 1.4: return .feliz
        default: break
        }
        if pet.sleepingByHand { return .sono }
        return cloudFace(state)
    }

    private var stage: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let now = tl.date
                let face = currentFace
                let since = now.timeIntervalSince(reactionAt)
                // Brincar: three hops in a row; the other reactions one hop.
                var hopT = 9.0
                if reaction == .brincar && since < 2.4 { hopT = since.truncatingRemainder(dividingBy: 0.8) }
                else if since < 0.6 { hopT = since }
                CloudPainter(kind: CloudCharacterKind.current, face: face, skin: CloudSkin.resolved(on: now),
                             t: now.timeIntervalSinceReferenceDate,
                             faceT: now.timeIntervalSince(faceStart), hopT: hopT,
                             blinking: now < blinkUntil, look: look(size),
                             cold: (weather.temperature ?? 22) < 18, hot: (weather.temperature ?? 22) > 30,
                             raining: weather.raining)
                    .draw(in: &ctx, size: size)
                effects(&ctx, size: size, since: since)
            }
            .onChange(of: tl.date) { _, now in
                let f = currentFace
                if f != lastFace { lastFace = f; faceStart = now }
                if now > blinkAt {
                    blinkUntil = now.addingTimeInterval(0.12)
                    blinkAt = now.addingTimeInterval(Double.random(in: 0...1) < 0.3 ? 0.28 : 2.2 + Double.random(in: 0...2.6))
                }
            }
        }
        .frame(width: 300, height: 260)
        .contentShape(Rectangle())
        .onTapGesture { poke() }
        .help("Toque para fazer carinho")
    }

    private func look(_ size: CGSize) -> CGPoint {
        guard let w = NSApp.keyWindow, w.contentView is NSHostingView<CloudPetView> else { return .zero }
        let m = w.mouseLocationOutsideOfEventStream
        let cx = w.frame.width / 2, cy = w.frame.height - 34 - 90 - 130
        return CGPoint(x: tanh((m.x - cx) / 160), y: -tanh((m.y - cy) / 160))
    }

    /// Hearts (carinho), falling snack (lanche), stars (brincar).
    private func effects(_ ctx: inout GraphicsContext, size: CGSize, since: Double) {
        guard let r = reaction else { return }
        let cx = size.width / 2, cy = size.height * 0.5
        switch r {
        case .carinho where since < 1.6:
            for i in 0..<5 {
                let p = (since - Double(i) * 0.12) / 1.2
                guard p > 0 && p < 1 else { continue }
                var c = ctx
                c.opacity = 1 - p
                let x = cx + CGFloat(sin(Double(i) * 2.1)) * 60 + CGFloat(sin(p * 8 + Double(i))) * 6
                c.draw(Text("❤️").font(.system(size: 22)), at: CGPoint(x: x, y: cy - 40 - CGFloat(p) * 90))
            }
        case .lanche where since < 1.8:
            let p = min(1, since / 0.6)
            var c = ctx
            c.opacity = since < 0.6 ? 1 : max(0, 1 - (since - 0.6) * 2)
            let food = ["🍪", "🍓", "🍙", "🍩"][Int(reactionAt.timeIntervalSince1970) % 4]
            c.draw(Text(food).font(.system(size: 34)), at: CGPoint(x: cx, y: -20 + CGFloat(p * p) * (cy - 10)))
            if since > 0.6 {
                for i in 0..<4 {
                    let q = (since - 0.6) / 1.0
                    var crumb = ctx
                    crumb.opacity = max(0, 1 - q)
                    let a = Double(i) * 1.6 + 0.4
                    crumb.fill(Path(ellipseIn: CGRect(x: cx + CGFloat(cos(a) * q * 50) - 2, y: cy + 10 + CGFloat(sin(a) * q * 20 + q * q * 40) - 2, width: 4, height: 4)),
                               with: .color(Color(hex: "#D6A15C")))
                }
            }
        case .brincar where since < 2.6:
            for i in 0..<8 {
                let p = (since - Double(i) * 0.15).truncatingRemainder(dividingBy: 1.2) / 1.2
                guard since > Double(i) * 0.15 else { continue }
                var c = ctx
                c.opacity = (1 - p) * 0.9
                let a = Double(i) / 8 * 2 * .pi
                c.draw(Text("✦").font(.system(size: 16)).foregroundColor(i % 2 == 0 ? Color(hex: "#FBBF24") : .white),
                       at: CGPoint(x: cx + CGFloat(cos(a)) * (70 + CGFloat(p) * 40), y: cy + CGFloat(sin(a)) * (45 + CGFloat(p) * 25)))
            }
        default: break
        }
    }

    // MARK: Stats

    private var stats: some View {
        let _ = tick
        return VStack(spacing: 9) {
            HStack(spacing: 14) {
                bar("Humor", pet.humor, "#F472B6", "face.smiling")
                bar("Energia", pet.energia(state), "#34D399", "bolt.fill")
            }
            HStack(spacing: 14) {
                bar("Foco", pet.foco(state), "#60A5FA", "scope")
                bar("Fome", pet.saciedade, "#FBBF24", "fork.knife")
            }
            Text(hint)
                .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private var hint: String {
        if pet.sleepingByHand { return "Dormindo. Acorde quando precisar dele." }
        if pet.saciedade < 25 { return "Está com fome. Que tal um lanchinho?" }
        if pet.humor < 30 { return "Está carente. Faça um carinho ou brinque com ele." }
        if pet.energia(state) < 20 { return "A energia é o que resta do seu plano do Claude." }
        return "Humor sobe quando você conversa e cuida dele. Energia é o seu plano do Claude; Foco, os agentes trabalhando."
    }

    private func bar(_ label: String, _ value: Double, _ color: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10)).foregroundColor(Color(hex: color))
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#D7DAE0"))
                Spacer()
                Text("\(Int(value))").font(.system(size: 10).monospacedDigit()).foregroundColor(Color(hex: "#6B7079"))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color(hex: color)).frame(width: g.size.width * CGFloat(max(0, min(1, value / 100))))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Care

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                careButton("Lanche", "🍪") { react(.lanche); pet.feed() }
                careButton("Brincar", "🎾") { react(.brincar); pet.interacted(xpGain: 4) }
                careButton("Carinho", "🫶") { react(.carinho); pet.interacted(xpGain: 2) }
                careButton(pet.sleepingByHand ? "Acordar" : "Dormir", pet.sleepingByHand ? "☀️" : "🌙") {
                    pet.setSleeping(!pet.sleepingByHand)
                    SoundEngine.shared.play(pet.sleepingByHand ? "sleep" : "pop")
                }
            }
            HStack(spacing: 10) {
                wideButton("Conversar", "bubble.left.and.bubble.right.fill") {
                    CloudChatWindow.shared.show(conversation: CloudChatStore.shared.newConversation())
                }
                wideButton("Missões e conquistas", "trophy.fill") { CloudPanelWindow.shared.show(.missoes) }
            }
        }
    }

    private func careButton(_ title: String, _ emoji: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji).font(.system(size: 24))
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#D7DAE0"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func wideButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Color(hex: "#D7DAE0"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func react(_ r: Reaction) {
        if pet.sleepingByHand { pet.setSleeping(false) }
        reaction = r
        reactionAt = Date()
        SoundEngine.shared.play(r == .tonto ? "dizzy" : "pop")
    }

    private func poke() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 1.5 } + [now]
        if taps.count >= 3 { taps = []; react(.tonto) }
        else { react(.carinho); pet.interacted(xpGain: 1) }
    }
}
#endif

#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - First launch: the egg
//
// The first time My Cloud opens, an egg asks for a name (and a character), hatches with a little
// show, says hello, and from then on that companion is Cloud: its name wakes it up, shows on the
// notch card, in the chat and in the panel.

enum CloudIdentity {
    /// The companion's name ("Cloud" until the egg hatches).
    static var name: String {
        get { UserDefaults.standard.string(forKey: "cloudPetName").flatMap { $0.isEmpty ? nil : $0 } ?? "Cloud" }
        set {
            UserDefaults.standard.set(newValue, forKey: "cloudPetName")
            VoiceSettings.refreshWakeNames()   // "Ei <nome>" wakes it right away
        }
    }
    static var hatched: Bool {
        get { UserDefaults.standard.bool(forKey: "myCloudHatched") }
        set { UserDefaults.standard.set(newValue, forKey: "myCloudHatched") }
    }
    /// Settings → Dados: the egg shows again at the next launch.
    static func resetOnboarding() { hatched = false }
}

@MainActor
final class CloudOnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = CloudOnboardingWindow()
    private var window: NSWindow?

    /// At launch: only until the egg has hatched once.
    func showIfNeeded() {
        guard !CloudIdentity.hatched else { return }
        show()
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: CloudOnboardingView { [weak self] in self?.window?.close() })
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closed: drop the view, or its egg animation keeps running at 60 fps in the background.
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}

struct CloudOnboardingView: View {
    let done: () -> Void
    enum Step { case naming, hatching, hello }
    @State private var step: Step = .naming
    @State private var name = ""
    @State private var kind: CloudCharacterKind = .bolinho
    @State private var hatchStart = Date()
    @FocusState private var focused: Bool

    private let accent = Color(hex: "#7CC4FF")

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#1B2340"), Color(hex: "#090B12")], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.25), .clear], center: .init(x: 0.5, y: 0.38), startRadius: 0, endRadius: 260)
            VStack(spacing: 18) {
                stage.frame(width: 300, height: 260)
                switch step {
                case .naming: naming
                case .hatching: Text("…").font(.system(size: 22, weight: .bold)).foregroundColor(.white.opacity(0.6))
                case .hello: hello
                }
            }
            .padding(.horizontal, 40).padding(.top, 20)
        }
        .frame(width: 560, height: 620)
        .environment(\.colorScheme, .dark)
    }

    // The egg, the hatching, then the companion.
    private var stage: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let h = tl.date.timeIntervalSince(hatchStart)
                switch step {
                case .naming:
                    drawEgg(&ctx, size, t: t, shake: 0.04, crack: 0, open: 0)
                case .hatching:
                    let shake = 0.04 + min(h / 1.6, 1) * 0.16
                    drawEgg(&ctx, size, t: t, shake: shake, crack: min(h / 1.2, 1), open: max(0, (h - 1.6) / 0.5))
                    if h > 1.7 {
                        let p = min((h - 1.7) / 0.5, 1)
                        var c = ctx
                        c.translateBy(x: 0, y: (1 - p) * 40)
                        c.opacity = p
                        CloudPainter(kind: kind, face: .surpreso, skin: .padrao, t: t, faceT: h - 1.7, hopT: 9, blinking: false,
                                     look: .zero, cold: false, hot: false, raining: false).draw(in: &c, size: size)
                        sparkles(&ctx, size, t: h - 1.7)
                    }
                case .hello:
                    CloudPainter(kind: kind, face: .feliz, skin: .padrao, t: t, faceT: 2, hopT: h - 2.2, blinking: false,
                                 look: .zero, cold: false, hot: false, raining: false).draw(in: &ctx, size: size)
                    if h < 4 { sparkles(&ctx, size, t: h - 1.7) }
                }
            }
        }
    }

    private var naming: some View {
        VStack(spacing: 14) {
            Text("Você ganhou um companheiro!").font(.system(size: 26, weight: .bold)).foregroundColor(.white)
            Text("Ele vai morar no notch do seu Mac, te ouvir, fazer coisas por você e crescer com o tempo. Como ele vai se chamar?")
                .font(.system(size: 14)).foregroundColor(Color(hex: "#B8C4DE")).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Ex.: Cláudio", text: $name)
                .textFieldStyle(.plain).font(.system(size: 20, weight: .semibold)).multilineTextAlignment(.center)
                .padding(.vertical, 10).padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(focused ? 0.8 : 0.25)))
                .frame(width: 280).focused($focused).onSubmit(hatch)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CloudCharacterKind.available.filter { $0 != .mochi }) { k in
                        Button { kind = k } label: {
                            Canvas { ctx, size in
                                CloudPainter(kind: k, face: .parado, skin: .padrao, t: 1, faceT: 2, hopT: 9, blinking: false,
                                             look: .zero, cold: false, hot: false, raining: false).draw(in: &ctx, size: size)
                            }
                            .frame(width: 46, height: 42)
                            .background(RoundedRectangle(cornerRadius: 10).fill(kind == k ? accent.opacity(0.22) : Color.white.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(kind == k ? accent : .clear))
                        }
                        .buttonStyle(.plain).help(k.title)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(width: 440)
            Text(kind.title).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            Button(action: hatch) {
                Text("Chocar o ovo").font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: "#06121F"))
                    .padding(.horizontal, 28).padding(.vertical, 11)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .onAppear { focused = true }
    }

    private var hello: some View {
        let n = CloudIdentity.name
        return VStack(spacing: 12) {
            Text("Oi! Eu sou o \(n).").font(.system(size: 28, weight: .bold)).foregroundColor(.white)
            VStack(alignment: .leading, spacing: 9) {
                tip("waveform", "Me chame dizendo \"Ei \(n)\" e peça o que quiser.")
                tip("bubble.left.fill", "Toque no balão do notch para conversar por texto.")
                tip("repeat", "Rotinas, gatilhos, missões e conquistas ficam no menu do ícone da barra.")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            Button(action: done) {
                Text("Vamos lá").font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: "#06121F"))
                    .padding(.horizontal, 32).padding(.vertical, 11).background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(accent).frame(width: 18)
            Text(text).font(.system(size: 13)).foregroundColor(Color(hex: "#D7DAE0"))
        }
    }

    private func hatch() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        CloudIdentity.name = clean
        UserDefaults.standard.set(kind.rawValue, forKey: "cloudCharacter")
        SoundEngine.shared.reload()
        // The name wakes it up, before the default ones.
        let current = VoiceSettings.wakeNames
        if !CloudTimers.norm(current).contains(CloudTimers.norm(clean)) { VoiceSettings.wakeNames = clean + ", " + current }
        hatchStart = Date()
        withAnimation { step = .hatching }
        SoundEngine.shared.play("peek")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { SoundEngine.shared.play("pop") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            SoundEngine.shared.play("greeting")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { step = .hello }
            CloudIdentity.hatched = true
            CloudMissions.shared.record(.conversa)
        }
    }

    // MARK: Drawing the egg

    private func eggPath(_ s: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -0.62 * s))
        p.addCurve(to: CGPoint(x: 0.44 * s, y: 0.1 * s), control1: CGPoint(x: 0.28 * s, y: -0.62 * s), control2: CGPoint(x: 0.44 * s, y: -0.25 * s))
        p.addCurve(to: CGPoint(x: 0, y: 0.5 * s), control1: CGPoint(x: 0.44 * s, y: 0.36 * s), control2: CGPoint(x: 0.26 * s, y: 0.5 * s))
        p.addCurve(to: CGPoint(x: -0.44 * s, y: 0.1 * s), control1: CGPoint(x: -0.26 * s, y: 0.5 * s), control2: CGPoint(x: -0.44 * s, y: 0.36 * s))
        p.addCurve(to: CGPoint(x: 0, y: -0.62 * s), control1: CGPoint(x: -0.44 * s, y: -0.25 * s), control2: CGPoint(x: -0.28 * s, y: -0.62 * s))
        return p
    }

    private func drawEgg(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double, shake: Double, crack: Double, open: Double) {
        let s = min(size.width, size.height) * 0.62
        var c = ctx
        c.translateBy(x: size.width / 2, y: size.height * 0.58)
        // shadow
        var sh = c; sh.opacity = 0.35
        sh.fill(Path(ellipseIn: CGRect(x: -0.3 * s, y: 0.47 * s, width: 0.6 * s, height: 0.08 * s)), with: .color(.black))
        c.rotate(by: .radians(sin(t * (shake > 0.1 ? 28 : 3)) * shake))
        let shell = Gradient(colors: [Color(hex: "#FFFCF5"), Color(hex: "#F3E7D3")])
        if open < 0.01 {
            c.fill(eggPath(s), with: .linearGradient(shell, startPoint: CGPoint(x: 0, y: -0.6 * s), endPoint: CGPoint(x: 0, y: 0.5 * s)))
            for (x, y, r) in [(-0.18, -0.2, 0.06), (0.16, 0.02, 0.05), (-0.06, 0.24, 0.045), (0.22, -0.32, 0.035)] {
                c.fill(Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)), with: .color(Color(hex: "#9CCBF5").opacity(0.7)))
            }
            c.fill(Path(ellipseIn: CGRect(x: -0.22 * s, y: -0.48 * s, width: 0.14 * s, height: 0.22 * s)), with: .color(.white.opacity(0.7)))
            if crack > 0 {
                var z = Path()
                let pts = [(-0.42, -0.02), (-0.28, -0.1), (-0.16, 0.0), (-0.02, -0.12), (0.1, -0.02), (0.24, -0.12), (0.42, -0.04)]
                let n = max(2, Int(Double(pts.count) * crack))
                z.move(to: CGPoint(x: pts[0].0 * s, y: pts[0].1 * s))
                for p in pts.prefix(n).dropFirst() { z.addLine(to: CGPoint(x: p.0 * s, y: p.1 * s)) }
                c.stroke(z, with: .color(Color(hex: "#A08C6E")), style: StrokeStyle(lineWidth: 0.018 * s, lineCap: .round, lineJoin: .round))
            }
        } else {
            // Bottom half stays, top half flies away.
            var bottom = c
            bottom.clip(to: Path(CGRect(x: -s, y: -0.06 * s, width: 2 * s, height: 2 * s)))
            bottom.fill(eggPath(s), with: .linearGradient(shell, startPoint: CGPoint(x: 0, y: -0.6 * s), endPoint: CGPoint(x: 0, y: 0.5 * s)))
            var top = c
            top.translateBy(x: open * 0.5 * s, y: -open * 0.6 * s)
            top.rotate(by: .radians(open * 0.9))
            top.opacity = max(0, 1 - open)
            top.clip(to: Path(CGRect(x: -s, y: -s, width: 2 * s, height: 0.94 * s)))
            top.fill(eggPath(s), with: .linearGradient(shell, startPoint: CGPoint(x: 0, y: -0.6 * s), endPoint: CGPoint(x: 0, y: 0.5 * s)))
        }
    }

    private func sparkles(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double) {
        guard t > 0 else { return }
        let p = min(t / 1.4, 1)
        let colors = ["#FDE68A", "#7CC4FF", "#F9A8D4", "#A7F3D0"]
        for i in 0..<14 {
            let a = Double(i) / 14 * .pi * 2
            let r = (0.2 + p * 0.55) * min(size.width, size.height)
            var c = ctx
            c.opacity = 1 - p
            let x = size.width / 2 + cos(a) * r, y = size.height * 0.5 + sin(a) * r * 0.75
            c.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(Color(hex: colors[i % 4])))
        }
    }
}
#endif

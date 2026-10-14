#if !APPSTORE
import SwiftUI
import AppKit

// MARK: - My Cloud's opening (replaces Coucou's greeting when a Cloud character is chosen)
//
// The chosen character (with its skin) drops into the card from above with a squash, a ring
// and a few sparkles, greets by name and time of day, says how to call it, and leaves for the
// notch. Same contract as GreetingCanvasView: 640×150 canvas, hover keeps it, the island's
// interrupt ends it, `.greetComplete` hands back to the state machine. macOS system sounds only.

private enum CG {
    static let card0 = 0.0, card1 = 0.35
    static let drop0 = 0.25, drop1 = 0.8
    static let land = 0.8
    static let title0 = 1.0, title1 = 1.4
    static let sub0 = 1.2, sub1 = 1.6
    static let autoLeave = 3.6
    static let leave = 0.4          // fade-out after the leave time
}

private let cardRect = CGRect(x: 10, y: 36, width: 620, height: 104)
private let charCenter = CGPoint(x: 92, y: 86)
private let charBox: CGFloat = 112

private func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (t - a) / (b - a))) }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
private func back(_ x: Double) -> Double { let c1 = 1.7, c3 = c1 + 1; return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2) }

struct CloudGreetingView: View {
    @ObservedObject var state: AppState
    @State private var start = Date()
    @State private var leaveAt: Double = CG.autoLeave
    @State private var fired = false
    @State private var landed = false
    @State private var greeted = false

    private let firstName: String = {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }()

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Boa noite" : h < 12 ? "Bom dia" : h < 18 ? "Boa tarde" : "Boa noite"
        return firstName.isEmpty ? "\(part)!" : "\(part), \(firstName)!"
    }

    private var subtitle: String {
        return "Sou o \(CloudIdentity.name). Diga “Ei \(CloudIdentity.name)” quando precisar."
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, _ in draw(&ctx, t: t, now: tl.date) }
                .onChange(of: t >= CG.land) { _, v in if v && !landed { landed = true; sound("Pop", 0.45) } }
                .onChange(of: t >= CG.title0) { _, v in if v && !greeted { greeted = true; sound("Glass", 0.25) } }
                .onChange(of: t >= leaveAt + CG.leave) { _, v in if v { finish() } }
        }
        .onAppear {
            start = Date(); leaveAt = CG.autoLeave; fired = false; landed = false; greeted = false
            sound("Morse", 0.2)
            // Safety: end even if the timeline stops ticking.
            DispatchQueue.main.asyncAfter(deadline: .now() + CG.autoLeave + CG.leave + 0.1) {
                if leaveAt == CG.autoLeave { finish() }
            }
        }
        // Pointer over the island: stay until it leaves (the island then sends the interrupt).
        .onReceive(NotificationCenter.default.publisher(for: .greetingHover)) { _ in
            if Date().timeIntervalSince(start) < leaveAt { leaveAt = .infinity }
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            let t = Date().timeIntervalSince(start)
            leaveAt = min(leaveAt, max(t, CG.sub1))
            DispatchQueue.main.asyncAfter(deadline: .now() + (leaveAt - t) + CG.leave + 0.05) { finish() }
        }
    }

    private func sound(_ name: String, _ volume: Float) {
        guard state.soundEnabled else { return }
        let s = NSSound(named: NSSound.Name(name))
        s?.volume = volume
        s?.play()
    }

    private func finish() {
        guard !fired else { return }
        fired = true
        NotificationCenter.default.post(name: .greetComplete, object: nil)
    }

    private func draw(_ ctx: inout GraphicsContext, t: Double, now: Date) {
        let out = leaveAt.isFinite ? seg(t, leaveAt, leaveAt + CG.leave) : 0
        let fade = 1 - out

        // Card
        var card = ctx
        card.opacity = easeOut(seg(t, CG.card0, CG.card1)) * fade
        let cardPath = Path(roundedRect: cardRect, cornerRadius: 20, style: .continuous)
        card.fill(cardPath, with: .color(Color(hex: "#141518")))

        // Sparkles drawn in toward where the character lands, then twinkling around it.
        var fx = ctx
        fx.clip(to: cardPath)
        for i in 0..<14 {
            let a = Double(i) / 14 * 2 * .pi + 0.4
            let inward = easeOut(seg(t, 0.1 + Double(i % 4) * 0.05, CG.land))
            let r0 = 150.0, r1 = 48.0 + Double(i % 3) * 9
            let r = r0 + (r1 - r0) * inward
            let tw = 0.5 + 0.5 * sin(t * 5 + Double(i))
            let p = CGPoint(x: charCenter.x + cos(a) * r, y: charCenter.y + sin(a) * r * 0.55)
            let size = 2.2 + 1.6 * tw
            fx.opacity = (t < CG.land ? inward : 0.35 + 0.4 * tw) * fade
            fx.fill(Path(ellipseIn: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)),
                    with: .color(i % 3 == 0 ? Color(hex: "#FBBF24") : .white))
        }

        // Landing ring
        let ring = seg(t, CG.land, CG.land + 0.55)
        if ring > 0 && ring < 1 {
            var rc = ctx
            rc.opacity = (1 - ring) * 0.7 * fade
            let rr = 20 + 70 * easeOut(ring)
            rc.stroke(Path(ellipseIn: CGRect(x: charCenter.x - rr, y: charCenter.y + 30 - rr * 0.28, width: rr * 2, height: rr * 0.56)),
                      with: .color(.white), lineWidth: 2)
        }

        // Character: falls in with a bounce, lands surprised, then happy, then looks at the text.
        let drop = seg(t, CG.drop0, CG.drop1)
        let y = charCenter.y - (1 - back(drop)) * 120
        let face: CloudFace = t < CG.land + 0.15 ? .surpreso : t < 2.4 ? .feliz : .parado
        let faceStart = t < CG.land + 0.15 ? CG.drop0 : t < 2.4 ? CG.land + 0.15 : 2.4
        let scale = (0.6 + 0.4 * easeOut(drop)) * (1 - 0.35 * out)
        var cc = ctx
        cc.opacity = min(1, drop * 3) * fade
        cc.translateBy(x: charCenter.x, y: y)
        cc.scaleBy(x: scale, y: scale)
        cc.translateBy(x: -charBox / 2, y: -charBox / 2)
        CloudPainter(kind: CloudCharacterKind.current, face: face, skin: CloudSkin.resolved(on: now),
                     t: now.timeIntervalSinceReferenceDate, faceT: t - faceStart,
                     hopT: t - CG.land, blinking: t > 2.9 && t < 3.02,
                     look: CGPoint(x: t > 2.4 ? 0.8 : 0, y: 0),
                     cold: false, hot: false, raining: false)
            .draw(in: &cc, size: CGSize(width: charBox, height: charBox))

        // Text
        let tx = 168.0
        let ti = easeOut(seg(t, CG.title0, CG.title1))
        var title = ctx
        title.opacity = ti * fade
        title.draw(Text(greeting).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white),
                   at: CGPoint(x: tx + (1 - ti) * 24, y: 74), anchor: .leading)
        let si = easeOut(seg(t, CG.sub0, CG.sub1))
        var sub = ctx
        sub.opacity = si * fade
        sub.draw(Text(subtitle).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(Color(hex: "#9CA3AF")),
                 at: CGPoint(x: tx + (1 - si) * 24, y: 102), anchor: .leading)
    }
}
#endif

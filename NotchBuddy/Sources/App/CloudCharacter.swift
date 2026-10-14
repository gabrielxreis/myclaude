#if !APPSTORE
import SwiftUI
import AppKit

// MARK: - Cloud's look (Settings → Geral → Personagem)
//
// Three characters drawn in code, each with its own quirks, plus skins that the user picks or
// that change by themselves with the weather and the holidays:
// – Nuvem: puffs that wobble when thinking, drizzle when sad, a rainbow when happy.
// – Marshmallow: squash and stretch, a cowlick that sways, melts a little when sleepy.
// – Vapor: wavy base always moving, floats higher, goes see-through when thinking, puffs when startled.
// "Mochi" keeps Coucou's original character (BotEngine).

extension CloudSkin {
    /// What Cloud wears now: the chosen skin, or (auto) the holiday, else the weather, else none.
    @MainActor static func resolved(on date: Date = Date()) -> CloudSkin {
        let c = chosen
        guard c == .auto else { return c }
        if let h = holiday(date) { return h }
        if let t = CloudWeather.shared.temperature {
            if t < 18 { return .cachecol }
            if t > 30 { return .oculos }
        }
        return .padrao
    }

}

// MARK: - Weather (Open-Meteo: free, no key; city from Settings)

@MainActor
final class CloudWeather: ObservableObject {
    static let shared = CloudWeather()
    @Published private(set) var temperature: Double?
    @Published private(set) var raining = false
    private var lastFetch: Date?

    static var city: String {
        get { UserDefaults.standard.string(forKey: "cloudWeatherCity") ?? "Rio de Janeiro" }
        set { UserDefaults.standard.set(newValue, forKey: "cloudWeatherCity"); Task { @MainActor in shared.refresh(force: true) } }
    }

    /// At most every 30 min; only while the skin is automatic.
    func refresh(force: Bool = false) {
        guard CloudSkin.chosen == .auto else { return }
        if !force, let l = lastFetch, Date().timeIntervalSince(l) < 1800 { return }
        lastFetch = Date()
        let city = Self.city
        Task {
            guard let q = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?count=1&language=pt&name=\(q)"),
                  let (gd, _) = try? await URLSession.shared.data(from: geoURL),
                  let g = try? JSONSerialization.jsonObject(with: gd) as? [String: Any],
                  let r = (g["results"] as? [[String: Any]])?.first,
                  let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double,
                  let wURL = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,precipitation"),
                  let (wd, _) = try? await URLSession.shared.data(from: wURL),
                  let w = try? JSONSerialization.jsonObject(with: wd) as? [String: Any],
                  let cur = w["current"] as? [String: Any] else { return }
            let t = cur["temperature_2m"] as? Double
            let rain = (cur["precipitation"] as? Double ?? 0) > 0.1
            await MainActor.run { self.temperature = t; self.raining = rain }
            appendAppLog("nb.log", "[Cloud] weather \(city): \(t ?? -99)°C rain=\(rain)")
        }
    }
}

// MARK: - Mood the character shows


/// A short expression on top of everything else ("não entendi").
@MainActor
final class CloudExpression {
    static let shared = CloudExpression()
    var puzzledUntil = Date.distantPast
    var cheerUntil = Date.distantPast
    func puzzle(for seconds: TimeInterval) { puzzledUntil = Date().addingTimeInterval(seconds) }
    func cheer(for seconds: TimeInterval) { cheerUntil = Date().addingTimeInterval(seconds) }
}

@MainActor
func cloudFace(_ state: AppState) -> CloudFace {
    if Date() < CloudExpression.shared.puzzledUntil { return .duvida }
    if Date() < CloudExpression.shared.cheerUntil { return .feliz }
    if state.voiceActive {
        switch state.voiceSubState {
        case .listening: return .ouvindo
        case .thinking: return .pensando
        case .speaking: return .falando
        case .none: break
        }
    }
    switch state.effectiveState {
    case .working: return .focado
    case .thinking, .searching: return .pensando
    case .finished: return .feliz
    case .approval, .question: return .surpreso
    case .error, .ratelimit, .dizzy: return .carente
    case .sleeping: return .sono
    case .idle: break
    }
    switch CloudPet.shared.mood(state) {
    case .sonolento: return .sono
    case .carente: return .carente
    case .animado: return .feliz
    case .focado: return .focado
    case .preocupado: return .surpreso
    default: return .parado
    }
}

// MARK: - View

struct CloudCharacterView: View {
    @ObservedObject var state: AppState
    let kind: CloudCharacterKind
    var paused: Bool = false
    /// Extra room above the character for particles (the island gives Mochi 40 pt); the
    /// character is drawn in the square below it, like BotEngine does.
    var overhang: CGFloat = 0
    @ObservedObject private var weather = CloudWeather.shared
    @State private var faceStart = Date()
    @State private var lastFace: CloudFace = .parado
    @State private var hopAt = Date.distantPast
    @State private var blinkAt = Date().addingTimeInterval(1.5)
    @State private var blinkUntil = Date.distantPast
    @State private var taps: [Date] = []
    @State private var dizzyUntil = Date.distantPast
    @State private var startledUntil = Date.distantPast

    var body: some View {
        TimelineView(.animation(paused: state.mode == .hidden || paused)) { tl in
            Canvas { ctx0, size0 in
                var ctx = ctx0
                let size = CGSize(width: size0.width, height: max(1, size0.height - overhang))
                // The painter centres a bit low (55 %); Mochi sits at the middle: match it.
                ctx.translateBy(x: 0, y: overhang - (overhang > 0 ? size.height * 0.05 : 0))
                let now = tl.date
                let face = now < dizzyUntil ? CloudFace.tonto : now < startledUntil ? CloudFace.surpreso : cloudFace(state)
                CloudPainter(kind: kind, face: face, skin: CloudSkin.resolved(on: now),
                             t: now.timeIntervalSinceReferenceDate,
                             faceT: now.timeIntervalSince(faceStart),
                             hopT: now.timeIntervalSince(hopAt),
                             blinking: now < blinkUntil,
                             look: look(),
                             cold: (weather.temperature ?? 22) < 18,
                             hot: (weather.temperature ?? 22) > 30,
                             raining: weather.raining)
                    .draw(in: &ctx, size: size)
            }
            .onChange(of: tl.date) { _, now in
                let f = cloudFace(state)
                if f != lastFace {
                    lastFace = f; faceStart = now
                    if f == .ouvindo || f == .surpreso { hopAt = now }   // "Ei Cloud": a little hop
                }
                if now > blinkAt {
                    blinkUntil = now.addingTimeInterval(0.12)
                    // Sometimes a double blink, like a real little creature.
                    let double = Double.random(in: 0...1) < 0.3
                    blinkAt = now.addingTimeInterval(double ? 0.28 : 2.2 + Double.random(in: 0...2.6))
                }
            }
        }
        .onAppear { weather.refresh() }
        .onTapGesture { poke() }
        // In the notch the clicks arrive through the window's mouse monitor.
        .onReceive(NotificationCenter.default.publisher(for: .cloudPoke)) { _ in poke() }
    }

    /// A poke: startled face and a hop. Three quick pokes: dizzy.
    private func poke() {
        // News waiting: a tap opens them.
        if CloudChangelog.shared.bubbleVisible { CloudChangelog.shared.open(); return }
        // Listening to me: a tap stops it (what was said is dropped), like pressing stop.
        if VoiceEngine.shared.isListeningForCommand {
            VoiceEngine.shared.cancelListening()
            CloudSounds.play(.stopped)
            appendAppLog("nb.log", "[Voice] listening stopped by a tap")
            return
        }
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 1.5 } + [now]
        if taps.count >= 3 {
            dizzyUntil = now.addingTimeInterval(2.2); taps = []
            SoundEngine.shared.play("dizzy")
        } else {
            startledUntil = now.addingTimeInterval(0.7)
            hopAt = now
            SoundEngine.shared.play("pop")
        }
    }

    /// Eyes toward the pointer, relative to the island's center (-1…1).
    private func look() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = IslandWindowController.islandScreen().frame
        let x = tanh((mouse.x - screen.midX) / 400)
        let y = -tanh((mouse.y - (screen.maxY - 60)) / 260)
        return CGPoint(x: x, y: y)
    }
}

#endif

#if !APPSTORE
import SwiftUI

// Pure drawing of Cloud's characters (no app state): CloudCharacterView feeds it each frame,
// and scripts/render-cloud.swift renders it to PNG for previews.

// MARK: - Characters, skins, faces

enum CloudCharacterKind: String, CaseIterable, Identifiable {
    case mochi, bolinho, nuvem, marshmallow, vapor
    case claquete, camera, gotinha, pipoca, lampada, planetinha, gatinho, bolha
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mochi: "Mochi (original)"
        case .bolinho: "Bolinho"
        case .claquete: "Claquete"
        case .camera: "Camerazinha"
        case .gotinha: "Gotinha"
        case .pipoca: "Pipoca"
        case .lampada: "Lâmpada"
        case .planetinha: "Planetinha"
        case .gatinho: "Gatinho de nuvem"
        case .bolha: "Bolha de sabão"
        case .nuvem: "Nuvem"
        case .marshmallow: "Marshmallow"
        case .vapor: "Vapor"
        }
    }
    /// The character in use. Bolinho by default; the public build never shows Mochi
    /// (Coucou's character can't be distributed).
    static var current: CloudCharacterKind {
        let k = CloudCharacterKind(rawValue: UserDefaults.standard.string(forKey: "cloudCharacter") ?? "") ?? .bolinho
        #if MYCLOUD_PUBLIC
        return k == .mochi ? .bolinho : k
        #else
        return k
        #endif
    }

    /// The characters offered in Settings.
    static var available: [CloudCharacterKind] {
        #if MYCLOUD_PUBLIC
        allCases.filter { $0 != .mochi }
        #else
        allCases
        #endif
    }
}

enum CloudSkin: String, CaseIterable, Identifiable {
    case auto, padrao, cachecol, fone, boina, oculos, coroa
    // Chosen by "auto" only (weather and holidays)
    case natal, anoNovo, carnaval, pascoa, junina, criancas, halloween
    var id: String { rawValue }
    static let pickable: [CloudSkin] = [.auto, .padrao, .cachecol, .fone, .boina, .oculos, .coroa]
    var title: String {
        switch self {
        case .auto: "Automática (clima e datas)"
        case .padrao: "Padrão"
        case .cachecol: "Cachecol"
        case .fone: "Fone"
        case .boina: "Boina de diretor"
        case .oculos: "Óculos escuros"
        case .coroa: "Coroa"
        default: rawValue
        }
    }
    static var chosen: CloudSkin {
        CloudSkin(rawValue: UserDefaults.standard.string(forKey: "cloudSkin") ?? "") ?? .auto
    }

    static func holiday(_ date: Date) -> CloudSkin? {
        let cal = Calendar(identifier: .gregorian)
        let m = cal.component(.month, from: date), d = cal.component(.day, from: date)
        let y = cal.component(.year, from: date)
        if m == 12 && d >= 18 && d <= 26 { return .natal }
        if (m == 12 && d >= 30) || (m == 1 && d == 1) { return .anoNovo }
        if m == 10 && d >= 10 && d <= 12 { return .criancas }
        if m == 10 && d >= 25 { return .halloween }
        if m == 6 || (m == 7 && d <= 10) { return .junina }
        let easter = easterSunday(y, cal)
        if let e = easter {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: e), to: cal.startOfDay(for: date)).day ?? 999
            if days >= -3 && days <= 0 { return .pascoa }
            if days >= -51 && days <= -46 { return .carnaval }   // Saturday to Ash Wednesday
        }
        return nil
    }

    /// Gregorian Easter (anonymous algorithm).
    static func easterSunday(_ y: Int, _ cal: Calendar) -> Date? {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4, f = (b + 8) / 25
        let g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = ((h + l - 7 * m + 114) % 31) + 1
        return cal.date(from: DateComponents(year: y, month: month, day: day))
    }
}

enum CloudFace: Equatable { case parado, ouvindo, pensando, falando, feliz, focado, sono, carente, surpreso, tonto }

// MARK: - Painter

struct CloudPainter {
    let kind: CloudCharacterKind
    let face: CloudFace
    let skin: CloudSkin
    let t: Double          // absolute time (s)
    let faceT: Double      // since the face changed
    let hopT: Double       // since the last hop
    let blinking: Bool
    let look: CGPoint
    let cold: Bool
    let hot: Bool
    let raining: Bool

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height) * (kind == .vapor ? 0.6 : 0.64)
        var oy = sin(t * 1.4) * 0.018 * s
        var breathe = sin(t * 2.1) * 0.018
        var tilt = 0.0
        var squash = 0.0   // marshmallow: + = flatter
        var alpha = 1.0
        if kind == .vapor { oy += sin(t * 1.1) * 0.035 * s - 0.04 * s }

        var f = FaceParams()
        f.gx = look.x; f.gy = look.y
        switch face {
        case .parado: break
        case .ouvindo: f.wide = 1.15; f.gx = 0; f.gy = 0; f.mouth = .o
            if kind == .bolinho { tilt = 0.09 * min(faceT / 0.3, 1); f.mouth = .none }   // head tilt, all ears
            if kind == .vapor { oy -= min(faceT, 0.5) * 0.12 * s }   // rises to listen
        case .pensando: f.gx = 0.8; f.gy = -0.8; f.mouth = .flat; tilt = sin(t * 1.2) * 0.04
            if kind == .vapor { alpha = 0.86 + sin(t * 2) * 0.06 }
        case .falando: oy += sin(t * .pi * 2 * 3.5) * 0.018 * s; f.mouth = sin(t * 14) > 0 ? .open : .smile; f.gx = 0; f.gy = 0.1
        case .feliz: oy -= abs(sin(t * 6)) * 0.06 * s; f.eyes = .happy; f.mouth = .big; f.blush = 0.85
            if kind == .marshmallow { squash = -abs(sin(t * 6)) * 0.08 }
        case .focado: f.gx = 0.15; f.gy = 0.55; f.wide = 0.92; f.open = 0.7; f.mouth = .flat; oy += sin(t * 9) * 0.006 * s
        case .sono: f.eyes = .closed; f.mouth = .o; breathe = sin(t * 1.1) * 0.025
            if kind == .marshmallow { squash = 0.12 + sin(t * 1.1) * 0.02 }   // melts a little
        case .carente: f.gx = -0.2; f.gy = 0.7; f.wide = 1.2; f.mouth = .sad; tilt = -0.06; f.blush = 0.75
        case .surpreso: f.wide = 1.3; f.mouth = .o; f.gx = 0; f.gy = -0.1
        case .tonto: f.eyes = .spiral; f.mouth = .wobbly; tilt = sin(t * 7) * 0.1; oy += sin(t * 9) * 0.01 * s
        }
        // Bolinho: no mouth at rest, only when it has something to say.
        if kind == .bolinho && face == .parado { f.mouth = .none }
        if blinking && f.eyes == .open { f.open = 0.08 }
        if hopT < 0.55 {
            let p = hopT / 0.55
            oy -= sin(min(p, 1) * .pi) * 0.15 * s
            if kind == .marshmallow { squash = p < 0.2 ? 0.14 * (1 - p / 0.2) : -sin(p * .pi) * 0.1 }
        }
        if cold && face != .sono { tilt += sin(t * 40) * 0.012 }   // shivering

        let center = CGPoint(x: size.width / 2, y: size.height * 0.55 + oy)

        // Ground shadow
        var sh = ctx
        sh.opacity = 0.35
        sh.fill(Path(ellipseIn: CGRect(x: size.width / 2 - 0.34 * s, y: size.height * 0.55 + 0.48 * s,
                                        width: 0.68 * s, height: 0.1 * s)), with: .color(.black))

        var c = ctx
        c.opacity = alpha
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .radians(tilt))
        c.scaleBy(x: 1 + breathe + squash * 0.6, y: 1 - breathe - squash)

        if face == .feliz && kind == .nuvem { rainbow(&c, s) }
        if kind == .vapor && face == .surpreso && faceT < 1 { steamBurst(&c, s) }
        if kind == .gotinha && face == .sono { c.opacity = 0.8 }   // evaporating
        behind(&c, s, f)
        // Bolha: pops when startled, then forms again.
        let popped = kind == .bolha && face == .surpreso && faceT < 0.45
        if popped { bubblePop(&c, s) } else {
            body(&c, s)
            if kind == .marshmallow { cowlick(&c, s) }
            if kind == .bolinho { cowlick(&c, s, small: true) }
            front(&c, s, f)
            if skin == .cachecol { scarf(&c, s) }
            if kind == .camera { lensEye(&c, s, f) } else { drawFace(&c, s, f) }
            accessory(&c, s)
        }

        // Effects around
        var fx = ctx
        fx.translateBy(x: center.x, y: center.y)
        if (face == .carente && (kind == .nuvem || kind == .gotinha)) || raining { drizzle(&fx, s) }
        if kind == .pipoca && face == .feliz { kernels(&fx, s) }
        if kind == .gotinha && face == .sono { steamUp(&fx, s) }
        if kind == .camera && face == .ouvindo { rec(&fx, s) }
        if face == .sono { zzz(&fx, s) }
        if face == .pensando { dots(&fx, s) }
        if face == .ouvindo { waves(&fx, s) }
        if cold && face != .sono { breath(&fx, s) }
        if hot { sweat(&fx, s) }
        if skin == .carnaval { confetti(&fx, s) }
    }

    // MARK: Bodies

    func bodyPath(_ s: Double) -> Path {
        var p = Path()
        switch kind {
        case .bolinho:
            p.addRoundedRect(in: CGRect(x: -0.56 * s, y: -0.36 * s, width: 1.12 * s, height: 0.76 * s),
                             cornerSize: CGSize(width: 0.36 * s, height: 0.36 * s), style: .continuous)
        case .marshmallow, .mochi:
            p.addRoundedRect(in: CGRect(x: -0.5 * s, y: -0.42 * s, width: s, height: 0.84 * s),
                             cornerSize: CGSize(width: 0.3 * s, height: 0.3 * s), style: .continuous)
        case .nuvem:
            let wob = face == .pensando ? sin(t * 5) * 0.02 : 0
            p.move(to: pt(-0.44, 0.32, s))
            p.addCurve(to: pt(-0.40, -0.04, s), control1: pt(-0.62, 0.30, s), control2: pt(-0.62, 0.0, s))
            p.addCurve(to: pt(0.08, -0.20 - wob, s), control1: pt(-0.40, -0.40 - wob, s), control2: pt(0.02, -0.46 - wob, s))
            p.addCurve(to: pt(0.46, -0.02, s), control1: pt(0.20, -0.40 + wob, s), control2: pt(0.56, -0.30 + wob, s))
            p.addCurve(to: pt(0.44, 0.34, s), control1: pt(0.66, 0.02, s), control2: pt(0.64, 0.32, s))
            p.addCurve(to: pt(-0.44, 0.32, s), control1: pt(0.30, 0.46, s), control2: pt(-0.30, 0.46, s))
            p.closeSubpath()
        case .claquete:
            p.addRoundedRect(in: CGRect(x: -0.5 * s, y: -0.2 * s, width: s, height: 0.62 * s),
                             cornerSize: CGSize(width: 0.1 * s, height: 0.1 * s), style: .continuous)
        case .camera:
            p.addRoundedRect(in: CGRect(x: -0.52 * s, y: -0.3 * s, width: 1.04 * s, height: 0.68 * s),
                             cornerSize: CGSize(width: 0.16 * s, height: 0.16 * s), style: .continuous)
            p.addRoundedRect(in: CGRect(x: -0.36 * s, y: -0.42 * s, width: 0.28 * s, height: 0.16 * s),
                             cornerSize: CGSize(width: 0.05 * s, height: 0.05 * s))
        case .gotinha:
            p.move(to: pt(0, -0.56, s))
            p.addCurve(to: pt(0.42, 0.14, s), control1: pt(0.1, -0.38, s), control2: pt(0.42, -0.12, s))
            p.addCurve(to: pt(0, 0.48, s), control1: pt(0.42, 0.36, s), control2: pt(0.22, 0.48, s))
            p.addCurve(to: pt(-0.42, 0.14, s), control1: pt(-0.22, 0.48, s), control2: pt(-0.42, 0.36, s))
            p.addCurve(to: pt(0, -0.56, s), control1: pt(-0.42, -0.12, s), control2: pt(-0.1, -0.38, s))
            p.closeSubpath()
        case .pipoca:
            for (x, y, r) in [(-0.28, 0.08, 0.25), (0.28, 0.08, 0.25), (0.0, -0.14, 0.3), (-0.22, -0.24, 0.2),
                              (0.24, -0.22, 0.2), (0.0, 0.18, 0.28)] {
                p.addEllipse(in: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
        case .lampada:
            p.addEllipse(in: CGRect(x: -0.4 * s, y: -0.48 * s, width: 0.8 * s, height: 0.8 * s))
            p.addRoundedRect(in: CGRect(x: -0.17 * s, y: 0.16 * s, width: 0.34 * s, height: 0.18 * s),
                             cornerSize: CGSize(width: 0.04 * s, height: 0.04 * s))
        case .planetinha, .bolha:
            p.addEllipse(in: CGRect(x: -0.42 * s, y: -0.42 * s, width: 0.84 * s, height: 0.84 * s))
        case .gatinho:
            p.move(to: pt(-0.44, 0.32, s))
            p.addCurve(to: pt(-0.40, -0.04, s), control1: pt(-0.62, 0.30, s), control2: pt(-0.62, 0.0, s))
            p.addCurve(to: pt(0.08, -0.20, s), control1: pt(-0.40, -0.40, s), control2: pt(0.02, -0.46, s))
            p.addCurve(to: pt(0.46, -0.02, s), control1: pt(0.20, -0.40, s), control2: pt(0.56, -0.30, s))
            p.addCurve(to: pt(0.44, 0.34, s), control1: pt(0.66, 0.02, s), control2: pt(0.64, 0.32, s))
            p.addCurve(to: pt(-0.44, 0.32, s), control1: pt(0.30, 0.46, s), control2: pt(-0.30, 0.46, s))
            p.closeSubpath()
        case .vapor:
            let w = 0.42, wave = sin(t * 2.4)
            p.move(to: pt(-w, 0, s))
            p.addCurve(to: pt(w, 0, s), control1: pt(-w, -0.56, s), control2: pt(w, -0.56, s))
            p.addLine(to: pt(w, 0.28, s))
            for i in 0..<4 {
                let x0 = w - Double(i) / 4 * 2 * w, x1 = w - Double(i + 1) / 4 * 2 * w
                let dip = (i % 2 == 1 ? 0.06 : -0.02) + wave * 0.02 * (i % 2 == 1 ? 1 : -1)
                p.addQuadCurve(to: pt(x1, 0.28, s), control: pt((x0 + x1) / 2, 0.40 + dip, s))
            }
            p.closeSubpath()
        }
        return p
    }

    func body(_ c: inout GraphicsContext, _ s: Double) {
        let path = bodyPath(s)
        if kind == .bolha { bubbleBody(&c, s, path); return }
        let tint: (Color, Color, Color) = {
            switch kind {
            case .nuvem: return (.white, Color(hex: "#F2F7FF"), Color(hex: "#D3E2F7"))
            case .vapor: return (.white, Color(hex: "#EEF6FF"), Color(hex: "#CDE1FA").opacity(0.85))
            case .camera: return (Color(hex: "#9AA3B2"), Color(hex: "#6B7280"), Color(hex: "#3F4654"))
            case .gotinha: return (Color(hex: "#F0F9FF"), Color(hex: "#BAE6FD"), Color(hex: "#60A5FA"))
            case .pipoca: return (Color(hex: "#FFFDF5"), Color(hex: "#FEF3C7"), Color(hex: "#FBD38D"))
            case .lampada:
                let on = face == .pensando || face == .feliz
                return on ? (Color(hex: "#FFFDE7"), Color(hex: "#FFF3B0"), Color(hex: "#FFD54F"))
                          : (face == .carente ? (Color(hex: "#F1F1EE"), Color(hex: "#E2E1DA"), Color(hex: "#C9C7BD"))
                                              : (Color(hex: "#FFFEF5"), Color(hex: "#FFF8D6"), Color(hex: "#F5E6A8")))
            case .planetinha: return (Color(hex: "#DDD6FE"), Color(hex: "#A78BFA"), Color(hex: "#6D28D9"))
            case .gatinho: return (.white, Color(hex: "#FFF7F2"), Color(hex: "#F1DDD3"))
            default: return (.white, Color(hex: "#F6F7FB"), Color(hex: "#DDE3EE"))
            }
        }()
        let glowColor: Color = {
            switch kind {
            case .lampada: return Color(hex: "#FFD54F").opacity(face == .pensando || face == .feliz ? 0.95 : (face == .carente ? 0.1 : 0.45))
            case .planetinha: return Color(hex: "#A78BFA").opacity(0.5)
            case .pipoca: return Color(hex: "#FBBF24").opacity(0.35)
            default: return Color(hex: "#7CC4FF").opacity(0.4)
            }
        }()
        var glow = c
        glow.addFilter(.shadow(color: glowColor, radius: (kind == .lampada && (face == .pensando || face == .feliz) ? 0.22 : 0.08) * s))
        glow.fill(path, with: .linearGradient(Gradient(stops: [.init(color: tint.0, location: 0),
                                                              .init(color: tint.1, location: 0.6),
                                                              .init(color: tint.2, location: 1)]),
                                              startPoint: pt(0, -0.5, s), endPoint: pt(0, 0.5, s)))
        var inner = c
        inner.clip(to: path)
        inner.fill(Path(CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s)),
                   with: .radialGradient(Gradient(colors: [Color(hex: "#8CA5D2").opacity(0.3), .clear]),
                                         center: pt(0.12, 0.5, s), startRadius: 0.05 * s, endRadius: 0.6 * s))
        inner.fill(Path(CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s)),
                   with: .radialGradient(Gradient(colors: [.white.opacity(0.95), .clear]),
                                         center: pt(-0.2, -0.28, s), startRadius: 0, endRadius: 0.34 * s))
    }

    func cowlick(_ c: inout GraphicsContext, _ s: Double, small: Bool = false) {
        var k = c
        k.translateBy(x: (small ? 0.1 : 0.04) * s, y: (small ? -0.36 : -0.42) * s)
        k.rotate(by: .radians(sin(t * 1.8) * 0.14))
        let r = small ? 0.75 : 1.0
        puff(&k, -0.05 * s * r, 0, 0.07 * s * r)
        puff(&k, 0.05 * s * r, -0.04 * s * r, 0.085 * s * r)
    }

    func puff(_ c: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double) {
        c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(colors: [.white, Color(hex: "#DDE3EE")]),
                                     center: CGPoint(x: x - r * 0.3, y: y - r * 0.4), startRadius: r * 0.1, endRadius: r))
    }

    // MARK: Face

    struct FaceParams {
        enum Eyes { case open, happy, closed, spiral }
        enum Mouth { case smile, big, open, o, flat, sad, none, wobbly }
        var gx = 0.0, gy = 0.0, open = 1.0, wide = 1.0, blush = 0.55
        var eyes = Eyes.open, mouth = Mouth.smile
    }

    func drawFace(_ c: inout GraphicsContext, _ s: Double, _ f: FaceParams) {
        let ey = faceY * s
        // Bolinho's eyes sit on a sphere: they travel further and flatten toward the edges.
        let ex = (kind == .bolinho ? 0.2 : 0.15) * s
        let travel = kind == .bolinho ? 0.075 : 0.045
        let gx = f.gx * travel * s, gy = f.gy * travel * 0.8 * s
        let eyeSize = kind == .bolinho ? 1.28 : 1.0
        let squeeze = kind == .bolinho ? 1 - abs(f.gx) * 0.18 : 1
        let ink = kind == .bolha ? Color(hex: "#E8F1FF") : Color(hex: "#16181E")
        for d in [-1.0, 1.0] {
            c.fill(Path(ellipseIn: CGRect(x: d * (ex + 0.12 * s) + gx * 0.4 - 0.07 * s, y: ey + 0.11 * s + gy * 0.3 - 0.038 * s,
                                          width: 0.14 * s, height: 0.076 * s)),
                   with: .color(Color(red: 1, green: 0.53, blue: 0.65).opacity(f.blush)))
        }
        for d in [-1.0, 1.0] {
            let x = d * ex + gx, y = ey + gy
            switch f.eyes {
            case .happy:
                var a = Path(); a.addArc(center: CGPoint(x: x, y: y + 0.03 * s), radius: 0.05 * s,
                                         startAngle: .radians(.pi * 1.12), endAngle: .radians(.pi * 1.88), clockwise: false)
                c.stroke(a, with: .color(ink), style: StrokeStyle(lineWidth: 0.032 * s, lineCap: .round))
            case .closed:
                var a = Path(); a.addArc(center: CGPoint(x: x, y: y - 0.01 * s), radius: 0.045 * s,
                                         startAngle: .radians(.pi * 0.15), endAngle: .radians(.pi * 0.85), clockwise: false)
                c.stroke(a, with: .color(ink), style: StrokeStyle(lineWidth: 0.028 * s, lineCap: .round))
            case .spiral:
                var sp = Path()
                for i in 0..<40 {
                    let a = Double(i) / 40 * .pi * 5 + t * 6, r = Double(i) / 40 * 0.06 * s
                    let p = CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
                    if i == 0 { sp.move(to: p) } else { sp.addLine(to: p) }
                }
                c.stroke(sp, with: .color(ink), style: StrokeStyle(lineWidth: 0.018 * s, lineCap: .round))
            case .open:
                let rx = 0.056 * s * f.wide * eyeSize * squeeze, ry = 0.078 * s * f.wide * eyeSize * max(f.open, 0.07)
                c.fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry)), with: .color(ink))
                if ry > 0.02 * s {
                    c.fill(Path(ellipseIn: CGRect(x: x - rx * 0.66, y: y - ry * 0.67, width: rx * 0.72, height: ry * 0.54)), with: .color(.white))
                    c.fill(Path(ellipseIn: CGRect(x: x + rx * 0.17, y: y + ry * 0.25, width: rx * 0.3, height: rx * 0.3)), with: .color(.white.opacity(0.6)))
                }
            }
        }
        let m = CGPoint(x: gx * 0.6, y: ey + 0.12 * s + gy * 0.5)
        let mouthFill = Color(hex: "#4A2230")
        var mp = Path()
        switch f.mouth {
        case .smile:
            mp.addArc(center: CGPoint(x: m.x, y: m.y - 0.02 * s), radius: 0.03 * s, startAngle: .radians(.pi * 0.2), endAngle: .radians(.pi * 0.8), clockwise: false)
            c.stroke(mp, with: .color(ink), style: StrokeStyle(lineWidth: 0.02 * s, lineCap: .round))
        case .sad:
            mp.addArc(center: CGPoint(x: m.x, y: m.y + 0.03 * s), radius: 0.03 * s, startAngle: .radians(.pi * 1.2), endAngle: .radians(.pi * 1.8), clockwise: false)
            c.stroke(mp, with: .color(ink), style: StrokeStyle(lineWidth: 0.02 * s, lineCap: .round))
        case .flat:
            mp.move(to: CGPoint(x: m.x - 0.025 * s, y: m.y)); mp.addLine(to: CGPoint(x: m.x + 0.025 * s, y: m.y))
            c.stroke(mp, with: .color(ink), style: StrokeStyle(lineWidth: 0.02 * s, lineCap: .round))
        case .big:
            mp.addArc(center: CGPoint(x: m.x, y: m.y - 0.022 * s), radius: 0.045 * s, startAngle: .zero, endAngle: .radians(.pi), clockwise: false)
            c.fill(mp, with: .color(mouthFill))
        case .open:
            c.fill(Path(ellipseIn: CGRect(x: m.x - 0.03 * s, y: m.y - 0.025 * s, width: 0.06 * s, height: 0.05 * s)), with: .color(mouthFill))
        case .o:
            c.fill(Path(ellipseIn: CGRect(x: m.x - 0.02 * s, y: m.y - 0.024 * s, width: 0.04 * s, height: 0.048 * s)), with: .color(mouthFill))
        case .wobbly:
            mp.move(to: CGPoint(x: m.x - 0.04 * s, y: m.y))
            for i in 1...8 { mp.addLine(to: CGPoint(x: m.x - 0.04 * s + Double(i) * 0.01 * s, y: m.y + (i % 2 == 0 ? -1 : 1) * 0.008 * s)) }
            c.stroke(mp, with: .color(ink), style: StrokeStyle(lineWidth: 0.016 * s, lineCap: .round))
        case .none:
            break
        }
    }

    // MARK: Skins

    /// Top of the head for hats, by body.
    var headTop: Double {
        switch kind {
        case .nuvem, .gatinho: -0.40
        case .claquete: -0.5
        case .camera: -0.44
        case .gotinha: -0.48
        case .bolinho: -0.36
        default: -0.42
        }
    }

    /// Eye line of each body.
    var faceY: Double {
        switch kind {
        case .vapor: -0.04
        case .nuvem, .gatinho: 0.08
        case .bolinho, .planetinha, .bolha: 0.0
        case .claquete: 0.12
        case .gotinha: 0.12
        case .pipoca: 0.02
        case .lampada: -0.1
        default: 0.04
        }
    }

    func accessory(_ c: inout GraphicsContext, _ s: Double) {
        let top = headTop * s
        switch skin {
        case .fone:
            var band = Path()
            band.addArc(center: CGPoint(x: 0, y: -0.02 * s), radius: 0.52 * s, startAngle: .radians(.pi * 1.08), endAngle: .radians(.pi * 1.92), clockwise: false)
            c.stroke(band, with: .color(Color(hex: "#2B2F38")), style: StrokeStyle(lineWidth: 0.05 * s, lineCap: .round))
            for d in [-1.0, 1.0] {
                c.fill(Path(ellipseIn: CGRect(x: d * 0.52 * s - 0.07 * s, y: -0.09 * s, width: 0.14 * s, height: 0.22 * s)), with: .color(Color(hex: "#2B2F38")))
                c.fill(Path(ellipseIn: CGRect(x: d * 0.52 * s - 0.03 * s, y: -0.04 * s, width: 0.06 * s, height: 0.12 * s)), with: .color(Color(hex: "#7CC4FF")))
            }
        case .boina:
            c.fill(Path(ellipseIn: CGRect(x: -0.24 * s, y: top - 0.08 * s, width: 0.6 * s, height: 0.18 * s)), with: .color(Color(hex: "#1F2128")))
            c.fill(Path(CGRect(x: 0.04 * s, y: top - 0.15 * s, width: 0.025 * s, height: 0.07 * s)), with: .color(Color(hex: "#1F2128")))
        case .oculos:
            let ey = faceY * s
            let gex = (kind == .bolinho ? 0.2 : 0.15)
            for d in [-1.0, 1.0] {
                c.fill(Path(ellipseIn: CGRect(x: d * gex * s - 0.1 * s, y: ey - 0.075 * s, width: 0.2 * s, height: 0.15 * s)), with: .color(Color(hex: "#0E1016").opacity(0.95)))
            }
            var bridge = Path(); bridge.move(to: CGPoint(x: -0.06 * s, y: ey - 0.01 * s)); bridge.addLine(to: CGPoint(x: 0.06 * s, y: ey - 0.01 * s))
            c.stroke(bridge, with: .color(Color(hex: "#0E1016")), lineWidth: 0.02 * s)
        case .coroa, .anoNovo:
            if skin == .anoNovo { partyHat(&c, s, top); break }
            var cr = Path()
            let y = top
            cr.move(to: CGPoint(x: -0.14 * s, y: y)); cr.addLine(to: CGPoint(x: -0.16 * s, y: y - 0.14 * s))
            cr.addLine(to: CGPoint(x: -0.07 * s, y: y - 0.06 * s)); cr.addLine(to: CGPoint(x: 0.02 * s, y: y - 0.17 * s))
            cr.addLine(to: CGPoint(x: 0.1 * s, y: y - 0.06 * s)); cr.addLine(to: CGPoint(x: 0.19 * s, y: y - 0.14 * s))
            cr.addLine(to: CGPoint(x: 0.17 * s, y: y)); cr.closeSubpath()
            c.fill(cr, with: .color(Color(hex: "#F5C542")))
            c.fill(Path(ellipseIn: CGRect(x: 0, y: y - 0.065 * s, width: 0.044 * s, height: 0.044 * s)), with: .color(Color(hex: "#E2554F")))
        case .natal:
            var hat = Path()
            hat.move(to: CGPoint(x: -0.26 * s, y: top + 0.04 * s))
            hat.addQuadCurve(to: CGPoint(x: 0.34 * s, y: top - 0.2 * s), control: CGPoint(x: 0.02 * s, y: top - 0.42 * s))
            hat.addLine(to: CGPoint(x: 0.26 * s, y: top + 0.04 * s)); hat.closeSubpath()
            c.fill(hat, with: .color(Color(hex: "#D7333A")))
            c.fill(Path(roundedRect: CGRect(x: -0.3 * s, y: top - 0.01 * s, width: 0.6 * s, height: 0.09 * s), cornerRadius: 0.045 * s), with: .color(.white))
            c.fill(Path(ellipseIn: CGRect(x: 0.29 * s, y: top - 0.25 * s, width: 0.1 * s, height: 0.1 * s)), with: .color(.white))
        case .halloween:
            var brim = Path(); brim.addEllipse(in: CGRect(x: -0.36 * s, y: top - 0.04 * s, width: 0.72 * s, height: 0.12 * s))
            c.fill(brim, with: .color(Color(hex: "#3B1E5C")))
            var cone = Path()
            cone.move(to: CGPoint(x: -0.2 * s, y: top + 0.01 * s)); cone.addLine(to: CGPoint(x: 0.12 * s, y: top - 0.42 * s))
            cone.addLine(to: CGPoint(x: 0.2 * s, y: top + 0.01 * s)); cone.closeSubpath()
            c.fill(cone, with: .color(Color(hex: "#4B2775")))
            c.fill(Path(CGRect(x: -0.19 * s, y: top - 0.05 * s, width: 0.38 * s, height: 0.045 * s)), with: .color(Color(hex: "#F2913D")))
        case .pascoa:
            for d in [-1.0, 1.0] {
                var e = c
                e.translateBy(x: d * 0.13 * s, y: top - 0.12 * s)
                e.rotate(by: .radians(d * (0.18 + sin(t * 2 + d) * 0.05)))
                e.fill(Path(ellipseIn: CGRect(x: -0.06 * s, y: -0.16 * s, width: 0.12 * s, height: 0.3 * s)), with: .color(.white))
                e.fill(Path(ellipseIn: CGRect(x: -0.03 * s, y: -0.12 * s, width: 0.06 * s, height: 0.22 * s)), with: .color(Color(hex: "#FFB3C7")))
            }
        case .junina:
            c.fill(Path(ellipseIn: CGRect(x: -0.4 * s, y: top - 0.05 * s, width: 0.8 * s, height: 0.14 * s)), with: .color(Color(hex: "#E8C77A")))
            c.fill(Path(roundedRect: CGRect(x: -0.18 * s, y: top - 0.18 * s, width: 0.36 * s, height: 0.16 * s), cornerRadius: 0.06 * s), with: .color(Color(hex: "#DDB863")))
            c.fill(Path(CGRect(x: -0.18 * s, y: top - 0.06 * s, width: 0.36 * s, height: 0.03 * s)), with: .color(Color(hex: "#C0392B")))
        case .criancas:
            c.fill(Path(ellipseIn: CGRect(x: -0.12 * s, y: top - 0.1 * s, width: 0.24 * s, height: 0.14 * s)), with: .color(Color(hex: "#3B82F6")))
            var stem = Path(); stem.move(to: CGPoint(x: 0, y: top - 0.1 * s)); stem.addLine(to: CGPoint(x: 0, y: top - 0.17 * s))
            c.stroke(stem, with: .color(Color(hex: "#2B2F38")), lineWidth: 0.02 * s)
            let a = t * 9
            for i in 0..<2 {
                let ang = a + Double(i) * .pi
                var blade = Path()
                blade.addEllipse(in: CGRect(x: -0.1 * s, y: -0.025 * s, width: 0.2 * s, height: 0.05 * s))
                var bc = c
                bc.translateBy(x: 0, y: top - 0.17 * s)
                bc.scaleBy(x: cos(ang), y: 1)
                bc.fill(blade, with: .color(i == 0 ? Color(hex: "#F43F5E") : Color(hex: "#FACC15")))
            }
        default: break
        }
    }

    func partyHat(_ c: inout GraphicsContext, _ s: Double, _ top: Double) {
        var cone = Path()
        cone.move(to: CGPoint(x: -0.13 * s, y: top + 0.02 * s)); cone.addLine(to: CGPoint(x: 0.02 * s, y: top - 0.3 * s))
        cone.addLine(to: CGPoint(x: 0.15 * s, y: top + 0.02 * s)); cone.closeSubpath()
        c.fill(cone, with: .linearGradient(Gradient(colors: [Color(hex: "#F5C542"), Color(hex: "#E2554F")]),
                                           startPoint: CGPoint(x: 0, y: top - 0.3 * s), endPoint: CGPoint(x: 0, y: top)))
        c.fill(Path(ellipseIn: CGRect(x: -0.02 * s, y: top - 0.35 * s, width: 0.08 * s, height: 0.08 * s)), with: .color(.white))
    }

    func scarf(_ c: inout GraphicsContext, _ s: Double) {
        let y = kind == .vapor ? 0.18 : 0.28
        var p = Path()
        p.move(to: pt(-0.46, y, s)); p.addQuadCurve(to: pt(0.48, y - 0.02, s), control: pt(0, y + 0.12, s))
        p.addLine(to: pt(0.48, y + 0.08, s)); p.addQuadCurve(to: pt(-0.46, y + 0.1, s), control: pt(0, y + 0.24, s))
        p.closeSubpath()
        c.fill(p, with: .color(Color(hex: "#C93A3A")))
        let sway = sin(t * 2.2) * 0.02
        var tail = Path()
        tail.move(to: pt(0.18, y + 0.12, s)); tail.addLine(to: pt(0.28 + sway, y + 0.34, s))
        tail.addLine(to: pt(0.18 + sway, y + 0.36, s)); tail.addLine(to: pt(0.1, y + 0.14, s)); tail.closeSubpath()
        c.fill(tail, with: .color(Color(hex: "#B83232")))
        for i in -3...3 {
            var st = Path()
            st.move(to: pt(Double(i) * 0.12, y + 0.05, s)); st.addLine(to: pt(Double(i) * 0.12 + 0.02, y + 0.16, s))
            c.stroke(st, with: .color(.white.opacity(0.85)), lineWidth: 0.016 * s)
        }
    }

    // MARK: Effects

    func rainbow(_ c: inout GraphicsContext, _ s: Double) {
        let colors = ["#F87171", "#FBBF24", "#34D399", "#60A5FA", "#A78BFA"]
        for (i, hex) in colors.enumerated() {
            var a = Path()
            a.addArc(center: pt(0, 0.1, s), radius: (0.62 + Double(i) * 0.035) * s,
                     startAngle: .radians(.pi * 1.08), endAngle: .radians(.pi * 1.92), clockwise: false)
            c.stroke(a, with: .color(Color(hex: hex).opacity(0.55)), lineWidth: 0.03 * s)
        }
    }

    func steamBurst(_ c: inout GraphicsContext, _ s: Double) {
        let p = faceT
        for i in 0..<6 {
            let ang = Double(i) / 6 * .pi * 2
            let r = (0.4 + p * 0.4) * s
            var e = c
            e.opacity = max(0, 1 - p)
            e.fill(Path(ellipseIn: CGRect(x: cos(ang) * r - 0.06 * s, y: sin(ang) * r * 0.7 - 0.06 * s, width: 0.12 * s, height: 0.12 * s)),
                   with: .color(.white.opacity(0.7)))
        }
    }

    func drizzle(_ c: inout GraphicsContext, _ s: Double) {
        for i in 0..<6 {
            let x = (-0.35 + Double(i) * 0.14) * s
            let p = (t * 1.2 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            var d = Path()
            d.move(to: CGPoint(x: x, y: (0.45 + p * 0.4) * s)); d.addLine(to: CGPoint(x: x - 0.01 * s, y: (0.5 + p * 0.4) * s))
            var dc = c; dc.opacity = 1 - p
            dc.stroke(d, with: .color(Color(hex: "#7CC4FF")), style: StrokeStyle(lineWidth: 0.018 * s, lineCap: .round))
        }
    }

    func zzz(_ c: inout GraphicsContext, _ s: Double) {
        for i in 0..<3 {
            let p = (t * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var z = c; z.opacity = 1 - p
            z.draw(Text("z").font(.system(size: (0.07 + p * 0.07) * s, weight: .semibold)).foregroundColor(Color(hex: "#C8DCFF")),
                   at: CGPoint(x: (0.38 + p * 0.2) * s, y: -(0.4 + p * 0.35) * s))
        }
    }

    func dots(_ c: inout GraphicsContext, _ s: Double) {
        for i in 0..<3 {
            let a = 0.35 + 0.65 * max(0, sin(t * 4 - Double(i) * 0.7))
            let r = (0.022 + Double(i) * 0.007) * s
            c.fill(Path(ellipseIn: CGRect(x: (0.36 + Double(i) * 0.09) * s - r, y: -(0.52 + Double(i) * 0.06) * s - r, width: 2 * r, height: 2 * r)),
                   with: .color(.white.opacity(a)))
        }
    }

    func waves(_ c: inout GraphicsContext, _ s: Double) {
        for i in 0..<3 {
            let p = (t * 1.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            for d in [-1.0, 1.0] {
                var a = Path()
                let start = d < 0 ? Double.pi * 0.7 : -Double.pi * 0.3
                a.addArc(center: CGPoint(x: d * 0.58 * s, y: 0), radius: (0.07 + p * 0.16) * s,
                         startAngle: .radians(start), endAngle: .radians(start + .pi * 0.6), clockwise: false)
                c.stroke(a, with: .color(Color(hex: "#7CC4FF").opacity(0.7 * (1 - p))), lineWidth: 0.016 * s)
            }
        }
    }

    func breath(_ c: inout GraphicsContext, _ s: Double) {
        let p = (t * 0.6).truncatingRemainder(dividingBy: 1)
        var b = c; b.opacity = 0.5 * (1 - p)
        b.fill(Path(ellipseIn: CGRect(x: (0.1 + p * 0.2) * s, y: (0.12 - p * 0.1) * s, width: (0.06 + p * 0.08) * s, height: (0.04 + p * 0.05) * s)),
               with: .color(.white))
    }

    func sweat(_ c: inout GraphicsContext, _ s: Double) {
        let p = (t * 0.7).truncatingRemainder(dividingBy: 1)
        var d = Path()
        let x = 0.36 * s, y = (-0.2 + p * 0.2) * s
        d.move(to: CGPoint(x: x, y: y - 0.04 * s))
        d.addQuadCurve(to: CGPoint(x: x, y: y + 0.03 * s), control: CGPoint(x: x + 0.04 * s, y: y + 0.02 * s))
        d.addQuadCurve(to: CGPoint(x: x, y: y - 0.04 * s), control: CGPoint(x: x - 0.04 * s, y: y + 0.02 * s))
        var dc = c; dc.opacity = 1 - p * 0.6
        dc.fill(d, with: .color(Color(hex: "#7CC4FF")))
    }

    func confetti(_ c: inout GraphicsContext, _ s: Double) {
        let colors = ["#F87171", "#FBBF24", "#34D399", "#60A5FA", "#F472B6"]
        for i in 0..<10 {
            let p = (t * 0.4 + Double(i) * 0.13).truncatingRemainder(dividingBy: 1)
            let x = (-0.5 + Double(i % 5) * 0.25 + sin(t + Double(i)) * 0.05) * s
            var cc = c
            cc.translateBy(x: x, y: (-0.6 + p * 1.2) * s)
            cc.rotate(by: .radians(t * 3 + Double(i)))
            cc.fill(Path(CGRect(x: -0.015 * s, y: -0.008 * s, width: 0.03 * s, height: 0.016 * s)), with: .color(Color(hex: colors[i % 5])))
        }
    }

    // MARK: Character quirks

    /// Drawn before the body (behind it).
    func behind(_ c: inout GraphicsContext, _ s: Double, _ f: FaceParams) {
        switch kind {
        case .planetinha: ring(&c, s, front: false)
        case .gatinho:
            if face == .feliz { nyanTrail(&c, s) }
            var tail = Path()                                   // tail wagging behind
            let w = sin(t * 4) * 0.08
            tail.move(to: pt(0.4, 0.22, s))
            tail.addQuadCurve(to: pt(0.66, -0.12 + w, s), control: pt(0.74, 0.22, s))
            c.stroke(tail, with: .color(Color(hex: "#EADBD2")), style: StrokeStyle(lineWidth: 0.09 * s, lineCap: .round))
            let perk = face == .ouvindo ? -0.06 : 0.0           // ears perk up when listening
            for d in [-1.0, 1.0] {
                var ear = Path()
                ear.move(to: pt(d * 0.12, -0.3, s))
                ear.addLine(to: pt(d * 0.3, -0.56 + perk, s))
                ear.addLine(to: pt(d * 0.38, -0.2, s))
                ear.closeSubpath()
                c.fill(ear, with: .color(Color(hex: "#FBF3EE")))
                var inner = Path()
                inner.move(to: pt(d * 0.19, -0.3, s)); inner.addLine(to: pt(d * 0.29, -0.47 + perk, s)); inner.addLine(to: pt(d * 0.33, -0.27, s)); inner.closeSubpath()
                c.fill(inner, with: .color(Color(hex: "#FFB8C8")))
            }
        default: break
        }
    }

    /// Drawn on the body, under the face.
    func front(_ c: inout GraphicsContext, _ s: Double, _ f: FaceParams) {
        switch kind {
        case .claquete:
            // The clapper: opens while talking, claps when happy.
            var open = 0.0
            if face == .falando { open = (sin(t * 10) + 1) * 0.12 }
            if face == .feliz { open = abs(sin(t * 6)) * 0.35 }
            var stick = c
            stick.translateBy(x: -0.5 * s, y: -0.2 * s)
            stick.rotate(by: .radians(-open))
            let bar = CGRect(x: 0, y: -0.16 * s, width: s, height: 0.15 * s)
            stick.fill(Path(roundedRect: bar, cornerRadius: 0.03 * s), with: .color(Color(hex: "#1F2128")))
            for i in 0..<5 {
                var st = Path()
                let x = (0.06 + Double(i) * 0.2) * s
                st.move(to: CGPoint(x: x, y: -0.16 * s)); st.addLine(to: CGPoint(x: x + 0.1 * s, y: -0.16 * s))
                st.addLine(to: CGPoint(x: x + 0.04 * s, y: -0.01 * s)); st.addLine(to: CGPoint(x: x - 0.06 * s, y: -0.01 * s)); st.closeSubpath()
                stick.fill(st, with: .color(.white))
            }
            // top stripe of the board
            c.fill(Path(CGRect(x: -0.5 * s, y: -0.2 * s, width: s, height: 0.06 * s)), with: .color(Color(hex: "#1F2128")))
        case .camera:
            c.fill(Path(ellipseIn: CGRect(x: 0.28 * s, y: -0.22 * s, width: 0.1 * s, height: 0.1 * s)), with: .color(Color(hex: "#E5E7EB").opacity(0.8)))
        case .lampada:
            for i in 0..<3 {   // screw base
                c.fill(Path(roundedRect: CGRect(x: -0.17 * s, y: (0.33 + Double(i) * 0.06) * s, width: 0.34 * s, height: 0.05 * s), cornerRadius: 0.02 * s),
                       with: .color(Color(hex: i % 2 == 0 ? "#9CA3AF" : "#6B7280")))
            }
            c.fill(Path(ellipseIn: CGRect(x: -0.06 * s, y: 0.5 * s, width: 0.12 * s, height: 0.06 * s)), with: .color(Color(hex: "#4B5563")))
        case .planetinha:
            ring(&c, s, front: true)
            if face == .focado {   // two moons per agent at work
                for i in 0..<2 {
                    let a = t * 1.6 + Double(i) * .pi
                    c.fill(Path(ellipseIn: CGRect(x: cos(a) * 0.62 * s - 0.05 * s, y: sin(a) * 0.18 * s - 0.05 * s, width: 0.1 * s, height: 0.1 * s)),
                           with: .color(Color(hex: "#E5E7EB")))
                }
            }
        case .gatinho:
            for d in [-1.0, 1.0] {   // whiskers
                for k in [-1.0, 1.0] {
                    var w = Path()
                    w.move(to: pt(d * 0.3, 0.2 + k * 0.03, s)); w.addLine(to: pt(d * 0.5, 0.18 + k * 0.07, s))
                    c.stroke(w, with: .color(Color(hex: "#9CA3AF").opacity(0.7)), lineWidth: 0.01 * s)
                }
            }
        case .pipoca:
            for (x, y) in [(-0.3, -0.05), (0.32, 0.25), (0.1, -0.33)] {   // golden toasted bits
                c.fill(Path(ellipseIn: CGRect(x: x * s, y: y * s, width: 0.05 * s, height: 0.035 * s)), with: .color(Color(hex: "#F59E0B").opacity(0.5)))
            }
        default: break
        }
    }

    func ring(_ c: inout GraphicsContext, _ s: Double, front: Bool) {
        var r = Path()
        let spin = t * 0.8
        r.addArc(center: .zero, radius: 0.6 * s, startAngle: .radians(front ? 0 : .pi), endAngle: .radians(front ? .pi : 2 * .pi), clockwise: false)
        var rc = c
        rc.scaleBy(x: 1, y: 0.26)
        rc.rotate(by: .radians(0))
        rc.stroke(r, with: .linearGradient(Gradient(colors: [Color(hex: "#FDE68A"), Color(hex: "#F472B6"), Color(hex: "#FDE68A")]),
                                           startPoint: CGPoint(x: -0.6 * s * cos(spin), y: 0), endPoint: CGPoint(x: 0.6 * s * cos(spin), y: 0)),
                  lineWidth: 0.07 * s)
    }

    func nyanTrail(_ c: inout GraphicsContext, _ s: Double) {
        let colors = ["#F87171", "#FBBF24", "#34D399", "#60A5FA", "#A78BFA"]
        for (i, hex) in colors.enumerated() {
            let y = (-0.12 + Double(i) * 0.06) * s
            var p = Path()
            p.move(to: CGPoint(x: -0.45 * s, y: y))
            for k in 1...6 { p.addLine(to: CGPoint(x: (-0.45 - Double(k) * 0.08) * s, y: y + (k % 2 == 0 ? 0 : 0.025 * s) * (sin(t * 8) > 0 ? 1 : -1))) }
            c.stroke(p, with: .color(Color(hex: hex)), lineWidth: 0.06 * s)
        }
    }

    /// Camerazinha: the lens is a single big eye.
    func lensEye(_ c: inout GraphicsContext, _ s: Double, _ f: FaceParams) {
        let r = 0.24 * s
        c.fill(Path(ellipseIn: CGRect(x: -r - 0.03 * s, y: -r + 0.02 * s, width: 2 * (r + 0.03 * s), height: 2 * (r + 0.03 * s))), with: .color(Color(hex: "#1F2128")))
        c.fill(Path(ellipseIn: CGRect(x: -r, y: -r + 0.05 * s, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(colors: [Color(hex: "#3B82F6"), Color(hex: "#1E3A8A"), Color(hex: "#0B1020")]),
                                     center: CGPoint(x: 0, y: 0.05 * s), startRadius: 0, endRadius: r))
        switch f.eyes {
        case .happy, .closed:
            var lid = Path()
            lid.addArc(center: CGPoint(x: 0, y: 0.05 * s + (f.eyes == .happy ? 0.05 * s : 0)), radius: 0.12 * s,
                       startAngle: .radians(f.eyes == .happy ? .pi * 1.1 : .pi * 0.1), endAngle: .radians(f.eyes == .happy ? .pi * 1.9 : .pi * 0.9), clockwise: false)
            c.stroke(lid, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 0.03 * s, lineCap: .round))
        default:
            // The aperture opens and closes with the mood.
            let ap = (0.07 + (f.wide - 1) * 0.12) * s * max(f.open, 0.1)
            let px = f.gx * 0.08 * s, py = 0.05 * s + f.gy * 0.06 * s
            c.fill(Path(ellipseIn: CGRect(x: px - ap, y: py - ap, width: 2 * ap, height: 2 * ap)), with: .color(Color(hex: "#05070C")))
            c.fill(Path(ellipseIn: CGRect(x: px - ap * 0.2 - 0.07 * s, y: py - 0.09 * s, width: 0.07 * s, height: 0.05 * s)), with: .color(.white.opacity(0.85)))
        }
        for d in [-1.0, 1.0] {   // blush beside the lens
            c.fill(Path(ellipseIn: CGRect(x: d * 0.36 * s - 0.05 * s, y: 0.16 * s, width: 0.1 * s, height: 0.05 * s)),
                   with: .color(Color(red: 1, green: 0.53, blue: 0.65).opacity(f.blush)))
        }
    }

    func bubbleBody(_ c: inout GraphicsContext, _ s: Double, _ path: Path) {
        c.fill(path, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.05), Color(hex: "#BFDBFE").opacity(0.22)]),
                                           center: .zero, startRadius: 0.1 * s, endRadius: 0.42 * s))
        let shift = t * 0.6
        c.stroke(path, with: .linearGradient(Gradient(colors: [Color(hex: "#F472B6"), Color(hex: "#60A5FA"), Color(hex: "#34D399"), Color(hex: "#FBBF24"), Color(hex: "#F472B6")]),
                                             startPoint: CGPoint(x: -0.42 * s * cos(shift), y: -0.42 * s * sin(shift)),
                                             endPoint: CGPoint(x: 0.42 * s * cos(shift), y: 0.42 * s * sin(shift))),
                 lineWidth: 0.025 * s)
        c.fill(Path(ellipseIn: CGRect(x: -0.26 * s, y: -0.3 * s, width: 0.16 * s, height: 0.09 * s)), with: .color(.white.opacity(0.75)))
    }

    func bubblePop(_ c: inout GraphicsContext, _ s: Double) {
        let p = faceT / 0.45
        for i in 0..<10 {
            let a = Double(i) / 10 * .pi * 2
            var l = Path()
            l.move(to: CGPoint(x: cos(a) * (0.3 + p * 0.2) * s, y: sin(a) * (0.3 + p * 0.2) * s))
            l.addLine(to: CGPoint(x: cos(a) * (0.42 + p * 0.25) * s, y: sin(a) * (0.42 + p * 0.25) * s))
            var lc = c; lc.opacity = 1 - p
            lc.stroke(l, with: .color(Color(hex: "#BFDBFE")), style: StrokeStyle(lineWidth: 0.02 * s, lineCap: .round))
        }
    }

    func kernels(_ c: inout GraphicsContext, _ s: Double) {
        for i in 0..<5 {
            let p = (t * 0.9 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
            let x = (-0.4 + Double(i) * 0.2) * s + sin(Double(i) * 3) * 0.05 * s
            let y = (-0.4 - sin(p * .pi) * 0.35) * s
            var k = c; k.opacity = 1 - p * 0.7
            k.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.07 * s, height: 0.06 * s)), with: .color(Color(hex: "#FFFBEB")))
        }
    }

    func steamUp(_ c: inout GraphicsContext, _ s: Double) {
        for i in 0..<3 {
            let p = (t * 0.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var k = c; k.opacity = 0.5 * (1 - p)
            k.fill(Path(ellipseIn: CGRect(x: (-0.15 + Double(i) * 0.15) * s, y: (-0.6 - p * 0.3) * s, width: 0.1 * s, height: 0.07 * s)), with: .color(.white))
        }
    }

    func rec(_ c: inout GraphicsContext, _ s: Double) {
        guard sin(t * 6) > -0.2 else { return }
        c.fill(Path(ellipseIn: CGRect(x: 0.3 * s, y: -0.56 * s, width: 0.07 * s, height: 0.07 * s)), with: .color(Color(hex: "#EF4444")))
        c.draw(Text("REC").font(.system(size: 0.07 * s, weight: .bold)).foregroundColor(Color(hex: "#EF4444")),
               at: CGPoint(x: 0.48 * s, y: -0.525 * s))
    }

    private func pt(_ x: Double, _ y: Double, _ s: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
}
#endif

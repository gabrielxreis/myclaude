// Renders Cloud's characters to PNG (same drawing code as the app), for previews.
// swiftc -parse-as-library -o /tmp/render scripts/render-cloud.swift NotchBuddy/Sources/App/CloudPainter.swift NotchBuddy/Sources/CoucouKit/ColorHex.swift
import SwiftUI
import AppKit

@main
struct RenderCloud {
    @MainActor static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "cloud-preview.png"
        if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "vitrine" { showcase(out); return }
        if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "icone" { appIcon(out); return }
        if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "heroi" { heroFrames(out); return }
        if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "turma" { gangFrames(out); return }
        if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "menubar" { menuBar(out); return }
        let kinds: [CloudCharacterKind] = Array(CloudCharacterKind.allCases.dropFirst())
        let rows: [(CloudFace, CloudSkin, String)] = [
            (.parado, .padrao, "parado"), (.ouvindo, .padrao, "ouvindo"), (.feliz, .padrao, "feliz"),
            (.tonto, .padrao, "tonto (cutucado)"), (.surpreso, .padrao, "surpreso"), (.falando, .padrao, "falando"),
            (.pensando, .padrao, "pensando"), (.sono, .padrao, "com sono"), (.carente, .padrao, "carente"),
            (.parado, .cachecol, "frio: cachecol"), (.parado, .oculos, "calor: óculos"), (.parado, .fone, "fone"),
            (.parado, .boina, "boina"), (.parado, .coroa, "coroa"), (.parado, .natal, "Natal"),
            (.parado, .halloween, "Halloween"), (.parado, .pascoa, "Páscoa"), (.parado, .junina, "Festa Junina"),
        ]
        let cell: CGFloat = 170
        let view = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 110)
                ForEach(kinds, id: \.self) { k in Text(k.title).font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(width: cell) }
            }.frame(height: 34)
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 0) {
                    Text(rows[r].2).font(.system(size: 12)).foregroundColor(.gray).frame(width: 110, alignment: .leading).padding(.leading, 10)
                    ForEach(kinds, id: \.self) { k in
                        Canvas { ctx, size in
                            CloudPainter(kind: k, face: rows[r].0, skin: rows[r].1, t: 1.3, faceT: 2, hopT: 9,
                                         blinking: false, look: CGPoint(x: rows[r].2 == "parado" ? 0.7 : 0, y: 0), cold: rows[r].1 == .cachecol,
                                         hot: rows[r].1 == .oculos, raining: false).draw(in: &ctx, size: size)
                        }.frame(width: cell, height: cell)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.05, green: 0.055, blue: 0.07))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { print("falhou"); return }
        try? png.write(to: URL(fileURLWithPath: out))
        print("ok", out)
    }

    /// The 12 characters large, three moods each: for choosing.
    @MainActor static func showcase(_ out: String) {
        let kinds = Array(CloudCharacterKind.allCases.dropFirst())
        let cols = 4
        let view = VStack(spacing: 18) {
            ForEach(0..<(kinds.count + cols - 1) / cols, id: \.self) { r in
                HStack(spacing: 18) {
                    ForEach(0..<cols, id: \.self) { c in
                        let i = r * cols + c
                        if i < kinds.count {
                            VStack(spacing: 2) {
                                Canvas { ctx, size in
                                    CloudPainter(kind: kinds[i], face: .parado, skin: .padrao, t: 1.3, faceT: 2, hopT: 9, blinking: false,
                                                 look: CGPoint(x: 0.4, y: 0.1), cold: false, hot: false, raining: false).draw(in: &ctx, size: size)
                                }.frame(width: 230, height: 200)
                                HStack(spacing: 0) {
                                    ForEach([CloudFace.ouvindo, .feliz, .sono], id: \.self) { f in
                                        Canvas { ctx, size in
                                            CloudPainter(kind: kinds[i], face: f, skin: .padrao, t: 1.3, faceT: 2, hopT: 9, blinking: false,
                                                         look: .zero, cold: false, hot: false, raining: false).draw(in: &ctx, size: size)
                                        }.frame(width: 76, height: 70)
                                    }
                                }
                                Text(kinds[i].title).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.09, green: 0.1, blue: 0.12)))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(red: 0.04, green: 0.045, blue: 0.055))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: out))
        print("ok", out)
    }

    @MainActor static func savePNG<V: View>(_ v: V, _ out: String, scale: CGFloat = 1) {
        let r = ImageRenderer(content: v); r.scale = scale; r.isOpaque = false
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: out)); print("ok", out)
    }

    /// 1024×1024 app icon: Bolinho on a night-blue squircle (macOS icon grid: 824 px body).
    @MainActor static func appIcon(_ out: String) {
        let v = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.36), Color(red: 0.05, green: 0.06, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            RadialGradient(colors: [Color(red: 0.49, green: 0.77, blue: 1).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 380)
                .frame(width: 824, height: 824).clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            Canvas { ctx, size in
                CloudPainter(kind: .bolinho, face: .parado, skin: .padrao, t: 1.3, faceT: 2, hopT: 9, blinking: false,
                             look: CGPoint(x: 0.25, y: -0.1), cold: false, hot: false, raining: false).draw(in: &ctx, size: size)
            }
            .frame(width: 760, height: 760)
            .offset(y: -10)
        }
        .frame(width: 1024, height: 1024)
        savePNG(v, out)
    }

    /// Menu bar template: a cloud silhouette with two eye holes (black + alpha), 24×18 pt at 3x.
    @MainActor static func menuBar(_ out: String) {
        let v = Canvas { ctx, size in
            let s = size.height * 1.05
            var c = ctx
            c.translateBy(x: size.width / 2, y: size.height * 0.56)
            let p = CloudPainter(kind: .nuvem, face: .parado, skin: .padrao, t: 0, faceT: 2, hopT: 9, blinking: false,
                                 look: .zero, cold: false, hot: false, raining: false).bodyPath(s)
            c.fill(p, with: .color(.black))
            c.blendMode = .clear
            for d in [-1.0, 1.0] {
                c.fill(Path(ellipseIn: CGRect(x: d * 0.15 * s - 0.06 * s, y: 0.0 * s, width: 0.12 * s, height: 0.17 * s)), with: .color(.black))
            }
        }
        .frame(width: 24, height: 18)
        savePNG(v, out, scale: 3)
    }

    /// Bolinho going through its moods (frames for a GIF): out is a folder.
    @MainActor static func heroFrames(_ out: String) {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let moods: [(CloudFace, Double)] = [(.parado, 1.6), (.ouvindo, 1.6), (.feliz, 1.4), (.pensando, 1.6), (.sono, 1.6)]
        let fps = 20.0
        var frame = 0, t = 0.0
        for (face, dur) in moods {
            var ft = 0.0
            while ft < dur {
                let f = face, tt = t, fT = ft
                let v = Canvas { ctx, size in
                    CloudPainter(kind: .bolinho, face: f, skin: .padrao, t: tt, faceT: fT, hopT: f == .ouvindo ? fT : 9,
                                 blinking: f == .parado && fT > 1.0 && fT < 1.12, look: CGPoint(x: sin(tt * 1.3) * 0.6, y: 0),
                                 cold: false, hot: false, raining: false).draw(in: &ctx, size: size)
                }
                .frame(width: 360, height: 300)
                .background(Color(red: 0.05, green: 0.055, blue: 0.07))
                savePNG(v, String(format: "%@/f%04d.png", out, frame), scale: 1)
                frame += 1; t += 1 / fps; ft += 1 / fps
            }
        }
    }

    /// All 12 characters idling together (frames for a GIF).
    @MainActor static func gangFrames(_ out: String) {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let kinds = Array(CloudCharacterKind.allCases.dropFirst())
        let faces: [CloudFace] = [.parado, .feliz, .ouvindo, .parado, .falando, .parado, .feliz, .pensando, .parado, .focado, .feliz, .surpreso]
        for i in 0..<60 {
            let t = Double(i) / 20
            let v = VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { c in
                            let k = r * 6 + c
                            Canvas { ctx, size in
                                CloudPainter(kind: kinds[k], face: faces[k], skin: .padrao, t: t + Double(k) * 0.37, faceT: 2, hopT: 9,
                                             blinking: false, look: CGPoint(x: sin(t * 2 + Double(k)) * 0.5, y: 0),
                                             cold: false, hot: false, raining: false).draw(in: &ctx, size: size)
                            }
                            .frame(width: 140, height: 130)
                        }
                    }
                }
            }
            .background(Color(red: 0.05, green: 0.055, blue: 0.07))
            savePNG(v, String(format: "%@/f%04d.png", out, i), scale: 1)
        }
    }
}

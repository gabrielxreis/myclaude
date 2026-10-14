#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - What's new (after an update)
//
// When the app opens with news I haven't seen, Cloud is happy and a bubble under the notch asks
// "Quer ver o que eu sei fazer de novo?". Tapping the bubble (or Cloud) opens an animated list of
// the news: Cloud on top, each item springing in one after the other. Seen once, never again.
// New entries go at the top of `entries` with a new id.

struct CloudNews: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
}

@MainActor
final class CloudChangelog: ObservableObject {
    static let shared = CloudChangelog()

    static let entries: [CloudNews] = [
        CloudNews(id: "2026-10-13-agir-falando", icon: "bolt.fill", title: "Faço enquanto você fala",
                  detail: "\u{201C}Abre o YouTube no Chrome, pesquisa carros e coloca o mais assistido\u{201D}: cada parte já roda enquanto você continua falando."),
        CloudNews(id: "2026-10-13-tela", icon: "cursorarrow.click.2", title: "Clico, digito e uso qualquer app",
                  detail: "\u{201C}Clica em Filtros\u{201D}, \u{201C}digita bom dia\u{201D}, \u{201C}aperta enter\u{201D}, \u{201C}rola pra baixo\u{201D}, \u{201C}nova aba\u{201D}, \u{201C}pausa\u{201D}. Na hora, sem esperar o Claude."),
        CloudNews(id: "2026-10-13-sites", icon: "safari.fill", title: "Pesquiso dentro do site certo",
                  detail: "YouTube, Amazon, Mercado Livre, Wikipédia, Spotify… sempre no Chrome e na mesma aba."),
        CloudNews(id: "2026-10-13-nome", icon: "character.bubble.fill", title: "Meu nome é você quem escolhe",
                  detail: "Ei, Hey, Oi, Olá, E aí + o meu nome. Eu entendo as variações e você pode me ensinar como fala."),
        CloudNews(id: "2026-10-13-duvida", icon: "questionmark.bubble.fill", title: "Quando não entendo, eu pergunto",
                  detail: "Faço cara de dúvida e peço para você repetir, sem precisar me chamar de novo."),
        CloudNews(id: "2026-10-13-tamagotchi", icon: "heart.fill", title: "Cuide de mim",
                  detail: "Toque no meu card no notch: lanche, brincar, carinho, dormir. Eu tenho fome agora!"),
        CloudNews(id: "2026-10-13-permissoes", icon: "lock.shield.fill", title: "Tudo configurado de uma vez",
                  detail: "Ajustes → Permissões mostra o que falta e liga tudo em sequência."),
    ]

    private static let seenKey = "cloudNewsSeen"
    private var seen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.seenKey) }
    }

    var unseen: [CloudNews] { Self.entries.filter { !seen.contains($0.id) } }
    @Published private(set) var bubbleVisible = false
    private var bubble: NSPanel?

    /// At launch, after the opening: news → happy face and the bubble (once per batch of news).
    func announceIfNeeded() {
        // A brand new install sees everything as news: mark it all seen silently the first time.
        if UserDefaults.standard.object(forKey: Self.seenKey) == nil && !CloudIdentity.hatched {
            seen = Set(Self.entries.map(\.id)); return
        }
        guard !unseen.isEmpty, !bubbleVisible else { return }
        CloudExpression.shared.cheer(for: 6)
        showBubble()
        SoundEngine.shared.play("proud")
        appendAppLog("nb.log", "[Cloud] news: \(unseen.count) unseen")
    }

    func showBubble() {
        let screen = IslandWindowController.islandScreen()
        let w: CGFloat = 300, h: CGFloat = 74
        let top = screen.frame.maxY - max(AppState.shared.notchHeight, 24) - 10
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - w / 2, y: top - h, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: CloudNewsBubble(count: unseen.count) { [weak self] in self?.open() })
        p.orderFrontRegardless()
        bubble = p
        bubbleVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.hideBubble() }
    }

    func hideBubble() {
        bubble?.orderOut(nil)
        bubble = nil
        bubbleVisible = false
    }

    /// The animated list; what it shows is marked seen.
    func open() {
        let news = unseen.isEmpty ? Array(Self.entries.prefix(6)) : unseen
        hideBubble()
        seen = seen.union(news.map(\.id))
        CloudChangelogWindow.shared.show(news)
    }
}

/// The bubble under the notch, with its tail pointing up at Cloud.
struct CloudNewsBubble: View {
    let count: Int
    let onTap: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Triangle().fill(Color.white).frame(width: 16, height: 8)
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundColor(Color(hex: "#8B5CF6"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aprendi \(count == 1 ? "uma coisa nova" : "coisas novas")!")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.black)
                    Text("Quer ver o que eu sei fazer de novo?")
                        .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(.black.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .scaleEffect(shown ? 1 : 0.4, anchor: .top)
        .opacity(shown ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { shown = true } }
    }

    struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
            return p
        }
    }
}

// MARK: - Window

@MainActor
final class CloudChangelogWindow: NSObject, NSWindowDelegate {
    static let shared = CloudChangelogWindow()
    private var window: NSWindow?

    func show(_ news: [CloudNews]) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.backgroundColor = NSColor(red: 0.055, green: 0.06, blue: 0.075, alpha: 1)
        w.contentView = NSHostingView(rootView: CloudChangelogView(news: news))
        w.delegate = self
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil   // stops the animation
        window = nil
    }
}

struct CloudChangelogView: View {
    let news: [CloudNews]
    @State private var visible = 0
    @State private var start = Date()

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSince(start)
                    CloudPainter(kind: CloudCharacterKind.current, face: .feliz, skin: CloudSkin.resolved(on: tl.date),
                                 t: tl.date.timeIntervalSinceReferenceDate, faceT: t, hopT: t.truncatingRemainder(dividingBy: 1.6),
                                 blinking: false, look: .zero, cold: false, hot: false, raining: false)
                        .draw(in: &ctx, size: size)
                }
            }
            .frame(width: 150, height: 130)
            Text("O que eu aprendi")
                .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(news.enumerated()), id: \.element.id) { i, n in
                        if i < visible {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: n.icon)
                                    .font(.system(size: 16, weight: .semibold)).foregroundColor(Color(hex: "#A78BFA"))
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color(hex: "#8B5CF6").opacity(0.18)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(n.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                    Text(n.detail).font(.system(size: 11.5)).foregroundColor(Color(hex: "#A1A1AA"))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                                                    removal: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(width: 460, height: 600)
        .background(Color(red: 0.055, green: 0.06, blue: 0.075))
        .preferredColorScheme(.dark)
        .onAppear {
            start = Date()
            for i in 0..<news.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + Double(i) * 0.22) {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { visible = i + 1 }
                    SoundEngine.shared.play("pop")
                }
            }
        }
    }
}
#endif

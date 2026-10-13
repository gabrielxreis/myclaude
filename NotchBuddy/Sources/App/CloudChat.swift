#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - Chat history
//
// Every conversation with Cloud (typed in the chat window or spoken with "Ei Cloud") is kept
// on this Mac in ~/Library/Application Support/MyCloud/chats.json. Each one carries the
// Claude Code session id, so going back to an old chat resumes it with its full context.

struct CloudMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, cloud }
    var id = UUID()
    let role: Role
    let text: String
    var date = Date()
    /// Who answered when it wasn't Claude ("ChatGPT").
    var via: String? = nil
}

struct CloudConversation: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var sessionId: String?
    var messages: [CloudMessage] = []
    var updated = Date()
    var fromVoice = false
}

@MainActor
final class CloudChatStore: ObservableObject {
    static let shared = CloudChatStore()

    @Published private(set) var conversations: [CloudConversation] = []
    /// Conversations waiting for Claude's answer.
    @Published private(set) var thinking: Set<UUID> = []
    /// The spoken conversation in progress ("Ei Cloud"), nil once it is forgotten (90 s).
    var voiceConversationId: UUID?
    /// The conversation typed in the notch's chat, until "Nova conversa".
    var notchConversationId: UUID?

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyCloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chats.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let list = try? JSONDecoder().decode([CloudConversation].self, from: data) {
            conversations = list
        }
    }

    func conversation(_ id: UUID) -> CloudConversation? { conversations.first { $0.id == id } }

    @discardableResult
    func newConversation(fromVoice: Bool = false) -> UUID {
        let c = CloudConversation(title: "Nova conversa", fromVoice: fromVoice)
        conversations.insert(c, at: 0)
        save()
        return c.id
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if voiceConversationId == id { voiceConversationId = nil }
        save()
    }

    func isThinking(_ id: UUID) -> Bool { thinking.contains(id) }

    /// Records an exchange Cloud answered itself (a local action), without Claude.
    func record(user: String, cloud: String, in id: UUID) {
        guard let idx = index(id) else { return }
        CloudPet.shared.interacted()
        append(CloudMessage(role: .user, text: user), to: idx)
        if conversations[0].messages.count == 1 { conversations[0].title = Self.title(from: user) }
        append(CloudMessage(role: .cloud, text: cloud), to: 0)
    }

    /// Sends `text` to Claude in conversation `id` and records both sides. nil on failure.
    func send(_ text: String, in id: UUID, voice: Bool) async -> String? {
        guard let idx = index(id) else { return nil }
        if !voice {   // typed "abre o Safari e pesquisa…" too
            let local = CloudLocalActions.process(text)
            if local.rest == nil, !local.replies.isEmpty {
                let reply = local.replies.joined(separator: " ")
                record(user: text, cloud: reply, in: id)
                return reply
            }
        }
        CloudPet.shared.interacted()
        append(CloudMessage(role: .user, text: text), to: idx)
        if conversations[idx].messages.count == 1 { conversations[idx].title = Self.title(from: text) }
        thinking.insert(id)
        defer { thinking.remove(id) }

        // Questions and research: ChatGPT (Codex CLI on the ChatGPT plan), when chosen in Settings.
        if ChatGPTBrain.answersQuestions && ChatGPTBrain.isQuestion(text) {
            let answer = await ChatGPTBrain.ask(text, voice: voice)
                ?? "Não consegui falar com o ChatGPT agora. Confere se o Codex está logado (codex login)."
            if let i = index(id) { append(CloudMessage(role: .cloud, text: answer, via: "ChatGPT"), to: i) }
            return answer
        }

        let session = conversations[idx].sessionId
        guard let reply = await ClaudeCLIBrain.ask(text, sessionId: session, voice: voice) else {
            if let i = index(id) {
                append(CloudMessage(role: .cloud, text: "Não consegui falar com o Claude agora. Tenta de novo em instantes."), to: i)
            }
            return nil
        }
        guard let idx2 = index(id) else { return reply.text }   // deleted while waiting
        if let s = reply.sessionId { conversations[idx2].sessionId = s }
        append(CloudMessage(role: .cloud, text: reply.text), to: idx2)
        CloudQuickActions.shared.reload()   // Cloud may have added a quick action
        return reply.text
    }

    private func index(_ id: UUID) -> Int? { conversations.firstIndex { $0.id == id } }

    private func append(_ m: CloudMessage, to idx: Int) {
        conversations[idx].messages.append(m)
        conversations[idx].updated = m.date
        // Most recent first.
        let c = conversations.remove(at: idx)
        conversations.insert(c, at: 0)
        save()
    }

    private static func title(from text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 48 ? String(t.prefix(48)) + "…" : t
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

// MARK: - Window

@MainActor
final class CloudChatWindow: NSObject, NSWindowDelegate {
    static let shared = CloudChatWindow()
    private var window: NSWindow?
    private let selection = CloudChatSelection()

    /// Opens the chat window on `conversation` (or the most recent one).
    func show(conversation: UUID? = nil, draft: String? = nil) {
        selection.draft = draft
        if let conversation { selection.id = conversation }
        else if selection.id == nil { selection.id = CloudChatStore.shared.conversations.first?.id }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Cloud"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 560, height: 380)
            w.contentView = NSHostingView(rootView: CloudChatView(store: .shared, selection: selection))
            w.center()
            w.setFrameAutosaveName("CloudChatWindow")
            w.delegate = self
            // Opens on the Space I am on, even over a full-screen app.
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class CloudChatSelection: ObservableObject {
    @Published var id: UUID?
    /// Text to pre-fill in the message field (the quick action "+" chip).
    var draft: String?
}

// MARK: - Views

struct CloudChatView: View {
    @ObservedObject var store: CloudChatStore
    @ObservedObject var selection: CloudChatSelection

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
                .background(Color(hex: "#141518"))
            Divider()
            if let id = selection.id, let convo = store.conversation(id) {
                CloudConversationView(store: store, conversation: convo, initialDraft: selection.draft)
                    .id(id)
            } else {
                VStack(spacing: 10) {
                    Text("Nenhuma conversa aberta").foregroundColor(.secondary)
                    Button("Nova conversa") { selection.id = store.newConversation() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(hex: "#1B1C20"))
        .environment(\.colorScheme, .dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Conversas").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { selection.id = store.newConversation() } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("Nova conversa")
            }
            .padding(.horizontal, 14)
            .padding(.top, 34)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.conversations) { c in
                        row(c)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func row(_ c: CloudConversation) -> some View {
        let selected = selection.id == c.id
        return HStack(spacing: 8) {
            Image(systemName: c.fromVoice ? "waveform" : "text.bubble")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(c.updated.formatted(.relative(presentation: .named).locale(Locale(identifier: "pt_BR"))))
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if store.isThinking(c.id) { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.white.opacity(0.09) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selection.id = c.id }
        .contextMenu {
            Button("Apagar conversa", role: .destructive) {
                if selection.id == c.id { selection.id = nil }
                store.delete(c.id)
            }
        }
    }
}

struct CloudConversationView: View {
    @ObservedObject var store: CloudChatStore
    let conversation: CloudConversation
    var initialDraft: String? = nil
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // VStack, not LazyVStack: selectable Text inside a lazy stack renders upside
                    // down on macOS once rows are reused.
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(conversation.messages) { m in
                            bubble(m).id(m.id)
                        }
                        if store.isThinking(conversation.id) {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Cloud está pensando…").font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            .id("thinking")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 40)
                    .padding(.bottom, 12)
                }
                .onAppear { scrollToEnd(proxy, animated: false) }
                .onChange(of: conversation.messages.count) { scrollToEnd(proxy, animated: true) }
                .onChange(of: store.isThinking(conversation.id)) { scrollToEnd(proxy, animated: true) }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Mensagem para o Cloud", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || store.isThinking(conversation.id))
            }
            .padding(12)
        }
        .onAppear {
            if let initialDraft, draft.isEmpty { draft = initialDraft }
            focused = true
        }
    }

    @ViewBuilder private func bubble(_ m: CloudMessage) -> some View {
        if m.role == .user {
            HStack {
                Spacer(minLength: 60)
                Text(m.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#2B2D33")))
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.via.map { "Cloud · \($0)" } ?? "Cloud")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                ChatMarkdownView(markdown: m.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        let target: AnyHashable? = store.isThinking(conversation.id) ? "thinking" : conversation.messages.last?.id
        guard let target else { return }
        if animated { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) } }
        else { proxy.scrollTo(target, anchor: .bottom) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !store.isThinking(conversation.id) else { return }
        draft = ""
        let id = conversation.id
        Task { _ = await store.send(text, in: id, voice: false) }
    }
}
#endif

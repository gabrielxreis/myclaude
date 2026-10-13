#if !APPSTORE
import AppKit

// MARK: - Offloading a camera card
//
// "Cláudio, descarrega o cartão pro SSD": finds the camera card that is mounted, asks what it
// can't guess (camera, SSD, folder) in the same conversation, creates <SSD>/<pasta>/<Câmera>/SDn
// (n = next free number), copies everything in the background whatever screen I'm on, checks
// every file arrived with the same size, and tells me. The card is never modified.

@MainActor
final class CardOffload: ObservableObject {
    static let shared = CardOffload()

    /// What the notch shows while copying ("Sony → SD2: 45%"), nil when idle.
    @Published private(set) var status: String?

    private enum Question { case camera, ssd, folder }
    private(set) var awaiting: Bool = false
    private var question: Question?
    private var card: URL?
    private var camera: String?
    private var ssd: URL?
    private var ssdChoices: [URL] = []
    private var folder: String?
    private var running = false
    // What to do besides copying, from the request.
    private var dual = false          // "nos dois SSDs", "backup duplo"
    private var proxies = false       // "com proxy"
    private var transcribe = false    // "e transcreve"
    private var davinci = false       // "e cria o projeto no DaVinci"

    // MARK: Understanding the request

    static func isRequest(_ text: String) -> Bool {
        let n = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        let card = ["cartao", "cartão", "sd", "memory card"].contains { n.contains($0) }
        let act = ["descarrega", "descarregar", "copia", "copiar", "passa", "passar", "transfere", "backup", "entra no"]
            .contains { n.contains($0) }
        return card && act
    }

    /// Starts the flow from the request; returns what Cloud says (a question or "copiando…").
    func begin(_ text: String) -> String {
        guard !running else { return "Já estou copiando um cartão. Te aviso quando terminar." }
        reset()
        let vols = Self.externalVolumes()
        guard let c = vols.first(where: Self.isCameraCard) else {
            return "Não achei nenhum cartão de câmera conectado. Coloca o cartão e me chama de novo."
        }
        card = c
        var n = Self.norm(text)
        dual = ["dois ssd", "nos dois", "backup duplo", "duplo", "ambos", "2 ssd"].contains { n.contains($0) }
        proxies = n.contains("proxy") || n.contains("proxies")
        transcribe = n.contains("transcre") || n.contains("transcri")
        davinci = n.contains("davinci") || n.contains("da vinci") || n.contains("timeline")
        // "cria o projeto no DaVinci" is not the SSD folder.
        for phrase in ["o projeto no davinci", "projeto no davinci", "o projeto no da vinci", "projeto no da vinci"] {
            n = n.replacingOccurrences(of: phrase, with: "")
        }
        camera = Self.brands.first { n.contains(Self.norm($0)) } ?? Self.detectCamera(c)
        ssdChoices = vols.filter { $0 != c && !Self.isCameraCard($0) }
        ssd = ssdChoices.first { Self.squash(n).contains(Self.squash($0.lastPathComponent)) }
        // One SSD, or a double backup: no need to ask which.
        if ssd == nil && (ssdChoices.count == 1 || (dual && ssdChoices.count >= 2)) { ssd = ssdChoices.first }
        // "…na pasta Clientes", "…no projeto Casamento Ana": the original words, accents kept.
        if let i = n.range(of: "pasta ") ?? n.range(of: "projeto ") {
            var rest = String(n[i.upperBound...])
            for stop in [" no ssd", " nos dois", " e ", " com ", ","] {
                if let r = rest.range(of: stop) { rest = String(rest[..<r.lowerBound]) }
            }
            // Same words with their original capitals and accents.
            let words = rest.split(separator: " ").count
            if let o = Self.originalWords(text, matching: rest) { folder = o } else if words > 0 { folder = Self.folderName(rest.capitalized) }
        }
        return next()
    }

    /// An answer to the last question.
    func answer(_ text: String) -> String {
        let n = Self.norm(text)
        if ["cancela", "cancelar", "deixa", "esquece", "para"].contains(where: { n.hasPrefix($0) }) {
            reset(); return "Beleza, cancelei. O cartão ficou como estava."
        }
        switch question {
        case .camera:
            camera = Self.brands.first { n.contains(Self.norm($0)) } ?? text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).capitalized
        case .ssd:
            let ordinals = ["primeiro", "segundo", "terceiro", "quarto"]
            if ["dois", "ambos", "todos"].contains(where: { n.contains($0) }), ssdChoices.count >= 2 { dual = true; ssd = ssdChoices[0] }
            else if let i = ordinals.firstIndex(where: { n.contains($0) }), i < ssdChoices.count { ssd = ssdChoices[i] }
            else {
                let q = Self.squash(n)
                ssd = ssdChoices.first { let v = Self.squash($0.lastPathComponent); return v.contains(q) || q.contains(v) }
                    ?? ssdChoices.first { q.hasSuffix(String(Self.squash($0.lastPathComponent).suffix(1))) && q.count <= 6 }
            }
            if ssd == nil { return "Não entendi qual. " + ask(.ssd) }
        case .folder:
            if ["raiz", "nenhuma", "nada", "na raiz", "direto"].contains(where: { n.contains($0) }) { folder = "" }
            else if ["sim", "isso", "essa", "mesma", "pode"].contains(where: { n.hasPrefix($0) }), let last = Self.lastFolder { folder = last }
            else { folder = Self.folderName(text) }
        case nil:
            break
        }
        return next()
    }

    private func next() -> String {
        if camera == nil { return ask(.camera) }
        if ssd == nil {
            if ssdChoices.isEmpty { reset(); return "Achei o cartão, mas nenhum SSD conectado. Conecta o SSD e me chama de novo." }
            return ask(.ssd)
        }
        if folder == nil { return ask(.folder) }
        return start()
    }

    private func ask(_ q: Question) -> String {
        question = q; awaiting = true
        switch q {
        case .camera: return "De qual câmera é esse cartão?"
        case .ssd:
            let names = ssdChoices.map(\.lastPathComponent)
            return "Pra qual SSD: \(names.dropLast().joined(separator: ", ")) ou \(names.last ?? "")?"
        case .folder:
            if let last = Self.lastFolder, !last.isEmpty { return "Em qual pasta do \(ssd!.lastPathComponent)? A mesma de antes, \(last)?" }
            return "Em qual pasta do \(ssd!.lastPathComponent)? Pode dizer o nome do projeto, ou raiz."
        }
    }

    private func reset() {
        awaiting = false; question = nil; card = nil; camera = nil; ssd = nil; ssdChoices = []; folder = nil
        dual = false; proxies = false; transcribe = false; davinci = false
    }

    /// The words of `text` that normalise to `wanted` (keeps "Casamento Ana" as spoken).
    static func originalWords(_ text: String, matching wanted: String) -> String? {
        let orig = text.split(separator: " ").map(String.init)
        let want = wanted.split(separator: " ").map(String.init)
        guard !want.isEmpty, orig.count >= want.count else { return nil }
        for i in 0...(orig.count - want.count) {
            let slice = orig[i..<(i + want.count)]
            if slice.map({ norm($0).trimmingCharacters(in: .punctuationCharacters) }) == want {
                return folderName(slice.joined(separator: " "))
            }
        }
        return nil
    }

    // MARK: Copying

    private func start() -> String {
        guard let card, let camera, let ssd, let folder else { reset(); return "Faltou alguma informação, me chama de novo." }
        awaiting = false; question = nil
        // Backup duplo: this SSD plus the next one connected.
        var targets = [ssd]
        if dual, let other = ssdChoices.first(where: { $0 != ssd }) { targets.append(other) }
        let firstDir = Self.cameraDir(ssd, folder, camera)
        var n = 1
        while targets.contains(where: { FileManager.default.fileExists(atPath: Self.cameraDir($0, folder, camera).appendingPathComponent("SD\(n)").path) }) { n += 1 }
        var dests: [URL] = []
        for t in targets {
            let d = Self.cameraDir(t, folder, camera).appendingPathComponent("SD\(n)", isDirectory: true)
            do { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
            catch { reset(); return "Não consegui criar a pasta no \(t.lastPathComponent): \(error.localizedDescription)" }
            dests.append(d)
        }
        _ = firstDir
        Self.lastFolder = folder
        let label = "\(camera) → SD\(n)"
        let shown = dests.map { Self.shortPath($0) }.joined(separator: " e ")
        let job = Job(card: card, dests: dests, label: label, shown: shown, proxies: proxies, transcribe: transcribe,
                      davinci: davinci, project: folder.isEmpty ? "\(camera) SD\(n)" : folder)
        running = true
        status = "Copiando cartão \(label): 0%"
        CloudPet.shared.interacted(xpGain: 10)
        appendAppLog("nb.log", "[Cloud] offload \(card.path) → \(dests.map(\.path))")
        Task { await run(job) }
        let extras = [dual && dests.count < 2 ? "só achei um SSD, então vai só nele" : nil,
                      proxies ? "depois faço os proxies" : nil, transcribe ? "transcrevo" : nil,
                      davinci ? "monto no DaVinci" : nil].compactMap { $0 }
        reset()
        return "Criei \(shown) e comecei a copiar" + (extras.isEmpty ? "" : "; " + extras.joined(separator: ", ")) +
            ". Pode continuar o que estava fazendo, te aviso quando terminar."
    }

    private struct Job {
        let card: URL; let dests: [URL]; let label: String; let shown: String
        let proxies: Bool; let transcribe: Bool; let davinci: Bool; let project: String
    }

    private static func cameraDir(_ ssd: URL, _ folder: String, _ camera: String) -> URL {
        (folder.isEmpty ? ssd : ssd.appendingPathComponent(folder, isDirectory: true)).appendingPathComponent(camera, isDirectory: true)
    }

    private static func shortPath(_ u: URL) -> String {
        u.path.replacingOccurrences(of: "/Volumes/", with: "")
    }

    nonisolated private static let skip: Set<String> = [".Spotlight-V100", ".Trashes", ".fseventsd", ".TemporaryItems", ".DS_Store"]
    nonisolated static let videoExts: Set<String> = ["mp4", "mov", "mxf", "mts", "m2ts", "avi", "mkv", "insv", "lrv"]

    private func run(_ job: Job) async {
        let files = Self.files(in: job.card)
        let total = max(1, files.reduce(0) { $0 + $1.size })
        // Progress: the slowest destination, every second.
        let progress = Task { @MainActor in
            while !Task.isCancelled {
                let done = job.dests.map { Self.files(in: $0).reduce(0) { $0 + $1.size } }.min() ?? 0
                status = "Copiando cartão \(job.label): \(min(99, Int(Double(done) / Double(total) * 100)))%"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        // Every destination at the same time.
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for d in job.dests { group.addTask { Self.rsync(job.card, d) } }
            var r: [Bool] = []
            for await ok in group { r.append(ok) }
            return r
        }
        progress.cancel()

        // Every file in every copy, same size.
        var problems: [String] = []
        for d in job.dests {
            let copied = Dictionary(Self.files(in: d).map { ($0.rel, $0.size) }, uniquingKeysWith: { a, _ in a })
            let missing = files.filter { copied[$0.rel] != $0.size }.count
            if missing > 0 { problems.append("\(missing) arquivos não conferem em \(Self.shortPath(d))") }
        }
        let ok = results.allSatisfy { $0 } && problems.isEmpty
        let gb = String(format: "%.1f", Double(total) / 1_000_000_000)
        var message = ok
            ? "Copiei \(files.count) \(files.count == 1 ? "arquivo" : "arquivos") (\(gb) GB) do cartão para \(job.shown), tudo conferido."
            : "A cópia terminou com problema: \(problems.joined(separator: "; ")). O cartão não foi mexido, dá para tentar de novo."
        appendAppLog("nb.log", "[Cloud] offload done ok=\(ok) \(problems)")

        if ok, let main = job.dests.first {
            let videos = Self.files(in: main).filter { Self.videoExts.contains(($0.rel as NSString).pathExtension.lowercased()) }
                .map { main.appendingPathComponent($0.rel) }
            if job.proxies && !videos.isEmpty { message += " " + (await makeProxies(videos, in: main)) }
            if job.transcribe && !videos.isEmpty { message += " " + (await transcribeAll(videos, in: main)) }
            if job.davinci { message += " " + (await buildInDaVinci(job, main)) }
        }
        SoundEngine.shared.play(ok ? "finish" : "error")
        if ok { CloudPet.shared.taskFinished() }
        status = nil
        running = false
        Self.notify(message)
        if let id = CloudChatStore.shared.voiceConversationId ?? CloudChatStore.shared.conversations.first?.id {
            CloudChatStore.shared.record(user: "(cartão \(job.label))", cloud: message, in: id)
        }
    }

    nonisolated private static func rsync(_ src: URL, _ dest: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        p.arguments = ["-a"] + skip.map { "--exclude=\($0)" } + ["--exclude=._*", src.path + "/", dest.path + "/"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    // MARK: After the copy

    nonisolated static var ffmpeg: String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 720p H.264 proxies (hardware encoder) in SDn/Proxy, same names.
    private func makeProxies(_ videos: [URL], in root: URL) async -> String {
        guard let ff = Self.ffmpeg else { return "Não fiz os proxies: falta o ffmpeg (a /ogab instala)." }
        let dir = root.appendingPathComponent("Proxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var done = 0
        for (i, v) in videos.enumerated() {
            status = "Gerando proxies \(i + 1)/\(videos.count)"
            let out = dir.appendingPathComponent(v.deletingPathExtension().lastPathComponent + "_proxy.mp4")
            let ok = await Self.runTool(ff, ["-y", "-loglevel", "error", "-i", v.path, "-vf", "scale=-2:720",
                                            "-c:v", "h264_videotoolbox", "-b:v", "6M", "-c:a", "aac", "-b:a", "128k", out.path])
            if ok { done += 1 }
        }
        return "Proxies prontos: \(done) de \(videos.count) em \(Self.shortPath(dir))."
    }

    /// Transcription on this Mac (Apple's on-device recognizer, pt-BR): SDn/Transcricoes/<clip>.txt.
    private func transcribeAll(_ videos: [URL], in root: URL) async -> String {
        guard let ff = Self.ffmpeg else { return "Não transcrevi: falta o ffmpeg." }
        let dir = root.appendingPathComponent("Transcricoes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var done = 0
        for (i, v) in videos.enumerated() {
            status = "Transcrevendo \(i + 1)/\(videos.count)"
            let wav = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: wav) }
            guard await Self.runTool(ff, ["-y", "-loglevel", "error", "-i", v.path, "-vn", "-ac", "1", "-ar", "16000", wav.path]) else { continue }
            var text = await Self.whisper(wav)
            if text == nil { text = await FileTranscriber.transcribe(wav) }
            if let text, !text.isEmpty {
                try? text.write(to: dir.appendingPathComponent(v.deletingPathExtension().lastPathComponent + ".txt"), atomically: true, encoding: .utf8)
                done += 1
            }
        }
        return "Transcrições: \(done) de \(videos.count) em \(Self.shortPath(dir))."
    }

    /// The /ogab builds the DaVinci project and timeline from the copied files.
    private func buildInDaVinci(_ job: Job, _ main: URL) async -> String {
        status = "Montando no DaVinci…"
        let prompt = """
        /ogab Cria (ou abre, se já existir) o projeto "\(job.project)" no DaVinci Resolve, importa para o Media Pool \
        todos os vídeos de "\(main.path)" (sem a pasta Proxy) e monta uma timeline com os clipes em ordem de \
        gravação. No fim responda em uma frase curta o que foi feito.
        """
        guard let r = await ClaudeCLIBrain.ask(prompt, sessionId: nil, voice: false) else {
            return "Não consegui montar no DaVinci agora (o DaVinci precisa estar aberto)."
        }
        return r.text
    }

    /// The Python that has the Whisper (the one the terminal uses, python.org's, comes first).
    private static var cachedPython: String??
    private static func whisperPython() async -> String? {
        if let c = cachedPython { return c }
        let candidates = ["/Library/Frameworks/Python.framework/Versions/Current/bin/python3", "/usr/local/bin/python3",
                          "/opt/homebrew/bin/python3", "/usr/bin/python3"].filter { FileManager.default.isExecutableFile(atPath: $0) }
        for c in candidates {
            var ok = await runTool(c, ["-c", "import mlx_whisper"])
            if !ok { ok = await runTool(c, ["-c", "import faster_whisper"]) }
            if ok { cachedPython = .some(c); return c }
        }
        cachedPython = .some(nil); return nil
    }

    /// Local Whisper through the /ogab's transcriber (free, on this Mac); nil when not available.
    private static func whisper(_ wav: URL) async -> String? {
        let script = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/ogab/scripts/transcrever.py")
        guard FileManager.default.fileExists(atPath: script.path),
              let py = await whisperPython() else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: out) }
        guard await runTool(py, [script.path, wav.path, out.path, "--motor", "whisper", "--idioma", "pt"]),
              let data = try? Data(contentsOf: out),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segs = json["segments"] as? [[String: Any]] else { return nil }
        return segs.compactMap { ($0["text"] as? String)?.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    nonisolated private static func runTool(_ path: String, _ args: [String]) async -> Bool {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path); p.arguments = args
            // A GUI app has no shell PATH: the tools (and the /ogab's scripts) need it.
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = "/Library/Frameworks/Python.framework/Versions/Current/bin:/usr/local/bin:/opt/homebrew/bin:\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            p.environment = env
            let err = Pipe()
            p.standardOutput = FileHandle.nullDevice; p.standardError = err
            do { try p.run() } catch { appendAppLog("nb.log", "[Cloud] tool \(path) failed to start: \(error)"); return false }
            let data = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let tail = String(decoding: data.suffix(600), as: UTF8.self)
                appendAppLog("nb.log", "[Cloud] tool \((path as NSString).lastPathComponent) exit \(p.terminationStatus): \(tail)")
            }
            return p.terminationStatus == 0
        }.value
    }


    private static func notify(_ text: String) {
        let esc = text.replacingOccurrences(of: "\"", with: "'")
        NSAppleScript(source: "display notification \"\(esc)\" with title \"My Cloud\" sound name \"Glass\"")?.executeAndReturnError(nil)
    }

    // MARK: Volumes and cameras

    nonisolated static func files(in root: URL) -> [(rel: String, size: Int)] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                      options: [], errorHandler: nil) else { return [] }
        var out: [(String, Int)] = []
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let u as URL in en {
            let name = u.lastPathComponent
            if skip.contains(name) { en.skipDescendants(); continue }
            if name.hasPrefix("._") { continue }
            guard let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
            out.append((String(u.path.dropFirst(base.count)), v.fileSize ?? 0))
        }
        return out
    }

    static func externalVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsRootFileSystemKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .filter { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                return v?.volumeIsRootFileSystem != true && v?.volumeIsInternal != true && u.path.hasPrefix("/Volumes/")
            }
    }

    static func isCameraCard(_ v: URL) -> Bool {
        let fm = FileManager.default
        return ["DCIM", "PRIVATE/M4ROOT", "PRIVATE/AVCHD", "XDROOT", "CLIP", "CONTENTS"].contains {
            fm.fileExists(atPath: v.appendingPathComponent($0).path)
        }
    }

    static let brands = ["Sony", "Canon", "Nikon", "Panasonic", "Fujifilm", "GoPro", "DJI", "Blackmagic", "Insta360", "iPhone"]

    static func detectCamera(_ v: URL) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: v.appendingPathComponent("PRIVATE/M4ROOT").path) || fm.fileExists(atPath: v.appendingPathComponent("XDROOT").path) { return "Sony" }
        let dcim = (try? fm.contentsOfDirectory(atPath: v.appendingPathComponent("DCIM").path)) ?? []
        let joined = dcim.joined(separator: " ").uppercased()
        if joined.contains("CANON") { return "Canon" }
        if joined.contains("NIKON") || joined.contains("NCZ") { return "Nikon" }
        if joined.contains("GOPRO") { return "GoPro" }
        if joined.contains("PANA") { return "Panasonic" }
        if joined.contains("FUJI") { return "Fujifilm" }
        if joined.contains("MEDIA") || joined.contains("DJI") { return "DJI" }
        if joined.contains("MSDCF") { return "Sony" }
        return nil
    }

    static var lastFolder: String? {
        get { UserDefaults.standard.string(forKey: "cardOffloadLastFolder") }
        set { UserDefaults.standard.set(newValue, forKey: "cardOffloadLastFolder") }
    }

    /// "projeto Teste Cloud", "na pasta Clientes" → "Teste Cloud", "Clientes".
    static func folderName(_ text: String) -> String {
        var words = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(separator: " ").map(String.init)
        let filler: Set<String> = ["na", "no", "em", "a", "o", "pasta", "projeto", "do", "da", "dentro", "de"]
        while let f = words.first, filler.contains(norm(f)), words.count > 1 { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// Letters and digits only: "SSD_A" = "ssd a" = "ssda".
    static func squash(_ s: String) -> String {
        String(norm(s).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func norm(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }
}
#endif

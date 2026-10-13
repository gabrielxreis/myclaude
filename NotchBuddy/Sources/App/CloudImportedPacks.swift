import AppKit

// MARK: - Imported characters
//
// ~/Library/Application Support/MyCloud/personagens/<pack>/ with one PNG per mood: parado.png
// (required), ouvindo, feliz, pensando, falando, focado, sono, carente, surpreso, tonto; optional
// personagem.json {"nome", "autor"}. They stay on this Mac (never in the code, the repository or the
// updates); the app animates them (breathing, hop, tilt, squash) and draws the mood effects.

enum CloudImportedPacks {
    static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyCloud/personagens", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    struct Pack: Identifiable, Hashable { let id: String; let name: String; let url: URL }

    static func all() -> [Pack] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("parado.png").path) }
            .map { u in
                let meta = (try? Data(contentsOf: u.appendingPathComponent("personagem.json")))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                return Pack(id: u.lastPathComponent, name: meta?["nome"] as? String ?? u.lastPathComponent, url: u)
            }
            .sorted { $0.name < $1.name }
    }

    static var selectedID: String? {
        get { UserDefaults.standard.string(forKey: "cloudImportedPack") ?? all().first?.id }
        set { UserDefaults.standard.set(newValue, forKey: "cloudImportedPack"); cache.removeAll() }
    }

    static var selectedName: String? { all().first { $0.id == selectedID }?.name }

    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]

    /// The first image that exists among `names`, for the selected pack (cached).
    static func image(_ names: [String]) -> NSImage? {
        guard let id = selectedID else { return nil }
        for n in names {
            let key = id + "/" + n
            if let img = cache[key] { return img }
            let url = folder.appendingPathComponent(id).appendingPathComponent(n + ".png")
            if let img = NSImage(contentsOf: url) { cache[key] = img; return img }
        }
        return nil
    }

    /// Copies a folder of PNGs (parado.png at least) into the characters folder.
    @discardableResult
    static func importFolder(_ src: URL) -> String? {
        guard FileManager.default.fileExists(atPath: src.appendingPathComponent("parado.png").path) else {
            return "A pasta precisa ter pelo menos parado.png (e se quiser: ouvindo, feliz, pensando, sono...)."
        }
        let dest = folder.appendingPathComponent(src.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: src, to: dest) } catch { return error.localizedDescription }
        selectedID = dest.lastPathComponent
        return nil
    }
}

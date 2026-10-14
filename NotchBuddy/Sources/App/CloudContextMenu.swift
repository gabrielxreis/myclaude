#if !APPSTORE
import AppKit

// MARK: - Right click on the character
//
// A menu at the pointer to change the skin and the character without opening Settings:
// Skins (with the current one checked), Personagem, the imported characters, and a shortcut
// to Settings. Mochi keeps Coucou's wardrobe.

@MainActor
final class CloudContextMenu: NSObject {
    static let shared = CloudContextMenu()

    func show() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let skinTitle = NSMenuItem(title: "Skin", action: nil, keyEquivalent: "")
        skinTitle.isEnabled = false
        menu.addItem(skinTitle)
        for s in CloudSkin.pickable {
            let item = NSMenuItem(title: s.title, action: #selector(pickSkin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.rawValue
            item.state = CloudSkin.chosen == s ? .on : .off
            item.isEnabled = CloudCharacterKind.current != .mochi
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let charItem = NSMenuItem(title: "Personagem", action: nil, keyEquivalent: "")
        let charMenu = NSMenu()
        for k in CloudCharacterKind.available where k != .importado {
            let item = NSMenuItem(title: k.title, action: #selector(pickCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = k.rawValue
            item.state = CloudCharacterKind.current == k ? .on : .off
            charMenu.addItem(item)
        }
        let packs = CloudImportedPacks.all()
        if !packs.isEmpty {
            charMenu.addItem(.separator())
            for p in packs {
                let item = NSMenuItem(title: p.name, action: #selector(pickPack(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.id
                item.state = CloudCharacterKind.current == .importado && CloudImportedPacks.selectedID == p.id ? .on : .off
                charMenu.addItem(item)
            }
        }
        charItem.submenu = charMenu
        menu.addItem(charItem)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        SoundEngine.shared.play("pop")
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func pickSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        appendAppLog("nb.log", "[Cloud] menu skin \(raw)")
        UserDefaults.standard.set(raw, forKey: "cloudSkin")
        if raw == CloudSkin.auto.rawValue { CloudWeather.shared.refresh(force: true) }
        poke()
    }

    @objc private func pickCharacter(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: "cloudCharacter")
        SoundEngine.shared.reload()
        poke()
    }

    @objc private func pickPack(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        CloudImportedPacks.selectedID = id
        UserDefaults.standard.set(CloudCharacterKind.importado.rawValue, forKey: "cloudCharacter")
        poke()
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openFullSettings, object: "personagem")
    }

    /// The new look greets with a little hop.
    private func poke() {
        NotificationCenter.default.post(name: .cloudPoke, object: nil)
    }
}

extension Notification.Name {
    /// A click on the character (notch or desktop): it reacts.
    static let cloudPoke = Notification.Name("myCloud.poke")
}
#endif

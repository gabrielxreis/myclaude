import Foundation

// MARK: - From Coucou's identity to My Cloud's
//
// My Cloud has its own bundle id (com.gabrielreis.mycloud). The first launch copies the
// settings saved under the old one (fr.louisraille.NotchBuddy), before anything reads them.
// Files (chats, quick actions, hooks, logs) live in Application Support and don't move.

enum MyCloudMigration {
    static let oldDomain = "fr.louisraille.NotchBuddy"

    static func run() {
        let d = UserDefaults.standard
        if !d.bool(forKey: "myCloudMigratedFromCoucou"),
           Bundle.main.bundleIdentifier != oldDomain,
           let old = d.persistentDomain(forName: oldDomain), !old.isEmpty {
            for (k, v) in old where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        }
        d.set(true, forKey: "myCloudMigratedFromCoucou")
        // Bolinho is My Cloud's own character: it replaces Mochi once (Mochi stays pickable
        // in the personal build).
        if !d.bool(forKey: "myCloudBolinhoDefault") {
            if (d.string(forKey: "cloudCharacter") ?? "mochi") == "mochi" { d.set("bolinho", forKey: "cloudCharacter") }
            d.set(true, forKey: "myCloudBolinhoDefault")
        }
    }
}

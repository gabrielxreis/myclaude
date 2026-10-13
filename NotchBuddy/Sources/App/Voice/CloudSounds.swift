#if !APPSTORE
import AppKit

// MARK: - Listening sounds
//
// A short "tink" when Cloud starts listening and a "pop" when it stops, so I know the mic is
// open without looking. macOS system sounds (Coucou's own sounds can't ship with My Cloud).
// Settings → Voz → "Sons ao ouvir".

enum CloudSounds {
    enum Cue { case started, stopped }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "cloudListenSounds") as? Bool ?? true
    }

    static func play(_ cue: Cue) {
        guard enabled else { return }
        let name = cue == .started ? "Tink" : "Pop"
        let s = NSSound(named: NSSound.Name(name))
        s?.volume = 0.5
        s?.play()
    }
}
#endif

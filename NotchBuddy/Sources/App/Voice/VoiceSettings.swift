#if !APPSTORE
import AVFoundation
import Speech

// MARK: - VoiceSettings

/// Persisted voice feature settings and permission helpers.
enum VoiceSettings {
    static let enabledKey      = "voiceEnabled"
    static let speakEnabledKey = "voiceSpeakEnabled"
    static let captionEnabledKey = "voiceCaptionEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Coucou responds aloud after each command. Default: on.
    /// Cloud answers out loud only when a voice is chosen; "Só texto" (the default) shows
    /// the answer in the notch and stays silent.
    static var speakEnabled: Bool {
        get { ttsEngine != "off" }
        set { if !newValue { ttsEngine = "off" } else if ttsEngine == "off" { ttsEngine = "system" } }
    }

    /// Show caption capsule below notch during voice. Default: on.
    static var captionEnabled: Bool {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: captionEnabledKey) == nil { return true }  // default on
            return d.bool(forKey: captionEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: captionEnabledKey) }
    }

    /// Names Cloud answers to after "Ei/Oi/OK/Hey", comma-separated (Settings → Voz → Nome).
    static var wakeNames: String {
        get { UserDefaults.standard.string(forKey: "voiceWakeNames") ?? WakePhrase.defaultNames }
        set {
            UserDefaults.standard.set(newValue, forKey: "voiceWakeNames")
            WakePhrase.names = WakePhrase.parseNames(newValue)
        }
    }

    /// What Cloud may do with Claude (the quick local actions always work):
    /// "consultar" read and search only · "lista" (default) only the rules in `allowedRules` ·
    /// "automatico" Claude Code's auto permission mode, which the user turns on themselves.
    static var executionMode: String {
        get {
            let v = UserDefaults.standard.string(forKey: "cloudExecutionMode") ?? "lista"
            return ["consultar", "lista", "automatico"].contains(v) ? v : "lista"
        }
        set { UserDefaults.standard.set(newValue, forKey: "cloudExecutionMode") }
    }

    /// Claude Code permission rules Cloud may use in "lista" mode, one per line.
    static var allowedRules: [String] {
        get {
            let text = UserDefaults.standard.string(forKey: "cloudAllowedRules") ?? defaultAllowedRules
            return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
    }
    static var allowedRulesText: String {
        get { UserDefaults.standard.string(forKey: "cloudAllowedRules") ?? defaultAllowedRules }
        set { UserDefaults.standard.set(newValue, forKey: "cloudAllowedRules") }
    }
    static var defaultAllowedRules: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return """
        # Ler e pesquisar
        Read
        Glob
        Grep
        WebSearch
        WebFetch
        # Usar skills (a /ogab e as outras)
        Skill
        # Abrir apps, arquivos, pastas e sites
        Bash(open:*)
        # Scripts da /ogab
        Bash(python3 \(home)/.claude/skills/ogab:*)
        Bash(bash \(home)/.claude/skills/ogab:*)
        # Atalhos rápidos do Cloud
        Edit(~/Library/Application Support/MyCloud/acoes-rapidas.json)
        Write(~/Library/Application Support/MyCloud/acoes-rapidas.json)
        """
    }

    /// Language Cloud ANSWERS in: "pt" (default), "en" or "fr".
    static var language: String {
        get { UserDefaults.standard.string(forKey: "voiceLanguage") ?? "pt" }
        set { UserDefaults.standard.set(newValue, forKey: "voiceLanguage") }
    }
    static var answerLocale: Locale {
        switch language {
        case "fr": Locale(identifier: "fr-FR")
        case "en": Locale(identifier: "en-US")
        default:   Locale(identifier: "pt-BR")
        }
    }

    /// Language Cloud LISTENS to: "auto" (the Mac's dictation language, default), "pt", "en" or "fr".
    /// Independent from the answer language: speak French, hear English.
    static var listenLanguage: String {
        get { UserDefaults.standard.string(forKey: "voiceListenLanguage") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "voiceListenLanguage") }
    }

    /// Coucou already offered to answer in the language you speak (asked once).
    static var languageOfferDone: Bool {
        get { UserDefaults.standard.bool(forKey: "voiceLanguageOfferDone") }
        set { UserDefaults.standard.set(newValue, forKey: "voiceLanguageOfferDone") }
    }

    /// Voice used to answer: "system" (macOS voices) or "elevenlabs" (user's API key).
    static var ttsEngine: String {
        get { UserDefaults.standard.string(forKey: "voiceTTSEngine") ?? "off" }
        set { UserDefaults.standard.set(newValue, forKey: "voiceTTSEngine") }
    }
    /// ElevenLabs voice: "female" (default) or "male".
    static var elevenGender: String {
        get { UserDefaults.standard.string(forKey: "voiceElevenGender") ?? "female" }
        set { UserDefaults.standard.set(newValue, forKey: "voiceElevenGender") }
    }

    /// Mac voice pitch per voice type (Settings → Voice). The male default is higher than
    /// the voice's own, so it sounds younger. Range 0.8–1.6 (AVSpeech accepts 0.5–2).
    static let defaultPitchFemale = 1.1
    static let defaultPitchMale   = 1.25
    static func pitchKey(for gender: String) -> String { gender == "male" ? "voicePitchMale" : "voicePitchFemale" }
    static func pitch(for gender: String) -> Double {
        let v = UserDefaults.standard.double(forKey: pitchKey(for: gender))
        let fallback = gender == "male" ? defaultPitchMale : defaultPitchFemale
        return v == 0 ? fallback : min(1.6, max(0.8, v))
    }

    /// Claude is Coucou's brain (the user's Anthropic API key): what I say after
    /// "OK Coucou" goes to Claude, which acts with Coucou's tools and searches the web.
    /// Off by default: my words leave the Mac only once this is turned on.
    static var claudeBrainEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "voiceClaudeBrain") }
        set { UserDefaults.standard.set(newValue, forKey: "voiceClaudeBrain") }
    }
    /// The older web-search-only path follows the same switch.
    static var webSearchEnabled: Bool { claudeBrainEnabled }

    /// Weather by voice (Open-Meteo, no key). Off by default: network only when the user
    /// turned it on and set a city.
    static var weatherEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "voiceWeatherEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "voiceWeatherEnabled") }
    }
    static var weatherCity: String {
        get { UserDefaults.standard.string(forKey: "voiceWeatherCity") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "voiceWeatherCity") }
    }

    // MARK: - Permissions

    enum PermissionStatus { case granted, denied, undetermined }

    static var micStatus: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:              return .granted
        case .denied, .restricted:     return .denied
        case .notDetermined:           return .undetermined
        @unknown default:              return .undetermined
        }
    }

    static var speechStatus: PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:              return .granted
        case .denied, .restricted:     return .denied
        case .notDetermined:           return .undetermined
        @unknown default:              return .undetermined
        }
    }

    /// Request microphone then speech recognition. Returns true if both granted.
    @MainActor
    static func requestPermissions() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { return false }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }
}
#endif

import AVFoundation

/// Ein vorlesbarer Text samt Sprache (BCP-47, z. B. "fr-FR").
struct SpeechText: Hashable {
    let text: String
    let language: String
}

/// Sprachausgabe der App: Prüfungs-/Hörverstehen-Audio und die
/// Lautsprecher-Buttons in Übungen und Vokabeltraining — Stimme der
/// jeweiligen Lernsprache (fr-FR bzw. de-DE), funktioniert offline.
/// Die Stimme ist pro Sprache in den Einstellungen wählbar; ohne Auswahl
/// nimmt die App die beste installierte Stimme.
/// @unchecked Sendable: wird nur vom Main Thread benutzt (UI-Callbacks).
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Liest den Text vor; auf A1/A2 etwas langsamer (wie im Prüfungs-Audio).
    func speak(_ text: String, level: CEFRLevel, language: String = "fr-FR", onFinish: (() -> Void)? = nil) {
        stop()
        self.onFinish = onFinish

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language)
        utterance.rate = level <= .a2 ? 0.42 : 0.48
        utterance.preUtteranceDelay = 0.3
        synthesizer.speak(utterance)
    }

    func speak(_ speech: SpeechText, level: CEFRLevel = .a2, onFinish: (() -> Void)? = nil) {
        speak(speech.text, level: level, language: speech.language, onFinish: onFinish)
    }

    func stop() {
        if synthesizer.isSpeaking {
            // Löst didCancel aus — das ruft den offenen onFinish-Callback auf,
            // damit kein Abspiel-Button im "Läuft …"-Zustand hängen bleibt.
            synthesizer.stopSpeaking(at: .immediate)
        }
        onFinish?()
        onFinish = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
        onFinish = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish?()
        onFinish = nil
    }

    // MARK: - Stimmenwahl

    /// UserDefaults-Schlüssel der gewählten Stimme, pro Sprache ("voice.fr").
    static func voiceDefaultsKey(for language: String) -> String {
        "voice.\(String(language.prefix(2)))"
    }

    /// Alle installierten Stimmen der Sprache, beste Qualität zuerst.
    static func availableVoices(for language: String) -> [AVSpeechSynthesisVoice] {
        let prefix = String(language.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted {
                if $0.quality != $1.quality { return rank($0.quality) > rank($1.quality) }
                // Exakte Region (fr-FR) vor Varianten (fr-CA).
                if ($0.language == language) != ($1.language == language) {
                    return $0.language == language
                }
                return $0.name < $1.name
            }
    }

    static func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String? {
        switch voice.quality {
        case .premium: return String(localized: "Premium")
        case .enhanced: return String(localized: "Hohe Qualität")
        default: return nil
        }
    }

    /// In den Einstellungen gewählte Stimme — nil heißt „Automatisch".
    static func selectedVoiceID(for language: String) -> String? {
        let id = UserDefaults.standard.string(forKey: voiceDefaultsKey(for: language))
        return (id?.isEmpty == false) ? id : nil
    }

    /// Gewählte Stimme, falls (noch) installiert; sonst die beste verfügbare.
    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if let id = selectedVoiceID(for: language),
           let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }
        return availableVoices(for: language).first
            ?? AVSpeechSynthesisVoice(language: language)
    }

    private static func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }
}

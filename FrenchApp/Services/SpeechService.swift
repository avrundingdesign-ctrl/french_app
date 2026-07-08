import AVFoundation

/// Französische Sprachausgabe für das Hörverstehen der Niveau-Prüfungen.
/// Nutzt die System-TTS-Stimme (fr-FR) — funktioniert offline.
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

    /// Liest den Text vor; auf A1/A2 etwas langsamer (wie im DELF-Audio).
    func speak(_ text: String, level: CEFRLevel, onFinish: (() -> Void)? = nil) {
        stop()
        self.onFinish = onFinish

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = level <= .a2 ? 0.42 : 0.48
        utterance.preUtteranceDelay = 0.3
        synthesizer.speak(utterance)
    }

    func stop() {
        onFinish = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
        onFinish = nil
    }
}

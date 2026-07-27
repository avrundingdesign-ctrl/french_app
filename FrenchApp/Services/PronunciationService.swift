import AVFoundation
import Foundation
import Observation
import Speech

/// Nimmt eine Sprechübung auf und wandelt sie per Spracherkennung in Text um
/// (fr-FR bzw. de-DE). Läuft wenn möglich komplett auf dem Gerät; das Zielwort
/// wird der Erkennung als Kontext mitgegeben, damit sie fair vergleicht.
/// Die Bewertung selbst macht der PronunciationScorer.
@MainActor
@Observable
final class PronunciationService {
    enum Status: Equatable {
        case idle
        case recording
        case processing
        /// Mikrofon- oder Erkennungs-Berechtigung fehlt.
        case denied
        /// Spracherkennung für diese Sprache nicht verfügbar.
        case unavailable
    }

    private(set) var status: Status = .idle
    /// Bester bisher erkannter Text (live während der Aufnahme).
    private(set) var transcript = ""

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Wird mit dem finalen Transkript aufgelöst (oder dem letzten Zwischenstand).
    private var finish: ((String) -> Void)?
    /// Notbremse für `stopRecording`, falls die Erkennung kein Endergebnis
    /// liefert. Muss beim Auflösen gecancelt werden — sonst schlägt sie
    /// verspätet zu und bricht die inzwischen gestartete nächste Aufnahme ab.
    private var fallbackTask: Task<Void, Never>?

    /// Fragt Spracherkennungs- und Mikrofon-Berechtigung an.
    func requestAccess() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            status = .denied
            return false
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        if !micGranted { status = .denied }
        return micGranted
    }

    /// Ist die Erkennung für die Sprache grundsätzlich da (Gerät + iOS)?
    static func supportsRecognition(language: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: language)) != nil
    }

    /// Startet die Aufnahme. `target` fließt als Kontext in die Erkennung ein.
    func startRecording(language: String, target: String) {
        guard status == .idle || status == .denied else { return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable
        else {
            status = .unavailable
            return
        }

        transcript = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            status = .unavailable
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = [target]
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            status = .unavailable
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            status = .unavailable
            return
        }

        status = .recording

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.resolve()
                    }
                }
                if error != nil {
                    self.resolve()
                }
            }
        }
    }

    /// Beendet die Aufnahme; `completion` bekommt das (finale) Transkript.
    /// Wartet kurz auf das Endergebnis der Erkennung, fällt sonst auf den
    /// letzten Zwischenstand zurück.
    func stopRecording(completion: @escaping (String) -> Void) {
        guard status == .recording else { return }
        status = .processing
        finish = completion

        stopAudio()
        recognitionRequest?.endAudio()

        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            // `try?` schluckt den Abbruch der Sleep — ohne diese Prüfung liefe
            // resolve() auch für eine längst abgelöste Aufnahme weiter.
            guard !Task.isCancelled else { return }
            self?.resolve()
        }
    }

    /// Bricht ohne Ergebnis ab (View verschwindet, nächste Aufgabe).
    func cancel() {
        finish = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        stopAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        status = .idle
    }

    private func resolve() {
        fallbackTask?.cancel()
        fallbackTask = nil
        guard let finish else {
            // Kein Stop unterwegs (z. B. Erkennungsfehler mitten in der
            // Aufnahme): Zustand aufräumen.
            if status == .recording || status == .processing { cancel() }
            return
        }
        self.finish = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopAudio()
        status = .idle
        finish(transcript)
    }

    private func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

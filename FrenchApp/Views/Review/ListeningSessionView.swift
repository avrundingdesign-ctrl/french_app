import SwiftUI

/// Hörtraining-Session: Dictée, Hör-Lückentext oder Minimal-Paare.
/// Übungsmodus, kein Prüfungsdruck — Audio darf beliebig oft abgespielt
/// werden und startet pro Aufgabe einmal automatisch.
struct ListeningSessionView: View {
    let mode: ListeningTrainer.Mode
    let level: CEFRLevel

    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [ListeningTrainer.Exercise] = []
    @State private var built = false
    @State private var index = 0
    @State private var feedback: LessonSession.Feedback?
    @State private var correctCount = 0
    @State private var isPlaying = false

    private static let exerciseCount = 8

    private var current: ListeningTrainer.Exercise? {
        exercises.indices.contains(index) ? exercises[index] : nil
    }

    var body: some View {
        Group {
            if let exercise = current {
                activeView(exercise)
            } else if built {
                finishedView
            }
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        .onAppear(perform: build)
        .onDisappear { SpeechService.shared.stop() }
    }

    private func build() {
        guard !built else { return }
        built = true
        let trainer = ListeningTrainer()
        exercises = trainer.exercises(mode: mode, upTo: level, count: Self.exerciseCount)
    }

    // MARK: - Aktive Übung

    private func activeView(_ exercise: ListeningTrainer.Exercise) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    playCard(exercise)
                    exerciseView(exercise)
                        .id(exercise.id)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            if let feedback {
                FeedbackBanner(feedback: feedback) {
                    advance()
                }
            }
        }
        .task(id: exercise.id) {
            // Jede Aufgabe startet einmal automatisch.
            play(exercise)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                SpeechService.shared.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: exercises.isEmpty ? 0 : Double(index) / Double(exercises.count))
                .tint(Theme.accent)
            Text("\(index + 1)/\(exercises.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func playCard(_ exercise: ListeningTrainer.Exercise) -> some View {
        HStack(spacing: 14) {
            Button {
                play(exercise)
            } label: {
                Image(systemName: isPlaying ? "speaker.wave.3.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: isPlaying)
            }
            .buttonStyle(.plain)
            .disabled(isPlaying)

            VStack(alignment: .leading, spacing: 3) {
                Text(isPlaying ? "Läuft …" : "Nochmal anhören")
                    .font(.subheadline.weight(.semibold))
                Text("Beliebig oft abspielbar — das ist Training, keine Prüfung.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func play(_ exercise: ListeningTrainer.Exercise) {
        guard !isPlaying else { return }
        isPlaying = true
        SpeechService.shared.speak(exercise.audio, level: level) {
            isPlaying = false
        }
    }

    @ViewBuilder
    private func exerciseView(_ exercise: ListeningTrainer.Exercise) -> some View {
        switch exercise.kind {
        case .multipleChoice(let mc):
            MCExerciseView(exercise: mc) { record($0, for: exercise) }
        case .textInput(let input):
            TextInputExerciseView(exercise: input) { record($0, for: exercise) }
        case .matching, .wordOrder:
            EmptyView()
        }
    }

    private func record(_ outcome: AnswerOutcome, for exercise: ListeningTrainer.Exercise) {
        guard feedback == nil else { return }
        if outcome.correct { correctCount += 1 }

        let correctAnswer: String
        let explanation: String?
        switch exercise.kind {
        case .multipleChoice(let mc):
            correctAnswer = mc.correctAnswer
            explanation = mc.explanation
        case .textInput(let input):
            correctAnswer = input.fullSolution
            explanation = exercise.translation
        case .matching, .wordOrder:
            correctAnswer = ""
            explanation = nil
        }
        feedback = LessonSession.Feedback(
            correct: outcome.correct,
            accentHint: outcome.accentHint,
            correctAnswer: correctAnswer,
            explanation: explanation
        )
    }

    private func advance() {
        SpeechService.shared.stop()
        feedback = nil
        withAnimation { index += 1 }
    }

    // MARK: - Abschluss

    private var finishedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: exercises.isEmpty ? "moon.zzz.fill" : "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(exercises.isEmpty ? Theme.accent : Theme.success)
            Text(exercises.isEmpty ? "Noch kein Material" : "Hörtraining beendet!")
                .font(.title2.bold())
            Text(exercises.isEmpty
                 ? "Für dieses Niveau gibt es noch keine Sätze."
                 : "\(correctCount) von \(exercises.count) richtig — dein Ohr wird immer schärfer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                dismiss()
            } label: {
                Text("Fertig")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

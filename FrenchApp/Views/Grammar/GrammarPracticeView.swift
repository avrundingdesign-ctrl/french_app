import SwiftUI

/// Grammatik-Training: Übungen zu einem Thema oder gemischt über alle
/// freigeschalteten Themen. Übungsmodus mit sofortigem Feedback,
/// ohne Auswirkung auf Lektionsfortschritt oder SRS.
struct GrammarPracticeView: View {
    let rules: [GrammarRule]
    var content: ContentStore = .shared
    var title = "Grammatik-Training"

    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [RuntimeExercise] = []
    @State private var built = false
    @State private var index = 0
    @State private var feedback: LessonSession.Feedback?
    @State private var correctCount = 0

    private var current: RuntimeExercise? {
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
        .onAppear {
            guard !built else { return }
            built = true
            exercises = GrammarPractice(content: content).session(rules: rules)
        }
    }

    private func activeView(_ exercise: RuntimeExercise) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
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
            .padding(.horizontal)
            .padding(.top, 12)

            ScrollView {
                exerciseView(exercise)
                    .id(exercise.id)
                    .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            if let feedback {
                FeedbackBanner(feedback: feedback) {
                    self.feedback = nil
                    withAnimation { index += 1 }
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseView(_ exercise: RuntimeExercise) -> some View {
        switch exercise.kind {
        case .multipleChoice(let mc):
            MCExerciseView(exercise: mc) { record($0, for: exercise) }
        case .textInput(let input):
            TextInputExerciseView(exercise: input) { record($0, for: exercise) }
        case .wordOrder(let order):
            WordOrderExerciseView(exercise: order) { record($0, for: exercise) }
        case .matching(let matching):
            MatchingExerciseView(exercise: matching) { record($0, for: exercise) }
        }
    }

    private func record(_ outcome: AnswerOutcome, for exercise: RuntimeExercise) {
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
            explanation = input.translation ?? input.hint
        case .wordOrder(let order):
            correctAnswer = order.tokens.joined(separator: " ")
            explanation = order.de
        case .matching:
            correctAnswer = exercise.answerSummary
            explanation = nil
        }
        feedback = LessonSession.Feedback(
            correct: outcome.correct,
            accentHint: outcome.accentHint,
            correctAnswer: correctAnswer,
            explanation: explanation
        )
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: exercises.isEmpty ? "moon.zzz.fill" : "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(exercises.isEmpty ? Theme.accent : Theme.success)
            Text(exercises.isEmpty ? "Noch nichts freigeschaltet" : "\(title) beendet!")
                .font(.title2.bold())
            Text(exercises.isEmpty
                 ? "Schließe zuerst eine Lektion ab, um Grammatikthemen freizuschalten."
                 : "\(correctCount) von \(exercises.count) richtig.")
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

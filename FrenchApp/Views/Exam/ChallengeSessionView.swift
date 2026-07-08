import SwiftUI
import SwiftData

/// Vertiefungskapitel: komplexere Übungen, die Grammatik und Wortschatz des
/// Niveaus kombinieren — Transformation, texte à trous, Konnektoren,
/// integriertes Lesen/Hören. Kein Zeitlimit, sofortiges Feedback,
/// Audio beliebig oft abspielbar.
struct ChallengeSessionView: View {
    struct Question: Identifiable {
        let exercise: RuntimeExercise
        let context: String?
        let audioScript: String?
        let passage: String?
        let passageTitle: String?

        var id: String { exercise.id }
    }

    let chapter: ChallengeChapter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var questions: [Question] = []
    @State private var built = false
    @State private var index = 0
    @State private var feedback: LessonSession.Feedback?
    @State private var correctCount = 0
    @State private var isPlaying = false
    @State private var finished = false

    var body: some View {
        Group {
            if !finished, let question = current {
                activeView(question)
            } else if built {
                finishedView
            }
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
        .onAppear(perform: build)
        .onDisappear { SpeechService.shared.stop() }
    }

    private var current: Question? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    private func build() {
        guard !built else { return }
        built = true
        let factory = ExerciseFactory(content: .shared)
        var result: [Question] = []
        for (taskIndex, task) in chapter.tasks.enumerated() {
            for (questionIndex, spec) in task.questions.enumerated() {
                let ref = ExerciseRef(
                    lessonID: chapter.id,
                    exerciseIndex: taskIndex,
                    subIndex: questionIndex
                )
                guard let exercise = factory.standaloneExercise(spec: spec, ref: ref) else {
                    continue
                }
                result.append(Question(
                    exercise: exercise,
                    context: task.context,
                    audioScript: task.audioScript,
                    passage: task.passage,
                    passageTitle: task.passageTitle
                ))
            }
        }
        questions = result
        finished = result.isEmpty
    }

    // MARK: - Aktive Übung

    private func activeView(_ question: Question) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let context = question.context {
                        Text(context)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if question.audioScript != nil {
                        playCard(question)
                    }
                    if let passage = question.passage {
                        PassageCard(title: question.passageTitle, passage: passage)
                    }
                    exerciseView(question)
                        .id(question.id)
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
            ProgressView(value: questions.isEmpty ? 0 : Double(index) / Double(questions.count))
                .tint(Theme.levelColor(chapter.level))
            Text("\(index + 1)/\(questions.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func playCard(_ question: Question) -> some View {
        HStack(spacing: 14) {
            Button {
                play(question)
            } label: {
                Image(systemName: isPlaying ? "speaker.wave.3.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.levelColor(chapter.level))
                    .symbolEffect(.pulse, isActive: isPlaying)
            }
            .buttonStyle(.plain)
            .disabled(isPlaying)

            VStack(alignment: .leading, spacing: 3) {
                Text(isPlaying ? "Läuft …" : "Aufnahme abspielen")
                    .font(.subheadline.weight(.semibold))
                Text("Beliebig oft abspielbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func play(_ question: Question) {
        guard !isPlaying, let script = question.audioScript else { return }
        isPlaying = true
        SpeechService.shared.speak(script, level: chapter.level) {
            isPlaying = false
        }
    }

    @ViewBuilder
    private func exerciseView(_ question: Question) -> some View {
        switch question.exercise.kind {
        case .multipleChoice(let mc):
            MCExerciseView(exercise: mc) { record($0, for: question) }
        case .textInput(let input):
            TextInputExerciseView(exercise: input) { record($0, for: question) }
        case .wordOrder(let order):
            WordOrderExerciseView(exercise: order) { record($0, for: question) }
        case .matching(let matching):
            MatchingExerciseView(exercise: matching) { record($0, for: question) }
        }
    }

    private func record(_ outcome: AnswerOutcome, for question: Question) {
        guard feedback == nil else { return }
        if outcome.correct { correctCount += 1 }

        let correctAnswer: String
        let explanation: String?
        switch question.exercise.kind {
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
            correctAnswer = question.exercise.answerSummary
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
        if index + 1 < questions.count {
            withAnimation { index += 1 }
        } else {
            finalize()
            withAnimation { finished = true }
        }
    }

    /// Abschluss festhalten — bester Score bleibt erhalten.
    private func finalize(now: Date = .now) {
        let score = questions.isEmpty ? 0 : Double(correctCount) / Double(questions.count)
        let chapterID = chapter.id
        let descriptor = FetchDescriptor<ChallengeProgress>(
            predicate: #Predicate { $0.chapterID == chapterID }
        )
        if let existing = ((try? modelContext.fetch(descriptor)) ?? []).first {
            existing.completedAt = now
            existing.bestScore = max(existing.bestScore, score)
            existing.timesCompleted += 1
        } else {
            modelContext.insert(ChallengeProgress(chapterID: chapter.id, completedAt: now, bestScore: score))
        }
    }

    // MARK: - Abschluss

    private var finishedView: some View {
        let score = questions.isEmpty ? 0 : Double(correctCount) / Double(questions.count)
        return ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    ProgressRing(
                        progress: score,
                        color: score >= 0.8 ? Theme.success : Theme.warning,
                        lineWidth: 12
                    )
                    .frame(width: 120, height: 120)
                    VStack {
                        Text("\(Int((score * 100).rounded()))%")
                            .font(.title.bold().monospacedDigit())
                        Text("richtig")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 48)

                Text("\(chapter.title) abgeschlossen!")
                    .font(.title2.bold())
                Text(score >= 0.8
                     ? "Stark — du kombinierst Grammatik und Wortschatz sicher. Bereit für die Niveau-Prüfung?"
                     : "\(correctCount) von \(questions.count) richtig. Wiederhole das Kapitel jederzeit — es zählt nur dein bester Lauf.")
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
                .tint(Theme.levelColor(chapter.level))
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

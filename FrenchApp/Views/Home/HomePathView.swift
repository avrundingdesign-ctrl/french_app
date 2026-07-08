import SwiftUI
import SwiftData

/// Zentraler Hub (Spec Screen 2): vertikaler Lernpfad nach Niveau und Einheit,
/// Freischalt-Status, Fortschritt pro Niveau, Einstieg in fällige Wiederholungen.
struct HomePathView: View {
    @Query private var progress: [LessonProgress]
    @Query private var reviewStates: [ReviewState]
    @Query private var settingsList: [UserSettings]
    @Query private var certificates: [EarnedCertificate]

    @State private var activeLesson: CourseLesson?
    @State private var activeExam: ExamDefinition?
    @State private var showReview = false
    @State private var showGrammarPractice = false

    private let content = ContentStore.shared

    private var snapshot: ProgressSnapshot {
        ProgressSnapshot(progress: progress, content: content)
    }

    private var dueCount: Int {
        guard let settings = settingsList.first else { return 0 }
        return SRSService.dueCount(states: reviewStates, settings: settings)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if dueCount > 0 {
                        reviewBanner
                    }

                    if !unlockedGrammarRules.isEmpty {
                        grammarPracticeBanner
                    }

                    ForEach(content.levels) { level in
                        levelSection(level)
                    }

                    examOnlySection

                    phase2Teaser
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Français")
            .fullScreenCover(item: $activeLesson) { lesson in
                LessonSessionView(mode: .lesson(lesson))
            }
            .fullScreenCover(item: $activeExam) { exam in
                ExamSessionView(exam: exam)
            }
            .fullScreenCover(isPresented: $showReview) {
                ReviewSessionView()
            }
            .fullScreenCover(isPresented: $showGrammarPractice) {
                GrammarPracticeView(rules: unlockedGrammarRules)
            }
        }
    }

    // MARK: - Bausteine

    private var reviewBanner: some View {
        Button {
            showReview = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fällige Wiederholungen")
                        .font(.headline)
                    Text("\(dueCount) \(dueCount == 1 ? "Karte wartet" : "Karten warten") auf dich")
                        .font(.subheadline)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func levelSection(_ level: CEFRLevel) -> some View {
        let (done, total) = snapshot.levelProgress(level)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                LevelBadge(level: level)
                Text(level.subtitle)
                    .font(.headline)
                Spacer()
                Text("\(done)/\(total)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                .tint(Theme.levelColor(level))

            ForEach(content.units.filter { $0.level == level }) { unit in
                unitCard(unit)
            }

            if let exam = content.examByLevel[level] {
                examCard(exam)
            }
        }
    }

    // MARK: - Grammatik-Training

    private var unlockedGrammarRules: [GrammarRule] {
        content.grammarRules.filter { snapshot.isGrammarCovered($0.id) }
    }

    /// Gemischte Grammatik-Übungen aus allen bereits gelernten Themen.
    private var grammarPracticeBanner: some View {
        Button {
            showGrammarPractice = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grammatik-Training")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("\(unlockedGrammarRules.count) \(unlockedGrammarRules.count == 1 ? "Thema" : "Themen") freigeschaltet — gemischt üben")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Niveau-Prüfung

    private var earnedLevels: Set<CEFRLevel> {
        Set(certificates.compactMap(\.level))
    }

    /// Prüfungen für Niveaus ohne Lektionen (C1) — am Ende des Pfads.
    private var examOnlySection: some View {
        let examOnly = content.exams
            .filter { !content.levels.contains($0.level) }
            .sorted { $0.level < $1.level }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(examOnly) { exam in
                HStack {
                    LevelBadge(level: exam.level)
                    Text(exam.level.subtitle)
                        .font(.headline)
                    Spacer()
                }
                examCard(exam)
            }
        }
    }

    private func examCard(_ exam: ExamDefinition) -> some View {
        let passed = earnedLevels.contains(exam.level)
        let unlocked = snapshot.isExamUnlocked(exam.level, earnedLevels: earnedLevels)
        let color = Theme.levelColor(exam.level)

        return Button {
            if unlocked {
                activeExam = exam
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(passed ? Theme.success : (unlocked ? color : Color(.systemFill)))
                        .frame(width: 40, height: 40)
                    Image(systemName: passed ? "checkmark.seal.fill" : (unlocked ? "seal.fill" : "lock.fill"))
                        .font(.subheadline)
                        .foregroundStyle(unlocked || passed ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Niveau-Prüfung \(exam.level.rawValue)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(unlocked ? Color.primary : Color.secondary)
                    Text(examSubtitle(exam, passed: passed, unlocked: unlocked))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if passed {
                    Text("Wiederholen")
                        .font(.caption)
                        .foregroundStyle(color)
                } else if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(unlocked && !passed ? color.opacity(0.45) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    private func examSubtitle(_ exam: ExamDefinition, passed: Bool, unlocked: Bool) -> String {
        if passed {
            return "Bestanden — Zertifikat in deiner Galerie"
        }
        if unlocked {
            return "\(exam.level.examBrand)-Stil · 4 Teile · \(exam.durationMinutes) Minuten"
        }
        let (_, total) = snapshot.levelProgress(exam.level)
        if total == 0, let previous = CEFRLevel.allCases.filter({ $0 < exam.level }).max() {
            return "Bestehe zuerst die Niveau-Prüfung \(previous.rawValue)"
        }
        return "Schließe zuerst alle Lektionen von \(exam.level.rawValue) ab"
    }

    private func unitCard(_ unit: CourseUnit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: unit.icon ?? "folder")
                    .foregroundStyle(Theme.levelColor(unit.level))
                Text(unit.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, lesson in
                lessonRow(lesson, number: index + 1, isLast: index == unit.lessons.count - 1)
            }
        }
        .card()
    }

    private func lessonRow(_ lesson: CourseLesson, number: Int, isLast: Bool) -> some View {
        let unlocked = snapshot.isUnlocked(lesson)
        let completed = snapshot.isCompleted(lesson.id)

        return Button {
            if unlocked {
                activeLesson = lesson
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(completed ? Theme.success : (unlocked ? Theme.accent : Color(.systemFill)))
                        .frame(width: 40, height: 40)
                    if completed {
                        Image(systemName: "checkmark")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    } else if unlocked {
                        Image(systemName: "play.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(unlocked ? Color.primary : Color.secondary)
                        .multilineTextAlignment(.leading)
                    Text(lessonSubtitle(lesson))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if unlocked && !completed {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if completed {
                    Text("Wiederholen")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    private func lessonSubtitle(_ lesson: CourseLesson) -> String {
        var parts: [String] = []
        if !lesson.newVocab.isEmpty {
            parts.append("\(lesson.newVocab.count) neue Wörter")
        }
        if let grammarIDs = lesson.grammar, !grammarIDs.isEmpty {
            let titles = grammarIDs.compactMap { content.grammarByID[$0]?.title }
            if !titles.isEmpty {
                parts.append(titles.joined(separator: ", "))
            }
        }
        return parts.joined(separator: " · ")
    }

    private var phase2Teaser: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(.secondary)
            Text("Der komplette Pfad von A1 bis B2 — bonne route !")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

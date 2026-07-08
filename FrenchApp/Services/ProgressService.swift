import Foundation

/// Abgeleiteter Fortschritt: Freischaltung, Niveau-Statistik, Grammatik-Status.
/// Bewusst zustandslos — Quelle ist immer die aktuelle Liste der `LessonProgress`-Einträge.
struct ProgressSnapshot {
    let completedLessonIDs: Set<String>
    private let content: ContentStore

    init(progress: [LessonProgress], content: ContentStore) {
        self.completedLessonIDs = Set(progress.map(\.lessonID))
        self.content = content
    }

    func isCompleted(_ lessonID: String) -> Bool {
        completedLessonIDs.contains(lessonID)
    }

    /// Sequenzielle Freischaltung (Spec §7): offen, wenn erste Lektion des Kurses
    /// oder die vorherige Lektion abgeschlossen ist. Abgeschlossene bleiben offen.
    func isUnlocked(_ lesson: CourseLesson) -> Bool {
        if isCompleted(lesson.id) { return true }
        guard let previous = content.lesson(before: lesson) else { return true }
        return isCompleted(previous.id)
    }

    /// Die nächste offene, noch nicht abgeschlossene Lektion.
    var nextLesson: CourseLesson? {
        content.orderedLessons.first { !isCompleted($0.id) }
    }

    func levelProgress(_ level: CEFRLevel) -> (done: Int, total: Int) {
        let lessons = content.lessons(for: level)
        let done = lessons.filter { isCompleted($0.id) }.count
        return (done, lessons.count)
    }

    /// Die Niveau-Prüfung öffnet sich, sobald alle Lektionen des Niveaus abgeschlossen
    /// sind. Niveaus ohne Lektionen (C1) schaltet das Zertifikat des vorherigen
    /// Niveaus frei.
    func isExamUnlocked(_ level: CEFRLevel, earnedLevels: Set<CEFRLevel> = []) -> Bool {
        let (done, total) = levelProgress(level)
        if total > 0 { return done == total }
        guard let previous = CEFRLevel.allCases.filter({ $0 < level }).max() else {
            return false
        }
        return earnedLevels.contains(previous)
    }

    /// Grammatikregeln gelten als behandelt, sobald eine verknüpfte Lektion abgeschlossen ist.
    func isGrammarCovered(_ ruleID: String) -> Bool {
        content.lessons(covering: ruleID).contains { isCompleted($0.id) }
    }

    var coveredGrammarCount: Int {
        content.grammarRules.filter { isGrammarCovered($0.id) }.count
    }
}

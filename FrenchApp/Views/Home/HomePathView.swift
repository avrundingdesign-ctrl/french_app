import SwiftUI
import SwiftData

/// Zentraler Hub (Spec Screen 2): vertikaler Lernpfad nach Niveau und Einheit,
/// Freischalt-Status, Fortschritt pro Niveau, Einstieg in fällige Wiederholungen.
struct HomePathView: View {
    @Query private var progress: [LessonProgress]
    @Query private var reviewStates: [ReviewState]
    @Query private var settingsList: [UserSettings]

    @State private var activeLesson: CourseLesson?
    @State private var showReview = false

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

                    ForEach(content.levels) { level in
                        levelSection(level)
                    }

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
            .fullScreenCover(isPresented: $showReview) {
                ReviewSessionView()
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
        }
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
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text("A2, B1 und B2 folgen in den nächsten Phasen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

import SwiftUI

// MARK: - Multiple Choice

struct MCExerciseView: View {
    let exercise: MCExercise
    let onAnswered: (AnswerOutcome) -> Void

    @State private var selectedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ExerciseHeader(
                instruction: exercise.instruction,
                prompt: exercise.prompt,
                detail: exercise.promptDetail
            )

            VStack(spacing: 10) {
                ForEach(exercise.options.indices, id: \.self) { index in
                    Button {
                        select(index)
                    } label: {
                        HStack {
                            Text(exercise.options[index])
                                .font(.body.weight(.medium))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if selectedIndex != nil && index == exercise.correctIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.success)
                            } else if selectedIndex == index {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.danger)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(optionBackground(index), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(optionBorder(index), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedIndex != nil)
                }
            }
        }
    }

    private func select(_ index: Int) {
        guard selectedIndex == nil else { return }
        selectedIndex = index
        onAnswered(AnswerOutcome(
            correct: index == exercise.correctIndex,
            userAnswer: exercise.options[index]
        ))
    }

    private func optionBackground(_ index: Int) -> Color {
        guard let selected = selectedIndex else {
            return Color(.secondarySystemGroupedBackground)
        }
        if index == exercise.correctIndex { return Theme.success.opacity(0.12) }
        if index == selected { return Theme.danger.opacity(0.12) }
        return Color(.secondarySystemGroupedBackground)
    }

    private func optionBorder(_ index: Int) -> Color {
        guard let selected = selectedIndex else { return .clear }
        if index == exercise.correctIndex { return Theme.success }
        if index == selected { return Theme.danger }
        return .clear
    }
}

// MARK: - Matching (Wortpaare zuordnen)

struct MatchingExerciseView: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let pairID: String
        let text: String
    }

    let exercise: MatchingExercise
    let onAnswered: (AnswerOutcome) -> Void

    @State private var leftItems: [Item] = []
    @State private var rightItems: [Item] = []
    @State private var matched: Set<String> = []
    @State private var selectedLeft: Item?
    @State private var selectedRight: Item?
    @State private var wrongPair: (String, String)?
    @State private var hadMistake = false
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ExerciseHeader(
                instruction: exercise.instruction,
                prompt: "Französisch ↔ Deutsch",
                detail: nil
            )

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    ForEach(leftItems) { item in
                        matchButton(item, isLeft: true)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(rightItems) { item in
                        matchButton(item, isLeft: false)
                    }
                }
            }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        guard leftItems.isEmpty else { return }
        leftItems = exercise.pairs
            .map { Item(id: "l_\($0.id)", pairID: $0.id, text: $0.fr) }
            .shuffled()
        rightItems = exercise.pairs
            .map { Item(id: "r_\($0.id)", pairID: $0.id, text: $0.de) }
            .shuffled()
    }

    private func matchButton(_ item: Item, isLeft: Bool) -> some View {
        let isMatched = matched.contains(item.pairID)
        let isSelected = (isLeft ? selectedLeft : selectedRight)?.id == item.id
        let isWrong = wrongPair.map { isLeft ? $0.0 == item.id : $0.1 == item.id } ?? false

        return Button {
            select(item, isLeft: isLeft)
        } label: {
            Text(item.text)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    isMatched ? Theme.success.opacity(0.12)
                        : isWrong ? Theme.danger.opacity(0.15)
                        : isSelected ? Theme.accent.opacity(0.15)
                        : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isMatched ? Theme.success
                                : isWrong ? Theme.danger
                                : isSelected ? Theme.accent
                                : .clear,
                            lineWidth: 1.5
                        )
                )
                .opacity(isMatched ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isMatched || finished)
    }

    private func select(_ item: Item, isLeft: Bool) {
        guard wrongPair == nil else { return }
        if isLeft {
            selectedLeft = selectedLeft?.id == item.id ? nil : item
        } else {
            selectedRight = selectedRight?.id == item.id ? nil : item
        }
        checkPair()
    }

    private func checkPair() {
        guard let left = selectedLeft, let right = selectedRight else { return }
        if left.pairID == right.pairID {
            matched.insert(left.pairID)
            selectedLeft = nil
            selectedRight = nil
            if matched.count == exercise.pairs.count {
                finished = true
                onAnswered(AnswerOutcome(correct: !hadMistake))
            }
        } else {
            hadMistake = true
            wrongPair = (left.id, right.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                wrongPair = nil
                selectedLeft = nil
                selectedRight = nil
            }
        }
    }
}

// MARK: - Freitext (Cloze & Konjugation)

struct TextInputExerciseView: View {
    let exercise: TextInputExercise
    let onAnswered: (AnswerOutcome) -> Void

    @State private var text = ""
    @State private var answered = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ExerciseHeader(
                instruction: exercise.instruction,
                prompt: promptLine,
                detail: exercise.translation
            )

            if let hint = exercise.hint {
                Label(hint, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                TextField("Antwort", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.default)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(submit)
                    .disabled(answered)

                AccentBar(text: $text)
                    .disabled(answered)
            }

            Button(action: submit) {
                Text("Prüfen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(answered || text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { focused = true }
    }

    private var promptLine: String {
        exercise.prefix + "___" + exercise.suffix
    }

    private func submit() {
        guard !answered, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        answered = true
        focused = false
        let result = exercise.check(text)
        switch result {
        case .correct:
            onAnswered(AnswerOutcome(correct: true, userAnswer: text))
        case .correctWithAccentHint:
            onAnswered(AnswerOutcome(correct: true, accentHint: true, userAnswer: text))
        case .wrong:
            onAnswered(AnswerOutcome(correct: false, userAnswer: text))
        }
    }
}

// MARK: - Satzbau (Wörter ordnen)

struct WordOrderExerciseView: View {
    struct Token: Identifiable, Equatable {
        let id: Int
        let text: String
    }

    let exercise: WordOrderExercise
    let onAnswered: (AnswerOutcome) -> Void

    @State private var pool: [Token] = []
    @State private var chosen: [Token] = []
    @State private var answered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ExerciseHeader(
                instruction: exercise.instruction,
                prompt: "„\(exercise.de)“",
                detail: nil
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Dein Satz:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(chosen) { token in
                        tokenChip(token, filled: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            FlowLayout(spacing: 8) {
                ForEach(pool) { token in
                    tokenChip(token, filled: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Button(action: submit) {
                Text("Prüfen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(answered || !pool.isEmpty || chosen.isEmpty)
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        guard pool.isEmpty && chosen.isEmpty else { return }
        let tokens = exercise.tokens.enumerated().map { Token(id: $0.offset, text: $0.element) }
        var shuffled = tokens.shuffled()
        var attempts = 0
        while shuffled.map(\.text) == exercise.tokens && attempts < 5 && tokens.count > 2 {
            shuffled = tokens.shuffled()
            attempts += 1
        }
        pool = shuffled
    }

    private func tokenChip(_ token: Token, filled: Bool) -> some View {
        Button {
            move(token, toChosen: !filled)
        } label: {
            Text(token.text)
                .font(.body.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    filled ? Theme.accent.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(filled ? Theme.accent.opacity(0.4) : Color(.separator), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    private func move(_ token: Token, toChosen: Bool) {
        if toChosen {
            pool.removeAll { $0.id == token.id }
            chosen.append(token)
        } else {
            chosen.removeAll { $0.id == token.id }
            pool.append(token)
        }
    }

    private func submit() {
        guard !answered else { return }
        answered = true
        let built = chosen.map(\.text).joined(separator: " ")
        let target = exercise.tokens.joined(separator: " ")
        let result = AnswerChecker.check(input: built, answer: target)
        onAnswered(AnswerOutcome(
            correct: result != .wrong,
            accentHint: result == .correctWithAccentHint,
            userAnswer: built
        ))
    }
}

// MARK: - Gemeinsame Bausteine

struct ExerciseHeader: View {
    let instruction: String
    let prompt: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(prompt)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Eingabeleiste für französische Sonderzeichen.
struct AccentBar: View {
    @Binding var text: String

    private static let accents = ["é", "è", "ê", "à", "ç", "ù", "â", "î", "ô", "û", "ë", "ï", "œ", "'"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.accents, id: \.self) { accent in
                    Button {
                        text.append(accent)
                    } label: {
                        Text(accent)
                            .font(.title3)
                            .frame(width: 38, height: 38)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Einfaches Fluss-Layout für Wort-Chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: proposal.width ?? totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

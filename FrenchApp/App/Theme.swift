import SwiftUI

enum Theme {
    /// Bleu de France.
    static let accent = Color(red: 0 / 255, green: 85 / 255, blue: 164 / 255)
    static let success = Color(red: 0.20, green: 0.62, blue: 0.35)
    static let danger = Color(red: 0.85, green: 0.25, blue: 0.22)
    static let warning = Color(red: 0.93, green: 0.60, blue: 0.10)

    static func levelColor(_ level: CEFRLevel) -> Color {
        switch level {
        case .a1: return accent
        case .a2: return Color(red: 0.05, green: 0.55, blue: 0.55)
        case .b1: return Color(red: 0.80, green: 0.45, blue: 0.10)
        case .b2: return Color(red: 0.45, green: 0.30, blue: 0.65)
        case .c1: return Color(red: 0.70, green: 0.18, blue: 0.32)
        }
    }
}

// MARK: - Wiederverwendbare Bausteine

struct LevelBadge: View {
    let level: CEFRLevel

    var body: some View {
        Text(level.rawValue)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.levelColor(level), in: Capsule())
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func card() -> some View {
        modifier(CardBackground())
    }
}

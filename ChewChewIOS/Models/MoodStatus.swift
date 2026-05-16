import Foundation

enum Mood: String {
    case sleepy, happy, puffy, champ

    var imageName: String {
        switch self {
        case .sleepy: "DaramSleepy"
        case .happy:  "DaramHappy"
        case .puffy:  "DaramPuffy"
        case .champ:  "DaramChamp"
        }
    }
}

struct MoodStatus {
    let mood: Mood
    let title: String
    let subtitle: String

    static func from(count: Int) -> MoodStatus {
        let goal = Constants.dailyGoal
        if count <= 0   { return .init(mood: .sleepy, title: "아직 식사 전이에요 🥱", subtitle: "한 입 씹어볼까요?") }
        if count < 100  { return .init(mood: .happy,  title: "냠냠, 시작했어요!",     subtitle: "천천히, 꼭꼭 씹어요") }
        if count < 250  { return .init(mood: .happy,  title: "리듬 좋아요!",          subtitle: "목표까지 \(goal - count)회") }
        if count < 450  { return .init(mood: .puffy,  title: "볼이 빵빵해요 🐿️",      subtitle: "절반 넘었어요!") }
        if count < goal { return .init(mood: .puffy,  title: "거의 다 왔어요!",       subtitle: "목표 \(Int(Double(count) / Double(goal) * 100))% 달성") }
        return .init(mood: .champ, title: "🎉 목표 달성!", subtitle: "오늘 정말 잘했어요")
    }
}

struct FeedbackLine: Identifiable, Hashable {
    enum Kind: Hashable { case good, warn, cheer }

    let id = UUID()
    let kind: Kind
    let text: String

    var emoji: String {
        switch kind {
        case .good:  "👍"
        case .warn:  "🐢"
        case .cheer: "💚"
        }
    }

    static let all: [FeedbackLine] = [
        .init(kind: .good,  text: "좋은 페이스예요! 👍"),
        .init(kind: .warn,  text: "천천히 씹어보세요 🐢"),
        .init(kind: .cheer, text: "잘하고 있어요! 💚"),
        .init(kind: .warn,  text: "한 입을 30번 씹어볼까요?"),
        .init(kind: .good,  text: "리듬이 안정적이에요!"),
        .init(kind: .cheer, text: "씹을수록 포만감 UP!"),
    ]
}

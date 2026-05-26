import Foundation

/// 알림/UI 문구 풀. 카테고리별 배열에서 랜덤 선택해 재사용.
/// 각 문장은 32자 이하.
enum CaptionPool {
    /// 끼니 알림 본문 풀. ≥8문장, 각 ≤32자.
    static let mealReminder: [String] = [
        "밥 먹을 시간이에요 🍚",
        "주인님, 밥은 먹었나요?",
        "씹고 또 씹고, 밥 먹어요!",
        "오늘도 맛있는 식사 하세요",
        "끼니는 건강의 시작이에요",
        "잠깐, 밥 먹고 일해요! 🥢",
        "식사 시간 놓치지 마세요",
        "몸이 밥을 원하고 있어요",
        "꼭꼭 씹어서 먹어요 😊",
        "든든하게 한 끼 채워요!",
    ]

    /// 배열에서 랜덤 문자열 반환. 배열이 비어 있으면 빈 문자열.
    static func random(from pool: [String]) -> String {
        pool.randomElement() ?? ""
    }
}

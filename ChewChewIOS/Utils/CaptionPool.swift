import Foundation

/// 리포트·알림·UI 문구 풀. 카테고리별 배열에서 랜덤 선택해 재사용. 각 문장은 32자 이하.
/// REQ-03(리포트 점수 캡션)·REQ-13(끼니 알림) 등에서 공용으로 사용한다.
enum CaptionPool {

    enum Category {
        case report
        // 향후: streak, challenge, etc.
    }

    /// `grade`에 해당하는 캡션 풀에서 한 문장을 반환. 풀이 비어 있으면 nil.
    static func report(for grade: ReportCardModel.Grade) -> String? {
        let pool: [String]
        switch grade {
        case .good:
            pool = [
                "오늘은 정말 잘 씹었어요. 이 페이스 그대로 가요.",
                "한 입 한 입 꼼꼼히 씹은 덕분에 소화도 잘 될 거예요.",
                "오늘은 꼭꼭 잘 씹었어요. 내일도 이렇게 먹어요.",
                "식사 리듬이 안정적이에요. 좋은 흐름이에요.",
            ]
        case .soso:
            pool = [
                "조금만 더 천천히 먹으면 좋겠어요.",
                "한 입에 30회를 의식하면 점수가 훌쩍 오를 거예요.",
                "다음 식사엔 속도를 살짝만 줄여봐요.",
                "꾸준히 하다 보면 금방 좋아져요. 오늘도 수고했어요.",
            ]
        case .bad:
            pool = [
                "이번엔 조금 빨리 먹었네요. 다음엔 한 입 30회를 목표로 해봐요.",
                "천천히 씹을수록 포만감이 오래가요. 다음 식사에서 다시 해봐요.",
                "식사 속도를 조금만 줄이면 점수가 확 달라져요.",
                "괜찮아요. 다음 한 끼부터 천천히 가봐요.",
            ]
        }
        return pool.randomElement()
    }

    /// 끼니 알림 본문 풀. ≥8문장, 각 ≤32자.
    static let mealReminder: [String] = [
        "밥 먹을 시간이에요",
        "주인님, 밥은 먹었나요?",
        "씹고 또 씹고, 밥 먹어요",
        "오늘도 맛있는 식사 하세요",
        "끼니 거르지 말고 챙겨요",
        "잠깐, 밥 먹고 일해요",
        "식사 시간 놓치지 마세요",
        "슬슬 밥 먹을 시간이에요",
        "꼭꼭 씹어서 먹어요",
        "든든하게 한 끼 채워요",
    ]

    /// 배열에서 랜덤 문자열 반환. 배열이 비어 있으면 빈 문자열.
    static func random(from pool: [String]) -> String {
        pool.randomElement() ?? ""
    }
}

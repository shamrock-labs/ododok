import Foundation

/// 점수 등급별 한 줄 캡션 풀. `ReportCardModel.from`에서 `grade`에 맞는 문장을 랜덤 선택.
/// REQ-13/REQ-11 등 후속 기능에서 카테고리를 추가할 수 있도록 `Category` enum으로 확장점 확보.
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
                "오늘은 정말 잘 씹었어요. 이 페이스 계속 가요!",
                "한 입 한 입 꼼꼼히 씹은 덕분에 소화도 잘 될 거예요.",
                "꼭꼭 씹기 챔피언! 내일도 이렇게 먹어요.",
                "식사 리듬이 아주 안정적이에요. 최고예요!",
            ]
        case .soso:
            pool = [
                "조금 더 천천히 먹으면 완벽해질 것 같아요.",
                "한 입에 30회를 의식하면 점수가 훌쩍 오를 거예요.",
                "거의 다 왔어요! 다음 식사엔 속도를 살짝 줄여봐요.",
                "꾸준히 하다 보면 금방 좋아져요. 오늘도 수고했어요.",
            ]
        case .bad:
            pool = [
                "이번엔 조금 빨리 먹었네요. 다음엔 한 입 30회를 목표로 해봐요.",
                "천천히 씹을수록 포만감이 오래 가요. 다음 식사에서 도전!",
                "식사 속도를 조금만 줄이면 점수가 확 달라져요.",
                "괜찮아요, 다음 식사가 기회예요. 다람이가 응원해요!",
            ]
        }
        return pool.randomElement()
    }
}

import Foundation

/// 식사 점수 4요소 + 합계. PRD #3의 `SessionScore.swift` 정의 — 속도 / 리듬 / 연속성 / 길이
/// 가중평균으로 0~100 정수 산출. 가중치/임계값은 잠정 — 출시 후 사용자 데이터 기반으로
/// 후속 튜닝 PR에서 조정.
///
/// `ChewingSessionDTO`의 분석 5필드(`estimatedTotalChews`/`chewingFraction`/`chewingSeconds`/
/// `restSeconds`/`modelVersion`)가 모두 채워진 세션에서만 산출 가능. 시뮬레이터/AirPods
/// 미연결/60초 미만 세션은 nil 반환 → 호출자가 empty state 카드를 표시.
struct SessionScore: Equatable {
    /// 4요소 가중평균. 0~100 정수.
    let total: Int
    /// 분당 평균 저작 수 기준. sweet spot 28회/분 근처.
    let speed: Int
    /// 저작/휴식 비율(`chewingFraction`) 기반. 0.7 이상이면 100점.
    let rhythm: Int
    /// 추정 저작 수의 절대량. 한 끼당 300회 근처에서 100점.
    let continuity: Int
    /// 식사 시간 기준. sweet spot 12분 ± 4분.
    let length: Int

    enum Grade {
        case good, soso, bad

        static func from(total: Int) -> Grade {
            switch total {
            case 80...:     .good
            case 60..<80:   .soso
            default:        .bad
            }
        }
    }

    var grade: Grade { Grade.from(total: total) }

    static func compute(_ dto: ChewingSessionDTO) -> SessionScore? {
        guard
            let chews = dto.estimatedTotalChews,
            let fraction = dto.chewingFraction
        else { return nil }

        let mins = max(0.001, dto.durationSec / 60)
        let chewsPerMin = Double(chews) / mins

        // 가중치/임계값 튜닝 (#32) — 한국식 식사 흐름(7~10분, 150~250회, 대화 텀)에 맞춰
        // tolerance/cap을 완화. 일반 사용자가 자연스럽게 식사해도 70~85점이 잡히도록.
        let speed      = bell(value: chewsPerMin,         sweet: 28,  tolerance: 15)
        let rhythm     = Int((min(fraction / 0.5, 1.0) * 100).rounded())
        let continuity = Int((min(Double(chews) / 200.0, 1.0) * 100).rounded())
        let length     = bell(value: dto.durationSec,     sweet: 720, tolerance: 600)

        let total = Int((Double(speed + rhythm + continuity + length) / 4.0).rounded())
        return SessionScore(
            total: max(0, min(100, total)),
            speed: speed,
            rhythm: rhythm,
            continuity: continuity,
            length: length
        )
    }

    /// sweet spot에서 100점, tolerance 밖에서 0점에 선형 점근.
    private static func bell(value: Double, sweet: Double, tolerance: Double) -> Int {
        let diff = abs(value - sweet)
        let normalized = max(0.0, 1.0 - diff / tolerance)
        return Int((normalized * 100).rounded())
    }
}

import Foundation

/// 식사 한 끼 동안 ChewingPredictor가 뱉은 prediction 스트림을 누적해, 세션 종료 시 분석 통계를 산출.
/// chewing-imu-collector의 `SessionAnalyzer.AnalysisResult` 로직을 온라인 누적 형태로 포팅.
///
/// 가정: prediction은 0.5초 stride로 고정 간격으로 도착한다 (ChewingPredictor.strideCount = 25 @ 50Hz).
/// 따라서 N번째 prediction의 윈도우 시작 시각은 `N × 0.5초`로 결정적.
actor SessionStatsBuilder {

    private var labels: [ChewingLabel] = []
    private static let strideSec = 0.5
    private static let maxBoutGap = 1.0
    private static let avgChewsPerSecond = 1.2  // 연구 기반 평균 씹기 주파수

    func append(_ prediction: ChewingPrediction) {
        labels.append(prediction.label)
    }

    /// 누적된 라벨로부터 최종 통계 계산. 호출 후 builder는 재사용하지 않는다.
    func build(modelVersion: String) -> SessionStats {
        let total = labels.count
        let chewing = labels.filter { $0 == .chewing }.count
        let rest = total - chewing
        let chewingSeconds = Double(chewing) * Self.strideSec
        let restSeconds = Double(rest) * Self.strideSec
        let fraction = total > 0 ? Double(chewing) / Double(total) : 0
        let estimatedTotalChews = computeEstimatedChews()

        return SessionStats(
            chewingSeconds: chewingSeconds,
            restSeconds: restSeconds,
            chewingFraction: fraction,
            estimatedTotalChews: estimatedTotalChews,
            modelVersion: modelVersion
        )
    }

    /// 연속된 chewing 윈도우를 bout으로 묶어 (gap ≤ 1.0s 허용),
    /// 각 bout 의 (지속시간 × 1.2) round로 chew 개수 추정 후 합산.
    /// collector `SessionAnalyzer.swift:31-53` 그대로 옮긴 로직.
    private func computeEstimatedChews() -> Int {
        var bouts: [(start: Double, end: Double)] = []
        var boutStart: Double? = nil
        var prevEnd: Double? = nil

        for (i, label) in labels.enumerated() where label == .chewing {
            let tStart = Double(i) * Self.strideSec
            let tEnd = tStart + Self.strideSec
            if let prev = prevEnd, tStart - prev > Self.maxBoutGap {
                bouts.append((boutStart!, prev))
                boutStart = tStart
            } else if boutStart == nil {
                boutStart = tStart
            }
            prevEnd = tEnd
        }
        if let start = boutStart, let end = prevEnd {
            bouts.append((start, end))
        }

        return bouts.reduce(0) { acc, bout in
            let duration = bout.end - bout.start
            return acc + max(1, Int((duration * Self.avgChewsPerSecond).rounded()))
        }
    }
}

/// 세션 종료 시 산출된 분석 통계. `ChewingSessionDTO` 의 5개 분석 필드와 1:1 매핑.
struct SessionStats: Sendable, Equatable {
    let chewingSeconds: Double
    let restSeconds: Double
    let chewingFraction: Double
    let estimatedTotalChews: Int
    let modelVersion: String
}

import Foundation

/// ChewingClassifier 모델 출력 라벨. CoreML이 Int64로 뱉으므로 rawValue를 맞춰둠.
enum ChewingLabel: Int64, Sendable {
    case rest = 0
    case chewing = 1
}

/// 한 윈도우(2초 분량) 추론 결과.
/// `confidence`는 chewing(=1) 클래스의 확률 (0.0–1.0).
struct ChewingPrediction: Sendable {
    let label: ChewingLabel
    let confidence: Double
}

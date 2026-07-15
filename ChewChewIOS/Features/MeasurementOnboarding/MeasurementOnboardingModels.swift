import Foundation

enum MeasurementOnboardingStage: String, CaseIterable {
    case intro
    case connection
    case baseline
    case calibration
    case adjustment
    case ready
    case signalIssue

    var progressIndex: Int {
        switch self {
        case .intro, .connection: 0
        case .baseline, .calibration: 1
        case .adjustment: 2
        case .ready: 3
        case .signalIssue: 2
        }
    }
}

enum MeasurementOnboardingIssue: Equatable {
    case motionUnavailable
    case insufficientCalibration
    case insufficientSeparation
    case adjustmentNeeded
    case sensor(String)

    var message: String {
        switch self {
        case .motionUnavailable:
            return "AirPods 움직임 센서를 사용할 수 없어요."
        case .insufficientCalibration:
            return "씹기 신호를 충분히 찾지 못했어요."
        case .insufficientSeparation:
            return "정지 상태와 씹기 신호를 충분히 구분하지 못했어요."
        case .adjustmentNeeded:
            return "신호가 일정하게 이어지지 않았어요."
        case let .sensor(message):
            return message
        }
    }
}

struct MeasurementOnboardingTiming {
    let cueCount: Int
    let baselineDuration: Duration
    let adjustmentCueIntervalOverride: Duration?

    init(
        cueCount: Int,
        baselineDuration: Duration = .seconds(5),
        cueInterval: Duration? = nil
    ) {
        self.cueCount = cueCount
        self.baselineDuration = baselineDuration
        self.adjustmentCueIntervalOverride = cueInterval
    }

    static let live = MeasurementOnboardingTiming(cueCount: 10)
}

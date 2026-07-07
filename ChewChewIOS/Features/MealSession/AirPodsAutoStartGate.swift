import CoreMotion

enum AirPodsAutoStartDecision: Equatable {
    case block
    case requestPermission
    case waitForAirPodsConnection
    case startCountdown
}

enum AirPodsAutoStartGate {
    static func decision(
        status: CMAuthorizationStatus,
        available: Bool,
        hasHeadphoneAudioRoute: Bool
    ) -> AirPodsAutoStartDecision {
        guard available else {
            return .block
        }

        switch status {
        case .authorized:
            return hasHeadphoneAudioRoute ? .startCountdown : .waitForAirPodsConnection
        case .notDetermined:
            return .requestPermission
        case .denied, .restricted:
            return .block
        @unknown default:
            return .block
        }
    }
}

import AVFoundation

/// AirPods/블루투스/유선 헤드폰 라우트 판정의 단일 정본.
enum AirPodsRouteDetector {
    static func isHeadphoneRoute(_ portType: AVAudioSession.Port) -> Bool {
        switch portType {
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones, .headsetMic:
            return true
        default:
            return false
        }
    }

    static func hasHeadphoneAudioRoute(outputs: [AVAudioSessionPortDescription]) -> Bool {
        outputs.contains { isHeadphoneRoute($0.portType) }
    }
}

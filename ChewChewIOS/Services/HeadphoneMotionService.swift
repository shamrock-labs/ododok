import CoreMotion
import Foundation

/// AirPods CMDeviceMotion 한 샘플. 시각화용 magnitude 2개와 추론·저장용 raw 6채널을
/// 함께 노출한다. 기존 호출자는 magnitude만 쓰면 되고, IMUSessionRecorder는 raw를 쓴다.
struct HeadphoneMotionSample {
    let timestamp: TimeInterval

    let rotationRateMagnitude: Double
    let userAccelerationMagnitude: Double

    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double

    let userAccelX: Double
    let userAccelY: Double
    let userAccelZ: Double

    /// `default` / `headphone_left` / `headphone_right` — DB의 `sensor_location` 값과 일치.
    let sensorLocation: String
}

final class HeadphoneMotionService {
    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ChewChew.HeadphoneMotion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var isDeviceMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    var isDeviceMotionActive: Bool {
        manager.isDeviceMotionActive
    }

    var authorizationStatus: CMAuthorizationStatus {
        CMHeadphoneMotionManager.authorizationStatus()
    }

    func start(
        onSample: @escaping (HeadphoneMotionSample) -> Void,
        onError: @escaping (String) -> Void
    ) {
        stop()

        manager.startDeviceMotionUpdates(to: queue) { motion, error in
            if let error {
                DispatchQueue.main.async {
                    onError(error.localizedDescription)
                }
                return
            }

            guard let motion else { return }

            let rotation = motion.rotationRate
            let acceleration = motion.userAcceleration
            let sample = HeadphoneMotionSample(
                timestamp: motion.timestamp,
                rotationRateMagnitude: Self.magnitude(x: rotation.x, y: rotation.y, z: rotation.z),
                userAccelerationMagnitude: Self.magnitude(
                    x: acceleration.x,
                    y: acceleration.y,
                    z: acceleration.z
                ),
                rotationX: rotation.x,
                rotationY: rotation.y,
                rotationZ: rotation.z,
                userAccelX: acceleration.x,
                userAccelY: acceleration.y,
                userAccelZ: acceleration.z,
                sensorLocation: Self.sensorLocationString(motion.sensorLocation)
            )

            DispatchQueue.main.async {
                onSample(sample)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private static func magnitude(x: Double, y: Double, z: Double) -> Double {
        sqrt(x * x + y * y + z * z)
    }

    private static func sensorLocationString(_ location: CMDeviceMotion.SensorLocation) -> String {
        switch location {
        case .default:        return "default"
        case .headphoneLeft:  return "headphone_left"
        case .headphoneRight: return "headphone_right"
        @unknown default:     return "default"
        }
    }
}

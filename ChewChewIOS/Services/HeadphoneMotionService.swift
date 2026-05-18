import CoreMotion
import Foundation

/// AirPods CMDeviceMotion 한 샘플. UI 파형용 magnitude 2개와 학습/추론용 raw 채널 전체를
/// 함께 노출한다. 기존 호출자는 magnitude만 쓰면 되고, IMUSessionRecorder는 raw 전부를 쓴다.
/// 학습 레포의 18컬럼 CSV와 컬럼 1:1 매칭이 되도록 attitude/gravity/magneticField까지 포함.
struct HeadphoneMotionSample {
    /// `CMDeviceMotion.timestamp` — 부팅 후 mach 시각. 학습 레포 CSV의 `t_mach` 컬럼.
    let timestamp: TimeInterval

    let rotationRateMagnitude: Double
    let userAccelerationMagnitude: Double

    let attitudeRoll: Double
    let attitudePitch: Double
    let attitudeYaw: Double

    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double

    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double

    let userAccelX: Double
    let userAccelY: Double
    let userAccelZ: Double

    /// AirPods는 magnetometer를 노출하지 않는 경우가 있어 0으로 박힐 수 있음 — 컬럼 형태는 유지.
    let magneticFieldX: Double
    let magneticFieldY: Double
    let magneticFieldZ: Double

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

            let attitude = motion.attitude
            let rotation = motion.rotationRate
            let gravity = motion.gravity
            let acceleration = motion.userAcceleration
            let mag = motion.magneticField.field

            let sample = HeadphoneMotionSample(
                timestamp: motion.timestamp,
                rotationRateMagnitude: Self.magnitude(x: rotation.x, y: rotation.y, z: rotation.z),
                userAccelerationMagnitude: Self.magnitude(
                    x: acceleration.x,
                    y: acceleration.y,
                    z: acceleration.z
                ),
                attitudeRoll: attitude.roll,
                attitudePitch: attitude.pitch,
                attitudeYaw: attitude.yaw,
                rotationX: rotation.x,
                rotationY: rotation.y,
                rotationZ: rotation.z,
                gravityX: gravity.x,
                gravityY: gravity.y,
                gravityZ: gravity.z,
                userAccelX: acceleration.x,
                userAccelY: acceleration.y,
                userAccelZ: acceleration.z,
                magneticFieldX: mag.x,
                magneticFieldY: mag.y,
                magneticFieldZ: mag.z,
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

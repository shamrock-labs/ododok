import CoreMotion
import Foundation

struct HeadphoneMotionSample {
    let timestamp: TimeInterval
    let rotationRateMagnitude: Double
    let userAccelerationMagnitude: Double
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
                )
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
}

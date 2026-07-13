import Foundation

struct ChewPulseDeliveryGate {
    let minimumInterval: TimeInterval
    private(set) var lastDeliveryTime: TimeInterval?

    mutating func shouldDeliver(at time: TimeInterval) -> Bool {
        if let lastDeliveryTime,
           time - lastDeliveryTime + 1e-9 < minimumInterval {
            return false
        }
        lastDeliveryTime = time
        return true
    }

    mutating func reset() {
        lastDeliveryTime = nil
    }
}

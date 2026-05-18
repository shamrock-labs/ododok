import CoreML
import Foundation

/// 슬라이딩 윈도우 (2초 / 0.5초 stride) 기반 씹기 예측기.
/// `feed(_:)` 로 IMU 샘플을 넣으면 버퍼가 찰 때부터 매 25샘플(0.5초)마다 ChewingPrediction을 반환.
/// 입력 18채널 IMURow 중 추론에 쓰이는 6채널(rotation x/y/z + user_accel x/y/z)만 내부에서 추출.
/// 50Hz 가정 — Pro 1세대 25Hz 환경에서는 윈도우 길이가 2배가 되지만 동작 자체는 함.
actor ChewingPredictor {

    private let model: ChewingClassifier
    private var buffer: [IMURow] = []
    private var totalSamples = 0

    private let windowCount = 100  // 2s × 50Hz
    private let strideCount = 25   // 0.5s stride

    init() throws {
        model = try ChewingClassifier(configuration: .init())
        buffer.reserveCapacity(windowCount)
    }

    /// IMU 샘플 1개를 추가한다. 버퍼가 찬 뒤 strideCount마다 예측값을 반환, 그 외엔 nil.
    func feed(_ row: IMURow) -> ChewingPrediction? {
        buffer.append(row)
        if buffer.count > windowCount { buffer.removeFirst() }
        totalSamples += 1
        guard buffer.count == windowCount, totalSamples % strideCount == 0 else { return nil }
        return predict()
    }

    private func predict() -> ChewingPrediction? {
        let rotX = buffer.map(\.rotationX)
        let rotY = buffer.map(\.rotationY)
        let rotZ = buffer.map(\.rotationZ)
        let accX = buffer.map(\.userAccelX)
        let accY = buffer.map(\.userAccelY)
        let accZ = buffer.map(\.userAccelZ)

        guard let output = try? model.prediction(input: ChewingClassifierInput(
            rotation_x_rms:    rms(rotX), rotation_x_std:    std(rotX),
            rotation_y_rms:    rms(rotY), rotation_y_std:    std(rotY),
            rotation_z_rms:    rms(rotZ), rotation_z_std:    std(rotZ),
            user_accel_x_rms:  rms(accX), user_accel_x_std:  std(accX),
            user_accel_y_rms:  rms(accY), user_accel_y_std:  std(accY),
            user_accel_z_rms:  rms(accZ), user_accel_z_std:  std(accZ)
        )),
        let label = ChewingLabel(rawValue: output.chewing_label) else { return nil }

        return ChewingPrediction(label: label, confidence: output.classProbability[1] ?? 0)
    }
}

// MARK: - Feature helpers

private func rms(_ v: [Double]) -> Double {
    v.isEmpty ? 0 : (v.reduce(0.0) { $0 + $1 * $1 } / Double(v.count)).squareRoot()
}

private func std(_ v: [Double]) -> Double {
    guard v.count > 1 else { return 0 }
    let mean = v.reduce(0.0, +) / Double(v.count)
    return (v.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count)).squareRoot()
}

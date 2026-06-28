import Foundation

struct ChewCounterSnapshot: Sendable {
    let chewCount: Int
    let chewTimestamps: [Double]
    let chewAmplitudes: [Double]
    let avgInterval: Double
    let intervalStd: Double
    let intervalCV: Double
}

/// Real-time chew counter using a band-pass IIR filter (0.5–3 Hz) + peak detection.
///
/// Feed every raw IMU sample via `feed(_:)`.
/// Call `setChewing(_:)` whenever the Level-1 classifier (ChewingPredictor) updates.
/// 최근 신호가 씹기 상태로 판단될 때만 후보 피크를 카운트한다.
actor ChewCounter {

    // 1st-order IIR high-pass: y[n] = α*(y[n-1] + x[n] - x[n-1])
    // α = exp(-2π*fc/fs), fc=0.5 Hz, fs=50 Hz → α ≈ 0.9391
    private let hpAlpha = 0.9391
    private var hpPrev: Double = 0
    private var hpPrevInput: Double = 0

    // 1st-order IIR low-pass: y[n] = β*y[n-1] + (1-β)*x[n]
    // fc=2.2 Hz로 낮춰 한 번 씹을 때 생기는 짧은 보조 봉우리를 덜 센다.
    private let lpBeta = 0.7585
    private var lpState: Double = 0

    // 3-sample sliding window for local-max peak detection (1-sample lag)
    private var f0: Double = 0
    private var f1: Double = 0

    private var sampleCount: Int = 0
    private var lastPeakSample: Int = 0
    // 0.64 s at 50 Hz — 한 번 씹을 때 여러 피크가 생기는 과카운트를 줄인다.
    private let minPeakGap = 32
    // Filters idle sensor noise floor; tune down if micro-chewing is suppressed,
    // up if non-eating motion contributes false positives.
    private let minPeakAmplitude: Double = 0.006
    // Heading-motion guard: rotation magnitude above this threshold (rad/s) indicates
    // a deliberate head turn/nod rather than a jaw chew — peaks are suppressed.
    private let headingMotionThreshold: Double = 0.12
    private var chewingStateDetector = ChewingStateDetector()

    private(set) var isChewing: Bool = false
    private(set) var chewCount: Int = 0
    private(set) var chewTimestamps: [Double] = []
    private(set) var chewAmplitudes: [Double] = []
    // 세션 통계용: ChewingStateDetector가 씹기 상태로 판단한 누적 샘플 수(/50 = 초).
    private var chewingSamples: Int = 0

    func setChewing(_ chewing: Bool) {
        isChewing = chewing
    }

    func feed(rotX: Double, rotY: Double, rotZ: Double) {
        feed(rotX: rotX, rotY: rotY, rotZ: rotZ, accelX: 0, accelY: 0, accelZ: 0)
    }

    func feed(
        rotX: Double,
        rotY: Double,
        rotZ: Double,
        accelX: Double,
        accelY: Double,
        accelZ: Double
    ) {
        sampleCount += 1
        let chewingState = chewingStateDetector.feed(
            rotX: rotX,
            rotY: rotY,
            rotZ: rotZ,
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ
        )
        if chewingState.isChewing { chewingSamples += 1 }

        // Heading-motion guard: large rotation across any axis = head turn/nod, not a chew.
        let rotMag = (rotX * rotX + rotY * rotY + rotZ * rotZ).squareRoot()
        if rotMag > headingMotionThreshold {
            f0 = 0; f1 = 0  // reset sliding window to prevent phantom peaks after motion
            return
        }

        // High-pass (removes DC / slow head-pose drift)
        let hp = hpAlpha * (hpPrev + rotY - hpPrevInput)
        hpPrevInput = rotY
        hpPrev = hp

        // Low-pass (removes high-frequency noise / impact spikes)
        lpState = lpBeta * lpState + (1 - lpBeta) * hp
        let f2 = lpState

        defer { f0 = f1; f1 = f2 }

        guard sampleCount >= 3 else { return }

        // f1 is a local maximum: f1 > f0, f1 > f2, above zero (one chew oscillation peak).
        // ML `isChewing` gate removed — ML missed micro-chewing (closed-mouth teeth tapping).
        // 단발 피크는 버리고, 짧은 시간 동안 씹기형 신호가 지속될 때만 카운트한다.
        if f1 > f0 &&
            f1 > f2 &&
            f1 > minPeakAmplitude &&
            (sampleCount - lastPeakSample) >= minPeakGap &&
            chewingState.isChewing {
            chewCount += 1
            chewTimestamps.append(Double(sampleCount) / 50.0)
            chewAmplitudes.append(f1)
            lastPeakSample = sampleCount
        }
    }

    func reset() {
        hpPrev = 0; hpPrevInput = 0; lpState = 0
        f0 = 0; f1 = 0
        chewingStateDetector.reset()
        sampleCount = 0; lastPeakSample = 0
        chewCount = 0; isChewing = false
        chewingSamples = 0
        chewTimestamps.removeAll()
        chewAmplitudes.removeAll()
    }

    func snapshot() -> ChewCounterSnapshot {
        ChewCounterSnapshot(
            chewCount: chewCount,
            chewTimestamps: chewTimestamps,
            chewAmplitudes: chewAmplitudes,
            avgInterval: avgInterval,
            intervalStd: intervalStd,
            intervalCV: intervalCV
        )
    }

    // inter-chew intervals (N-1개)
    var chewIntervals: [Double] {
        guard chewTimestamps.count > 1 else { return [] }
        return zip(chewTimestamps, chewTimestamps.dropFirst()).map { $1 - $0 }.filter { $0 <= 2.0 }
    }

    // 평균 씹기 간격 (초)
    var avgInterval: Double {
        let ivs = chewIntervals
        guard !ivs.isEmpty else { return 0 }
        return ivs.reduce(0, +) / Double(ivs.count)
    }

    // 표준편차 (초)
    var intervalStd: Double {
        let ivs = chewIntervals
        guard ivs.count > 1 else { return 0 }
        let mean = avgInterval
        return (ivs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(ivs.count)).squareRoot()
    }

    // 변동계수 (CV) — 리듬 규칙성 지표 (낮을수록 규칙적)
    var intervalCV: Double {
        avgInterval > 0 ? intervalStd / avgInterval : 0
    }

    /// 세션 종료 시 chewing_session 분석 5필드를 산출한다(ML SessionStatsBuilder 대체).
    /// chewing/rest 초는 ChewingStateDetector가 씹기로 판단한 샘플 비율(50Hz 가정)로,
    /// estimatedTotalChews는 DSP 피크 카운트로 채운다.
    func sessionStats(modelVersion: String) -> SessionStats {
        let chewingSeconds = Double(chewingSamples) / 50.0
        let restSeconds = Double(max(0, sampleCount - chewingSamples)) / 50.0
        let fraction = sampleCount > 0 ? Double(chewingSamples) / Double(sampleCount) : 0
        return SessionStats(
            chewingSeconds: chewingSeconds,
            restSeconds: restSeconds,
            chewingFraction: fraction,
            estimatedTotalChews: chewCount,
            modelVersion: modelVersion
        )
    }
}

/// 세션 종료 시 산출된 분석 통계. `ChewingSessionDTO`의 5개 분석 필드와 1:1 매핑.
struct SessionStats: Sendable, Equatable {
    let chewingSeconds: Double
    let restSeconds: Double
    let chewingFraction: Double
    let estimatedTotalChews: Int
    let modelVersion: String
}

private struct ChewingState {
    let isChewing: Bool
}

private struct ChewingStateDetector {
    private var rotationXOneToFive = BiquadBandpass(lowCutHz: 1.0, highCutHz: 5.0)
    private var rotationYOneToFive = BiquadBandpass(lowCutHz: 1.0, highCutHz: 5.0)
    private var rotationZOneToFive = BiquadBandpass(lowCutHz: 1.0, highCutHz: 5.0)

    private var rotationXJitterBand = BiquadBandpass(lowCutHz: 2.5, highCutHz: 8.0)
    private var rotationYJitterBand = BiquadBandpass(lowCutHz: 2.5, highCutHz: 8.0)
    private var rotationZJitterBand = BiquadBandpass(lowCutHz: 2.5, highCutHz: 8.0)
    private var accelXJitterBand = BiquadBandpass(lowCutHz: 2.5, highCutHz: 8.0)
    private var accelYJitterBand = BiquadBandpass(lowCutHz: 2.5, highCutHz: 8.0)
    private var accelZJitterBand = BiquadBandpass(lowCutHz: 2.5, highCutHz: 8.0)

    private var rotationXOneToFiveEnergy = 0.0
    private var rotationYOneToFiveEnergy = 0.0
    private var rotationZOneToFiveEnergy = 0.0
    private var rotationXJitterBandEnergy = 0.0
    private var rotationYJitterBandEnergy = 0.0
    private var rotationZJitterBandEnergy = 0.0
    private var accelXJitterBandEnergy = 0.0
    private var accelYJitterBandEnergy = 0.0
    private var accelZJitterBandEnergy = 0.0

    private var rotationYMean = 0.0
    private var rotationYVariance = 0.0
    private var consecutiveChewingLikeSamples = 0
    private var consecutiveNonChewingLikeSamples = 0
    private var isChewing = false

    // 0.8초 EWMA: 너무 짧은 단발 피크는 버리고, 2초 안팎의 지속 신호는 빠르게 따라간다.
    private let featureAlpha = exp(-1.0 / (50.0 * 0.8))
    // 게이트 임계값 — 2026-06-28 실기기 튜닝으로 과소카운트 해결을 위해 완화한 최적값.
    // 원본의 빡빡한 우세도 게이트가 실제 씹기를 진동으로 오판해 버리던 걸 푼 결과다.
    private let minimumRotationYStd = 0.030
    private let minimumRotationYDominance = 0.15
    private let minimumRotationYJitterBandDominance = 0.15
    private let maximumAccelToRotation = 0.050
    private let hardJitterAccelToRotation = 0.060
    private let enterSampleCount = 10
    private let exitSampleCount = 90
    private let epsilon = 1e-12

    mutating func feed(
        rotX: Double,
        rotY: Double,
        rotZ: Double,
        accelX: Double,
        accelY: Double,
        accelZ: Double
    ) -> ChewingState {
        let delta = rotY - rotationYMean
        rotationYMean += (1 - featureAlpha) * delta
        rotationYVariance = featureAlpha * (rotationYVariance + (1 - featureAlpha) * delta * delta)

        rotationXOneToFiveEnergy = smoothEnergy(rotationXOneToFive.feed(rotX), previous: rotationXOneToFiveEnergy)
        rotationYOneToFiveEnergy = smoothEnergy(rotationYOneToFive.feed(rotY), previous: rotationYOneToFiveEnergy)
        rotationZOneToFiveEnergy = smoothEnergy(rotationZOneToFive.feed(rotZ), previous: rotationZOneToFiveEnergy)

        rotationXJitterBandEnergy = smoothEnergy(rotationXJitterBand.feed(rotX), previous: rotationXJitterBandEnergy)
        rotationYJitterBandEnergy = smoothEnergy(rotationYJitterBand.feed(rotY), previous: rotationYJitterBandEnergy)
        rotationZJitterBandEnergy = smoothEnergy(rotationZJitterBand.feed(rotZ), previous: rotationZJitterBandEnergy)
        accelXJitterBandEnergy = smoothEnergy(accelXJitterBand.feed(accelX), previous: accelXJitterBandEnergy)
        accelYJitterBandEnergy = smoothEnergy(accelYJitterBand.feed(accelY), previous: accelYJitterBandEnergy)
        accelZJitterBandEnergy = smoothEnergy(accelZJitterBand.feed(accelZ), previous: accelZJitterBandEnergy)

        let rotationOneToFiveEnergy = rotationXOneToFiveEnergy +
            rotationYOneToFiveEnergy +
            rotationZOneToFiveEnergy
        let rotationJitterBandEnergy = rotationXJitterBandEnergy +
            rotationYJitterBandEnergy +
            rotationZJitterBandEnergy
        let accelJitterBandEnergy = accelXJitterBandEnergy +
            accelYJitterBandEnergy +
            accelZJitterBandEnergy

        let rotationYStd = rotationYVariance.squareRoot()
        let rotationYDominance = rotationYOneToFiveEnergy / (rotationOneToFiveEnergy + epsilon)
        let rotationYJitterBandDominance = rotationYJitterBandEnergy / (rotationJitterBandEnergy + epsilon)
        let accelToRotation = accelJitterBandEnergy / (rotationJitterBandEnergy + epsilon)
        let hardJitterLike = accelToRotation >= hardJitterAccelToRotation
        let chewingLike = rotationYStd >= minimumRotationYStd &&
            rotationYDominance >= minimumRotationYDominance &&
            rotationYJitterBandDominance >= minimumRotationYJitterBandDominance &&
            accelToRotation <= maximumAccelToRotation

        if hardJitterLike {
            isChewing = false
            consecutiveChewingLikeSamples = 0
            consecutiveNonChewingLikeSamples = exitSampleCount
        } else if chewingLike {
            consecutiveChewingLikeSamples += 1
            consecutiveNonChewingLikeSamples = 0
        } else {
            consecutiveNonChewingLikeSamples += 1
            consecutiveChewingLikeSamples = 0
        }

        if !isChewing && consecutiveChewingLikeSamples >= enterSampleCount {
            isChewing = true
        }
        if isChewing && consecutiveNonChewingLikeSamples >= exitSampleCount {
            isChewing = false
        }

        return ChewingState(isChewing: isChewing)
    }

    mutating func reset() {
        self = ChewingStateDetector()
    }

    private func smoothEnergy(_ value: Double, previous: Double) -> Double {
        featureAlpha * previous + (1 - featureAlpha) * value * value
    }
}

private struct BiquadBandpass {
    private let b0: Double
    private let b1: Double
    private let b2: Double
    private let a1: Double
    private let a2: Double

    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    init(lowCutHz: Double, highCutHz: Double, sampleRateHz: Double = 50.0) {
        let centerHz = (lowCutHz * highCutHz).squareRoot()
        let q = centerHz / (highCutHz - lowCutHz)
        let omega = 2 * Double.pi * centerHz / sampleRateHz
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha

        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
        a1 = (-2 * cos(omega)) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func feed(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

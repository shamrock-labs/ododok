import Foundation

struct ChewCounterSnapshot: Sendable {
    let chewCount: Int
    let chewTimestamps: [Double]
    let chewAmplitudes: [Double]
    let avgInterval: Double
    let intervalStd: Double
    let intervalCV: Double
}

/// 씹기 감지 튜닝 다이얼. 각 임계값을 직접 조절한다(디버그 슬라이더).
/// 이전엔 우세도·accel/rotation 게이트를 "진동거부 뼈대"라며 고정했지만, 민감도 최대에서도
/// 과소카운트가 재현돼 게이트 자체를 의심하게 됐다 — 그래서 우세도까지 전부 노출한다.
/// `bypassChewingGate`는 게이트(isChewing)를 무시하고 봉우리만으로 센다(진단·원인격리용).
struct ChewSensitivity: Sendable, Equatable, Codable {
    // 피크 카운팅
    var minPeakAmplitude: Double
    var minPeakGap: Int
    var headingMotionThreshold: Double
    // 씹기 상태 게이트 — 진입/종료 지속
    var minimumRotationYStd: Double
    var enterSampleCount: Int
    var exitSampleCount: Int
    // 씹기 상태 게이트 — 진동거부 우세도(이전 고정값, 이제 조절 가능)
    var minimumRotationYDominance: Double
    var minimumRotationYJitterBandDominance: Double
    var maximumAccelToRotation: Double
    // 진단: 게이트를 무시하고 봉우리만으로 카운트(원인이 게이트인지 봉우리인지 격리)
    var bypassChewingGate: Bool

    /// 실기기 튜닝 최적값(2026-06-28, docs/chew-tuning.md). 게이트 3조건을 크게 완화한
    /// 값 — 원본의 빡빡한 우세도 게이트가 실제 씹기를 버려 과소카운트가 났던 걸 푼 결과다.
    static let defaults = ChewSensitivity(
        minPeakAmplitude: 0.006,
        minPeakGap: 32,
        headingMotionThreshold: 0.12,
        minimumRotationYStd: 0.030,
        enterSampleCount: 10,
        exitSampleCount: 90,
        minimumRotationYDominance: 0.15,
        minimumRotationYJitterBandDominance: 0.15,
        maximumAccelToRotation: 0.050,
        bypassChewingGate: false
    )
}

/// 실시간 진단 스냅샷 — "왜 0인지"를 화면에 띄우기 위한 계측값.
struct ChewDiagnostics: Sendable {
    let sampleCount: Int
    let chewCount: Int
    /// 게이트 무시, 봉우리 조건만 충족한 누적 수. chewCount와 차이가 크면 게이트가 범인.
    let rawPeakCount: Int
    let isChewing: Bool
    let chewingFraction: Double
    /// heading guard로 버려진 샘플 수. 크면 머리 움직임이 과잉 차단 중.
    let headingBlockedCount: Int
    // 최근 게이트 입력값 (chewingLike 판정 근거)
    let rotationYStd: Double
    let rotationYDominance: Double
    let rotationYJitterBandDominance: Double
    let accelToRotation: Double
    let chewingLike: Bool
    let hardJitterLike: Bool
    let lastRotMag: Double
}

/// Real-time chew counter using a band-pass IIR filter (0.5–3 Hz) + peak detection.
/// 최근 신호가 씹기 상태로 판단될 때만 후보 피크를 카운트한다.
actor ChewCounter {

    // 1st-order IIR high-pass: y[n] = α*(y[n-1] + x[n] - x[n-1]), fc=0.5 Hz @ 50 Hz
    private let hpAlpha = 0.9391
    private var hpPrev: Double = 0
    private var hpPrevInput: Double = 0

    // 1st-order IIR low-pass, fc≈2.2 Hz
    private let lpBeta = 0.7585
    private var lpState: Double = 0

    // 3-sample sliding window for local-max peak detection (1-sample lag)
    private var f0: Double = 0
    private var f1: Double = 0

    private var sampleCount: Int = 0
    private var lastPeakSample: Int = 0
    private var lastRawPeakSample: Int = 0
    private var sensitivity: ChewSensitivity
    private var chewingStateDetector = ChewingStateDetector()

    private(set) var isChewing: Bool = false
    private(set) var chewCount: Int = 0
    private(set) var chewTimestamps: [Double] = []
    private(set) var chewAmplitudes: [Double] = []
    private var chewingSamples: Int = 0

    // 진단 누적/최근값
    private var rawPeakCount: Int = 0
    private var headingBlockedCount: Int = 0
    private var lastIsChewing = false
    private var lastRotationYStd: Double = 0
    private var lastRotationYDominance: Double = 0
    private var lastRotationYJitterBandDominance: Double = 0
    private var lastAccelToRotation: Double = 0
    private var lastChewingLike = false
    private var lastHardJitterLike = false
    private var lastRotMag: Double = 0

    init(sensitivity: ChewSensitivity = .defaults) {
        self.sensitivity = sensitivity
    }

    /// 측정 중 슬라이더로 튜닝을 바꿀 때 호출. 다음 샘플부터 즉시 반영된다.
    func setSensitivity(_ sensitivity: ChewSensitivity) {
        self.sensitivity = sensitivity
    }

    var currentSensitivity: ChewSensitivity { sensitivity }

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
            accelZ: accelZ,
            minimumRotationYStd: sensitivity.minimumRotationYStd,
            minimumRotationYDominance: sensitivity.minimumRotationYDominance,
            minimumRotationYJitterBandDominance: sensitivity.minimumRotationYJitterBandDominance,
            maximumAccelToRotation: sensitivity.maximumAccelToRotation,
            enterSampleCount: sensitivity.enterSampleCount,
            exitSampleCount: sensitivity.exitSampleCount
        )
        if chewingState.isChewing { chewingSamples += 1 }

        // 진단: 게이트 입력값 저장(heading guard로 return하더라도 직전 값은 남긴다)
        lastIsChewing = chewingState.isChewing
        lastRotationYStd = chewingState.rotationYStd
        lastRotationYDominance = chewingState.rotationYDominance
        lastRotationYJitterBandDominance = chewingState.rotationYJitterBandDominance
        lastAccelToRotation = chewingState.accelToRotation
        lastChewingLike = chewingState.chewingLike
        lastHardJitterLike = chewingState.hardJitterLike

        // Heading-motion guard: large rotation across any axis = head turn/nod, not a chew.
        let rotMag = (rotX * rotX + rotY * rotY + rotZ * rotZ).squareRoot()
        lastRotMag = rotMag
        if rotMag > sensitivity.headingMotionThreshold {
            headingBlockedCount += 1
            f0 = 0; f1 = 0
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

        // f1 is a local maximum above the noise floor (one chew oscillation peak).
        let shape = f1 > f0 && f1 > f2 && f1 > sensitivity.minPeakAmplitude

        // 진단용: 게이트를 무시하고 봉우리만으로 카운트(독립 gap). chewCount와 비교해
        // "게이트가 범인인지(둘 차이 큼) 봉우리가 안 생기는지(둘 다 0)"를 가른다.
        if shape && (sampleCount - lastRawPeakSample) >= sensitivity.minPeakGap {
            rawPeakCount += 1
            lastRawPeakSample = sampleCount
        }

        // 실제 카운트: 봉우리 + 게이트(isChewing). bypass면 게이트 무시.
        let gateOpen = sensitivity.bypassChewingGate || chewingState.isChewing
        if shape && (sampleCount - lastPeakSample) >= sensitivity.minPeakGap && gateOpen {
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
        sampleCount = 0; lastPeakSample = 0; lastRawPeakSample = 0
        chewCount = 0; isChewing = false
        chewingSamples = 0
        rawPeakCount = 0; headingBlockedCount = 0
        lastIsChewing = false
        lastRotationYStd = 0; lastRotationYDominance = 0
        lastRotationYJitterBandDominance = 0; lastAccelToRotation = 0
        lastChewingLike = false; lastHardJitterLike = false; lastRotMag = 0
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

    func diagnostics() -> ChewDiagnostics {
        ChewDiagnostics(
            sampleCount: sampleCount,
            chewCount: chewCount,
            rawPeakCount: rawPeakCount,
            isChewing: lastIsChewing,
            chewingFraction: sampleCount > 0 ? Double(chewingSamples) / Double(sampleCount) : 0,
            headingBlockedCount: headingBlockedCount,
            rotationYStd: lastRotationYStd,
            rotationYDominance: lastRotationYDominance,
            rotationYJitterBandDominance: lastRotationYJitterBandDominance,
            accelToRotation: lastAccelToRotation,
            chewingLike: lastChewingLike,
            hardJitterLike: lastHardJitterLike,
            lastRotMag: lastRotMag
        )
    }

    // inter-chew intervals (N-1개)
    var chewIntervals: [Double] {
        guard chewTimestamps.count > 1 else { return [] }
        return zip(chewTimestamps, chewTimestamps.dropFirst()).map { $1 - $0 }.filter { $0 <= 2.0 }
    }

    var avgInterval: Double {
        let ivs = chewIntervals
        guard !ivs.isEmpty else { return 0 }
        return ivs.reduce(0, +) / Double(ivs.count)
    }

    var intervalStd: Double {
        let ivs = chewIntervals
        guard ivs.count > 1 else { return 0 }
        let mean = avgInterval
        return (ivs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(ivs.count)).squareRoot()
    }

    var intervalCV: Double {
        avgInterval > 0 ? intervalStd / avgInterval : 0
    }

    /// 세션 종료 시 chewing_session 분석 5필드를 산출한다.
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
    let rotationYStd: Double
    let rotationYDominance: Double
    let rotationYJitterBandDominance: Double
    let accelToRotation: Double
    let chewingLike: Bool
    let hardJitterLike: Bool
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

    // 0.8초 EWMA. 진입/종료 지속 및 우세도 임계값은 ChewSensitivity에서 feed 인자로 주입.
    private let featureAlpha = exp(-1.0 / (50.0 * 0.8))
    private let epsilon = 1e-12

    mutating func feed(
        rotX: Double,
        rotY: Double,
        rotZ: Double,
        accelX: Double,
        accelY: Double,
        accelZ: Double,
        minimumRotationYStd: Double,
        minimumRotationYDominance: Double,
        minimumRotationYJitterBandDominance: Double,
        maximumAccelToRotation: Double,
        enterSampleCount: Int,
        exitSampleCount: Int
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
        // hard-jitter 차단선은 허용 상한보다 약간 위. 상한을 올리면 같이 따라 올라간다.
        let hardJitterAccelToRotation = maximumAccelToRotation + 0.010
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

        return ChewingState(
            isChewing: isChewing,
            rotationYStd: rotationYStd,
            rotationYDominance: rotationYDominance,
            rotationYJitterBandDominance: rotationYJitterBandDominance,
            accelToRotation: accelToRotation,
            chewingLike: chewingLike,
            hardJitterLike: hardJitterLike
        )
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

import Foundation

struct ChewDetectionSnapshot: Sendable, Equatable {
    let chewCount: Int
    let chewTimestamps: [Double]
    let chewAmplitudes: [Double]
    let avgInterval: Double
    let intervalStd: Double
    let intervalCV: Double
}

struct ChewDetectionEvent: Sendable, Equatable {
    let count: Int
    let timestamp: Double
    let amplitude: Double
}

struct ChewDetectionSample {
    let timestamp: TimeInterval
    let rotX: Double
    let rotY: Double
    let rotZ: Double
    let accelX: Double
    let accelY: Double
    let accelZ: Double
}

struct ChewPeak: Equatable {
    let timestamp: TimeInterval
    let amplitude: Double
}

struct ChewDetectionConfiguration: Sendable, Equatable {
    let minPeakAmplitude: Double

    static let standard = ChewDetectionConfiguration(minPeakAmplitude: 0.006)
}

/// Guided calibration reads the same filtered rotation-Y peaks as the counter,
/// but deliberately skips the activity gate and count confirmation rules.
actor ChewPeakAmplitudeProbe {
    private let hpAlpha = 0.9391
    private let lpBeta = 0.7585
    private let headingMotionThreshold = 0.12

    private var hpPrevious = 0.0
    private var hpPreviousInput = 0.0
    private var lowPassState = 0.0
    private var previousFiltered = 0.0
    private var currentFiltered = 0.0
    private var currentTimestamp: TimeInterval?
    private var firstTimestamp: TimeInterval?
    private var lastInputTimestamp: TimeInterval?
    private var peakCount = 0

    func feed(_ input: ChewDetectionSample) -> ChewDetectionEvent? {
        guard lastInputTimestamp.map({ input.timestamp > $0 }) ?? true else { return nil }
        lastInputTimestamp = input.timestamp
        firstTimestamp = firstTimestamp ?? input.timestamp

        let rotationMagnitude = (
            input.rotX * input.rotX +
                input.rotY * input.rotY +
                input.rotZ * input.rotZ
        ).squareRoot()
        guard rotationMagnitude <= headingMotionThreshold else {
            previousFiltered = 0
            currentFiltered = 0
            currentTimestamp = nil
            return nil
        }

        let highPass = hpAlpha * (hpPrevious + input.rotY - hpPreviousInput)
        hpPreviousInput = input.rotY
        hpPrevious = highPass
        lowPassState = lpBeta * lowPassState + (1 - lpBeta) * highPass
        let nextFiltered = lowPassState

        defer {
            previousFiltered = currentFiltered
            currentFiltered = nextFiltered
            currentTimestamp = input.timestamp
        }

        guard currentFiltered > previousFiltered,
              currentFiltered > nextFiltered,
              currentFiltered > 0,
              let peakTimestamp = currentTimestamp else { return nil }

        peakCount += 1
        return ChewDetectionEvent(
            count: peakCount,
            timestamp: peakTimestamp - (firstTimestamp ?? peakTimestamp),
            amplitude: currentFiltered
        )
    }
}

private struct PeakWindowCandidate {
    let windowStartedAt: TimeInterval
    var strongestPeak: ChewPeak
}

struct RepresentativePeakWindow {
    private let windowDuration: TimeInterval
    private var activeCandidate: PeakWindowCandidate?

    init(windowDuration: TimeInterval = 0.30) {
        self.windowDuration = windowDuration
    }

    mutating func collect(_ peak: ChewPeak) -> ChewPeak? {
        guard var current = activeCandidate else {
            activeCandidate = PeakWindowCandidate(windowStartedAt: peak.timestamp, strongestPeak: peak)
            return nil
        }

        guard peak.timestamp - current.windowStartedAt < windowDuration else {
            activeCandidate = PeakWindowCandidate(windowStartedAt: peak.timestamp, strongestPeak: peak)
            return current.strongestPeak
        }

        if peak.amplitude > current.strongestPeak.amplitude {
            current.strongestPeak = peak
            activeCandidate = current
        }
        return nil
    }

    mutating func flushIfExpired(at timestamp: TimeInterval) -> ChewPeak? {
        guard let current = activeCandidate,
              timestamp - current.windowStartedAt >= windowDuration else {
            return nil
        }
        activeCandidate = nil
        return current.strongestPeak
    }

    mutating func flush() -> ChewPeak? {
        defer { activeCandidate = nil }
        return activeCandidate?.strongestPeak
    }

    mutating func reset() {
        activeCandidate = nil
    }
}

/// Real-time chew counter using a band-pass IIR filter (0.5–3 Hz) + peak detection.
///
/// Feed every raw IMU sample via `feed(_:)`.
/// `isChewingGateOpen`은 feed()가 DSP 활동 Gate 출력을 매 샘플 반영한다.
/// keep-alive 신호등 톤 등 외부가 "현재 peak를 셀 수 있는 구간인지"를 읽는 단일 통로다.
/// 최근 신호가 씹기 상태로 판단될 때만 후보 피크를 카운트한다.
actor ChewDetectionEngine {
    static let modelVersion = "dsp-chewcounter-2"

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
    private var firstTimestamp: TimeInterval?
    private var lastInputTimestamp: TimeInterval?
    private var f1Timestamp: TimeInterval?
    private var lastPeakTimestamp: TimeInterval?
    private var peakSelectionWindow = RepresentativePeakWindow()
    private let minPeakGapSeconds: TimeInterval = 0.32
    // Filters idle sensor noise floor. 온보딩 로컬 실험은 configuration으로 사용자별 값을 주입한다.
    private let configuration: ChewDetectionConfiguration
    // Heading-motion guard: rotation magnitude above this threshold (rad/s) indicates
    // a deliberate head turn/nod rather than a jaw chew — peaks are suppressed.
    private let headingMotionThreshold: Double = 0.12
    private var chewingActivityGate = ChewingActivityGate()
    private var isSessionFinished = false

    // 지속 씹기 알림: ChewingActivityGate가 열린 상태가 3초(150샘플 @50Hz) 이어질 때마다
    // handler를 1회 호출하고 누적을 0으로 되돌린다. 계속 씹으면 3초 간격으로 반복 발화.
    // 씹기 상태가 풀리면(detector exit) 누적도 리셋 — 3초 미만 구간은 발화하지 않는다.
    private let sustainedAlertSamples = 150
    private var sustainedChewingSamples = 0
    private var onSustainedChewing: (@Sendable () -> Void)?

    private(set) var isChewingGateOpen: Bool = false
    private(set) var confirmedChewCount: Int = 0
    private(set) var chewTimestamps: [Double] = []
    private(set) var chewAmplitudes: [Double] = []
    // 세션 통계용: ChewingActivityGate가 열린 누적 샘플 수(/50 = 초).
    private var chewingSamples: Int = 0
    // 저작 타임라인: 1초(50샘플) 버킷마다 isChewing 과반을 '1'/'0'로 누적한다.
    // 서버 chewing_session.chewing_timeline 칼럼(문자열 인덱스 = 경과 초)과 1:1.
    private var timelineAccumulator = ChewingTimelineAccumulator()

    init(configuration: ChewDetectionConfiguration = .standard) {
        self.configuration = configuration
    }

    /// 씹기 3초 지속마다 호출될 handler 등록. actor 밖(오디오 등)으로 신호를 보내는 유일한 통로.
    func setSustainedChewingHandler(_ handler: (@Sendable () -> Void)?) {
        onSustainedChewing = handler
    }

    @discardableResult
    func feed(_ input: ChewDetectionSample) -> ChewDetectionEvent? {
        guard !isSessionFinished else { return nil }
        let timestamp = input.timestamp
        guard lastInputTimestamp.map({ timestamp > $0 }) ?? true else { return nil }
        firstTimestamp = firstTimestamp ?? timestamp
        lastInputTimestamp = timestamp
        sampleCount += 1
        let gateState = chewingActivityGate.feed(input)
        if gateState.isOpen { chewingSamples += 1 }
        isChewingGateOpen = gateState.isOpen
        // 지속 씹기 알림 누적 — 3초(150샘플)마다 발화 후 리셋, 씹기 끊기면 리셋.
        if gateState.isOpen {
            sustainedChewingSamples += 1
            if sustainedChewingSamples >= sustainedAlertSamples {
                sustainedChewingSamples = 0
                onSustainedChewing?()
            }
        } else {
            sustainedChewingSamples = 0
        }
        // 초당 타임라인은 sampleCount·chewingSamples와 동일 시점에 누적한다(heading-guard return 이전).
        timelineAccumulator.feed(isChewing: gateState.isOpen)

        // Heading-motion guard: large rotation across any axis = head turn/nod, not a chew.
        let rotMag = (
            input.rotX * input.rotX +
                input.rotY * input.rotY +
                input.rotZ * input.rotZ
        ).squareRoot()
        if rotMag > headingMotionThreshold {
            f0 = 0; f1 = 0  // reset sliding window to prevent phantom peaks after motion
            f1Timestamp = nil
            peakSelectionWindow.reset()
            return nil
        }

        let expiredPeakEvent = finalizePeakCandidateIfNeeded(at: timestamp)

        // High-pass (removes DC / slow head-pose drift)
        let hp = hpAlpha * (hpPrev + input.rotY - hpPrevInput)
        hpPrevInput = input.rotY
        hpPrev = hp

        // Low-pass (removes high-frequency noise / impact spikes)
        lpState = lpBeta * lpState + (1 - lpBeta) * hp
        let f2 = lpState

        defer {
            f0 = f1
            f1 = f2
            f1Timestamp = timestamp
        }

        guard sampleCount >= 3 else {
            return expiredPeakEvent
        }

        // f1 is a local maximum: f1 > f0, f1 > f2, above zero (one chew oscillation peak).
        // 단발 피크는 버리고, 짧은 시간 동안 씹기형 신호가 지속될 때만 카운트한다.
        let isLocalPeakCandidate = f1 > f0 && f1 > f2 && f1 > configuration.minPeakAmplitude
        guard isLocalPeakCandidate, gateState.isOpen, let peakTimestamp = f1Timestamp else {
            return expiredPeakEvent
        }
        return collectPeak(ChewPeak(timestamp: peakTimestamp, amplitude: f1)) ?? expiredPeakEvent
    }

    func reset() {
        hpPrev = 0; hpPrevInput = 0; lpState = 0
        f0 = 0; f1 = 0
        f1Timestamp = nil
        chewingActivityGate.reset()
        sampleCount = 0
        firstTimestamp = nil; lastInputTimestamp = nil; lastPeakTimestamp = nil
        peakSelectionWindow.reset()
        confirmedChewCount = 0; isChewingGateOpen = false
        isSessionFinished = false
        chewingSamples = 0
        sustainedChewingSamples = 0
        onSustainedChewing = nil
        timelineAccumulator.reset()
        chewTimestamps.removeAll()
        chewAmplitudes.removeAll()
    }

    func snapshot() -> ChewDetectionSnapshot {
        ChewDetectionSnapshot(
            chewCount: confirmedChewCount,
            chewTimestamps: chewTimestamps,
            chewAmplitudes: chewAmplitudes,
            avgInterval: avgInterval,
            intervalStd: intervalStd,
            intervalCV: intervalCV
        )
    }

    /// 입력 Queue가 모두 비워진 뒤 마지막 peak 후보를 한 번만 확정한다.
    @discardableResult
    func finishSession() -> ChewDetectionEvent? {
        guard !isSessionFinished else { return nil }
        isSessionFinished = true
        return finalizePeakCandidate()
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

    /// 세션 종료 시 chewing_session 분석 6필드를 산출한다.
    /// chewing/rest 초는 ChewingActivityGate가 열린 샘플 비율(50Hz 가정)로,
    /// estimatedTotalChews는 DSP 피크 카운트로, chewingTimeline은 1초 버킷 과반으로 채운다.
    func sessionStats() -> SessionStats {
        let chewingSeconds = Double(chewingSamples) / 50.0
        let restSeconds = Double(max(0, sampleCount - chewingSamples)) / 50.0
        let fraction = sampleCount > 0 ? Double(chewingSamples) / Double(sampleCount) : 0
        return SessionStats(
            chewingSeconds: chewingSeconds,
            restSeconds: restSeconds,
            chewingFraction: fraction,
            estimatedTotalChews: confirmedChewCount,
            modelVersion: Self.modelVersion,
            chewingTimeline: timelineAccumulator.makeTimeline()
        )
    }

    private func collectPeak(_ peak: ChewPeak) -> ChewDetectionEvent? {
        if let lastPeakTimestamp,
           peak.timestamp - lastPeakTimestamp < minPeakGapSeconds {
            return nil
        }

        guard let selected = peakSelectionWindow.collect(peak) else { return nil }
        return confirmChew(selected)
    }

    private func finalizePeakCandidateIfNeeded(at timestamp: TimeInterval) -> ChewDetectionEvent? {
        guard let selected = peakSelectionWindow.flushIfExpired(at: timestamp) else { return nil }
        return confirmChew(selected)
    }

    private func finalizePeakCandidate() -> ChewDetectionEvent? {
        guard let selected = peakSelectionWindow.flush() else { return nil }
        return confirmChew(selected)
    }

    private func confirmChew(_ peak: ChewPeak) -> ChewDetectionEvent? {
        if let lastPeakTimestamp,
           peak.timestamp - lastPeakTimestamp < minPeakGapSeconds {
            return nil
        }

        let relativeTimestamp = peak.timestamp - (firstTimestamp ?? peak.timestamp)
        confirmedChewCount += 1
        chewTimestamps.append(relativeTimestamp)
        chewAmplitudes.append(peak.amplitude)
        lastPeakTimestamp = peak.timestamp
        return ChewDetectionEvent(
            count: confirmedChewCount,
            timestamp: relativeTimestamp,
            amplitude: peak.amplitude
        )
    }
}

/// 세션 종료 시 산출된 분석 통계. `ChewingSessionDTO`의 6개 분석 필드와 1:1 매핑.
struct SessionStats: Sendable, Equatable {
    let chewingSeconds: Double
    let restSeconds: Double
    let chewingFraction: Double
    let estimatedTotalChews: Int
    let modelVersion: String
    let chewingTimeline: String?
}

/// 1초(50샘플) 버킷마다 isChewing 과반을 '1'/'0'로 누적해 chewing_timeline 문자열을 만든다.
/// 서버 chewing_session.chewing_timeline(문자열 인덱스 = 경과 초)과 1:1 — 한 초의 절반 초과면 '1'.
/// 상한 maxSeconds(기본 7200 = 2시간)를 넘는 초는 버려 서버 varchar(7200) 컬럼을 넘기지 않는다.
struct ChewingTimelineAccumulator {
    private let samplesPerSecond: Int
    private let maxSeconds: Int
    private var bucketSamples = 0
    private var bucketChewing = 0
    private var bytes: [UInt8] = []

    private static let asciiZero = UInt8(ascii: "0")
    private static let asciiOne = UInt8(ascii: "1")

    init(samplesPerSecond: Int = 50, maxSeconds: Int = 7200) {
        self.samplesPerSecond = samplesPerSecond
        self.maxSeconds = maxSeconds
    }

    /// 샘플 하나의 씹기 여부를 넣는다. 1초가 차면 과반 판정을 한 글자로 굳힌다.
    mutating func feed(isChewing: Bool) {
        bucketSamples += 1
        if isChewing { bucketChewing += 1 }
        guard bucketSamples >= samplesPerSecond else { return }
        if bytes.count < maxSeconds {
            bytes.append(majoritySymbol(chewing: bucketChewing, total: bucketSamples))
        }
        bucketSamples = 0
        bucketChewing = 0
    }

    /// 남은 부분 초까지 반영한 '0'/'1' 문자열. 한 샘플도 없으면 nil.
    func makeTimeline() -> String? {
        var result = bytes
        if bucketSamples > 0 && result.count < maxSeconds {
            result.append(majoritySymbol(chewing: bucketChewing, total: bucketSamples))
        }
        return result.isEmpty ? nil : String(bytes: result, encoding: .utf8)
    }

    mutating func reset() {
        bucketSamples = 0
        bucketChewing = 0
        bytes.removeAll()
    }

    private func majoritySymbol(chewing: Int, total: Int) -> UInt8 {
        chewing * 2 > total ? Self.asciiOne : Self.asciiZero
    }
}

private struct ChewingGateState {
    let isOpen: Bool
}

private struct ChewingActivityGate {
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
    private var matchingSampleStreak = 0
    private var nonMatchingSampleStreak = 0
    private var isOpen = false

    // 0.8초 EWMA: 너무 짧은 단발 피크는 버리고, 2초 안팎의 지속 신호는 빠르게 따라간다.
    private let featureAlpha = exp(-1.0 / (50.0 * 0.8))
    // 게이트 임계값 — 2026-06-28 실기기 튜닝으로 과소카운트 해결을 위해 완화한 최적값.
    // 원본의 빡빡한 우세도 게이트가 실제 씹기를 진동으로 오판해 버리던 걸 푼 결과다.
    private let minimumRotationYStd = 0.030
    private let minimumRotationYDominance = 0.15
    private let minimumRotationYJitterBandDominance = 0.15
    private let maximumAccelToRotation = 0.050
    private let hardJitterAccelToRotation = 0.060
    private let samplesRequiredToOpen = 10
    private let samplesRequiredToClose = 30
    private let epsilon = 1e-12

    mutating func feed(_ sample: ChewDetectionSample) -> ChewingGateState {
        let delta = sample.rotY - rotationYMean
        rotationYMean += (1 - featureAlpha) * delta
        rotationYVariance = featureAlpha * (rotationYVariance + (1 - featureAlpha) * delta * delta)
        updateFilteredEnergies(with: sample)

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
        let matchesChewingGate = rotationYStd >= minimumRotationYStd &&
            rotationYDominance >= minimumRotationYDominance &&
            rotationYJitterBandDominance >= minimumRotationYJitterBandDominance &&
            accelToRotation <= maximumAccelToRotation

        if hardJitterLike {
            isOpen = false
            matchingSampleStreak = 0
            nonMatchingSampleStreak = samplesRequiredToClose
        } else if matchesChewingGate {
            matchingSampleStreak += 1
            nonMatchingSampleStreak = 0
        } else {
            nonMatchingSampleStreak += 1
            matchingSampleStreak = 0
        }

        if !isOpen && matchingSampleStreak >= samplesRequiredToOpen {
            isOpen = true
        }
        if isOpen && nonMatchingSampleStreak >= samplesRequiredToClose {
            isOpen = false
        }

        return ChewingGateState(isOpen: isOpen)
    }

    mutating func reset() {
        self = ChewingActivityGate()
    }

    private mutating func updateFilteredEnergies(with sample: ChewDetectionSample) {
        rotationXOneToFiveEnergy = smoothEnergy(
            rotationXOneToFive.feed(sample.rotX), previous: rotationXOneToFiveEnergy
        )
        rotationYOneToFiveEnergy = smoothEnergy(
            rotationYOneToFive.feed(sample.rotY), previous: rotationYOneToFiveEnergy
        )
        rotationZOneToFiveEnergy = smoothEnergy(
            rotationZOneToFive.feed(sample.rotZ), previous: rotationZOneToFiveEnergy
        )
        rotationXJitterBandEnergy = smoothEnergy(
            rotationXJitterBand.feed(sample.rotX), previous: rotationXJitterBandEnergy
        )
        rotationYJitterBandEnergy = smoothEnergy(
            rotationYJitterBand.feed(sample.rotY), previous: rotationYJitterBandEnergy
        )
        rotationZJitterBandEnergy = smoothEnergy(
            rotationZJitterBand.feed(sample.rotZ), previous: rotationZJitterBandEnergy
        )
        accelXJitterBandEnergy = smoothEnergy(
            accelXJitterBand.feed(sample.accelX), previous: accelXJitterBandEnergy
        )
        accelYJitterBandEnergy = smoothEnergy(
            accelYJitterBand.feed(sample.accelY), previous: accelYJitterBandEnergy
        )
        accelZJitterBandEnergy = smoothEnergy(
            accelZJitterBand.feed(sample.accelZ), previous: accelZJitterBandEnergy
        )
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
        let qualityFactor = centerHz / (highCutHz - lowCutHz)
        let omega = 2 * Double.pi * centerHz / sampleRateHz
        let alpha = sin(omega) / (2 * qualityFactor)
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

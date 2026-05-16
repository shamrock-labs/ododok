import Foundation
import Observation
import CoreMotion

enum IMUWaveformSource: Equatable {
    case idle
    case simulator
    case connecting
    case live
    case demo
    case unavailable
    case denied
    case restricted
    case error(String)

    var statusText: String {
        switch self {
        case .idle:
            "식사 시작 시 파형 표시"
        case .simulator:
            "시뮬레이터 · 데모 파형"
        case .connecting:
            "AirPods IMU 연결 중"
        case .live:
            "AirPods IMU 수신 중"
        case .demo:
            "AirPods 없음 · 데모 파형"
        case .unavailable:
            "지원 AirPods 없음 · 데모 파형"
        case .denied:
            "모션 권한 필요 · 데모 파형"
        case .restricted:
            "모션 사용 제한됨 · 데모 파형"
        case .error:
            "IMU 수신 오류 · 데모 파형"
        }
    }

    var usesRealMotion: Bool {
        self == .live || self == .connecting
    }
}

/// 앱의 글로벌 상태 + 식사 세션 관리.
///
/// 현재 chew 신호는 `startEating()` 호출 시 가짜 Timer가 0.85초마다 `chew()`를
/// 흉내냄. 추후 AirPods Pro 2의 `CMHeadphoneMotionManager`를 붙이게 되면
/// `startFakeChewLoop()` 대신 실제 IMU 신호 → chew 추정 알고리즘으로 갈아끼우면 됨.
@Observable
final class AppState {
    private static let maxIMUWaveformSamples = 54
    private static let idleIMUWaveformSamples: [Double] = (0..<maxIMUWaveformSamples).map { i in
        0.05 + sin(Double(i) * 0.42) * 0.015
    }

    // MARK: - Persisted-ish state (현재는 인메모리)

    var chewCount: Int = 247
    var streak: Int = 7
    var points: Int = 1240
    var animKey: Int = 0
    var weeklyScores: [Int] = [72, 85, 68, 78, 82, 88, 41]

    // MARK: - Eating session

    /// 현재 식사 중인지 여부. 홈의 "식사 시작/종료" 버튼이 토글, 트래킹 탭이 관찰.
    var isEating: Bool = false

    /// 식사 시작 시각. 통계/지속시간 표시 등에 사용.
    @ObservationIgnored private(set) var eatingStartedAt: Date?

    /// 최근 60초 안의 chew 타임스탬프 (분당 저작 횟수 계산용).
    @ObservationIgnored private var chewTimestamps: [Date] = []

    /// 분당 저작 횟수. chew() 호출 시 갱신.
    var chewRatePerMinute: Int = 0

    /// 화면 표시용 최근 IMU 에너지 샘플. 원시 IMU 데이터는 저장하지 않음.
    var imuWaveformSamples: [Double] = AppState.idleIMUWaveformSamples
    var imuWaveformSource: IMUWaveformSource = .idle

    // MARK: - IMU diagnostics (원시 데이터는 저장 안 함, 진단 지표만)

    /// 현재 식사 세션에서 받은 실제 IMU 샘플 개수 (데모/페이크 timer는 카운트 X).
    var imuSampleCount: Int = 0

    /// 마지막으로 실제 IMU 샘플이 들어온 시각. 백그라운드 수집 검증용.
    var lastIMUSampleAt: Date?

    /// 앱 foreground 여부. scenePhase 관찰자가 갱신.
    var isInForeground: Bool = true

    /// 마지막으로 background로 전환된 시각. 백그라운드 체류 시간 표시용.
    var lastBackgroundedAt: Date?

    @ObservationIgnored private let headphoneMotionService = HeadphoneMotionService()
    @ObservationIgnored private var fakeChewTimer: Timer?
    @ObservationIgnored private var demoIMUWaveformTimer: Timer?
    @ObservationIgnored private var imuWaveformPhase: Double = 0
    @ObservationIgnored private var goalAlreadyHit = false

    // MARK: - Eating actions

    func startEating() {
        guard !isEating else { return }
        isEating = true
        eatingStartedAt = Date()
        // 새 세션 시작 시 IMU 진단 지표 리셋 — 백그라운드 수집 여부 검증에 깨끗한 기준 제공
        imuSampleCount = 0
        lastIMUSampleAt = nil
        startFakeChewLoop()

        if !startHeadphoneMotionLoop() {
            startDemoIMUWaveformLoop(source: imuWaveformSource)
        }
    }

    func stopEating() {
        guard isEating else { return }
        isEating = false
        eatingStartedAt = nil
        stopHeadphoneMotionLoop()
        stopFakeChewLoop()
        stopDemoIMUWaveformLoop()
        resetIMUWaveform()
        imuWaveformSource = .idle
        chewTimestamps.removeAll()
        chewRatePerMinute = 0
    }

    func toggleEating() {
        isEating ? stopEating() : startEating()
    }

    // MARK: - Chew (한 입 = 한 번의 저작 신호)

    /// 한 번의 chew 이벤트. 추후 실제 IMU 감지기가 호출할 진입점.
    func chew() {
        chewCount += 1
        points += 1
        animKey &+= 1

        let now = Date()
        chewTimestamps = chewTimestamps.filter { now.timeIntervalSince($0) < 60 }
        chewTimestamps.append(now)
        chewRatePerMinute = chewTimestamps.count

        if chewCount >= Constants.dailyGoal && !goalAlreadyHit {
            goalAlreadyHit = true
            points += 200
        }
    }

    // MARK: - Scene phase

    /// SwiftUI `scenePhase` 변화 시 호출. background/foreground 전환 시각만 기록하고
    /// IMU 수집 자체는 OS 정책에 맡김 — 실기기에서 BG 동작 여부를 카운터로 검증할 수 있음.
    func sceneDidChange(toForeground: Bool) {
        let wasInForeground = isInForeground
        isInForeground = toForeground
        if wasInForeground && !toForeground {
            lastBackgroundedAt = Date()
        }
    }

    // MARK: - IMU waveform

    /// 실제 AirPods motion source가 붙으면 이 진입점으로 정규화된 에너지를 전달.
    func appendIMUWaveformSample(_ energy: Double) {
        let sample = min(1.0, max(0.0, energy))
        var samples = imuWaveformSamples
        samples.append(sample)
        if samples.count > Self.maxIMUWaveformSamples {
            samples.removeFirst(samples.count - Self.maxIMUWaveformSamples)
        }
        imuWaveformSamples = samples
    }

    /// CMDeviceMotion의 회전/가속도 크기를 화면용 턱 움직임 에너지로 단순 합성.
    func recordIMUEnergy(rotationRateMagnitude: Double, userAccelerationMagnitude: Double) {
        let energy = rotationRateMagnitude * 0.12 + userAccelerationMagnitude * 0.75
        appendIMUWaveformSample(energy)
    }

    // MARK: - Reset

    func reset() {
        stopEating()
        chewCount = 247
        streak = 7
        points = 1240
        animKey = 0
        weeklyScores = [72, 85, 68, 78, 82, 88, 41]
        resetIMUWaveform()
        imuWaveformSource = .idle
        goalAlreadyHit = false
    }

    // MARK: - Derived

    var status: MoodStatus { MoodStatus.from(count: chewCount) }

    var progress: Double {
        min(1.0, max(0.0, Double(chewCount) / Double(Constants.dailyGoal)))
    }

    var imuWaveformStatusText: String {
        imuWaveformSource.statusText
    }

    var isIMUWaveformLive: Bool {
        isEating && (imuWaveformSource.usesRealMotion || imuWaveformSource == .demo)
    }

    // MARK: - Fake chew loop (백엔드 IMU 붙으면 이 함수만 교체)

    private func startFakeChewLoop() {
        stopFakeChewLoop()
        fakeChewTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: true) { [weak self] _ in
            self?.chew()
        }
    }

    private func stopFakeChewLoop() {
        fakeChewTimer?.invalidate()
        fakeChewTimer = nil
    }

    private func startHeadphoneMotionLoop() -> Bool {
        #if targetEnvironment(simulator)
        imuWaveformSource = .simulator
        return false
        #else
        switch headphoneMotionService.authorizationStatus {
        case .denied:
            imuWaveformSource = .denied
            return false
        case .restricted:
            imuWaveformSource = .restricted
            return false
        case .notDetermined, .authorized:
            break
        @unknown default:
            break
        }

        guard headphoneMotionService.isDeviceMotionAvailable else {
            imuWaveformSource = .unavailable
            return false
        }

        stopDemoIMUWaveformLoop()
        imuWaveformSource = .connecting
        headphoneMotionService.start { [weak self] sample in
            guard let self else { return }
            self.imuWaveformSource = .live
            self.imuSampleCount += 1
            self.lastIMUSampleAt = Date()
            self.recordIMUEnergy(
                rotationRateMagnitude: sample.rotationRateMagnitude,
                userAccelerationMagnitude: sample.userAccelerationMagnitude
            )
        } onError: { [weak self] message in
            guard let self else { return }
            if self.isEating {
                self.startDemoIMUWaveformLoop(source: .error(message))
            } else {
                self.imuWaveformSource = .error(message)
            }
        }

        return true
        #endif
    }

    private func stopHeadphoneMotionLoop() {
        headphoneMotionService.stop()
    }

    private func startDemoIMUWaveformLoop(source: IMUWaveformSource = .demo) {
        stopDemoIMUWaveformLoop()
        if isEating, !imuWaveformSource.usesRealMotion {
            imuWaveformSource = source
        }
        imuWaveformPhase = 0
        demoIMUWaveformTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.imuWaveformPhase += 0.38

            let bitePulse = pow(max(0, sin(self.imuWaveformPhase)), 2.8)
            let microMotion = sin(self.imuWaveformPhase * 3.1) * 0.08
            let energy = 0.12 + bitePulse * 0.72 + microMotion
            self.appendIMUWaveformSample(energy)
        }
    }

    private func stopDemoIMUWaveformLoop() {
        demoIMUWaveformTimer?.invalidate()
        demoIMUWaveformTimer = nil
    }

    private func resetIMUWaveform() {
        imuWaveformPhase = 0
        imuWaveformSamples = Self.idleIMUWaveformSamples
    }
}

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
/// 화면의 `chewCount` 카운터는 사실 도토리(in-app 화폐) 카운터로, 식사 동안 가짜 Timer가
/// 0.85초마다 `chew()`를 호출해 데모용으로 굴린다 (실제 씹기 횟수와 무관).
/// 실 씹기 검출은 `ChewingPredictor`가 IMU sample을 받아 `SessionStatsBuilder`에 누적하고,
/// 세션 종료 시 `chewing_session` 행의 분석 5필드로 저장 — Tracking 탭의 "오늘의 식사 기록"
/// 에서 사후 확인.
@Observable
final class AppState {
    private static let maxIMUWaveformSamples = 54
    private static let idleIMUWaveformSamples: [Double] = (0..<maxIMUWaveformSamples).map { i in
        0.05 + sin(Double(i) * 0.42) * 0.015
    }

    // MARK: - Persisted-ish state (현재는 인메모리)
    //
    // 신규 디바이스 첫 실행은 모두 0/빈 상태에서 시작. 시드값을 더미로 박아 두면
    // 새 사용자에게 "이미 누군가 사용한 듯한" 느낌을 주고, `dailyGoal` 도달 보너스가
    // 첫 식사에서 즉시 트리거되는 부작용도 있어 제거.

    var chewCount: Int = 0
    var streak: Int = 0
    var points: Int = 0
    var animKey: Int = 0
    var weeklyScores: [Int] = []

    // MARK: - Wardrobe (다람쥐 꾸미기)

    /// 보유 중인 ShopItem id 집합.
    var owned: Set<String> = []

    /// 장착 슬롯. 타입당 1개. nil = 미장착.
    var equipped: Equipped = Equipped()

    /// AcornPack 보유 수량. 효과 실연동은 자정 롤오버 합류 시.
    var ownedAcornPacks: [String: Int] = [:]

    struct Equipped: Codable, Equatable {
        var hat: String?
        var glasses: String?
        var acc: String?
    }

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
    /// 초기값 false — 앱 launch 시점엔 아직 .active phase가 아니므로, scenePhase가
    /// `.active`로 처음 도달할 때 `sceneDidChange(toForeground:true)`의 전이
    /// 조건(`!wasInForeground && toForeground`)이 성립해 일일 출석 보너스가 트리거된다.
    var isInForeground: Bool = false

    /// 마지막으로 background로 전환된 시각. 백그라운드 체류 시간 표시용.
    var lastBackgroundedAt: Date?

    /// 시뮬레이터에선 첫 접근을 막아 CoreMotion 권한 다이얼로그가 안 뜨도록 lazy.
    /// 실기기에선 식사 시작 시 최초 1회 init.
    @ObservationIgnored private lazy var headphoneMotionService = HeadphoneMotionService()
    @ObservationIgnored private var fakeChewTimer: Timer?
    @ObservationIgnored private var demoIMUWaveformTimer: Timer?
    @ObservationIgnored private var imuWaveformPhase: Double = 0
    @ObservationIgnored private var goalAlreadyHit = false

    // MARK: - ML inference

    /// 식사 세션 동안 활성. nil이면 추론 없이 (모델 로드 실패) 가짜 Timer만 동작.
    @ObservationIgnored private var predictor: ChewingPredictor?

    /// 세션 prediction 누적 → 종료 시 통계 산출.
    @ObservationIgnored private var statsBuilder: SessionStatsBuilder?

    /// 현재 사용 중인 ChewingClassifier 빌드 버전 식별자. DB의 `model_version` 컬럼에 저장.
    private static let modelVersion = "ChewingClassifier-v1"

    // MARK: - Remote persistence

    /// 원격 백엔드(InsForge)에 대한 추상화. 테스트/시뮬레이터에선 NoopRemoteStore 주입 가능.
    @ObservationIgnored let remoteStore: RemoteStore

    /// 게임 상태 원격 동기화(upsert/delete) 직렬화 큐.
    /// 짧은 시간에 여러 mutate가 일어나면 detached Task들의 네트워크 도착 순서가 뒤집혀
    /// 중간 상태가 winner로 굳을 수 있어, 각 작업이 이전 작업 종료를 await하는 체인으로 직렬화한다.
    @ObservationIgnored private var remoteSyncChain: Task<Void, Never> = Task {}

    /// user_stats는 profiles에 FK가 걸려 있어 첫 upsert 전에 profile 행이 존재해야 한다.
    /// 동기화 체인에서 한 번만 보장하면 되므로 플래그로 추적 — fetchUserStats 성공 또는
    /// upsertProfile 완료 시 true.
    @ObservationIgnored private var profileEnsured: Bool = false

    /// 한 끼 식사의 raw IMU 6채널을 메모리에 모으는 버퍼. 식사 종료 시 봉인 + 업로드.
    @ObservationIgnored private var imuSessionRecorder: IMUSessionRecorder?

    /// 식사 종료 직후 IMU 세션 업로드 결과. 화면이 alert 표시할 때 binding으로 관찰.
    var sessionUploadStatus: SessionUploadStatus = .idle

    /// "오늘의 식사 기록" 리스트 — 오늘 0시 이후 시작된 chewing_session 행들.
    /// Tracking 탭이 관찰만 하고, fetch/append는 AppState가 single source of truth.
    /// 세션 종료 + INSERT 성공 시 자동 append, 탭 진입 시 fetchTodaySessions로 재동기화.
    var todaySessions: [ChewingSessionDTO] = []

    /// 식사 종료 직후 표시할 리포트 카드의 source. INSERT 성공 시 set, 카드 dismiss 시 nil.
    /// ContentView가 .sheet binding으로 관찰. PRD #3 — 종료 후 2초 이내 카드 표시.
    var lastCompletedSession: ChewingSessionDTO?

    /// 도토리 적립 시 ContentView가 overlay로 보여줄 RewardDialogView trigger.
    /// RewardLedger가 +n🌰 반환했을 때 set, 사용자가 다이얼로그 dismiss 시 nil.
    /// 이번 PR에선 일일 출석 보너스만 trigger — 세션 종료 적립 trigger는 후속.
    var pendingRewardGrant: RewardGrant?

    /// 업로드 실패 시 사용자가 "다시 시도"를 누르면 재시도할 payload (finalize 결과 + 분석 통계).
    /// in-memory 1회 retry 한정 — 영구 retry 큐는 다음 PR.
    @ObservationIgnored private var pendingUpload: (output: IMUSessionRecorder.Output, stats: SessionStats?)?

    enum SessionUploadStatus: Equatable {
        case idle
        case uploading
        case success
        case failure
        var isTerminal: Bool { self == .success || self == .failure }
    }

    // MARK: - Init

    init(remoteStore: RemoteStore = NoopRemoteStore()) {
        self.remoteStore = remoteStore
        loadPersistedSnapshot()
        // 로컬 즉시 표시 후, 더 최신인 원격 스냅샷이 있으면 머지.
        Task { [weak self] in
            await self?.syncFromRemoteIfNewer()
        }
    }

    // MARK: - Eating actions

    func startEating() {
        guard !isEating else { return }
        isEating = true
        let now = Date()
        eatingStartedAt = now
        // 새 세션 시작 시 IMU 진단 지표 리셋 — 백그라운드 수집 여부 검증에 깨끗한 기준 제공
        imuSampleCount = 0
        lastIMUSampleAt = nil
        // raw IMU 6채널을 모을 봉투 — 식사 종료 시 finalize + 업로드.
        imuSessionRecorder = IMUSessionRecorder(startedAt: now)
        // ChewingPredictor + StatsBuilder — 식사 종료 시 chewing_session 분석 5필드 산출용.
        // 모델 로드 실패 시 predictor=nil이면 stats만 비고 나머지는 정상 동작.
        predictor = try? ChewingPredictor()
        statsBuilder = SessionStatsBuilder()
        // 가짜 Timer는 식사 내내 굴림 — 도토리 카운터(`chewCount`)는 실 씹기와 무관한
        // in-app 화폐 기능이라 ML 추론 결과를 카운터에 반영하지 않음.
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
        // 식사 종료 시 게임 진행 상태를 디스크에 한 번에 스냅샷 저장
        persistSnapshot()

        // IMU 세션 봉인 → Storage 업로드 → chewing_session INSERT.
        // 결과를 sessionUploadStatus로 publish해서 UI alert이 관찰할 수 있게 한다.
        let builder = statsBuilder
        statsBuilder = nil
        predictor = nil
        if let recorder = imuSessionRecorder {
            imuSessionRecorder = nil
            let endedAt = Date()
            let output = recorder.finalize(endedAt: endedAt)
            // 빈 세션(시뮬레이터 등에서 IMU 샘플 0개)은 사용자에게 알릴 가치 없어 스킵.
            guard output.sampleCount > 0 else { return }
            sessionUploadStatus = .uploading
            Task { [weak self] in
                let stats = await builder?.build(modelVersion: AppState.modelVersion)
                await self?.performSessionUpload(output, stats: stats)
            }
        }
    }

    func toggleEating() {
        isEating ? stopEating() : startEating()
    }

    // MARK: - Chew (한 입 = 한 번의 저작 신호)

    /// 한 번의 chew 이벤트. 추후 실제 IMU 감지기가 호출할 진입점.
    /// 도토리(`points`) 적립은 이 함수에서 분리됨 — PRD #8의 보상 정책(일일 출석 +2🌰,
    /// 세션 종료 시 `estimatedTotalChews × 0.05`, 일일 상한 500🌰)이 fake Timer로 굴러
    /// 실 씹기와 무관하게 자동 누적되는 옛 동작과 어긋났던 문제 해소. 실제 도토리 적립은
    /// `RewardLedger`(commit ③)에서 세션 종료 시 / foreground 진입 시 처리.
    func chew() {
        chewCount += 1
        animKey &+= 1

        let now = Date()
        chewTimestamps = chewTimestamps.filter { now.timeIntervalSince($0) < 60 }
        chewTimestamps.append(now)
        chewRatePerMinute = chewTimestamps.count

        // dailyGoal 첫 도달 flag는 유지 — 향후 트로피/스트릭 trigger 등으로 활용.
        // 더 이상 여기서 도토리 보너스를 주지 않음.
        if chewCount >= Constants.dailyGoal && !goalAlreadyHit {
            goalAlreadyHit = true
        }
    }

    // MARK: - Shop / Wardrobe actions

    enum PurchaseResult: Equatable {
        case success
        case alreadyOwned
        case notEnoughPoints
    }

    /// ShopItem 구매. 자동 장착하지 않음 (명시적 `equip` 필요).
    @discardableResult
    func buyItem(_ item: ShopItem) -> PurchaseResult {
        if owned.contains(item.id) { return .alreadyOwned }
        guard points >= item.price else { return .notEnoughPoints }
        points -= item.price
        owned.insert(item.id)
        persistSnapshot()
        return .success
    }

    /// 보유한 아이템을 장착. 같은 타입의 기존 장착 아이템은 자동 교체.
    func equip(_ item: ShopItem) {
        guard owned.contains(item.id) else { return }
        switch item.type {
        case .hat:     equipped.hat = item.id
        case .glasses: equipped.glasses = item.id
        case .acc:     equipped.acc = item.id
        }
        persistSnapshot()
    }

    func unequip(_ type: ShopItem.Kind) {
        switch type {
        case .hat:     equipped.hat = nil
        case .glasses: equipped.glasses = nil
        case .acc:     equipped.acc = nil
        }
        persistSnapshot()
    }

    /// AcornPack 구매. 이번 라운드는 보유 카운트만 누적.
    @discardableResult
    func buyAcornPack(_ pack: AcornPack) -> PurchaseResult {
        guard points >= pack.price else { return .notEnoughPoints }
        points -= pack.price
        ownedAcornPacks[pack.id, default: 0] += 1
        persistSnapshot()
        return .success
    }

    func isOwned(_ item: ShopItem) -> Bool { owned.contains(item.id) }

    func isEquipped(_ item: ShopItem) -> Bool {
        switch item.type {
        case .hat:     return equipped.hat == item.id
        case .glasses: return equipped.glasses == item.id
        case .acc:     return equipped.acc == item.id
        }
    }

    var equippedHatItem: ShopItem?     { ShopItem.by(id: equipped.hat) }
    var equippedGlassesItem: ShopItem? { ShopItem.by(id: equipped.glasses) }
    var equippedAccItem: ShopItem?     { ShopItem.by(id: equipped.acc) }

    // MARK: - Scene phase

    /// SwiftUI `scenePhase` 변화 시 호출. background/foreground 전환 시각 기록 +
    /// 일일 출석 보너스 적립 trigger.
    @MainActor
    func sceneDidChange(toForeground: Bool) {
        let wasInForeground = isInForeground
        isInForeground = toForeground
        if !wasInForeground && toForeground {
            // foreground 진입 시 일일 출석 보너스 시도. 같은 날엔 한 번만 적립.
            let granted = RewardLedger.claimDailyAttendance()
            if granted > 0 {
                points += granted
                persistSnapshot()
                // ContentView overlay가 RewardDialogView를 표시. 같은 날 두 번째 진입은
                // granted=0이라 trigger 안 됨 — idempotency가 보장.
                pendingRewardGrant = RewardGrant(amount: granted, kind: .attendance)
            }
        }
        if wasInForeground && !toForeground {
            lastBackgroundedAt = Date()
            // 백그라운드 진입 시 안전하게 스냅샷 — 시스템 종료/메모리 회수 대비
            persistSnapshot()
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
        chewCount = 0
        streak = 0
        points = 0
        animKey = 0
        weeklyScores = []
        resetIMUWaveform()
        imuWaveformSource = .idle
        goalAlreadyHit = false
        owned = []
        equipped = Equipped()
        ownedAcornPacks = [:]
        todaySessions = []
        lastCompletedSession = nil
        // 저장된 스냅샷도 비워서 다음 실행에서 시드값이 살아남도록
        clearPersistedSnapshot()
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
            // raw 채널 전체(18컬럼)를 recorder에 누적. 출시 후 재학습 데이터셋으로
            // 그대로 쓸 수 있도록 attitude/gravity/magneticField까지 보존.
            // 같은 row를 ML predictor에도 흘려보내 SessionStatsBuilder에 누적.
            guard let recorder = self.imuSessionRecorder else { return }
            let tRel = Date().timeIntervalSince(recorder.startedAt)
            let row = IMURow(
                tMach: sample.timestamp,
                tRelSec: tRel,
                attitudeRoll: sample.attitudeRoll,
                attitudePitch: sample.attitudePitch,
                attitudeYaw: sample.attitudeYaw,
                rotationX: sample.rotationX,
                rotationY: sample.rotationY,
                rotationZ: sample.rotationZ,
                gravityX: sample.gravityX,
                gravityY: sample.gravityY,
                gravityZ: sample.gravityZ,
                userAccelX: sample.userAccelX,
                userAccelY: sample.userAccelY,
                userAccelZ: sample.userAccelZ,
                magneticFieldX: sample.magneticFieldX,
                magneticFieldY: sample.magneticFieldY,
                magneticFieldZ: sample.magneticFieldZ,
                sensorLocation: sample.sensorLocation
            )
            recorder.append(row)
            recorder.updateSensorLocation(sample.sensorLocation)

            // ML 추론은 별도 Task로 — actor 호출이 sample 콜백 빈도(50Hz)를 막지 않도록.
            // 결과는 통계 누적용으로만 사용; 화면 카운터(`chewCount` = 도토리)는 절대 건드리지 않음.
            if let predictor = self.predictor, let statsBuilder = self.statsBuilder {
                Task {
                    guard let prediction = await predictor.feed(row) else { return }
                    await statsBuilder.append(prediction)
                }
            }
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
        #if !targetEnvironment(simulator)
        // 시뮬레이터에선 lazy service 자체를 절대 init하지 않아 권한 다이얼로그가 안 뜸.
        headphoneMotionService.stop()
        #endif
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

    // MARK: - Local persistence (UserDefaults snapshot)
    //
    // 핵심 게임 진행 상태만 한 번에 통째로 JSON으로 직렬화해 UserDefaults에 저장한다.
    // 의도적으로 단순하게 (SwiftData / CoreData 아님). 저장 시점은:
    //   1) 식사 종료 시 (stopEating)
    //   2) 앱이 background로 갈 때 (sceneDidChange)
    //   3) 명시적 reset 시 → 저장 영역 자체를 비움
    // 세션 한정 데이터 (isEating, IMU 진단 카운터, 파형 샘플)는 저장하지 않는다.

    private static let persistenceKey = "ChewChewIOS.AppState.snapshot.v1"

    /// v2 — `owned`/`equipped`/`ownedAcornPacks` 추가. 모두 옵셔널이라
    /// v1 스냅샷을 디코드하면 자동으로 nil → 빈 상태로 초기화된다.
    private struct PersistedSnapshot: Codable {
        let chewCount: Int
        let streak: Int
        let points: Int
        let weeklyScores: [Int]
        let goalAlreadyHit: Bool
        let savedAt: Date
        var owned: [String]?
        var equipped: Equipped?
        var ownedAcornPacks: [String: Int]?
    }

    func persistSnapshot() {
        let now = Date()
        let snapshot = PersistedSnapshot(
            chewCount: chewCount,
            streak: streak,
            points: points,
            weeklyScores: weeklyScores,
            goalAlreadyHit: goalAlreadyHit,
            savedAt: now,
            owned: Array(owned),
            equipped: equipped,
            ownedAcornPacks: ownedAcornPacks
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistenceKey)

        // 원격 동기화는 best-effort — 실패해도 로컬은 위에서 이미 보장됨.
        // remoteSyncChain으로 직렬화해 짧은 시간 내 여러 mutate가 도착 순서로 뒤집히는 race를 방지.
        // user_stats는 profiles에 FK가 걸려 있어 첫 호출 한 번은 profile upsert 선행.
        let stats = makeUserStatsDTO(savedAt: now)
        let deviceId = DeviceIdentity.shared
        let store = remoteStore
        let previous = remoteSyncChain
        let needProfile = !profileEnsured
        profileEnsured = true
        remoteSyncChain = Task.detached {
            _ = await previous.value
            if needProfile {
                try? await store.upsertProfile(ProfileDTO(deviceId: deviceId, displayName: nil))
            }
            try? await store.upsertUserStats(stats)
        }
    }

    private func loadPersistedSnapshot() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
            let snapshot = try? JSONDecoder().decode(PersistedSnapshot.self, from: data)
        else { return }
        chewCount = snapshot.chewCount
        streak = snapshot.streak
        points = snapshot.points
        // 주간 점수는 7개 또는 빈 배열만 허용. 손상된 저장본(예: 다른 길이)은 무시하고
        // 현재 상태(시드 = 빈 배열) 유지.
        if snapshot.weeklyScores.isEmpty || snapshot.weeklyScores.count == 7 {
            weeklyScores = snapshot.weeklyScores
        }
        goalAlreadyHit = snapshot.goalAlreadyHit
        // v2 옵셔널 필드 — v1 스냅샷에선 nil이라 빈 상태가 됨
        if let savedOwned = snapshot.owned {
            owned = Set(savedOwned)
        }
        if let savedEquipped = snapshot.equipped {
            equipped = savedEquipped
        }
        if let savedPacks = snapshot.ownedAcornPacks {
            ownedAcornPacks = savedPacks
        }
    }

    func clearPersistedSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
        // RewardLedger도 함께 비움 — 사용자가 명시적 reset 했을 때 출석/세션 적립
        // idempotency 키도 같이 사라져 다음 첫 진입에서 다시 적립 가능.
        RewardLedger.resetAll()
        // 같은 체인으로 — 직전 upsert가 끝난 뒤 delete가 나가야 결과가 결정적.
        // profiles 삭제 → FK ON DELETE CASCADE로 user_stats도 자동 정리.
        // 다음 persistSnapshot이 profile을 다시 만들 수 있도록 플래그 리셋.
        profileEnsured = false
        let deviceId = DeviceIdentity.shared
        let store = remoteStore
        let previous = remoteSyncChain
        remoteSyncChain = Task.detached {
            _ = await previous.value
            try? await store.deleteUserData(deviceId: deviceId)
        }
    }

    // MARK: - Remote sync helpers

    private func makeUserStatsDTO(savedAt: Date) -> UserStatsDTO {
        UserStatsDTO(
            deviceId: DeviceIdentity.shared,
            chewCount: chewCount,
            streak: streak,
            points: points,
            weeklyScores: weeklyScores,
            goalAlreadyHit: goalAlreadyHit,
            owned: Array(owned),
            equipped: UserStatsDTO.EquippedDTO(
                hat: equipped.hat,
                glasses: equipped.glasses,
                acc: equipped.acc
            ),
            ownedAcornPacks: ownedAcornPacks,
            savedAt: savedAt
        )
    }

    /// 앱 시작 시 한 번 호출. 원격 row가 로컬보다 더 최신이면 in-memory 상태를 머지한다.
    /// `saved_at` 기준 최신 우선 — 다중 기기 동기화는 익명 디바이스 ID 정책상 보장 안 함.
    @MainActor
    private func syncFromRemoteIfNewer() async {
        guard let remote = try? await remoteStore.fetchUserStats(deviceId: DeviceIdentity.shared) else { return }
        // user_stats가 존재 = profiles도 존재 (FK 보장). 다음 persistSnapshot에서 profile 재호출 생략.
        profileEnsured = true
        let localSavedAt = localPersistedSavedAt() ?? .distantPast
        guard remote.savedAt > localSavedAt else { return }

        chewCount = remote.chewCount
        streak = remote.streak
        points = remote.points
        if remote.weeklyScores.isEmpty || remote.weeklyScores.count == 7 {
            weeklyScores = remote.weeklyScores
        }
        goalAlreadyHit = remote.goalAlreadyHit
        owned = Set(remote.owned)
        equipped = Equipped(
            hat: remote.equipped.hat,
            glasses: remote.equipped.glasses,
            acc: remote.equipped.acc
        )
        ownedAcornPacks = remote.ownedAcornPacks
        // 머지된 상태를 로컬에도 즉시 반영 — 다음 cold-start 비교가 일관되도록.
        // 단, 원격 upsert는 자기 자신을 다시 쏘는 셈이라 굳이 안 함.
        let snapshot = PersistedSnapshot(
            chewCount: chewCount,
            streak: streak,
            points: points,
            weeklyScores: weeklyScores,
            goalAlreadyHit: goalAlreadyHit,
            savedAt: remote.savedAt,
            owned: Array(owned),
            equipped: equipped,
            ownedAcornPacks: ownedAcornPacks
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private func localPersistedSavedAt() -> Date? {
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
            let snapshot = try? JSONDecoder().decode(PersistedSnapshot.self, from: data)
        else { return nil }
        return snapshot.savedAt
    }

    /// 식사 종료 후 IMU 세션 봉인 결과 + 분석 통계를 받아 Storage 업로드 → chewing_session INSERT.
    /// 결과는 `sessionUploadStatus`로 publish되어 UI alert이 관찰한다. 실패 시 payload를
    /// `pendingUpload`에 보관해 "다시 시도"가 가능하게.
    /// `stats`는 추론이 동작한 세션에서만 비-nil (시뮬레이터/AirPods 미연결 세션은 nil).
    @MainActor
    private func performSessionUpload(_ output: IMUSessionRecorder.Output, stats: SessionStats?) async {
        sessionUploadStatus = .uploading
        do {
            let deviceId = DeviceIdentity.shared
            let storagePath = try await remoteStore.uploadIMUCSV(
                sessionId: output.sessionId,
                deviceId: deviceId,
                csvData: output.csvData
            )
            let dto = ChewingSessionDTO(
                id: output.sessionId,
                deviceId: deviceId,
                startedAt: output.startedAt,
                endedAt: output.endedAt,
                durationSec: output.durationSec,
                sensorLocation: output.sensorLocation,
                sampleCount: output.sampleCount,
                sampleRateHz: 50,
                storagePath: storagePath,
                appVersion: Self.appVersion,
                chewingSeconds: stats?.chewingSeconds,
                restSeconds: stats?.restSeconds,
                chewingFraction: stats?.chewingFraction,
                estimatedTotalChews: stats?.estimatedTotalChews,
                modelVersion: stats?.modelVersion
            )
            try await remoteStore.insertSession(dto)
            sessionUploadStatus = .success
            pendingUpload = nil
            // 방금 INSERT한 행을 즉시 리스트에 반영 — GET 라운드트립 생략.
            // started_at 오름차순 정렬을 유지하기 위해 append (방금 종료된 세션이 가장 최신).
            todaySessions.append(dto)
            // 식사 종료 직후 ReportCardView를 sheet로 띄울 trigger. 사용자가 닫으면 nil.
            lastCompletedSession = dto
            // PRD #8: 세션 종료 적립 = estimatedTotalChews × 0.05. RewardLedger가
            // idempotency(같은 sessionId 중복 차단) + 일일 상한 500🌰 enforcement.
            let granted = RewardLedger.accrue(forSession: dto.id, chewCount: dto.estimatedTotalChews)
            if granted > 0 {
                points += granted
                persistSnapshot()
            }
        } catch {
            sessionUploadStatus = .failure
            pendingUpload = (output: output, stats: stats)
        }
    }

    /// Tracking 탭 .task에서 호출 — 오늘 0시 이후 세션을 원격에서 가져와 리스트 동기화.
    /// 실패는 silent (네트워크 끊김 등); 사용자에겐 빈 리스트로 보이는 게 alert보다 덜 거슬림.
    @MainActor
    func fetchTodaySessions() async {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let deviceId = DeviceIdentity.shared
        guard let rows = try? await remoteStore.fetchChewingSessions(deviceId: deviceId, since: startOfDay) else {
            return
        }
        todaySessions = rows
    }

    /// 단일 세션 삭제 — 캘린더 DaySessionsView에서 swipe로 호출. todaySessions에서도
    /// 즉시 제거해 UI 동기화. 실패는 silent — 다음 reload에서 서버 상태와 다시 sync.
    @MainActor
    func deleteSession(_ session: ChewingSessionDTO) async {
        let deviceId = DeviceIdentity.shared
        do {
            try await remoteStore.deleteChewingSession(id: session.id, deviceId: deviceId)
            todaySessions.removeAll { $0.id == session.id }
        } catch {
            return
        }
    }

    /// 모든 chewing_session 행 삭제 — MealCalendarView 도구바에서 confirm 후 호출.
    /// profiles / user_stats(도토리 등 게임 상태)는 보존. todaySessions도 비움.
    @MainActor
    func deleteAllChewingSessions() async {
        let deviceId = DeviceIdentity.shared
        do {
            try await remoteStore.deleteAllChewingSessions(deviceId: deviceId)
            todaySessions = []
        } catch {
            return
        }
    }

    /// Alert "다시 시도" 버튼에서 호출 — 마지막 실패한 payload로 1회 재시도.
    /// 영구 retry 큐는 후속 PR.
    @MainActor
    func retryLastSessionUpload() {
        guard let pending = pendingUpload else { return }
        Task { [weak self] in
            await self?.performSessionUpload(pending.output, stats: pending.stats)
        }
    }

    /// Alert dismiss 시 호출. 실패 상태에서 dismiss 하면 payload 폐기(= 데이터 손실 수용).
    /// RewardDialogView가 자동(2.5s) 또는 탭으로 dismiss 시 호출.
    @MainActor
    func dismissPendingRewardGrant() {
        pendingRewardGrant = nil
    }

    @MainActor
    func dismissSessionUploadStatus() {
        if sessionUploadStatus == .failure {
            pendingUpload = nil
        }
        sessionUploadStatus = .idle
    }

    private static let appVersion: String? = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }()
}

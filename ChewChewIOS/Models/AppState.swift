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

    /// PRD #11 streak 상태 — 프리즈 인벤토리 (0~3) + 마지막 성공 자정 시각.
    /// `streak`(count)과 함께 `StreakService.evaluate(_:)`가 일관 mutate.
    /// 마일스톤 7/30/100일 도달 시 프리즈 +1 적립, 2일 공백 시 자동 소진.
    var freezeInventory: Int = 0
    var lastSuccessDate: Date?

    /// 사용자가 onboarding에서 입력한 표시 이름. `profiles.displayName`과 매핑.
    /// nil이면 HomeView는 "친구" 등 fallback. didSet에서 UserDefaults 캐시 갱신.
    var displayName: String? {
        didSet {
            if let name = displayName {
                UserDefaults.standard.set(name, forKey: Self.displayNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.displayNameKey)
            }
        }
    }

    /// `fetchAndApplyDisplayName` 한 번 끝났는지. 시작 직후 DB fetch 완료 전엔 false로 두어
    /// "기존 사용자가 reinstall한 cold-start에서 sheet이 잠깐 깜빡이는" 케이스를 차단.
    /// 처음 fetch가 끝나면 true로 마크 — 그 시점에 displayName nil이면 진짜 신규 디바이스.
    var didLoadProfile: Bool = false

    /// 온보딩(이름 입력 + 사용법 튜토리얼)을 끝까지 마쳤는지. false인 동안 ContentView가
    /// onboarding sheet를 띄운다. 튜토리얼 마지막 "시작하기"/"건너뛰기"의 `completeOnboarding()`
    /// 에서 true로. 출석/스트릭 보상은 이 값이 true가 되기 전엔 트리거하지 않아, 보상이 온보딩
    /// 위로 떠버리는 회귀를 막는다. didSet으로 UserDefaults에 영속(단, init 내 대입은 didSet이
    /// 발동하지 않으므로 마이그레이션 시 명시적으로 write).
    var hasCompletedOnboarding: Bool = false {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingCompleteKey)
        }
    }

    private static let displayNameKey = "ChewChewIOS.AppState.displayName"
    private static let onboardingCompleteKey = "ChewChewIOS.AppState.hasCompletedOnboarding"

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

    /// 알림 딥링크(`chewchew://start`) 수신 시 true. 3초 후 자동 false.
    /// HomeView의 MealToggle 강조 스타일 트리거.
    var startButtonHighlighted: Bool = false

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

    /// 식사 세션 동안 백그라운드 IMU 수집이 끊기지 않도록 무음 오디오를 굴려 앱을 깨워두는 keep-alive.
    /// 식사 종료 시 stop. 시뮬레이터에선 노옵 (`BackgroundAudioKeepAlive` 내부 가드).
    @ObservationIgnored private let backgroundKeepAlive = BackgroundAudioKeepAlive()

    /// 식사 세션 동안 전화 통화 시작을 관찰해, 오디오 인터럽트가 전화 때문인지 판별한다.
    @ObservationIgnored private let callMonitor = CallInterruptionMonitor()

    /// 직전 인터럽트가 전화였는지 표시. 전화면 `.ended`에서 자동 재개하지 않고,
    /// 중단 알림의 "계속하기"를 누를 때까지 기다린다. 재난문자 등은 false라 자동 재개.
    @ObservationIgnored private var interruptionWasCall = false

    /// 식사 측정 Live Activity(잠금화면·다이내믹 아일랜드) 관리자. 설정에서 꺼져 있으면 노옵.
    @ObservationIgnored private let mealActivity = MealActivityController()

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

    /// 식사 시작 후 60초 미만에서 종료를 시도할 때 사용자에게 "더 측정할까요"를
    /// 묻는 확인 다이얼로그 플래그. 사용자가 "그만두기"를 선택하면 세션을 discard.
    var showShortSessionConfirm: Bool = false

    /// 시작 시점에 AirPods/모션 권한이 없거나 라우트가 비어 시작을 차단했을 때 띄우는 플래그.
    /// 종료 시 너무 짧은 세션 확인(showShortSessionConfirm)과 메시지를 분리한다.
    var showAirPodsConnectionPrompt: Bool = false

    /// 도토리 적립 시 ContentView가 overlay로 보여줄 RewardDialogView trigger.
    /// RewardLedger가 +n🌰 반환했을 때 set, 사용자가 다이얼로그 dismiss 시 nil.
    /// 출석 보너스(`.attendance`) + 세션 종료 적립(`.sessionComplete`) 두 종 trigger.
    /// 세션 적립 trigger는 `SessionResultSheet`와 동시 표시되지 않도록 ContentView
    /// overlay가 `lastCompletedSession == nil`(=sheet 닫힘)일 때만 그려진다.
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
        // displayName은 game state(`PersistedSnapshot`)과 다른 별도 캐시 키 — cold-start
        // 시 UserDefaults에서 즉시 read해 HomeView가 빈 이름으로 깜빡이지 않도록.
        displayName = UserDefaults.standard.string(forKey: Self.displayNameKey)
        // 온보딩 완료 플래그 로드. 신규 키라, 이미 이름이 있는 기존 사용자(앱 업데이트로 이 키가
        // 아직 없는 상태)는 사용법 튜토리얼을 본 적 없어도 다시 띄우지 않도록 true로 마이그레이션.
        // init 내 대입은 didSet을 발동시키지 않으므로 UserDefaults write는 명시적으로 한다.
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey)
        if !hasCompletedOnboarding && displayName != nil {
            hasCompletedOnboarding = true
            UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        }
        // 즉시 표시용 fallback — DB 실패 또는 응답 전에 화면 그려도 마지막 캐시값으로.
        loadPersistedSnapshot()
        Task { [weak self] in
            await self?.syncFromRemoteUserStats()
            await self?.fetchAndApplyDisplayName()
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

        // 잠금 화면/홈 화면으로 빠져도 AirPods IMU 콜백이 끊기지 않도록 ambient 오디오 keep-alive 활성.
        // 시뮬레이터에선 내부적으로 노옵.
        interruptionWasCall = false
        backgroundKeepAlive.onInterrupt = { [weak self] shouldResume in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if shouldResume {
                    // 전화였다면 자동 재개하지 않고 중단 알림의 "계속하기"를 기다린다.
                    guard AppState.shouldAutoResume(
                        interruptionWasCall: self.interruptionWasCall,
                        shouldResume: true
                    ) else { return }
                    // 재난문자 등 통화가 아닌 인터럽트 — 갭 기록 후 자동 재개.
                    #if os(iOS) && !targetEnvironment(simulator)
                    if let began = self.backgroundKeepAlive.interruptionBeganAt {
                        self.imuSessionRecorder?.recordInterruptionGap(began: began, ended: Date())
                    }
                    #endif
                    _ = self.startHeadphoneMotionLoop()
                } else {
                    // 인터럽트 시작 — IMU 루프 중단.
                    self.stopHeadphoneMotionLoop()
                }
            }
        }
        // 통화가 시작되면(앱이 살아있는 동안) 중단 알림을 띄워 통화 후 이어가게 한다.
        callMonitor.onCallStarted = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isEating else { return }
                self.interruptionWasCall = true
                self.mealActivity.setPaused(true)
                await MealNotificationService.scheduleInterruptionPrompt()
            }
        }
        callMonitor.start()
        // 중단 알림이 권한 부재로 막히지 않도록 세션 시작 시 1회 권한 확보(이미 결정됐으면 노옵).
        Task { await MealNotificationService.requestAuthorizationIfNeeded() }
        backgroundKeepAlive.start()
        mealActivity.start(startedAt: now)

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
        // 식사가 끝나면 더 이상 백그라운드 wake가 필요 없으므로 즉시 stop —
        // ambient 오디오 세션이 살아있는 동안엔 다른 앱(타이머/시스템 사운드 등)
        // 미디어 라우팅에 영향이 가니, 세션 끝과 동시에 해제하는 게 안전.
        backgroundKeepAlive.onInterrupt = nil
        backgroundKeepAlive.stop()
        callMonitor.onCallStarted = nil
        callMonitor.stop()
        interruptionWasCall = false
        MealNotificationService.cancelInterruptionPrompt()
        mealActivity.end()
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
            // 분석이 불가능한 세션(IMU 샘플 0개)은 DB·도토리·리포트 어디에도
            // 흔적을 남기지 않는다 — 사용자 입장에서 "아무 일도 안 일어난" 상태.
            guard output.sampleCount > 0 else { return }
            sessionUploadStatus = .uploading
            Task { [weak self] in
                let stats = await builder?.build(modelVersion: AppState.modelVersion)
                await self?.performSessionUpload(output, stats: stats)
            }
        }
    }

    /// 너무 짧게 끝낸 세션을 사용자가 "그만두기" 선택했을 때 호출.
    /// 측정 상태만 정리하고 DB·도토리·리포트엔 어떤 흔적도 남기지 않는다.
    func discardCurrentSession() {
        guard isEating else { return }
        isEating = false
        eatingStartedAt = nil
        stopHeadphoneMotionLoop()
        stopFakeChewLoop()
        stopDemoIMUWaveformLoop()
        backgroundKeepAlive.onInterrupt = nil
        backgroundKeepAlive.stop()
        callMonitor.onCallStarted = nil
        callMonitor.stop()
        interruptionWasCall = false
        MealNotificationService.cancelInterruptionPrompt()
        mealActivity.end()
        resetIMUWaveform()
        imuWaveformSource = .idle
        chewTimestamps.removeAll()
        chewRatePerMinute = 0
        persistSnapshot()
        statsBuilder = nil
        predictor = nil
        if let recorder = imuSessionRecorder {
            imuSessionRecorder = nil
            _ = recorder.finalize(endedAt: Date())
        }
    }

    func toggleEating() {
        isEating ? stopEating() : startEating()
    }

    /// 중단된 측정을 같은 세션으로 이어간다 — 중단 알림 "계속하기" 또는 `chewchew://resume`에서 호출.
    /// 녹음 버퍼·시작 시각·추론기를 그대로 두고 갭만 기록해, 한 끼가 통화로 두 세션으로 쪼개지지 않게 한다.
    /// 세션이 메모리에서 사라졌으면(앱 종료 등) 새로 시작하도록 시작 버튼을 강조한다.
    @MainActor
    func resumeMeasurement() {
        guard isEating else {
            requestStartHighlight()
            return
        }
        #if os(iOS) && !targetEnvironment(simulator)
        if let began = backgroundKeepAlive.interruptionBeganAt {
            imuSessionRecorder?.recordInterruptionGap(began: began, ended: Date())
        }
        #endif
        interruptionWasCall = false
        MealNotificationService.cancelInterruptionPrompt()
        mealActivity.setPaused(false)
        backgroundKeepAlive.resume()
        _ = startHeadphoneMotionLoop()
    }

    /// 중단 알림 "그만하기"에서 호출 — 멈춘 세션을 정상 종료(부분 기록 업로드)한다.
    @MainActor
    func stopMeasurementFromNotification() {
        MealNotificationService.cancelInterruptionPrompt()
        if isEating { stopEating() }
    }

    /// `.ended + shouldResume` 인터럽트에서 자동 재개할지 판단하는 순수 함수.
    /// 전화는 사용자가 중단 알림에서 직접 이어가므로 자동 재개하지 않는다.
    static func shouldAutoResume(interruptionWasCall: Bool, shouldResume: Bool) -> Bool {
        shouldResume && !interruptionWasCall
    }

    /// 딥링크(`chewchew://start`) 수신 시 호출. 시작 버튼을 3초간 강조.
    /// delay 파라미터는 단위테스트에서 0으로 주입 가능.
    @MainActor
    func requestStartHighlight(duration: TimeInterval = 3) {
        startButtonHighlighted = true
        Task {
            try? await Task.sleep(for: .seconds(duration))
            startButtonHighlighted = false
        }
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
            // XCUITest 안정성용 hook — `-skipAttendanceDialog` launch arg가 있으면
            // 출석 보너스를 trigger하지 않는다. 운영 빌드는 영향 없음(인자 미전달).
            // dialog가 MealToggle hit testing을 가리는 flaky 패턴 차단.
            if ProcessInfo.processInfo.arguments.contains("-skipAttendanceDialog") {
                return
            }
            // 신규 디바이스 첫 실행에선 온보딩(이름 입력 + 사용법 튜토리얼)이 끝나기 전까지
            // 출석/스트릭 보상 다이얼로그를 띄우지 않는다. 보상이 온보딩 sheet 위로 먼저 떠
            // 사용자가 보상→온보딩 순으로 마주치는 회귀를 차단. completeOnboarding()이
            // 튜토리얼 종료 직후 동일 경로를 호출해 이어준다.
            if hasCompletedOnboarding {
                grantDailyAttendanceIfNeeded()
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

    // MARK: - Erase all user data (REQ-05)

    /// 설정 '내 데이터 삭제' 확인 시 호출.
    /// 원격: profiles DELETE → FK CASCADE(user_stats/chewing_session/bout).
    /// 로컬: 모든 게임 상태를 초기화하고 스냅샷도 비움.
    @MainActor
    func eraseAllUserData() async {
        // 로컬 인메모리 상태 리셋 (reset()과 동일 범위)
        stopEating()
        chewCount = 0
        streak = 0
        points = 0
        animKey = 0
        freezeInventory = 0
        lastSuccessDate = nil
        resetIMUWaveform()
        imuWaveformSource = .idle
        goalAlreadyHit = false
        owned = []
        equipped = Equipped()
        ownedAcornPacks = [:]
        todaySessions = []
        lastCompletedSession = nil
        displayName = nil
        didLoadProfile = false
        // 로컬 스냅샷 + 원격 데이터 삭제 (clearPersistedSnapshot이 remoteStore.deleteUserData 포함)
        clearPersistedSnapshot()
    }

    // MARK: - Reset

    func reset() {
        stopEating()
        chewCount = 0
        streak = 0
        points = 0
        animKey = 0
        resetIMUWaveform()
        imuWaveformSource = .idle
        goalAlreadyHit = false
        owned = []
        equipped = Equipped()
        ownedAcornPacks = [:]
        todaySessions = []
        lastCompletedSession = nil
        displayName = nil
        hasCompletedOnboarding = false
        freezeInventory = 0
        lastSuccessDate = nil
        // 저장된 스냅샷도 비워서 다음 실행에서 시드값이 살아남도록
        clearPersistedSnapshot()
    }

    // MARK: - Derived

    var status: MoodStatus { MoodStatus.from(count: todayRealChewCount) }

    var progress: Double {
        min(1.0, max(0.0, Double(chewCount) / Double(Constants.dailyGoal)))
    }

    /// 오늘 세션들의 실제 씹기 횟수 합. 식사 중에는 갱신되지 않고 세션이 끝나
    /// `todaySessions`에 추가될 때만 변한다. `chewCount`는 fake 도토리 카운터라
    /// 화면에 노출되는 "실제 씹기" 수치는 반드시 이 값을 쓴다.
    var todayRealChewCount: Int {
        todaySessions.reduce(0) { $0 + ($1.estimatedTotalChews ?? 0) }
    }

    /// 실제 씹기 횟수 기반 일일 목표 진행도(0~1). 홈 다람이 둘레 링이 사용.
    var todayProgress: Double {
        min(1.0, max(0.0, Double(todayRealChewCount) / Double(Constants.dailyGoal)))
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

    // MARK: - Motion permission guard (REQ-01)

    /// `.notDetermined`이면 즉시 측정을 시작하지 않고 권한 요청 경로로 보낸다.
    /// CoreMotion은 명시적 request API 없이 `startDeviceMotionUpdates` 호출 시 시스템이
    /// 프롬프트를 띄운다. 권한 부여 → `onGranted()`, 거부(에러 콜백) → `onDenied()`.
    func requestMotionPermission(onGranted: @escaping () -> Void, onDenied: @escaping () -> Void) {
        headphoneMotionService.start { [weak self] _ in
            // 첫 샘플이 도착했다 = 권한이 허용됨. 업데이트를 즉시 멈추고 호출자에게 위임.
            self?.headphoneMotionService.stop()
            DispatchQueue.main.async { onGranted() }
        } onError: { _ in
            // 에러 = 권한 거부 또는 디바이스 없음.
            DispatchQueue.main.async { onDenied() }
        }
    }

    /// REQ-01 가드 결정 순수 함수.
    /// `.authorized && available`일 때만 true — `.notDetermined`는 false(권한 요청 경로로).
    static func shouldStartImmediately(status: CMAuthorizationStatus, available: Bool) -> Bool {
        status == .authorized && available
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
        case .notDetermined:
            // notDetermined는 startHeadphoneMotionLoop 경로에 도달하지 않는다.
            // HomeView.handleMealToggle()이 shouldStartImmediately=false로 먼저 걸러
            // requestMotionPermission 경로로 보내기 때문. 안전망으로만 존재.
            imuWaveformSource = .idle
            return false
        case .authorized:
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

    /// v2 — `owned`/`equipped`/`ownedAcornPacks` 추가.
    /// v3 — PRD #11 streak: `freezeInventory`/`lastSuccessDate` 추가. 모두 옵셔널이라
    /// 옛 스냅샷을 디코드하면 자동으로 nil → 기본값(0/nil)으로 초기화된다.
    private struct PersistedSnapshot: Codable {
        let chewCount: Int
        let streak: Int
        let points: Int
        let goalAlreadyHit: Bool
        let savedAt: Date
        var owned: [String]?
        var equipped: Equipped?
        var ownedAcornPacks: [String: Int]?
        var freezeInventory: Int?
        var lastSuccessDate: Date?
    }

    func persistSnapshot() {
        let now = Date()
        let snapshot = PersistedSnapshot(
            chewCount: chewCount,
            streak: streak,
            points: points,
            goalAlreadyHit: goalAlreadyHit,
            savedAt: now,
            owned: Array(owned),
            equipped: equipped,
            ownedAcornPacks: ownedAcornPacks,
            freezeInventory: freezeInventory,
            lastSuccessDate: lastSuccessDate
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
        // v3 옵셔널 필드 — 옛 스냅샷에선 nil이라 신규 streak 상태(0/nil)로 시작
        if let savedFreeze = snapshot.freezeInventory {
            freezeInventory = savedFreeze
        }
        if let savedLastSuccess = snapshot.lastSuccessDate {
            lastSuccessDate = savedLastSuccess
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

    /// 앱 시작 시 한 번 호출. DB(`user_stats`)를 source of truth로 삼아 무조건 덮어쓴다.
    /// fetch 성공 → DB값으로 in-memory + UserDefaults write-through.
    /// fetch nil(신규 디바이스) → 현재 상태(시드값 0) 유지.
    /// 네트워크 실패 → loadPersistedSnapshot이 채운 fallback 유지 (silent).
    @MainActor
    private func syncFromRemoteUserStats() async {
        let deviceId = DeviceIdentity.shared
        do {
            if let remote = try await remoteStore.fetchUserStats(deviceId: deviceId) {
                // user_stats 존재 = profiles도 존재 (FK 보장). profile 재호출 생략.
                profileEnsured = true
                applyRemoteSnapshot(remote)
                writeSnapshotToUserDefaults(savedAt: remote.savedAt)
            }
            // remote == nil → 신규 디바이스: 현재 시드값(0) 유지.
        } catch {
            // 네트워크 실패 → loadPersistedSnapshot이 채운 fallback 유지. silent.
        }
    }

    /// DB에서 받은 UserStatsDTO를 in-memory 상태에 적용.
    /// freezeInventory / lastSuccessDate는 DTO에 없어 건드리지 않음 (DTO 확장은 별도 PR).
    private func applyRemoteSnapshot(_ remote: UserStatsDTO) {
        chewCount = remote.chewCount
        streak = remote.streak
        points = remote.points
        goalAlreadyHit = remote.goalAlreadyHit
        owned = Set(remote.owned)
        equipped = Equipped(hat: remote.equipped.hat, glasses: remote.equipped.glasses, acc: remote.equipped.acc)
        ownedAcornPacks = remote.ownedAcornPacks
    }

    /// 현재 in-memory 상태를 UserDefaults에 write-through. savedAt은 DB row의 값을 그대로 사용.
    /// freezeInventory / lastSuccessDate는 현재 in-memory 값을 그대로 유지.
    private func writeSnapshotToUserDefaults(savedAt: Date) {
        let snapshot = PersistedSnapshot(
            chewCount: chewCount,
            streak: streak,
            points: points,
            goalAlreadyHit: goalAlreadyHit,
            savedAt: savedAt,
            owned: Array(owned),
            equipped: equipped,
            ownedAcornPacks: ownedAcornPacks,
            freezeInventory: freezeInventory,
            lastSuccessDate: lastSuccessDate
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
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
            // 리포트가 생성될 수 없는 세션(durationSec < 60 또는 분석 5필드 nil)은
            // 사용자에게 결과를 못 보여주는 만큼 도토리도 주지 않는다.
            let canRender = ReportCardModel.from(dto) != nil
            let granted = canRender
                ? RewardLedger.accrue(forSession: dto.id, chewCount: dto.estimatedTotalChews)
                : 0
            if granted > 0 {
                points += granted
            }
            // PRD #11 streak — 세션 종료 시 카운트 평가 + 마일스톤 프리즈 적립 + 2일+ 공백
            // 시 자동 방어. foreground 진입에선 evaluate 안 함(이번 PR 단순화) — 다음
            // 세션 종료에서 한 번에 정리.
            let streakEvents = StreakService.evaluate(self)
            if granted > 0 || !streakEvents.isEmpty {
                persistSnapshot()
            }
            // 우선순위: streak event(milestone/saved/reset) > 세션 종료 도토리.
            // 같은 시점에 둘 다 발생할 수 있어도 dialog는 1개만 — milestone이 더 임팩트.
            if let streakGrant = StreakService.noticeGrant(from: streakEvents) {
                pendingRewardGrant = streakGrant
            } else if granted > 0 {
                // SessionResultSheet가 먼저 떠 있는 상태 — ContentView overlay는
                // sheet 닫힌 후(`lastCompletedSession == nil`)에만 그려져, 다이얼로그가
                // sheet에 가려지지 않고 순차로 등장한다.
                pendingRewardGrant = RewardGrant(amount: granted, kind: .sessionComplete)
            }
        } catch {
            sessionUploadStatus = .failure
            pendingUpload = (output: output, stats: stats)
        }
    }

    /// DB의 `profiles.displayName`을 가져와 in-memory + UserDefaults 갱신.
    /// 신규 디바이스(profile 없음)거나 displayName이 nil/빈 문자열이면 그대로 둠.
    /// 종료 시 `didLoadProfile = true`로 마크 — ContentView가 onboarding sheet 띄울지
    /// 결정할 때 참조.
    @MainActor
    private func fetchAndApplyDisplayName() async {
        let deviceId = DeviceIdentity.shared
        let profile = try? await remoteStore.fetchProfile(deviceId: deviceId)
        if let name = profile?.displayName, !name.isEmpty {
            if name != displayName {
                displayName = name
            }
            // DB에 이름이 있다 = 이전에 온보딩을 마친 기존 사용자. 재설치로 로컬 플래그가
            // 비었어도 사용법 튜토리얼을 다시 띄우지 않도록 완료로 마크한다.
            if !hasCompletedOnboarding {
                hasCompletedOnboarding = true
            }
        }
        // displayName 먼저 set 후 마지막에 didLoadProfile = true. 둘이 같은 main-actor
        // 동기 블록에서 순차로 갱신되면 ContentView의 onboardingBinding 평가가 한 frame에
        // 일관된 두 값으로 수행돼, "didLoadProfile만 true + displayName 아직 nil" 중간
        // 상태에서 sheet이 열리는 race를 피한다.
        didLoadProfile = true
        // 재설치한 기존 사용자(위에서 hasCompletedOnboarding을 막 true로 올린 경우): foreground
        // 진입 시점엔 아직 false라 attendance를 건너뛰었으므로, 여기서 이어서 트리거한다.
        if isInForeground && hasCompletedOnboarding {
            grantDailyAttendanceIfNeeded()
        }
    }

    /// Onboarding sheet의 "저장" 버튼에서 호출. trim 후 in-memory + DB upsert.
    @MainActor
    func saveDisplayName(_ rawName: String) async {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        profileEnsured = true
        // 출석 보상은 여기서 트리거하지 않는다 — 이름 저장 뒤엔 사용법 튜토리얼이 이어지므로,
        // 보상은 튜토리얼이 끝나는 completeOnboarding()에서 띄운다(보상이 튜토리얼 위로
        // 떠버리는 회귀 방지). 이름 저장 시점엔 DB upsert만 수행.
        let deviceId = DeviceIdentity.shared
        try? await remoteStore.upsertProfile(ProfileDTO(deviceId: deviceId, displayName: trimmed))
    }

    /// 사용법 튜토리얼의 마지막 "시작하기"(또는 우상단 "건너뛰기")에서 호출. 온보딩 완료를
    /// 마크해 sheet을 닫고, 메인 화면이 보이는 이 시점에 비로소 도토리 출석 보상을 트리거한다.
    @MainActor
    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        grantDailyAttendanceIfNeeded()
    }

    /// 일일 출석 보상 + 스트릭 foreground 자동 방어를 한 번에 평가한다. RewardLedger와
    /// StreakService 양쪽 다 같은 날 중복 호출에 idempotent하므로 여러 진입점에서 안전.
    @MainActor
    private func grantDailyAttendanceIfNeeded() {
        let granted = RewardLedger.claimDailyAttendance()
        if granted > 0 {
            points += granted
        }
        let streakEvents = StreakService.evaluateForegroundDefense(self)
        if !streakEvents.isEmpty || granted > 0 {
            persistSnapshot()
        }
        // dialog 우선순위: streak event(savedByFreeze/reset) > 출석 보너스.
        if let streakGrant = StreakService.noticeGrant(from: streakEvents) {
            pendingRewardGrant = streakGrant
        } else if granted > 0 {
            pendingRewardGrant = RewardGrant(amount: granted, kind: .attendance)
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
        // 리포트가 가능한 세션만 노출. DB엔 남아 있어도 앱에선 없는 것처럼 처리.
        todaySessions = rows.filter { ReportCardModel.from($0) != nil }
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

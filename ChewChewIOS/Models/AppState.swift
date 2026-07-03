import Foundation
import Observation
import CoreMotion
#if canImport(UIKit)
import UIKit
#endif

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
            "AirPods 연결 중"
        case .live:
            "AirPods 신호 수신 중"
        case .demo:
            "AirPods 없음 · 데모 파형"
        case .unavailable:
            "지원 AirPods 없음 · 데모 파형"
        case .denied:
            "모션 권한 필요 · 데모 파형"
        case .restricted:
            "모션 사용 제한됨 · 데모 파형"
        case .error:
            "센서 수신 오류 · 데모 파형"
        }
    }

    var usesRealMotion: Bool {
        self == .live || self == .connecting
    }
}

/// 앱의 글로벌 상태 + 식사 세션 관리.
///
/// 실 씹기 검출은 `ChewCounter`(DSP)가 IMU sample을 받아 피크를 세고,
/// 세션 종료 시 `chewing_session` 행의 분석 5필드로 저장 — Tracking 탭의 "오늘의 식사 기록"
/// 에서 사후 확인. 식사 중 다람이의 씹기 모션은 `animKey`를 일정 주기로 올려 구동하며,
/// 실제 씹기 검출과는 무관한 화면 연출이다.
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

    var streak: Int = 0
    var points: Int = 0
    /// 다람이 씹기 모션 트리거 — 식사 중 펄스 타이머가 일정 주기로 올려 SquirrelView가
    /// 한 번 우물거리는 bounce를 재생한다. 실제 씹기 횟수가 아니라 화면 연출용 카운터.
    var animKey: Int = 0

    /// 스트릭 프리즈 인벤토리(0~3). ODO-54 전환 후 정본은 서버다 — `applyHome`이 서버 홈 응답의
    /// `freezeInventory`로 갱신하고 HomeView가 "🛡️N"으로 표시한다. 마일스톤 적립·소진 계산은 모두 서버.
    var freezeInventory: Int = 0

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

    /// 로그인에 사용한 소셜 provider 식별자("apple"/"kakao"/"google"). 설정 화면의
    /// "로그인 계정" 표시용. `completeLogin(method:)`에서 set, 로그아웃/세션 클리어 시 nil.
    /// didSet에서 UserDefaults 캐시 갱신 — cold-start에 즉시 복원한다.
    var loginMethod: String? {
        didSet {
            if let method = loginMethod {
                UserDefaults.standard.set(method, forKey: Self.loginMethodKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.loginMethodKey)
            }
        }
    }

    var friendInviteCode: String?
    var friendInviteDeepLink: String?
    var friendRankings: [FriendRankingDTO] = []

    /// 친구 영역(초대 코드·랭킹) 로딩 상태. 실패를 "불러오는 중"과 구분해, 무한 로딩 대신 에러+재시도를 노출한다.
    enum FriendAreaLoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    var friendAreaLoadState: FriendAreaLoadState = .loading

    /// 딥링크로 받았지만 아직 미로그인이라 보류 중인 초대 코드. 로그인/가입(OAuth) 완료 후 자동 수락한다.
    var pendingInviteCode: String?

    /// 전역 토스트(딥링크 친구 수락 결과 등). ContentView가 하단에 표시한다.
    var globalToast: String?

    /// `fetchAndApplyDisplayName` 한 번 끝났는지. 시작 직후 DB fetch 완료 전엔 false로 두어
    /// "기존 사용자가 reinstall한 cold-start에서 sheet이 잠깐 깜빡이는" 케이스를 차단.
    /// 처음 fetch가 끝나면 true로 마크 — 그 시점에 displayName nil이면 진짜 신규 디바이스.
    var didLoadProfile: Bool = false

    /// 서버 OAuth 로그인 여부(ODO-47). 토큰이 Keychain에 있으면 로그인 상태로 시작.
    /// false인 동안 ContentView가 LoginView를 fullScreenCover로 띄운다.
    var isLoggedIn: Bool = TokenManager.isLoggedIn

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
    private static let loginMethodKey = "ChewChewIOS.AppState.loginMethod"
    private static let onboardingCompleteKey = "ChewChewIOS.AppState.hasCompletedOnboarding"
    private static let pendingInviteCodeKey = "ChewChewIOS.AppState.pendingInviteCode"

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

    /// 끼니 리마인더 알림의 "식사 시작" 액션에서 set. HomeView가 관찰해 시작 가드를
    /// 그대로 태운다(모션 권한·AirPods 체크 재사용). 한 번 처리하면 false로 되돌린다.
    var pendingMealStartRequest: Bool = false

    /// 앱 foreground 여부. scenePhase 관찰자가 갱신.
    /// 초기값 false — 앱 launch 시점엔 아직 .active phase가 아니므로, scenePhase가
    /// `.active`로 처음 도달할 때 `sceneDidChange(toForeground:true)`의 전이
    /// 조건(`!wasInForeground && toForeground`)이 성립해 일일 출석 보너스가 트리거된다.
    var isInForeground: Bool = false

    /// 시뮬레이터에선 첫 접근을 막아 CoreMotion 권한 다이얼로그가 안 뜨도록 lazy.
    /// 실기기에선 식사 시작 시 최초 1회 init.
    @ObservationIgnored private lazy var headphoneMotionService = HeadphoneMotionService()
    @ObservationIgnored private var chewPulseTimer: Timer?
    @ObservationIgnored private var demoIMUWaveformTimer: Timer?
    @ObservationIgnored private var imuWaveformPhase: Double = 0

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

    // MARK: - 씹기 감지 (DSP)

    /// 식사 세션 동안 활성. IMU 샘플을 받아 DSP로 씹기 피크를 세고, 종료 시 세션 통계 산출.
    @ObservationIgnored private var chewCounter: ChewCounter?

    /// 씹기 3초 지속 감지마다 울리는 코드 합성 비프(에셋 없음). 식사 세션 동안만 활성.
    @ObservationIgnored private let chewBeepPlayer = ChewBeepPlayer()

    /// 현재 사용 중인 감지 알고리즘 식별자. DB의 `model_version` 컬럼에 저장.
    private static let modelVersion = "dsp-chewcounter-1"

    // MARK: - Remote persistence

    /// 원격 백엔드(InsForge)에 대한 추상화. 테스트/시뮬레이터에선 NoopRemoteStore 주입 가능.
    @ObservationIgnored let remoteStore: RemoteStore

    /// 제품·리텐션 분석 포트(ODO-79). Amplitude·(후속) Firebase로 fan-out. 테스트/미설정 시 Noop.
    @ObservationIgnored let analytics: AnalyticsService

    /// 서버 기반 식사 푸시 조정자(ODO-56) — APNs 토큰 등록 + 서버/로컬 알림 전환을 관리.
    @ObservationIgnored let mealPushCoordinator: MealPushCoordinator

    @ObservationIgnored private let authSessionManager: AuthSessionManaging

    /// 게임 상태 원격 동기화(upsert/delete) 직렬화 큐.
    /// 짧은 시간에 여러 mutate가 일어나면 detached Task들의 네트워크 도착 순서가 뒤집혀
    /// 중간 상태가 winner로 굳을 수 있어, 각 작업이 이전 작업 종료를 await하는 체인으로 직렬화한다.
    @ObservationIgnored private var remoteSyncChain: Task<Void, Never> = Task {}

    /// 한 끼 식사의 raw IMU 6채널을 메모리에 모으는 버퍼. 식사 종료 시 봉인 + 업로드.
    @ObservationIgnored private var imuSessionRecorder: IMUSessionRecorder?

    /// 식사 종료 직후 IMU 세션 업로드 결과. 화면이 alert 표시할 때 binding으로 관찰.
    var sessionUploadStatus: SessionUploadStatus = .idle

    /// 업로드 실패 시 사용자에게 보여줄 사유(서버가 준 메시지 / 오프라인 안내 등).
    /// nil이면 화면이 기본 카피를 쓴다. 성공·dismiss 시 비운다.
    var sessionUploadErrorMessage: String?

    /// 서버가 계산한 홈 상태(도토리/스트릭/오늘 진행도)의 최신 스냅샷. ODO-54 thin-client 전환 후
    /// 도토리·스트릭·오늘완료의 정본은 서버다. 세션 저장 응답·홈 조회·출석 적립이 이 값을 갱신하고,
    /// `points`/`streak`/`freezeInventory`와 derived 프로퍼티는 모두 여기서 흘러나온다.
    /// nil이면 아직 서버 응답 전 — 로컬 캐시 fallback. derived 프로퍼티가 이 값을 읽으므로
    /// 관찰 대상으로 둔다(변경 시 홈 화면 자동 갱신).
    private(set) var serverHome: HomeStateDTO?

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

    /// 도토리/스트릭 보상 시 ContentView가 overlay로 보여줄 RewardDialogView trigger.
    /// 서버 응답(세션 적립·스트릭 이벤트·출석 적립)을 받아 set, 다이얼로그 dismiss 시 nil.
    /// 출석(`.attendance`) + 세션 적립(`.sessionComplete`) + 스트릭 이벤트(`.streak*`) trigger.
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

    init(
        remoteStore: RemoteStore = NoopRemoteStore(),
        authSessionManager: AuthSessionManaging = NoopAuthSessionManager(),
        analytics: AnalyticsService = NoopAnalytics()
    ) {
        self.remoteStore = remoteStore
        self.authSessionManager = authSessionManager
        self.analytics = analytics
        self.mealPushCoordinator = MealPushCoordinator(remoteStore: remoteStore)
        // displayName은 game state(`PersistedSnapshot`)과 다른 별도 캐시 키 — cold-start
        // 시 UserDefaults에서 즉시 read해 HomeView가 빈 이름으로 깜빡이지 않도록.
        displayName = UserDefaults.standard.string(forKey: Self.displayNameKey)
        // 로그인 provider도 같은 캐시 키 방식으로 복원 — 설정 화면이 즉시 표시할 수 있게.
        loginMethod = UserDefaults.standard.string(forKey: Self.loginMethodKey)
        // 온보딩 완료 플래그 로드. 신규 키라, 이미 이름이 있는 기존 사용자(앱 업데이트로 이 키가
        // 아직 없는 상태)는 사용법 튜토리얼을 본 적 없어도 다시 띄우지 않도록 true로 마이그레이션.
        // init 내 대입은 didSet을 발동시키지 않으므로 UserDefaults write는 명시적으로 한다.
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey)
        if !hasCompletedOnboarding && displayName != nil {
            hasCompletedOnboarding = true
            UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        }
        // 로그인 도중 앱이 종료돼도 보류 초대가 살아남도록 복원(로그인 완료 시 소비).
        pendingInviteCode = UserDefaults.standard.string(forKey: Self.pendingInviteCodeKey)
        // 즉시 표시용 fallback — DB 실패 또는 응답 전에 화면 그려도 마지막 캐시값으로.
        loadPersistedSnapshot()
        Task { [weak self] in
            // push 경로의 authExpired를 기존 세션 만료 처리(handleRemoteError → expireSession)로 연결한다.
            // init 시점엔 self 캡처가 불가해 생성 직후 여기서 핸들러를 건다.
            await self?.mealPushCoordinator.setAuthExpiredHandler { [weak self] in
                Task { @MainActor in self?.handleRemoteError(RemoteStoreError.authExpired) }
            }
            await self?.refreshFromServerHome()
            await self?.fetchAndApplyDisplayName()
        }
    }

    // MARK: - Eating actions

    func startEating() {
        guard !isEating else { return }
        isEating = true
        analytics.track(.mealSessionStarted())
        let now = Date()
        eatingStartedAt = now
        // 새 세션 시작 시 IMU 진단 지표 리셋 — 백그라운드 수집 여부 검증에 깨끗한 기준 제공
        imuSampleCount = 0
        lastIMUSampleAt = nil
        // raw IMU 6채널을 모을 봉투 — 식사 종료 시 finalize + 업로드.
        imuSessionRecorder = IMUSessionRecorder(startedAt: now)
        // DSP 씹기 카운터 — 식사 종료 시 chewing_session 분석 5필드 산출용.
        let counter = ChewCounter()
        chewCounter = counter
        // 씹기 3초 지속마다 비프 — ChewCounter actor에서 발화하므로 재생은 MainActor로 홉.
        // AppState(self) 대신 플레이어만 캡처해 순환 참조·옵셔널 self 걱정을 없앤다.
        chewBeepPlayer.prepare()
        let beepPlayer = chewBeepPlayer
        Task {
            await counter.setSustainedChewingHandler {
                Task { @MainActor in
                    beepPlayer.play()
                }
            }
        }
        // 다람이 씹기 모션용 고정 주기 펄스 — 식사 내내 일정 간격으로 animKey만 올려
        // 화면 속 다람이가 자연스럽게 우물거리게 한다. 실제 씹기 검출과는 무관.
        startChewAnimationLoop()

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
                // keep-alive 오디오 세션이 .mixWithOthers라 통화는 우리 세션을 인터럽트하지 않는다
                // (onInterrupt 안 불림) → 측정 정지·카드 갱신을 통화 감지(CXCallObserver) 경로에서 직접 한다.
                // beginBackgroundTask로 실행시간을 확보해 "측정 정지 → 카드(통화 중 멈춤)"가 suspend 전에 끝나게 한다.
                // 통화 중엔 버튼·알림을 띄우지 않고(callActive=true), 종료 시점(onCallEnded)에 계속하기 + 알림을 보여준다.
                #if canImport(UIKit)
                let bgTask = UIApplication.shared.beginBackgroundTask(withName: "MealCallPause")
                defer {
                    if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
                }
                #endif
                self.interruptionWasCall = true
                self.backgroundKeepAlive.markInterruptionBegan()
                self.stopHeadphoneMotionLoop()                              // 측정 정지
                await self.mealActivity.setPaused(true, callActive: true)   // 통화 중 → 멈춤(버튼 없음)
            }
        }
        // 통화 종료 → 카드에 계속하기/그만하기 노출 + "이어서 진행할까요?" 알림.
        // 종료 시점에 앱이 깨어나야(오디오 .ended 또는 CXCallObserver 콜백) 갱신되므로 여기서도 실행시간을 확보한다.
        callMonitor.onCallEnded = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isEating, self.interruptionWasCall else { return }
                #if canImport(UIKit)
                let bgTask = UIApplication.shared.beginBackgroundTask(withName: "MealCallEnded")
                defer {
                    if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
                }
                #endif
                await self.mealActivity.setPaused(true, callActive: false)  // 통화 끝 → 계속/그만 노출
                await MealNotificationService.scheduleInterruptionPrompt()  // "이어서 진행할까요?" 알림
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
        // eatingStartedAt을 nil로 비우기 전에 측정 시간 캡처(중단/실패 이벤트의 duration_sec).
        let sessionDurationSec = eatingStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        eatingStartedAt = nil
        stopHeadphoneMotionLoop()
        stopChewAnimationLoop()
        stopDemoIMUWaveformLoop()
        // 식사가 끝나면 더 이상 백그라운드 wake가 필요 없으므로 즉시 stop —
        // ambient 오디오 세션이 살아있는 동안엔 다른 앱(타이머/시스템 사운드 등)
        // 미디어 라우팅에 영향이 가니, 세션 끝과 동시에 해제하는 게 안전.
        backgroundKeepAlive.onInterrupt = nil
        backgroundKeepAlive.stop()
        callMonitor.onCallStarted = nil
        callMonitor.onCallEnded = nil
        callMonitor.stop()
        interruptionWasCall = false
        MealNotificationService.cancelInterruptionPrompt()
        mealActivity.end()
        resetIMUWaveform()
        imuWaveformSource = .idle
        // 식사 종료 시 게임 진행 상태를 디스크에 한 번에 스냅샷 저장
        persistSnapshot()

        chewBeepPlayer.stop()

        // IMU 세션 봉인 → Storage 업로드 → chewing_session INSERT.
        // 결과를 sessionUploadStatus로 publish해서 UI alert이 관찰할 수 있게 한다.
        let counter = chewCounter
        chewCounter = nil
        if let recorder = imuSessionRecorder {
            imuSessionRecorder = nil
            let endedAt = Date()
            let output = recorder.finalize(endedAt: endedAt)
            // 분석이 불가능한 세션(IMU 샘플 0개)은 DB·도토리·리포트 어디에도
            // 흔적을 남기지 않는다 — 사용자 입장에서 "아무 일도 안 일어난" 상태.
            guard output.sampleCount > 0 else {
                analytics.track(.mealSessionAborted(reason: "no_samples", durationSec: sessionDurationSec))
                return
            }
            sessionUploadStatus = .uploading
            Task { [weak self] in
                let stats = await counter?.sessionStats(modelVersion: AppState.modelVersion)
                await self?.performSessionUpload(output, stats: stats)
            }
        }
    }

    /// 너무 짧게 끝낸 세션을 사용자가 "그만두기" 선택했을 때 호출.
    /// 측정 상태만 정리하고 DB·도토리·리포트엔 어떤 흔적도 남기지 않는다.
    func discardCurrentSession() {
        guard isEating else { return }
        isEating = false
        let sessionDurationSec = eatingStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        eatingStartedAt = nil
        stopHeadphoneMotionLoop()
        stopChewAnimationLoop()
        stopDemoIMUWaveformLoop()
        backgroundKeepAlive.onInterrupt = nil
        backgroundKeepAlive.stop()
        callMonitor.onCallStarted = nil
        callMonitor.onCallEnded = nil
        callMonitor.stop()
        interruptionWasCall = false
        MealNotificationService.cancelInterruptionPrompt()
        mealActivity.end()
        resetIMUWaveform()
        imuWaveformSource = .idle
        persistSnapshot()
        chewBeepPlayer.stop()
        chewCounter = nil
        if let recorder = imuSessionRecorder {
            imuSessionRecorder = nil
            _ = recorder.finalize(endedAt: Date())
        }
        analytics.track(.mealSessionAborted(reason: "user_discard", durationSec: sessionDurationSec))
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
        Task { await self.mealActivity.setPaused(false) }
        backgroundKeepAlive.resume()
        _ = startHeadphoneMotionLoop()
    }

    /// 중단 알림 "그만하기"에서 호출 — 멈춘 세션을 정상 종료(부분 기록 업로드)한다.
    @MainActor
    func stopMeasurementFromNotification() {
        MealNotificationService.cancelInterruptionPrompt()
        guard isEating else { return }
        if AppState.shouldConfirmShortSessionStop(startedAt: eatingStartedAt) {
            showShortSessionConfirm = true
            return
        }
        stopEating()
    }

    /// 앱 내 종료 버튼과 알림 "그만하기"가 공유하는 1분 미만 세션 확인 기준.
    static func shouldConfirmShortSessionStop(startedAt: Date?, now: Date = Date()) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) < 60
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

    /// 끼니 리마인더 알림의 "식사 시작" 액션 진입점. 측정 중이 아니면 시작 요청 플래그를
    /// 올려 HomeView가 시작 가드(권한·AirPods 확인)를 태우게 한다.
    @MainActor
    func requestMealStart() {
        guard !isEating else { return }
        pendingMealStartRequest = true
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
        analytics.track(.shopItemPurchased(itemId: item.id, itemType: item.type.rawValue, price: item.price))
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
        analytics.track(.acornPackPurchased(packId: pack.id, price: pack.price))
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
                Task { await grantDailyAttendanceIfNeeded() }
            }
        }
        if wasInForeground && !toForeground {
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

    /// 설정 '계정 삭제' 확인 시 호출.
    /// 원격: profiles DELETE → FK CASCADE(user_stats/chewing_session/bout).
    /// 로컬: 모든 게임 상태를 초기화하고 스냅샷도 비움.
    @MainActor
    func eraseAllUserData() async {
        // 로컬 인메모리 상태 리셋 (reset()과 동일 범위)
        stopEating()
        streak = 0
        points = 0
        animKey = 0
        freezeInventory = 0
        resetIMUWaveform()
        imuWaveformSource = .idle
        owned = []
        equipped = Equipped()
        ownedAcornPacks = [:]
        todaySessions = []
        lastCompletedSession = nil
        displayName = nil
        loginMethod = nil
        didLoadProfile = false
        // 로컬 스냅샷 + 원격 데이터 삭제 (clearPersistedSnapshot이 remoteStore.deleteUserData 포함)
        clearPersistedSnapshot()
    }

    // MARK: - Reset

    func reset() {
        stopEating()
        streak = 0
        points = 0
        animKey = 0
        resetIMUWaveform()
        imuWaveformSource = .idle
        owned = []
        equipped = Equipped()
        ownedAcornPacks = [:]
        todaySessions = []
        lastCompletedSession = nil
        displayName = nil
        loginMethod = nil
        hasCompletedOnboarding = false
        freezeInventory = 0
        TokenManager.clear()
        isLoggedIn = false
        analytics.setUserId(nil)
        SentryService.setUser(id: nil)
        // 저장된 스냅샷도 비워서 다음 실행에서 시드값이 살아남도록
        clearPersistedSnapshot()
    }

    /// 로그인 + 서버 토큰 발급 성공 후 호출(LoginView). 로그인 상태로 전환하고
    /// 로그인 계정 기준으로 홈/프로필을 다시 적재한다.
    /// `onboardingCompleted`는 로그인 응답(`/auth/login`)의 정본 — true면 즉시 온보딩을
    /// 스킵해, 재로그인 시 온보딩이 다시 뜨던 회귀를 막는다.
    func completeLogin(onboardingCompleted: Bool, method: String) {
        clearLocalSessionCache()
        // clearLocalSessionCache가 hasCompletedOnboarding을 false로 리셋하므로 그 뒤에 세팅한다.
        // 서버 응답이 완료라고 하면 즉시 온보딩 sheet을 스킵 — 재로그인 시 재노출 회귀 차단.
        if onboardingCompleted { hasCompletedOnboarding = true }
        // 로그인 provider 저장 — clearLocalSessionCache가 nil로 비운 뒤라 여기서 세팅한다.
        loginMethod = method
        isLoggedIn = true
        let deviceIdForLogin = DeviceIdentity.shared
        analytics.setUserId(deviceIdForLogin)
        analytics.setUserProperty("has_completed_onboarding", onboardingCompleted)
        SentryService.setUser(id: deviceIdForLogin)
        analytics.track(.login(method: method, onboardingCompleted: onboardingCompleted))
        syncAnalyticsUserProperties()
        Task { [weak self] in
            await self?.refreshFromServerHome()
            await self?.fetchAndApplyDisplayName()
            // 새 로그인(계정 전환 포함)은 항상 서버 발송 신호를 내린 뒤 시작한다 — 기기 전역 armed가 이전 계정에서
            // 누수돼 새 계정 끼니를 오배송/누락하지 않도록(ODO-103 P1). 콜드 스타트 복원은 completeLogin을 거치지
            // 않고 Keychain으로 isLoggedIn을 복원하므로, 같은 계정의 영속 armed(중복 푸시 수정)는 그대로 보존된다.
            await self?.mealPushCoordinator.clearRegistration()
            // 로그인 직후 끼니 알림 동기화 — 정본인 서버에서 이 계정 설정을 받아 화면·로컬을 맞추고 전달 경로를 정합한다.
            // (.task는 앱 시작 시 1회뿐이라, 앱 실행 중 로그인하면 여기서 다시 걸어줘야 계정 전환이 반영된다.)
            await self?.mealPushCoordinator.syncFromServer()
            // 미로그인 상태에서 받은 초대가 있으면 로그인/가입 완료 후 자동 수락한다.
            await self?.consumePendingInviteCodeIfNeeded()
        }
    }

    /// 분석 유저 속성을 현재 상태로 동기화(코호트 분석용). 로그인·콜드스타트 복원·서버 홈 갱신 시 호출.
    /// 가입일·총세션수는 서버 DTO에 없어 제외(서버 추가 시 후속).
    private func syncAnalyticsUserProperties() {
        analytics.setUserProperty("current_streak", currentStreak)
        analytics.setUserProperty("total_points", points)
    }

    /// 업로드 실패 원인을 저카디널리티 라벨로 분류(meal_session_failed의 reason 속성용).
    private static func uploadFailureReason(_ error: Error) -> String {
        guard let e = error as? RemoteStoreError else { return "unknown" }
        switch e {
        case .authExpired: return "auth_expired"
        case .server: return "server"
        case .offline: return "offline"
        case .malformed: return "malformed"
        case .http: return "http"
        case .invalidUploadResponse: return "invalid_upload"
        }
    }

    /// 로그아웃 — 로컬 토큰 제거 후 로그인 게이트로 복귀. 게임 데이터는 보존('계정 삭제'와 구분).
    func logout() {
        expireSession()
    }

    /// 사용자가 누른 로그아웃 — 서버 refresh token 폐기 후 로컬 세션을 종료한다.
    @MainActor
    func logoutFromServer() async {
        // 토큰이 아직 유효할 때 서버 푸시 토큰을 해제한다(만료 후엔 401이라 의미 없음).
        await mealPushCoordinator.handleLogout()
        await authSessionManager.logout()
        expireSession()
    }

    /// refresh 만료/폐기 등으로 인증 세션을 더 쓸 수 없을 때 로그인 게이트로 복귀한다.
    private func expireSession() {
        // 로컬 끼니 알림 정리 + 코디네이터의 in-memory 등록 토큰 리셋(서버 토큰 해제는 logoutFromServer에서
        // 토큰이 유효할 때 수행. 만료 경로는 401이라 DELETE 무의미하므로 in-memory만 비운다).
        MealNotificationService.cancelMealReminders()
        Task { await mealPushCoordinator.clearRegistration() }
        TokenManager.clear()
        isLoggedIn = false
        analytics.setUserId(nil)
        SentryService.setUser(id: nil)
        clearLocalSessionCache()
    }

    @MainActor
    private func handleRemoteError(_ error: Error) {
        if case RemoteStoreError.authExpired = error {
            expireSession()
        }
    }

    // MARK: - Derived

    var status: MoodStatus { MoodStatus.from(count: todayRealChewCount) }

    /// 홈에 표시할 "오늘 기준" 연속 출석 일수. ODO-54 전환 후 스트릭 정본은 서버다.
    /// 서버 홈 응답의 `streak`(이미 "현재 유효한" 값)을 그대로 쓰고, 서버 응답 전이면
    /// 로컬 캐시(`streak`)로 fallback.
    /// 주의: 오프라인 cold-start에선 만료 검증을 로컬에서 못 한다(`lastSuccessDate`는 서버 소유로
    /// 제거됨). 마지막 성공 스냅샷의 스트릭을 그대로 보여주는 건 ODO-54 Done-When "서버 실패 시
    /// 마지막 성공 상태 보존"에 따른 의도된 동작 — 다음 서버 응답에서 즉시 정정된다.
    var currentStreak: Int {
        serverHome?.streak ?? streak
    }

    /// 오늘의 실제 씹기 횟수. 서버가 계산한 값(오늘 0시 이후 60초+ 세션 합)을 정본으로 쓰고,
    /// 서버 응답 전이면 로컬 `todaySessions` 합으로 fallback. dailyGoal == 0은 "정책 없는 홈"
    /// (InsForge 레거시 어댑터의 legacyHome)의 표지라, 그때도 로컬 합산으로 fallback —
    /// 레거시 백엔드에서 홈 카운트/링이 0에 붙박이는 것을 막는다(todayProgress와 같은 기준).
    var todayRealChewCount: Int {
        if let serverHome, serverHome.dailyGoal > 0 { return serverHome.todayRealChewCount }
        return todaySessions.reduce(0) { $0 + ($1.estimatedTotalChews ?? 0) }
    }

    /// 일일 목표 진행도(0~1). 서버 홈 응답의 진행도를 정본으로 쓰고(분모 dailyGoal>0일 때),
    /// 서버 응답 전이면 로컬 계산으로 fallback. 홈 다람이 둘레 링이 사용.
    var todayProgress: Double {
        if let serverHome, serverHome.dailyGoal > 0 {
            return min(1.0, max(0.0, serverHome.todayProgress))
        }
        return min(1.0, max(0.0, Double(todayRealChewCount) / Double(Constants.dailyGoal)))
    }

    var imuWaveformStatusText: String {
        imuWaveformSource.statusText
    }

    var isIMUWaveformLive: Bool {
        isEating && (imuWaveformSource.usesRealMotion || imuWaveformSource == .demo)
    }

    // MARK: - Chew animation pulse (다람이 씹기 모션용 고정 주기 틱)

    /// 식사 중 다람이가 자연스럽게 우물거리도록 일정 간격으로 `animKey`를 올린다.
    /// SquirrelView가 `animKey` 변화를 받아 한 번 씹는 bounce를 재생 — 실제 씹기 검출과 무관.
    private func startChewAnimationLoop() {
        stopChewAnimationLoop()
        chewPulseTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: true) { [weak self] _ in
            self?.animKey &+= 1
        }
    }

    private func stopChewAnimationLoop() {
        chewPulseTimer?.invalidate()
        chewPulseTimer = nil
    }

    // MARK: - Motion permission guard (REQ-01)

    /// `.notDetermined`이면 즉시 측정을 시작하지 않고 권한 요청 경로로 보낸다.
    /// CoreMotion은 명시적 request API 없이 `startDeviceMotionUpdates` 호출 시 시스템이
    /// 프롬프트를 띄운다. 권한 부여 → `onGranted()`, 거부(에러 콜백) → `onDenied()`.
    func requestMotionPermission(onGranted: @escaping () -> Void, onDenied: @escaping () -> Void) {
        headphoneMotionService.start { [weak self] _ in
            // 첫 샘플이 도착했다 = 권한이 허용됨. 업데이트를 즉시 멈추고 호출자에게 위임.
            self?.headphoneMotionService.stop()
            DispatchQueue.main.async {
                self?.analytics.track(.permissionResult(type: "motion", granted: true))
                onGranted()
            }
        } onError: { [weak self] _ in
            // 에러 = 권한 거부 또는 디바이스 없음.
            DispatchQueue.main.async {
                self?.analytics.track(.permissionResult(type: "motion", granted: false))
                onDenied()
            }
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
            // 같은 row를 DSP ChewCounter에도 흘려보내 세션 통계용으로 누적.
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

            // DSP 씹기 감지는 별도 Task로 — actor 호출이 sample 콜백 빈도(50Hz)를 막지 않도록.
            // 결과는 세션 종료 시 통계 산출에만 쓴다.
            if let chewCounter = self.chewCounter {
                Task {
                    await chewCounter.feed(
                        rotX: row.rotationX,
                        rotY: row.rotationY,
                        rotZ: row.rotationZ,
                        accelX: row.userAccelX,
                        accelY: row.userAccelY,
                        accelZ: row.userAccelZ
                    )
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
    /// v3 — `freezeInventory` 추가. 옵셔널이라 옛 스냅샷은 nil → 기본값(0)으로 초기화.
    /// v4 — 미사용 가짜 카운터 `chewCount`/`goalAlreadyHit` 제거. 옛 스냅샷에 남아 있어도
    /// 디코드 시 미지 키로 무시돼 하위호환 문제 없음.
    /// v5(ODO-54) — `lastSuccessDate` 제거(스트릭 정본 서버화로 미사용). 옛 스냅샷의 잔존 키는 무시.
    private struct PersistedSnapshot: Codable {
        let streak: Int
        let points: Int
        let savedAt: Date
        var owned: [String]?
        var equipped: Equipped?
        var ownedAcornPacks: [String: Int]?
        var freezeInventory: Int?
    }

    /// 게임 진행 상태를 로컬 UserDefaults 캐시에 스냅샷 저장.
    ///
    /// ODO-54 전환 후 도토리/스트릭/오늘완료의 정본은 서버다. iOS는 더 이상 `user_stats`를
    /// 서버로 push하지 않는다 — 옛 push는 서버가 적립한 잔액을 클라 값으로 덮어써 버리기
    /// 때문(서버 PUT /v1/me/stats가 본문을 통째로 반영). 이 스냅샷은 cold-start 시 서버 응답
    /// 도착 전 화면을 그리기 위한 로컬 fallback 캐시 용도로만 남긴다.
    func persistSnapshot() {
        let now = Date()
        let snapshot = PersistedSnapshot(
            streak: streak,
            points: points,
            savedAt: now,
            owned: Array(owned),
            equipped: equipped,
            ownedAcornPacks: ownedAcornPacks,
            freezeInventory: freezeInventory
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistenceKey)
    }

    private func loadPersistedSnapshot() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
            let snapshot = try? JSONDecoder().decode(PersistedSnapshot.self, from: data)
        else { return }
        streak = snapshot.streak
        points = snapshot.points
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
        // v3 옵셔널 필드 — 옛 스냅샷에선 nil이라 신규 streak 상태(0)로 시작
        if let savedFreeze = snapshot.freezeInventory {
            freezeInventory = savedFreeze
        }
    }

    /// 로그아웃/계정 전환 시 iOS에 남은 계정별 화면 캐시만 제거한다.
    /// 원격 데이터 삭제는 `eraseAllUserData` 전용이며 여기서는 호출하지 않는다.
    private func clearLocalSessionCache() {
        streak = 0
        points = 0
        freezeInventory = 0
        owned = []
        equipped = Equipped()
        ownedAcornPacks = [:]
        todaySessions = []
        lastCompletedSession = nil
        pendingRewardGrant = nil
        sessionUploadStatus = .idle
        sessionUploadErrorMessage = nil
        pendingUpload = nil
        displayName = nil
        loginMethod = nil
        didLoadProfile = false
        hasCompletedOnboarding = false
        serverHome = nil
        homeApplyVersion += 1
        // 끼니 설정 로컬 캐시도 비운다 — 다음 계정이 이전 계정 알림시각을 보지 않도록(ODO-103).
        // 정본은 서버이므로 로그인 후 syncFromServer가 이 계정 값으로 다시 채운다.
        MealReminderSettings.clear()
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
    }

    func clearPersistedSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
        // 서버 홈 캐시도 비움 — reset/erase 후 화면이 옛 도토리/스트릭을 잠깐 보여주지 않도록.
        // 적립 멱등 키는 서버 reward_events에 있고, deleteUserData가 그 행들도 함께 제거한다.
        serverHome = nil
        homeApplyVersion += 1   // 초기화 직전 시작된 refreshFromServerHome이 완료 후 applyHome을 실행하지 못하게.
        // 같은 체인으로 — 직전 작업이 끝난 뒤 delete가 나가야 결과가 결정적.
        // profiles 삭제 → FK ON DELETE CASCADE로 user_stats도 자동 정리.
        let store = remoteStore
        let previous = remoteSyncChain
        remoteSyncChain = Task.detached {
            _ = await previous.value
            try? await store.deleteUserData()
        }
    }

    // MARK: - 서버 홈 상태 동기화 (ODO-54 thin-client)

    /// 서버가 계산한 홈 상태를 in-memory에 반영. 도토리/스트릭/프리즈는 서버값으로 덮고,
    /// derived 프로퍼티(currentStreak/todayRealChewCount/todayProgress)는 자동으로 따라온다.
    /// 로컬 캐시도 write-through해 다음 cold-start의 fallback이 최신값을 갖게 한다.
    /// applyHome이 일어날 때마다 증가 — 비행 중인 읽기(GET /home) 응답이 도착했을 때 그 사이
    /// 다른 응답(출석/세션 저장 POST)이 홈을 갱신했는지 판별하는 버전 카운터.
    @ObservationIgnored private var homeApplyVersion = 0

    @MainActor
    private func applyHome(_ home: HomeStateDTO) {
        homeApplyVersion += 1
        serverHome = home
        points = home.points
        streak = home.streak
        freezeInventory = home.freezeInventory
        if let name = home.displayName, !name.isEmpty, name != displayName {
            displayName = name
        }
        // 서버가 갱신한 streak/points를 분석 유저 속성에도 반영(세션 완료·출석 후 코호트 최신화).
        syncAnalyticsUserProperties()
        persistSnapshot()
    }

    /// 서버 홈 상태를 조회해 반영. 실패(네트워크 끊김 등)는 silent — loadPersistedSnapshot이
    /// 채운 로컬 캐시를 그대로 유지한다(서버 실패 시 마지막 성공 상태 보존, ODO-54 Done-When).
    @MainActor
    func refreshFromServerHome() async {
        let deviceId = DeviceIdentity.shared
        let versionAtRequest = homeApplyVersion
        do {
            let home = try await remoteStore.fetchHome(deviceId: deviceId)
            // 이 GET이 비행하는 동안 쓰기 응답(출석/세션 저장)이 홈을 갱신했다면 이 응답은 옛
            // 스냅샷이다 — 적용하면 방금 반영된 적립을 화면에서 되돌리므로 버린다(쓰기 응답 우선).
            guard versionAtRequest == homeApplyVersion else { return }
            applyHome(home)
        } catch {
            handleRemoteError(error)
        }
    }

    /// 서버 스트릭 이벤트 → 보상 다이얼로그 매핑. 계산은 서버가 끝냈고 iOS는 표시만 한다.
    /// NONE/INCREMENTED는 알림 없음(nil). 서버가 한 번에 한 이벤트만 주므로 단순 매핑으로 충분.
    private func rewardGrant(forStreak streak: SessionStreakDTO) -> RewardGrant? {
        switch streak.event {
        case "MILESTONE":       return RewardGrant(amount: 1, kind: .streakMilestone(streakCount: streak.current))
        case "SAVED_BY_FREEZE": return RewardGrant(amount: streak.freezeInventory, kind: .streakSaved)
        case "RESET":           return RewardGrant(amount: 0, kind: .streakReset)
        case "FIRST_DAY":       return RewardGrant(amount: 0, kind: .streakFirstDay)
        default:                return nil
        }
    }

    /// 앱-열기 출석 멱등키 — REQ-08 형식(`app-open-<deviceId>-<yyyyMMdd Asia/Seoul>`).
    /// iOS가 트리거 시점에 키를 만들고, 서버가 이 키로 일 1회 적립을 판정한다.
    /// 서버(AttendanceService)가 같은 포맷으로 키를 유도하므로, 포맷 변경 시 양쪽을 함께 고쳐야
    /// 같은 날 두 키가 갈라져 이중 적립되는 일을 막는다.
    static func attendanceKey(deviceId: String, now: Date = Date()) -> String {
        "app-open-\(deviceId)-\(attendanceKeyFormatter.string(from: now))"
    }

    /// DateFormatter의 포맷팅은 iOS 7+에서 thread-safe지만, 현재 호출 경로는 모두 MainActor다.
    /// 비-메인 호출자를 추가한다면 그 점을 인지하고 쓸 것.
    private static let attendanceKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

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
                modelVersion: stats?.modelVersion,
                chewingTimeline: stats?.chewingTimeline
            )
            // 정책 엔드포인트로 저장 — 서버가 적립/스트릭/오늘완료/홈을 계산해 함께 돌려준다.
            let result = try await remoteStore.createChewingSession(dto)
            sessionUploadStatus = .success
            sessionUploadErrorMessage = nil
            pendingUpload = nil
            // 서버가 계산한 도토리/스트릭/오늘 상태를 화면에 반영(정본). iOS는 재계산하지 않는다.
            applyHome(result.userStats)
            let isReportable = ReportCardModel.from(dto) != nil
            analytics.track(.mealSessionCompleted(
                durationSec: Int(dto.durationSec),
                sampleCount: dto.sampleCount,
                chewingFraction: dto.chewingFraction,
                estimatedTotalChews: dto.estimatedTotalChews,
                reportable: isReportable
            ))
            // 리포트가 생성될 수 없는 세션(durationSec < 60 또는 분석 5필드 nil)은 결과·보상
            // 다이얼로그 어디에도 반영하지 않는다 — 서버도 rewardEligible=false로 보상 0.
            // 알림 '그만하기'로 끝낸 너무 짧은 세션도 홈 '그만두기'(discard)와 동일하게 무보상.
            // raw IMU는 이미 업로드됐고, fetchTodaySessions가 reload 시 이런 세션을 필터한다.
            guard isReportable else { return }

            // 방금 저장한 행을 즉시 리스트에 반영 — GET 라운드트립 생략.
            // started_at 오름차순 정렬을 유지하기 위해 append (방금 종료된 세션이 가장 최신).
            todaySessions.append(dto)
            // 식사 종료 직후 ReportCardView를 sheet로 띄울 trigger. 사용자가 닫으면 nil.
            lastCompletedSession = dto
            // 우선순위: 스트릭 이벤트(마일스톤/프리즈/리셋/첫날) > 세션 적립 도토리. 둘 다
            // 발생해도 다이얼로그는 1개만 — milestone이 더 임팩트. 모두 서버 응답값으로 표시만 한다.
            // 멱등 재전송(idempotentReplay)이면 적립 0이므로 도토리 다이얼로그를 띄우지 않는다.
            // 다이얼로그는 우선순위 1개만 표시(스트릭 > 세션 적립). UI 정책.
            if let streakGrant = rewardGrant(forStreak: result.streak) {
                pendingRewardGrant = streakGrant
                analytics.track(.streakEvent(type: streakGrant.kind.analyticsType, amount: streakGrant.amount))
            } else if result.reward.grantedPoints > 0 && !result.reward.idempotentReplay {
                // SessionResultSheet가 먼저 떠 있는 상태 — ContentView overlay는
                // sheet 닫힌 후(`lastCompletedSession == nil`)에만 그려져, 다이얼로그가
                // sheet에 가려지지 않고 순차로 등장한다.
                pendingRewardGrant = RewardGrant(amount: result.reward.grantedPoints, kind: .sessionComplete)
            }
            // 적립 도토리 트래킹은 다이얼로그 우선순위와 분리한다 — 스트릭 마일스톤과 세션 적립이
            // 동시에 발생해도 reward_earned가 누락되지 않도록(과소집계 방지). streak_event와는 별도 이벤트.
            if result.reward.grantedPoints > 0 && !result.reward.idempotentReplay {
                analytics.track(.rewardEarned(amount: result.reward.grantedPoints, kind: "session_complete"))
            }
        } catch {
            handleRemoteError(error)
            if case RemoteStoreError.authExpired = error { return }
            analytics.track(.mealSessionFailed(reason: Self.uploadFailureReason(error)))
            sessionUploadStatus = .failure
            // 사용자에겐 부드러운 통일 카피(userMessage)만 노출 — 서버 원문은 로그(description)로만 남는다.
            sessionUploadErrorMessage = (error as? RemoteStoreError)?.userMessage
            pendingUpload = (output: output, stats: stats)
        }
    }

    /// 콜드 스타트·포그라운드 진입 시 서버에서 displayName + onboardingCompleted를 가져와
    /// in-memory + UserDefaults 갱신.
    ///
    /// 1) 로그인 상태면 `/auth/me`(정본 엔드포인트)로 onboardingCompleted를 권위 있게 설정.
    ///    성공 시 true/false 모두 반영 — 서버가 완료라고 해도, 미완료라고 해도 그대로 따른다.
    ///    me() 실패(오프라인·토큰 만료 등)면 step2의 profile 기반 레거시 폴백으로 내려간다.
    /// 2) profiles 테이블에서 displayName 로드(표시 이름 표시용 + me() 실패 시 온보딩 폴백).
    ///    displayName nil/빈 문자열이면 신규 사용자로 간주, profile fetch 실패도 silent 처리.
    /// 종료 시 `didLoadProfile = true` — ContentView가 onboarding sheet 표시 여부 결정에 사용.
    @MainActor
    private func fetchAndApplyDisplayName() async {
        // Step 1: /auth/me — onboardingCompleted 정본. 로그인 상태일 때만 시도.
        var meSucceeded = false
        if isLoggedIn {
            if let result = try? await authSessionManager.me() {
                // 서버 값이 정본 — true/false 모두 기존 로컬 값에 우선한다.
                hasCompletedOnboarding = result.onboardingCompleted
                // displayName도 함께 갱신(있을 때만).
                if let name = result.displayName, !name.isEmpty, name != displayName {
                    displayName = name
                }
                meSucceeded = true
            }
        }

        // Step 2: profiles 테이블 — displayName 로드 + me() 실패 시 온보딩 폴백.
        let profile: ProfileDTO?
        do {
            profile = try await remoteStore.fetchProfile()
        } catch {
            handleRemoteError(error)
            // profile fetch 실패해도 me()가 성공했으면 onboarding 판정은 이미 완료.
            didLoadProfile = true
            if isInForeground && hasCompletedOnboarding {
                await grantDailyAttendanceIfNeeded()
            }
            return
        }
        if let name = profile?.displayName, !name.isEmpty {
            if name != displayName {
                displayName = name
            }
            // me() 실패(오프라인 등) 폴백: DB에 이름이 있다 = 이전에 온보딩을 마친 기존 사용자.
            // 재설치로 로컬 플래그가 비었어도 사용법 튜토리얼을 다시 띄우지 않도록 완료로 마크.
            if !meSucceeded && !hasCompletedOnboarding {
                hasCompletedOnboarding = true
            }
        }
        // displayName 먼저 set 후 마지막에 didLoadProfile = true. 둘이 같은 main-actor
        // 동기 블록에서 순차로 갱신되면 ContentView의 onboardingBinding 평가가 한 frame에
        // 일관된 두 값으로 수행돼, "didLoadProfile만 true + displayName 아직 nil" 중간
        // 상태에서 sheet이 열리는 race를 피한다.
        // 콜드스타트 기존 유저 식별 복원 — Keychain 토큰이 있어 completeLogin()을
        // 거치지 않고 재실행된 경우 Analytics + Sentry에 ID를 등록한다.
        if isLoggedIn {
            let deviceIdForRestore = DeviceIdentity.shared
            analytics.setUserId(deviceIdForRestore)
            analytics.setUserProperty("has_completed_onboarding", hasCompletedOnboarding)
            SentryService.setUser(id: deviceIdForRestore)
            syncAnalyticsUserProperties()
        }
        didLoadProfile = true
        // 재설치한 기존 사용자(위에서 hasCompletedOnboarding을 막 true로 올린 경우) 또는
        // me()로 온보딩 완료를 확인한 경우: foreground 진입 시점엔 아직 false였을 수 있으므로,
        // 여기서 이어서 출석 적립을 트리거한다.
        if isInForeground && hasCompletedOnboarding {
            await grantDailyAttendanceIfNeeded()
        }
    }

    /// Onboarding sheet의 "저장" 버튼에서 호출. trim 후 in-memory + DB upsert.
    @MainActor
    func saveDisplayName(_ rawName: String) async {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        // 출석 보상은 여기서 트리거하지 않는다 — 이름 저장 뒤엔 사용법 튜토리얼이 이어지므로,
        // 보상은 튜토리얼이 끝나는 completeOnboarding()에서 띄운다(보상이 튜토리얼 위로
        // 떠버리는 회귀 방지). 이름 저장 시점엔 DB upsert만 수행.
        let deviceId = DeviceIdentity.shared
        do {
            try await remoteStore.upsertProfile(ProfileDTO(deviceId: deviceId, displayName: trimmed))
        } catch {
            handleRemoteError(error)
        }
    }

    /// 사용법 튜토리얼의 마지막 "시작하기"(또는 우상단 "건너뛰기")에서 호출. 온보딩 완료를
    /// 마크해 sheet을 닫고, 메인 화면이 보이는 이 시점에 비로소 도토리 출석 보상을 트리거한다.
    @MainActor
    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        analytics.track(.onboardingCompleted())
        Task { await grantDailyAttendanceIfNeeded() }
    }

    /// 앱-열기 출석 적립을 서버에 요청한다. iOS는 멱등키로 트리거만 하고, 일 1회 적립 판정과
    /// 잔액은 서버가 정본으로 정한다. 같은 날 이미 받았으면 서버가 idempotentReplay=true(적립 0)로
    /// 응답해 다이얼로그가 뜨지 않는다(여러 진입점에서 중복 호출해도 안전). 응답으로 홈 상태를
    /// 갱신해 foreground 진입 때 화면도 최신화된다. 실패(네트워크 등)는 silent — 다음 진입에서 재시도.
    ///
    /// foreground 스트릭 자동 방어는 ODO-54에서 드롭했다. 방어는 다음 세션 저장 응답의
    /// SAVED_BY_FREEZE 이벤트로 흡수되며, 서버 홈 조회(GET /v1/me/home)는 readOnly라 스트릭을
    /// 건드리지 않는다.
    @MainActor
    private func grantDailyAttendanceIfNeeded() async {
        let deviceId = DeviceIdentity.shared
        let key = Self.attendanceKey(deviceId: deviceId)
        let result: AttendanceResultDTO
        do {
            result = try await remoteStore.earnAttendance(deviceId: deviceId, idempotencyKey: key)
        } catch {
            handleRemoteError(error)
            return
        }
        applyHome(result.userStats)
        if result.grantedPoints > 0 && !result.idempotentReplay {
            pendingRewardGrant = RewardGrant(amount: result.grantedPoints, kind: .attendance)
            analytics.track(.rewardEarned(amount: result.grantedPoints, kind: "attendance"))
        }
    }

    /// Tracking 탭 .task에서 호출 — 오늘 0시 이후 세션을 원격에서 가져와 리스트 동기화.
    /// 실패는 silent (네트워크 끊김 등); 사용자에겐 빈 리스트로 보이는 게 alert보다 덜 거슬림.
    @MainActor
    func fetchTodaySessions() async {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let deviceId = DeviceIdentity.shared
        let rows: [ChewingSessionDTO]
        do {
            rows = try await remoteStore.fetchChewingSessions(deviceId: deviceId, since: startOfDay)
        } catch {
            handleRemoteError(error)
            return
        }
        // 리포트가 가능한 세션만 노출. DB엔 남아 있어도 앱에선 없는 것처럼 처리.
        todaySessions = rows.filter { ReportCardModel.from($0) != nil }
        // 오늘 씹기 수·진행도·완료 여부는 서버가 정본 — 세션 리스트 동기화와 함께 홈도 갱신한다.
        await refreshFromServerHome()
    }

    /// 단일 세션 삭제 — 캘린더 DaySessionsView에서 swipe로 호출. todaySessions에서도
    /// 즉시 제거해 UI 동기화. 실패는 silent — 다음 reload에서 서버 상태와 다시 sync.
    @MainActor
    func deleteSession(_ session: ChewingSessionDTO) async {
        let deviceId = DeviceIdentity.shared
        do {
            try await remoteStore.deleteChewingSession(id: session.id, deviceId: deviceId)
            todaySessions.removeAll { $0.id == session.id }
            // 오늘 씹기 수·진행도가 줄었을 수 있으므로 서버 홈을 다시 받아 반영.
            await refreshFromServerHome()
        } catch {
            handleRemoteError(error)
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
            // 오늘 씹기 수·진행도가 0으로 바뀌므로 서버 홈을 다시 받아 반영.
            await refreshFromServerHome()
        } catch {
            handleRemoteError(error)
            return
        }
    }

    @MainActor
    func refreshFriendArea() async {
        // 이미 코드를 받아둔 뒤의 새로고침은 화면을 비우지 않는다(첫 로딩일 때만 로딩 상태로).
        if friendInviteCode == nil { friendAreaLoadState = .loading }
        // 일시적 실패로 바로 에러를 띄우지 않는다: 짧은 backoff로 최대 3회 시도하고, 그 동안은 로딩(스피너) 유지.
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                let invite = try await remoteStore.fetchFriendInviteCode()
                friendInviteCode = invite.code
                friendInviteDeepLink = invite.deepLink
                friendRankings = try await remoteStore.fetchFriendRanking()
                friendAreaLoadState = .loaded
                return
            } catch {
                // 인증 만료는 재시도로 풀리지 않으므로 즉시 실패 처리(세션 만료 핸들링은 그대로).
                if case RemoteStoreError.authExpired = error {
                    handleRemoteError(error)
                    friendAreaLoadState = .failed
                    return
                }
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .seconds(1))  // 다음 시도 전 짧게 대기
                } else {
                    friendAreaLoadState = .failed  // 3회 모두 실패한 뒤에만 에러 노출
                }
            }
        }
    }

    @MainActor
    func acceptFriendInvite(code: String) async {
        do {
            let result = try await remoteStore.acceptFriendInvite(code: code)
            await refreshFriendArea()
            flashToast(result.bonusGranted ? "친구가 됐어요! 도토리 100개 받았어요" : "이미 친구예요")
        } catch {
            handleRemoteError(error) // authExpired면 세션 만료 처리(로그인 게이트로 복귀)
            flashToast(acceptErrorMessage(error))
        }
    }

    /// 딥링크(카카오/외부 공유)로 받은 초대 코드 처리. 로그인 상태면 바로 수락하고,
    /// 미로그인이면 보관했다가 로그인/가입(OAuth) 완료 후 자동 수락한다.
    @MainActor
    func receiveInviteCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        analytics.track(.friendInviteReceived(loggedIn: isLoggedIn))
        if isLoggedIn {
            Task { await acceptFriendInvite(code: trimmed) }
        } else {
            // 로그인 게이트(isLoggedIn=false)는 이미 노출됨. 로그인 후 자동 수락하도록 보관.
            pendingInviteCode = trimmed
            UserDefaults.standard.set(trimmed, forKey: Self.pendingInviteCodeKey)
            flashToast("로그인하면 친구가 돼요")
        }
    }

    /// 보류된 초대 코드가 있으면 수락하고 비운다(로그인 완료 직후 호출).
    @MainActor
    private func consumePendingInviteCodeIfNeeded() async {
        guard let code = pendingInviteCode else { return }
        pendingInviteCode = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingInviteCodeKey)
        await acceptFriendInvite(code: code)
    }

    /// 친구 수락 실패 토스트 문구. 서버 에러 코드(4011/4012)·오프라인·만료를 구분한다.
    private func acceptErrorMessage(_ error: Error) -> String {
        if case let RemoteStoreError.server(_, code, _) = error {
            switch code {
            case 4012: return "본인 초대 코드는 수락할 수 없어요"
            case 4011: return "유효하지 않은 초대 코드예요"
            default: break
            }
        }
        if case RemoteStoreError.offline = error { return "네트워크 연결을 확인해 주세요" }
        if case RemoteStoreError.authExpired = error { return "다시 로그인한 뒤 시도해 주세요" }
        return "친구 맺기에 실패했어요"
    }

    /// 전역 토스트 표시(2.2초). 같은 메시지일 때만 정리해 새 토스트가 일찍 사라지지 않게 한다.
    @MainActor
    func flashToast(_ message: String) {
        globalToast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.globalToast == message { self?.globalToast = nil }
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
        sessionUploadErrorMessage = nil
    }

    /// 표시용 앱 버전(`CFBundleShortVersionString`). 설정 화면이 "앱 버전" row에 사용.
    static let appVersion: String? = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }()
}

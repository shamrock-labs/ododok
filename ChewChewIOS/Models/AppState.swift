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

    /// 사용자가 온보딩에서 정한 표시 닉네임. `profiles.displayName`과 매핑.
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

    /// 전역 토스트(딥링크 친구 수락 결과 등). ContentView가 하단에 표시한다.
    var globalToast: String?

    /// 초대 수락 성공 후 친구 탭으로 이동시키는 일회성 요청 카운터.
    /// Int를 증가시켜 같은 화면에서 여러 번 성공해도 ContentView가 매번 감지하게 한다.
    var friendsTabRequestID: Int = 0

    /// `fetchAndApplyDisplayName` 한 번 끝났는지. 시작 직후 DB fetch 완료 전엔 false로 두어
    /// "기존 사용자가 reinstall한 cold-start에서 sheet이 잠깐 깜빡이는" 케이스를 차단.
    /// 처음 fetch가 끝나면 true로 마크 — 그 시점에 displayName nil이면 진짜 신규 디바이스.
    var didLoadProfile: Bool = false

    /// 서버 OAuth 로그인 여부(ODO-47). 토큰이 Keychain에 있으면 로그인 상태로 시작.
    /// false인 동안 ContentView가 LoginView를 fullScreenCover로 띄운다.
    var isLoggedIn: Bool = false

    /// 온보딩(닉네임 입력 + 사용법 튜토리얼)을 끝까지 마쳤는지. false인 동안 ContentView가
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

    struct Equipped: Codable, Equatable {
        var hat: String?
        var glasses: String?
        var acc: String?
    }

    // MARK: - Eating session

    /// 현재 식사 중인지 여부. 홈의 "식사 시작/종료" 버튼이 토글, 트래킹 탭이 관찰.
    @MainActor var isEating: Bool { mealSession.isEating }

    /// 식사 시작 시각. 통계/지속시간 표시 등에 사용.
    @MainActor var eatingStartedAt: Date? { mealSession.eatingStartedAt }

    /// 화면 표시용 최근 IMU 에너지 샘플. 원시 IMU 데이터는 저장하지 않음.
    @MainActor var imuWaveformSamples: [Double] { mealSession.imuWaveformSamples }
    @MainActor var imuWaveformSource: IMUWaveformSource {
        get { mealSession.imuWaveformSource }
        set { mealSession.imuWaveformSource = newValue }
    }

    // MARK: - IMU diagnostics (원시 데이터는 저장 안 함, 진단 지표만)

    /// 현재 식사 세션에서 받은 실제 IMU 샘플 개수 (데모/페이크 timer는 카운트 X).
    @MainActor var imuSampleCount: Int { mealSession.imuSampleCount }

    /// 마지막으로 실제 IMU 샘플이 들어온 시각. 백그라운드 수집 검증용.
    @MainActor var lastIMUSampleAt: Date? { mealSession.lastIMUSampleAt }

    /// 알림 딥링크(`chewchew://start`) 수신 시 true. 3초 후 자동 false.
    /// HomeView의 MealToggle 강조 스타일 트리거.
    @MainActor var startButtonHighlighted: Bool {
        get { mealSession.startButtonHighlighted }
        set { mealSession.startButtonHighlighted = newValue }
    }

    /// 끼니 리마인더 알림의 "식사 시작" 액션에서 set. HomeView가 관찰해 시작 가드를
    /// 그대로 태운다(모션 권한·AirPods 체크 재사용). 한 번 처리하면 false로 되돌린다.
    @MainActor var pendingMealStartRequest: Bool {
        get { mealSession.pendingMealStartRequest }
        set { mealSession.pendingMealStartRequest = newValue }
    }

    /// 앱 foreground 여부. scenePhase 관찰자가 갱신.
    /// 초기값 false — 앱 launch 시점엔 아직 .active phase가 아니므로, scenePhase가
    /// `.active`로 처음 도달할 때 `sceneDidChange(toForeground:true)`의 전이
    /// 조건(`!wasInForeground && toForeground`)이 성립해 일일 출석 보너스가 트리거된다.
    var isInForeground: Bool = false

    // MARK: - Remote persistence

    /// 원격 백엔드(InsForge)에 대한 추상화. 테스트/시뮬레이터에선 NoopRemoteStore 주입 가능.
    @ObservationIgnored let remoteStore: RemoteStore

    @ObservationIgnored private let authTokenStorage: any AuthTokenStorage

    @MainActor @ObservationIgnored lazy var home: HomeStore = HomeStore(
        repository: RemoteStoreHomeRepository(remoteStore: remoteStore),
        initialPoints: points,
        initialStreak: streak,
        initialFreezeInventory: freezeInventory,
        localTodayRealChewCount: { [weak self] in
            self?.localTodayRealChewCount ?? 0
        },
        onHomeApplied: { [weak self] home in
            self?.applyHomeFromStore(home)
        },
        onRemoteError: { [weak self] error in
            self?.handleRemoteError(error)
        },
        onRewardEarned: { [weak self] amount, kind in
            self?.analytics.track(.rewardEarned(amount: amount, kind: kind))
        },
        onStreakEvent: { [weak self] type, amount in
            self?.analytics.track(.streakEvent(type: type, amount: amount))
        }
    )

    @MainActor @ObservationIgnored lazy var records: RecordsStore = RecordsStore(
        repository: RemoteStoreMealSessionRepository(remoteStore: remoteStore)
    )

    @MainActor @ObservationIgnored lazy var auth: AuthStore = AuthStore(
        repository: authRepository,
        isLoggedIn: isLoggedIn,
        hasCompletedOnboarding: hasCompletedOnboarding,
        onLoginCompleted: { [weak self] result, method in
            self?.completeLogin(onboardingCompleted: result.onboardingCompleted, method: method)
        },
        onLogoutCompleted: { [weak self] in
            self?.expireSession()
        },
        onSessionExpired: { [weak self] in
            self?.expireSession()
        }
    )

    @MainActor @ObservationIgnored lazy var friends: FriendsStore = FriendsStore(
        repository: RemoteStoreFriendRepository(remoteStore: remoteStore),
        isLoggedIn: { [weak self] in self?.isLoggedIn ?? false },
        currentDisplayName: { [weak self] in self?.displayName },
        initialPendingInviteCode: UserDefaults.standard.string(forKey: Self.pendingInviteCodeKey),
        onToast: { [weak self] message in
            self?.flashToast(message)
        },
        onAuthExpired: { [weak self] in
            self?.auth.expireSession()
        },
        onInviteReceived: { [weak self] loggedIn in
            self?.analytics.track(.friendInviteReceived(loggedIn: loggedIn))
        },
        onInviteAccepted: { [weak self] in
            self?.friendsTabRequestID += 1
            Task { [weak self] in
                await self?.refreshFromServerHome()
            }
        },
        onPendingInviteCodeChanged: { code in
            if let code {
                UserDefaults.standard.set(code, forKey: Self.pendingInviteCodeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pendingInviteCodeKey)
            }
        }
    )

    @MainActor @ObservationIgnored lazy var reminders: ReminderStore = ReminderStore(
        coordinator: mealPushCoordinator,
        permissionProvider: SystemReminderPermissionProvider(),
        settingsStore: UserDefaultsReminderSettingsStore()
    )

    /// 제품·리텐션 분석 포트(ODO-79). Amplitude·(후속) Firebase로 fan-out. 테스트/미설정 시 Noop.
    @ObservationIgnored let analytics: AnalyticsService

    @MainActor @ObservationIgnored lazy var mealSession: MealSessionRuntimeStore = MealSessionRuntimeStore(
        analytics: analytics,
        onChewPulse: { [weak self] in
            self?.animKey &+= 1
        },
        onPersistSnapshot: { [weak self] in
            self?.persistSnapshot()
        },
        onSessionReadyForUpload: { [weak self] output, stats in
            self?.sessionUploadStatus = .uploading
            await self?.performSessionUpload(output, stats: stats)
        }
    )

    /// 서버 기반 식사 푸시 조정자(ODO-56) — APNs 토큰 등록 + 서버/로컬 알림 전환을 관리.
    @ObservationIgnored let mealPushCoordinator: MealPushCoordinator

    @ObservationIgnored private let authSessionManager: AuthSessionManaging
    @ObservationIgnored private let authRepository: AuthRepository

    /// 게임 상태 원격 동기화(upsert/delete) 직렬화 큐.
    /// 짧은 시간에 여러 mutate가 일어나면 detached Task들의 네트워크 도착 순서가 뒤집혀
    /// 중간 상태가 winner로 굳을 수 있어, 각 작업이 이전 작업 종료를 await하는 체인으로 직렬화한다.
    @ObservationIgnored private var remoteSyncChain: Task<Void, Never> = Task {}

    /// 식사 종료 직후 IMU 세션 업로드 결과. 화면이 alert 표시할 때 binding으로 관찰.
    var sessionUploadStatus: SessionUploadStatus = .idle

    /// 업로드 실패 시 사용자에게 보여줄 사유(서버가 준 메시지 / 오프라인 안내 등).
    /// nil이면 화면이 기본 카피를 쓴다. 성공·dismiss 시 비운다.
    var sessionUploadErrorMessage: String?

    /// 업로드 실패 시 사용자가 "다시 시도"를 누르면 재시도할 payload (finalize 결과 + 분석 통계).
    /// in-memory 1회 retry 한정 — 영구 retry 큐는 다음 PR.
    @ObservationIgnored private var pendingUpload: (output: IMUSessionRecorder.Output, stats: SessionStats?)?

    /// "오늘의 식사 기록" 리스트 — 오늘 0시 이후 시작된 chewing_session 행들.
    /// Tracking 탭이 관찰만 하고, fetch/append는 AppState가 single source of truth.
    /// 세션 종료 + INSERT 성공 시 자동 append, 탭 진입 시 fetchTodaySessions로 재동기화.
    var todaySessions: [ChewingSessionDTO] = []

    /// 식사 종료 직후 표시할 리포트 카드의 source. INSERT 성공 시 set, 카드 dismiss 시 nil.
    /// ContentView가 .sheet binding으로 관찰. PRD #3 — 종료 후 2초 이내 카드 표시.
    var lastCompletedSession: ChewingSessionDTO?

    /// 식사 시작 후 60초 미만에서 종료를 시도할 때 사용자에게 "더 측정할까요"를
    /// 묻는 확인 다이얼로그 플래그. 사용자가 "그만두기"를 선택하면 세션을 discard.
    @MainActor var showShortSessionConfirm: Bool {
        get { mealSession.showShortSessionConfirm }
        set { mealSession.showShortSessionConfirm = newValue }
    }

    /// 시작 시점에 AirPods/모션 권한이 없거나 라우트가 비어 시작을 차단했을 때 띄우는 플래그.
    /// 종료 시 너무 짧은 세션 확인(showShortSessionConfirm)과 메시지를 분리한다.
    @MainActor var showAirPodsConnectionPrompt: Bool {
        get { mealSession.showAirPodsConnectionPrompt }
        set { mealSession.showAirPodsConnectionPrompt = newValue }
    }

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
        authRepository: AuthRepository? = nil,
        analytics: AnalyticsService = NoopAnalytics(),
        authTokenStorage: any AuthTokenStorage = KeychainAuthTokenStorage(),
        startStartupTasks: Bool = true
    ) {
        self.remoteStore = remoteStore
        self.authTokenStorage = authTokenStorage
        self.authSessionManager = authSessionManager
        self.authRepository = authRepository
            ?? (authSessionManager as? AuthRepository)
            ?? AuthSessionManagerRepositoryAdapter(sessionManager: authSessionManager)
        self.analytics = analytics
        isLoggedIn = authTokenStorage.isLoggedIn
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
        // 즉시 표시용 fallback — DB 실패 또는 응답 전에 화면 그려도 마지막 캐시값으로.
        loadPersistedSnapshot()
        guard startStartupTasks else { return }
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

    @MainActor func startEating() { mealSession.startEating() }
    @MainActor func stopEating() { mealSession.stopEating() }
    @MainActor func discardCurrentSession() { mealSession.discardCurrentSession() }
    @MainActor func toggleEating() { mealSession.toggleEating() }
    @MainActor func resumeMeasurement() { mealSession.resumeMeasurement() }
    @MainActor func stopMeasurementFromNotification() { mealSession.stopMeasurementFromNotification() }
    @MainActor func requestStartHighlight(duration: TimeInterval = 3) { mealSession.requestStartHighlight(duration: duration) }
    @MainActor func requestMealStart() { mealSession.requestMealStart() }
    @MainActor func handleNotificationAction(_ action: String, deepLink: String?) {
        mealSession.handleNotificationAction(action, deepLink: deepLink)
    }

    static func shouldConfirmShortSessionStop(startedAt: Date?, now: Date = Date()) -> Bool {
        MealSessionRuntimeRules.shouldConfirmShortSessionStop(startedAt: startedAt, now: now)
    }

    static func shouldAutoResume(interruptionWasCall: Bool, shouldResume: Bool) -> Bool {
        MealSessionRuntimeRules.shouldAutoResume(interruptionWasCall: interruptionWasCall, shouldResume: shouldResume)
    }

    // MARK: - Shop / Wardrobe actions

    enum PurchaseResult: Equatable {
        case success
        case alreadyOwned
        case notEnoughPoints
    }

    /// ShopItem 구매. 자동 장착하지 않음 (명시적 `equip` 필요).
    @discardableResult
    @MainActor
    func buyItem(_ item: ShopItem) -> PurchaseResult {
        if owned.contains(item.id) { return .alreadyOwned }
        guard points >= item.price else { return .notEnoughPoints }
        points -= item.price
        home.syncLocalCache(points: points, streak: streak, freezeInventory: freezeInventory)
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

    func isOwned(_ item: ShopItem) -> Bool { owned.contains(item.id) }

    func isEquipped(_ item: ShopItem) -> Bool {
        switch item.type {
        case .hat:     return equipped.hat == item.id
        case .glasses: return equipped.glasses == item.id
        case .acc:     return equipped.acc == item.id
        }
    }

    var equippedHatItem: ShopItem? {
        ShopItem.by(id: equipped.hat)
    }

    var equippedGlassesItem: ShopItem? {
        ShopItem.by(id: equipped.glasses)
    }

    var equippedAccItem: ShopItem? {
        ShopItem.by(id: equipped.acc)
    }

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
            // 신규 디바이스 첫 실행에선 온보딩(닉네임 입력 + 사용법 튜토리얼)이 끝나기 전까지
            // 출석/스트릭 보상 다이얼로그를 띄우지 않는다. 보상이 온보딩 sheet 위로 먼저 떠
            // 사용자가 보상→온보딩 순으로 마주치는 회귀를 차단. completeOnboarding()이
            // 튜토리얼 종료 직후 동일 경로를 호출해 이어준다.
            if hasCompletedOnboarding {
                Task { await home.grantDailyAttendanceIfNeeded() }
            }
        }
        if wasInForeground && !toForeground {
            // 백그라운드 진입 시 안전하게 스냅샷 — 시스템 종료/메모리 회수 대비
            persistSnapshot()
        }
    }

    // MARK: - IMU waveform

    @MainActor func appendIMUWaveformSample(_ energy: Double) { mealSession.appendIMUWaveformSample(energy) }

    @MainActor func recordIMUEnergy(rotationRateMagnitude: Double, userAccelerationMagnitude: Double) {
        mealSession.recordIMUEnergy(
            rotationRateMagnitude: rotationRateMagnitude,
            userAccelerationMagnitude: userAccelerationMagnitude
        )
    }

    // MARK: - Erase all user data (REQ-05)

    /// 설정 '계정 삭제' 확인 시 호출.
    /// 원격: DELETE /v1/me → 계정 루트 삭제 + FK CASCADE.
    /// 로컬: 모든 게임 상태를 초기화하고 스냅샷도 비움.
    @MainActor
    func eraseAllUserData() async {
        // 삭제 요청은 현재 token 스냅샷으로 보내고, canonical session 저장소는 즉시 비운다.
        let deletionAccessToken = authTokenStorage.accessToken
        let deletionRefreshToken = authTokenStorage.refreshToken

        // 로컬 인메모리 상태 리셋 (reset()과 동일 범위)
        mealSession.resetRuntimeState()
        clearTransientRuntimeState()
        clearPendingInviteCode()
        streak = 0
        points = 0
        animKey = 0
        freezeInventory = 0
        owned = []
        equipped = Equipped()
        todaySessions = []
        lastCompletedSession = nil
        displayName = nil
        loginMethod = nil
        didLoadProfile = false
        hasCompletedOnboarding = false
        isLoggedIn = false
        analytics.setUserId(nil)
        SentryService.setUser(id: nil)
        MealNotificationService.cancelMealReminders()
        Task { await mealPushCoordinator.clearRegistration() }

        authTokenStorage.clear()

        await MainActor.run {
            home.reset()
        }
        clearPersistedSnapshot()
        scheduleRemoteUserDataDeletion(accessToken: deletionAccessToken, refreshToken: deletionRefreshToken)
    }

    // MARK: - Reset

    @MainActor
    func reset() {
        mealSession.resetRuntimeState()
        clearTransientRuntimeState()
        clearPendingInviteCode()
        streak = 0
        points = 0
        animKey = 0
        owned = []
        equipped = Equipped()
        todaySessions = []
        lastCompletedSession = nil
        displayName = nil
        loginMethod = nil
        hasCompletedOnboarding = false
        freezeInventory = 0
        authTokenStorage.clear()
        isLoggedIn = false
        analytics.setUserId(nil)
        SentryService.setUser(id: nil)
        // 저장된 스냅샷도 비워서 다음 실행에서 시드값이 살아남도록
        home.reset()
        clearPersistedSnapshot()
    }

    /// 로그인 + 서버 토큰 발급 성공 후 호출(LoginView). 로그인 상태로 전환하고
    /// 로그인 계정 기준으로 홈/프로필을 다시 적재한다.
    /// `onboardingCompleted`는 로그인 응답(`/auth/login`)의 정본 — true면 즉시 온보딩을
    /// 스킵해, 재로그인 시 온보딩이 다시 뜨던 회귀를 막는다.
    @MainActor
    func completeLogin(onboardingCompleted: Bool, method: String) {
        clearLocalSessionCache()
        // clearLocalSessionCache가 hasCompletedOnboarding을 false로 리셋하므로 그 뒤에 세팅한다.
        // 서버 응답이 완료라고 하면 즉시 온보딩 sheet을 스킵 — 재로그인 시 재노출 회귀 차단.
        if onboardingCompleted { hasCompletedOnboarding = true }
        // 로그인 provider 저장 — clearLocalSessionCache가 nil로 비운 뒤라 여기서 세팅한다.
        loginMethod = method
        isLoggedIn = true
        auth.markLoggedIn(onboardingCompleted: onboardingCompleted)
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
            await self?.friends.consumePendingInviteIfNeeded()
        }
    }

    /// 분석 유저 속성을 현재 상태로 동기화(코호트 분석용). 로그인·콜드스타트 복원·서버 홈 갱신 시 호출.
    /// 가입일·총세션수는 서버 DTO에 없어 제외(서버 추가 시 후속).
    @MainActor
    private func syncAnalyticsUserProperties() {
        analytics.setUserProperty("current_streak", home.currentStreak)
        analytics.setUserProperty("total_points", points)
    }

    /// 업로드 실패 원인을 저카디널리티 라벨로 분류(meal_session_failed의 reason 속성용).
    private static func uploadFailureReason(_ error: Error) -> String {
        guard let remoteError = error as? RemoteStoreError else { return "unknown" }
        switch remoteError {
        case .authExpired: return "auth_expired"
        case .server: return "server"
        case .offline: return "offline"
        case .malformed: return "malformed"
        case .http: return "http"
        case .invalidUploadResponse: return "invalid_upload"
        }
    }

    /// 로그아웃 — 로컬 토큰 제거 후 로그인 게이트로 복귀. 게임 데이터는 보존('계정 삭제'와 구분).
    @MainActor
    func logout() {
        expireSession()
    }

    /// 사용자가 누른 로그아웃 — 서버 refresh token 폐기 후 로컬 세션을 종료한다.
    @MainActor
    func logoutFromServer() async {
        // 토큰이 아직 유효할 때 서버 푸시 토큰을 해제한다(만료 후엔 401이라 의미 없음).
        await mealPushCoordinator.handleLogout()
        await auth.logout()
    }

    /// refresh 만료/폐기 등으로 인증 세션을 더 쓸 수 없을 때 로그인 게이트로 복귀한다.
    @MainActor
    private func expireSession() {
        // 로컬 끼니 알림 정리 + 코디네이터의 in-memory 등록 토큰 리셋(서버 토큰 해제는 logoutFromServer에서
        // 토큰이 유효할 때 수행. 만료 경로는 401이라 DELETE 무의미하므로 in-memory만 비운다).
        MealNotificationService.cancelMealReminders()
        Task { await mealPushCoordinator.clearRegistration() }
        authTokenStorage.clear()
        isLoggedIn = false
        analytics.setUserId(nil)
        SentryService.setUser(id: nil)
        clearLocalSessionCache()
    }

    @MainActor
    private func handleRemoteError(_ error: Error) {
        if case RemoteStoreError.authExpired = error {
            auth.expireSession()
        }
    }

    // MARK: - Derived

    private var localTodayRealChewCount: Int {
        todaySessions.reduce(0) { $0 + ($1.estimatedTotalChews ?? 0) }
    }

    @MainActor var imuWaveformStatusText: String {
        mealSession.imuWaveformStatusText
    }

    @MainActor var isIMUWaveformLive: Bool {
        mealSession.isIMUWaveformLive
    }

    // MARK: - Motion permission guard (REQ-01)

    /// `.notDetermined`이면 즉시 측정을 시작하지 않고 권한 요청 경로로 보낸다.
    /// CoreMotion은 명시적 request API 없이 `startDeviceMotionUpdates` 호출 시 시스템이
    /// 프롬프트를 띄운다. 권한 부여 → `onGranted()`, 거부(에러 콜백) → `onDenied()`.
    @MainActor func requestMotionPermission(onGranted: @escaping () -> Void, onDenied: @escaping () -> Void) {
        mealSession.requestMotionPermission(onGranted: onGranted, onDenied: onDenied)
    }

    /// REQ-01 가드 결정 순수 함수.
    /// `.authorized && available`일 때만 true — `.notDetermined`는 false(권한 요청 경로로).
    static func shouldStartImmediately(status: CMAuthorizationStatus, available: Bool) -> Bool {
        MealSessionRuntimeRules.shouldStartImmediately(status: status, available: available)
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

    /// v2 — `owned`/`equipped` 추가.
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
        // v3 옵셔널 필드 — 옛 스냅샷에선 nil이라 신규 streak 상태(0)로 시작
        if let savedFreeze = snapshot.freezeInventory {
            freezeInventory = savedFreeze
        }
    }

    /// 로그아웃/계정 전환 시 iOS에 남은 계정별 화면 캐시만 제거한다.
    /// 원격 데이터 삭제는 `eraseAllUserData` 전용이며 여기서는 호출하지 않는다.
    @MainActor
    private func clearLocalSessionCache() {
        clearTransientRuntimeState()
        streak = 0
        points = 0
        freezeInventory = 0
        owned = []
        equipped = Equipped()
        todaySessions = []
        displayName = nil
        loginMethod = nil
        didLoadProfile = false
        hasCompletedOnboarding = false
        auth.markLoggedOut()
        home.reset()
        homeApplyVersion += 1
        // 끼니 설정 로컬 캐시도 비운다 — 다음 계정이 이전 계정 알림시각을 보지 않도록(ODO-103).
        // 정본은 서버이므로 로그인 후 syncFromServer가 이 계정 값으로 다시 채운다.
        MealReminderSettings.clear()
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
    }

    @MainActor private func clearTransientRuntimeState() {
        mealSession.clearTransientRuntimeState()
        lastCompletedSession = nil
        sessionUploadStatus = .idle
        sessionUploadErrorMessage = nil
        pendingUpload = nil
    }

    @MainActor
    private func clearPendingInviteCode() {
        friends.setPendingInviteCode(nil)
        UserDefaults.standard.removeObject(forKey: Self.pendingInviteCodeKey)
    }

    func clearPersistedSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
        homeApplyVersion += 1   // 초기화 직전 시작된 refreshFromServerHome이 완료 후 applyHome을 실행하지 못하게.
    }

    private func scheduleRemoteUserDataDeletion(accessToken: String?, refreshToken: String?) {
        // 같은 체인으로 — 직전 작업이 끝난 뒤 delete가 나가야 결과가 결정적.
        let store = remoteStore
        let previous = remoteSyncChain
        remoteSyncChain = Task.detached {
            _ = await previous.value
            try? await store.deleteUserData(accessToken: accessToken, refreshToken: refreshToken)
        }
    }

    // MARK: - 서버 홈 상태 동기화 (ODO-54 thin-client)

    /// 서버가 계산한 홈 상태를 AppState의 레거시 캐시에 write-through한다.
    /// 홈 화면 표시 상태의 소유권은 HomeStore가 갖고, AppState의 points/streak/freezeInventory는
    /// Shop·스냅샷 호환용 캐시로만 남긴다.
    /// applyHome이 일어날 때마다 증가 — 비행 중인 읽기(GET /home) 응답이 도착했을 때 그 사이
    /// 다른 응답(출석/세션 저장 POST)이 홈을 갱신했는지 판별하는 버전 카운터.
    @ObservationIgnored private var homeApplyVersion = 0

    @MainActor
    private func applyHome(_ home: HomeStateDTO) {
        applyHomeLocally(home)
        self.home.applyExternal(home)
    }

    @MainActor
    private func applyHomeFromStore(_ home: HomeStateDTO) {
        applyHomeLocally(home)
    }

    @MainActor
    private func applyHomeLocally(_ home: HomeStateDTO) {
        homeApplyVersion += 1
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
        let versionAtRequest = homeApplyVersion
        await home.refresh { [weak self] in
            // 이 GET이 비행하는 동안 쓰기 응답(출석/세션 저장)이 홈을 갱신했다면 이 응답은 옛
            // 스냅샷이다 — 적용하면 방금 반영된 적립을 화면에서 되돌리므로 버린다(쓰기 응답 우선).
            guard let currentVersion = self?.homeApplyVersion else { return false }
            return versionAtRequest == currentVersion
        }
    }

    /// 앱-열기 출석 멱등키 — REQ-08 형식(`app-open-<deviceId>-<yyyyMMdd Asia/Seoul>`).
    /// iOS가 트리거 시점에 키를 만들고, 서버가 이 키로 일 1회 적립을 판정한다.
    /// 서버(AttendanceService)가 같은 포맷으로 키를 유도하므로, 포맷 변경 시 양쪽을 함께 고쳐야
    /// 같은 날 두 키가 갈라져 이중 적립되는 일을 막는다.
    static func attendanceKey(deviceId: String, now: Date = Date()) -> String {
        AttendanceKey.make(deviceId: deviceId, now: now)
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
            home.applySessionReward(from: result)
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
                auth.updateOnboardingCompleted(result.onboardingCompleted)
                // displayName도 함께 갱신(있을 때만).
                if let name = result.displayName, !name.isEmpty, name != displayName {
                    displayName = name
                }
                // 서버 원격 알림음 볼륨(있을 때만) 반영. 식사 중이면 keep-alive에 즉시, 아니면 다음 startEating에서.
                if let volume = result.alertVolume {
                    mealSession.updateAlertVolume(volume)
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
                await home.grantDailyAttendanceIfNeeded()
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
                auth.updateOnboardingCompleted(true)
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
            await home.grantDailyAttendanceIfNeeded()
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

    static func generatedNickname(number: Int) -> String {
        let normalized = max(0, min(9999, number))
        return "다람이 \(String(format: "%04d", normalized))"
    }

    @MainActor
    func saveGeneratedDisplayName() async {
        await saveDisplayName(Self.generatedNickname(number: Int.random(in: 1000...9999)))
    }

    /// 사용법 튜토리얼의 마지막 "시작하기"(또는 우상단 "건너뛰기")에서 호출. 온보딩 완료를
    /// 마크해 sheet을 닫고, 메인 화면이 보이는 이 시점에 비로소 도토리 출석 보상을 트리거한다.
    @MainActor
    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        auth.updateOnboardingCompleted(true)
        analytics.track(.onboardingCompleted())
        Task { await home.grantDailyAttendanceIfNeeded() }
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

    /// 딥링크(카카오/외부 공유)로 받은 초대 코드 처리. 로그인 상태면 바로 수락하고,
    /// 미로그인이면 보관했다가 로그인/가입(OAuth) 완료 후 자동 수락한다.
    @MainActor
    func receiveInviteCode(_ code: String) {
        friends.receiveInviteCode(code)
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

import Foundation
import Observation

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

/// 앱 전역 상태 facade. 기능별 Store가 화면 상태와 외부 효과의 실제 소유권을 나눠 갖는다.
@Observable
final class AppState {
    // MARK: - Local display cache

    var streak: Int = 0
    var points: Int = 0

    /// 다람이 씹기 모션 트리거. 실제 씹기 횟수가 아니라 화면 연출용 카운터.
    var animKey: Int = 0

    /// 스트릭 프리즈 인벤토리(0~3). 서버 홈 응답을 화면/스냅샷 호환용으로 캐시한다.
    var freezeInventory: Int = 0

    /// 사용자가 온보딩에서 정한 표시 닉네임. nil이면 HomeView는 fallback 문구를 쓴다.
    var displayName: String? {
        didSet {
            if let name = displayName {
                UserDefaults.standard.set(name, forKey: Self.displayNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.displayNameKey)
            }
        }
    }

    /// 로그인에 사용한 소셜 provider 식별자. 설정 화면 표시용으로 로컬 캐시한다.
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

    /// 프로필 복원 완료 여부. 완료 전에는 온보딩 sheet 판정을 보류한다.
    var didLoadProfile: Bool = false

    /// 서버 OAuth 로그인 여부. false면 ContentView가 로그인 화면을 띄운다.
    var isLoggedIn: Bool = false

    #if DEBUG
    /// OAuth 없이 목 데이터를 확인하는 개발용 계정. 명시적 로그아웃·초기화 전까지 복원한다.
    private(set) var isDebugProfileActive: Bool = false
    #else
    var isDebugProfileActive: Bool { false }
    #endif

    /// 온보딩 완료 여부. false면 ContentView가 온보딩 sheet를 띄운다.
    var hasCompletedOnboarding: Bool = false {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingCompleteKey)
        }
    }

    private static let displayNameKey = "ChewChewIOS.AppState.displayName"
    private static let loginMethodKey = "ChewChewIOS.AppState.loginMethod"
    private static let analyticsUserIdKey = "ChewChewIOS.AppState.analyticsUserId"
    private static let onboardingCompleteKey = "ChewChewIOS.AppState.hasCompletedOnboarding"
    private static let pendingInviteCodeKey = "ChewChewIOS.AppState.pendingInviteCode"
    #if DEBUG
    private static let debugProfileActiveKey = "ChewChewIOS.AppState.debugProfileActive"
    #endif

    // MARK: - Wardrobe (다람쥐 꾸미기)

    var owned: Set<String> = []

    var equipped: Equipped = Equipped()

    struct Equipped: Codable, Equatable {
        var hat: String?
        var glasses: String?
        var acc: String?
    }

    var isInForeground: Bool = false

    // MARK: - Stores / services

    /// 원격 백엔드 추상화. 테스트/시뮬레이터에선 NoopRemoteStore 주입 가능.
    @ObservationIgnored let remoteStore: RemoteStore

    @ObservationIgnored private let authTokenStorage: any AuthTokenStorage
    @ObservationIgnored private let localAccountDataCleaner: any LocalAccountDataClearing

    @MainActor @ObservationIgnored lazy var home: HomeStore = HomeStore(
        repository: RemoteStoreHomeRepository(
            remoteStore: remoteStore,
            debugProfileIsActive: { [weak self] in self?.isDebugProfileActive == true }
        ),
        initialPoints: points,
        initialStreak: streak,
        initialFreezeInventory: freezeInventory,
        serverReportTodayChewCount: { [weak self] in
            self?.serverReportTodayChewCount ?? 0
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

    @MainActor @ObservationIgnored lazy var auth: AuthStore = AuthStore(
        repository: authRepository,
        isLoggedIn: isLoggedIn,
        hasCompletedOnboarding: hasCompletedOnboarding,
        onLoginCompleted: { [weak self] result, method in
            self?.completeLogin(userId: result.userId, onboardingCompleted: result.onboardingCompleted, method: method)
        },
        onLogoutCompleted: { [weak self] in
            self?.expireSession(trackLogoutEvent: true)
        },
        onSessionExpired: { [weak self] in
            self?.handleSessionExpired()
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

    /// 제품·리텐션 분석 포트. 테스트/미설정 시 Noop.
    @ObservationIgnored let analytics: AnalyticsService

    @MainActor @ObservationIgnored lazy var chewProfileManager = ChewDetectionProfileManager(
        remoteStore: remoteStore
    )

    @MainActor @ObservationIgnored lazy var mealSession: MealSessionRuntimeStore = MealSessionRuntimeStore(
        analytics: analytics,
        onChewPulse: { [weak self] in
            self?.animKey &+= 1
        },
        onPersistSnapshot: { [weak self] in
            self?.persistSnapshot()
        },
        onSessionReadyForUpload: { [weak self] output, stats in
            await self?.mealResults.uploadSession(output, stats: stats)
        },
        chewDetectionContext: { [weak self] in
            guard let self else { return .standard }
            return self.chewProfileManager.mealContext(userId: self.storedAnalyticsUserId())
        }
    )

    @MainActor @ObservationIgnored lazy var mealResults: MealSessionResultStore = MealSessionResultStore(
        repository: RemoteStoreMealSessionUploadRepository(remoteStore: remoteStore),
        analytics: analytics,
        appVersion: Self.appVersion,
        onHomeReceived: { [weak self] home in
            self?.applyHome(home)
        },
        onSessionRewardReceived: { [weak self] result in
            self?.home.applySessionReward(from: result)
        },
        onRemoteError: { [weak self] error in
            self?.handleRemoteError(error)
        },
        refreshHome: { [weak self] in
            await self?.refreshFromServerHome()
        }
    )

    /// 서버 기반 식사 푸시 조정자.
    @ObservationIgnored let mealPushCoordinator: MealPushCoordinator

    @ObservationIgnored private let authSessionManager: AuthSessionManaging
    @ObservationIgnored private let authRepository: AuthRepository
    @ObservationIgnored private var didStartStartupTasks = false

    // MARK: - Init

    init(
        remoteStore: RemoteStore = NoopRemoteStore(),
        authSessionManager: AuthSessionManaging = NoopAuthSessionManager(),
        authRepository: AuthRepository? = nil,
        analytics: AnalyticsService = NoopAnalytics(),
        authTokenStorage: any AuthTokenStorage = KeychainAuthTokenStorage(),
        localAccountDataCleaner: any LocalAccountDataClearing = LocalAccountDataCleaner(),
        startStartupTasks: Bool = true
    ) {
        self.remoteStore = remoteStore
        self.authTokenStorage = authTokenStorage
        self.localAccountDataCleaner = localAccountDataCleaner
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
        // 서버 응답 전 화면을 위한 로컬 fallback 캐시.
        loadPersistedSnapshot()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: Self.debugProfileActiveKey) {
            isDebugProfileActive = true
            isLoggedIn = true
            hasCompletedOnboarding = true
            didLoadProfile = true
            displayName = StreakDemoFixture.home.displayName
            points = StreakDemoFixture.home.points
            streak = StreakDemoFixture.home.streak
            freezeInventory = StreakDemoFixture.home.freezeInventory
        }
        #endif
        if startStartupTasks {
            Task { [weak self] in
                await self?.startStartupTasks()
            }
        }
    }

    @MainActor
    func startStartupTasks() async {
        guard !didStartStartupTasks else { return }
        didStartStartupTasks = true
        #if DEBUG
        guard !isDebugProfileActive else { return }
        #endif

        await mealPushCoordinator.setAuthExpiredHandler { [weak self] in
            Task { @MainActor in self?.handleRemoteError(RemoteStoreError.authExpired) }
        }
        await refreshFromServerHome()
        await fetchAndApplyDisplayName()
        if let userId = storedAnalyticsUserId() {
            await chewProfileManager.activate(userId: userId)
        }
    }

    // MARK: - Shop / Wardrobe actions

    enum PurchaseResult: Equatable {
        case success
        case alreadyOwned
        case notEnoughPoints
    }

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

    @MainActor
    func sceneDidChange(toForeground: Bool) {
        let wasInForeground = isInForeground
        isInForeground = toForeground
        if !wasInForeground && toForeground {
            if isLoggedIn, let userId = storedAnalyticsUserId() {
                Task { await chewProfileManager.refreshIfStale(userId: userId) }
            }
            if ProcessInfo.processInfo.arguments.contains("-skipAttendanceDialog") {
                return
            }
            if hasCompletedOnboarding {
                Task { await home.grantDailyAttendanceIfNeeded() }
            }
        }
        if wasInForeground && !toForeground {
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

    // MARK: - Erase all user data

    @MainActor
    func eraseAllUserData() async throws {
        let deletionAccessToken = authTokenStorage.accessToken
        let deletionRefreshToken = authTokenStorage.refreshToken
        let deletedUserId = storedAnalyticsUserId()

        // 로컬 세션을 먼저 비우면 서버 실패를 복구하거나 재시도할 인증 수단이 사라진다.
        // DELETE /v1/me의 2xx 응답을 확인한 뒤에만 사용자에게 탈퇴 완료 상태를 보여준다.
        try await remoteStore.deleteUserData(
            accessToken: deletionAccessToken,
            refreshToken: deletionRefreshToken
        )

        try localAccountDataCleaner.clear()
        analytics.track(.accountDeleted(source: "settings"))
        mealSession.resetRuntimeState()
        clearTransientRuntimeState()
        clearPendingInviteCode()
        #if DEBUG
        isDebugProfileActive = false
        UserDefaults.standard.removeObject(forKey: Self.debugProfileActiveKey)
        #endif
        streak = 0
        points = 0
        animKey = 0
        freezeInventory = 0
        owned = []
        equipped = Equipped()
        mealResults.resetAll()
        displayName = nil
        loginMethod = nil
        if let deletedUserId {
            chewProfileManager.clearLocalAccountData(userId: deletedUserId)
        } else {
            chewProfileManager.deactivate()
        }
        clearAnalyticsUserId()
        didLoadProfile = false
        hasCompletedOnboarding = false
        isLoggedIn = false
        analytics.setUserId(nil)
        SentryService.setUser(id: nil)
        MealNotificationService.cancelMealReminders()
        await mealPushCoordinator.clearRegistration()

        authTokenStorage.clear()

        await MainActor.run {
            home.reset()
        }
        clearPersistedSnapshot()
    }

    @MainActor
    func saveChewDetectionSettings(_ settings: PersonalizedChewDetectionSettings) async throws {
        guard let userId = storedAnalyticsUserId(), isLoggedIn else {
            throw RemoteStoreError.authExpired
        }
        try await chewProfileManager.save(settings, userId: userId)
    }

    @MainActor
    func resetChewDetectionSettings() async throws {
        guard let userId = storedAnalyticsUserId(), isLoggedIn else {
            throw RemoteStoreError.authExpired
        }
        try await chewProfileManager.reset(userId: userId)
    }

    @MainActor
    func refreshChewDetectionProfileIfStale() async {
        guard let userId = storedAnalyticsUserId(), isLoggedIn else { return }
        await chewProfileManager.refreshIfStale(userId: userId)
    }

    // MARK: - Reset

    @MainActor
    func reset() {
        mealSession.resetRuntimeState()
        clearTransientRuntimeState()
        clearPendingInviteCode()
        #if DEBUG
        isDebugProfileActive = false
        UserDefaults.standard.removeObject(forKey: Self.debugProfileActiveKey)
        #endif
        streak = 0
        points = 0
        animKey = 0
        owned = []
        equipped = Equipped()
        mealResults.resetAll()
        displayName = nil
        loginMethod = nil
        hasCompletedOnboarding = false
        freezeInventory = 0
        clearAnalyticsUserId()
        chewProfileManager.deactivate()
        authTokenStorage.clear()
        isLoggedIn = false
        analytics.setUserId(nil)
        SentryService.setUser(id: nil)
        home.reset()
        clearPersistedSnapshot()
    }

    @MainActor
    func completeLogin(userId: String, onboardingCompleted: Bool, method: String) {
        clearLocalSessionCache()
        if onboardingCompleted { hasCompletedOnboarding = true }
        loginMethod = method
        isLoggedIn = true
        auth.markLoggedIn(onboardingCompleted: onboardingCompleted)
        storeAnalyticsUserId(userId)
        analytics.setUserId(userId)
        analytics.setUserProperty("anonymous_device_id", DeviceIdentity.shared)
        analytics.setUserProperty("has_completed_onboarding", onboardingCompleted)
        SentryService.setUser(id: userId)
        analytics.track(.login(method: method, onboardingCompleted: onboardingCompleted))
        syncAnalyticsUserProperties()
        Task { [weak self] in
            await self?.chewProfileManager.activate(userId: userId, forceRefresh: true)
            await self?.refreshFromServerHome()
            await self?.fetchAndApplyDisplayName()
            // 계정 전환 시 이전 계정의 푸시 등록이 새 계정으로 누수되지 않게 서버 발송 신호를 내린다.
            await self?.mealPushCoordinator.clearRegistration()
            await self?.mealPushCoordinator.syncFromServer()
            await self?.friends.consumePendingInviteIfNeeded()
        }
    }

    #if DEBUG
    /// Debug 로그인 화면에서 OAuth와 서버 프로필 조회를 건너뛰고 목 홈 세션을 시작한다.
    @MainActor
    func activateDebugProfile() {
        clearLocalSessionCache()
        isDebugProfileActive = true
        UserDefaults.standard.set(true, forKey: Self.debugProfileActiveKey)
        displayName = StreakDemoFixture.home.displayName
        hasCompletedOnboarding = true
        didLoadProfile = true
        isLoggedIn = true
        auth.markLoggedIn(onboardingCompleted: true)
        applyHome(StreakDemoFixture.home)
    }
    #endif

    @MainActor
    private func syncAnalyticsUserProperties() {
        analytics.setUserProperty("current_streak", home.currentStreak)
        analytics.setUserProperty("total_points", points)
    }

    @MainActor
    func logout() {
        expireSession(trackLogoutEvent: true)
    }

    @MainActor
    func logoutFromServer() async {
        await mealPushCoordinator.handleLogout()
        await auth.logout()
    }

    @MainActor
    private func expireSession(trackLogoutEvent: Bool) {
        let loggedOutUserId = storedAnalyticsUserId()
        if trackLogoutEvent {
            analytics.track(.logout(source: "settings"))
        }
        MealNotificationService.cancelMealReminders()
        Task { await mealPushCoordinator.clearRegistration() }
        authTokenStorage.clear()
        isLoggedIn = false
        if let loggedOutUserId {
            chewProfileManager.clearLocalAccountData(userId: loggedOutUserId)
        } else {
            chewProfileManager.deactivate()
        }
        clearAnalyticsUserId()
        analytics.setUserId(nil)
        SentryService.setUser(id: nil)
        clearLocalSessionCache()
    }

    @MainActor
    private func handleSessionExpired() {
        #if DEBUG
        if isDebugProfileActive {
            auth.markLoggedIn(onboardingCompleted: true)
            return
        }
        #endif
        expireSession(trackLogoutEvent: false)
    }

    @MainActor
    private func handleRemoteError(_ error: Error) {
        #if DEBUG
        guard !isDebugProfileActive else { return }
        #endif
        if case RemoteStoreError.authExpired = error {
            auth.expireSession()
        }
    }

    // MARK: - Derived

    @MainActor private var serverReportTodayChewCount: Int {
        mealResults.serverReportTodayChewCount
    }

    // MARK: - Local persistence (UserDefaults snapshot)

    private static let persistenceKey = "ChewChewIOS.AppState.snapshot.v1"

    /// 옵셔널 필드는 옛 스냅샷 하위 호환용이다.
    private struct PersistedSnapshot: Codable {
        let streak: Int
        let points: Int
        let savedAt: Date
        var owned: [String]?
        var equipped: Equipped?
        var freezeInventory: Int?
    }

    /// 서버 홈 응답 전 화면을 위한 로컬 fallback 캐시.
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
        if let savedOwned = snapshot.owned {
            owned = Set(savedOwned)
        }
        if let savedEquipped = snapshot.equipped {
            equipped = savedEquipped
        }
        if let savedFreeze = snapshot.freezeInventory {
            freezeInventory = savedFreeze
        }
    }

    @MainActor
    private func clearLocalSessionCache() {
        clearTransientRuntimeState()
        #if DEBUG
        isDebugProfileActive = false
        UserDefaults.standard.removeObject(forKey: Self.debugProfileActiveKey)
        #endif
        streak = 0
        points = 0
        freezeInventory = 0
        owned = []
        equipped = Equipped()
        mealResults.resetAll()
        displayName = nil
        loginMethod = nil
        didLoadProfile = false
        hasCompletedOnboarding = false
        auth.markLoggedOut()
        home.reset()
        homeApplyVersion += 1
        MealReminderSettings.clear()
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
    }

    @MainActor private func clearTransientRuntimeState() {
        mealSession.clearTransientRuntimeState()
        mealResults.resetTransientState()
    }

    @MainActor
    private func clearPendingInviteCode() {
        friends.setPendingInviteCode(nil)
        UserDefaults.standard.removeObject(forKey: Self.pendingInviteCodeKey)
    }

    func clearPersistedSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
        homeApplyVersion += 1
    }

    private func storeAnalyticsUserId(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: Self.analyticsUserIdKey)
    }

    private func storedAnalyticsUserId() -> String? {
        UserDefaults.standard.string(forKey: Self.analyticsUserIdKey)
    }

    private func clearAnalyticsUserId() {
        UserDefaults.standard.removeObject(forKey: Self.analyticsUserIdKey)
    }

    // MARK: - Server home sync

    /// 비행 중인 홈 조회가 최신 쓰기 응답을 덮지 않도록 판별하는 버전 카운터.
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
        syncAnalyticsUserProperties()
        persistSnapshot()
    }

    @MainActor
    func refreshFromServerHome() async {
        let versionAtRequest = homeApplyVersion
        await home.refresh { [weak self] in
            guard let currentVersion = self?.homeApplyVersion else { return false }
            return versionAtRequest == currentVersion
        }
    }

    static func attendanceKey(deviceId: String, now: Date = Date()) -> String {
        AttendanceKey.make(deviceId: deviceId, now: now)
    }

    @MainActor
    private func fetchAndApplyDisplayName() async {
        var meSucceeded = false
        if isLoggedIn {
            if let result = try? await authSessionManager.me() {
                storeAnalyticsUserId(result.userId)
                analytics.setUserId(result.userId)
                SentryService.setUser(id: result.userId)
                // 서버값은 승격만 한다. 로컬 완료 직후 서버 반영이 늦으면 false가 내려오는데,
                // 그대로 덮으면 온보딩 sheet가 재진입해 캘리브레이션 cover를 초기화시킨다.
                if result.onboardingCompleted { hasCompletedOnboarding = true }
                auth.updateOnboardingCompleted(hasCompletedOnboarding)
                if let name = result.displayName, !name.isEmpty, name != displayName {
                    displayName = name
                }
                if let volume = result.alertVolume {
                    mealSession.updateAlertVolume(volume)
                }
                meSucceeded = true
            }
        }

        let profile: ProfileDTO?
        do {
            profile = try await remoteStore.fetchProfile()
        } catch {
            handleRemoteError(error)
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
            if !meSucceeded && !hasCompletedOnboarding {
                hasCompletedOnboarding = true
                auth.updateOnboardingCompleted(true)
            }
        }
        if isLoggedIn {
            if let userId = storedAnalyticsUserId() {
                analytics.setUserId(userId)
                SentryService.setUser(id: userId)
            }
            analytics.setUserProperty("anonymous_device_id", DeviceIdentity.shared)
            analytics.setUserProperty("has_completed_onboarding", hasCompletedOnboarding)
            syncAnalyticsUserProperties()
        }
        didLoadProfile = true
        if isInForeground && hasCompletedOnboarding {
            await home.grantDailyAttendanceIfNeeded()
        }
    }

    @MainActor
    func saveDisplayName(_ rawName: String) async {
        guard let displayName = Self.normalizedDisplayName(rawName) else { return }
        self.displayName = displayName
        let deviceId = DeviceIdentity.shared
        do {
            try await remoteStore.upsertProfile(ProfileDTO(deviceId: deviceId, displayName: displayName))
        } catch {
            handleRemoteError(error)
        }
    }

    static func normalizedDisplayName(_ rawName: String) -> String? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(8))
    }

    static func generatedNickname(number: Int) -> String {
        let normalized = max(0, min(9999, number))
        return "다람이 \(String(format: "%04d", normalized))"
    }

    @MainActor
    func saveGeneratedDisplayName() async {
        await saveDisplayName(Self.generatedNickname(number: Int.random(in: 1000...9999)))
    }

    @MainActor
    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        auth.updateOnboardingCompleted(true)
        analytics.track(.onboardingCompleted())
        Task { await home.grantDailyAttendanceIfNeeded() }
    }

    @MainActor
    func receiveInviteCode(_ code: String) {
        friends.receiveInviteCode(code)
    }

    @MainActor
    func flashToast(_ message: String) {
        globalToast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.globalToast == message { self?.globalToast = nil }
        }
    }

    static let appVersion: String? = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }()
}

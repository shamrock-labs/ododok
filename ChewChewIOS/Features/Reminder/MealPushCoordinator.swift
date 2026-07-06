import Foundation
import UIKit

/// 끼니 설정 저장(`apply`)의 결과 — 설정 화면이 실패 다이얼로그 표시 여부를 정한다(ODO-103).
enum MealSettingsSaveOutcome: Equatable {
    case saved                       // 서버 저장 성공
    case saveFailed(reason: String)  // 오프라인/서버 — 저장 실패(설정 화면이 실패 다이얼로그를 띄움)
    case sessionExpired              // 세션 만료 — onAuthExpired가 로그인 게이트로 보냄
    case skipped                     // 미로그인 — 다이얼로그 없음
}

/// 식사 알림을 "서버 단독 + 오프라인 보조" 정책으로 조율한다(ODO-56, ODO-103).
///
/// 서버 수신 가능 = 로그인 AND 알림 권한 AND 서버에 활성 APNs 토큰 보유.
///  - 가능: 로컬 예약은 취소(서버가 APNs로 발송).
///  - 불가: 끼니 시각을 아는 경우에만 로컬 알림으로 보조(REQ-13 경로).
///
/// 끼니 설정의 정본은 서버다(`/v1/me/meal-notifications`, 계정별). 화면·로컬 캐시는 `syncFromServer()`로
/// 서버에서 받아 맞추고(앱 시작·로그인), 설정 변경 시에만 `apply(_:)`로 서버에 올린다(사용자 입력 = 정본).
///
/// 폴백 정책(ODO-103): 로컬 보조는 "서버에 도달해 끼니 시각을 확보했는데 서버 푸시가 아직 안 선" 경우에만 한다.
/// 서버에 도달조차 못 하면(오프라인/서버 다운) 끼니 시각을 신뢰할 수 없으므로 로컬을 새로 걸지 않는다.
/// 서버가 실제로 살아 있다면 영속 토큰으로 알아서 발송하므로, 로컬을 안 걸어도 중복도 누락도 아니다.
///
/// 동시성: actor로 등록 상태 접근을 직렬화한다. 로컬/서버 전환은 항상 `reconcileDelivery` 한 곳에서만 하고,
/// 기준은 `serverDeliveryArmed`(서버가 실제로 보낼 수 있나) 단일 신호다. 이 신호는 in-memory가 아니라
/// 영속(UserDefaults)이라 콜드 스타트마다 리셋되지 않는다 — in-memory 토큰을 기준으로 삼던 탓에 콜드 스타트
/// 직후 "서버도 보내고 로컬도 보내는" 중복이 났던 것을 닫는다(ODO-103). UIApplication 호출만 메인으로 hop한다.
actor MealPushCoordinator {

    private let remoteStore: RemoteStore
    /// 로그인 여부 제공자. 기본은 TokenManager.isLoggedIn(Keychain) — 테스트에서 주입해 결정적으로 만든다.
    private let isLoggedIn: @Sendable () -> Bool
    /// 서버 호출이 인증 만료(authExpired)를 던졌을 때 호출 — AppState가 세션을 만료시켜 로그인 게이트로 보낸다.
    private var onAuthExpired: @Sendable () -> Void
    /// 끼니 설정 로컬 캐시·armed 플래그를 읽고 쓰는 저장소. 테스트에서 격리된 suite를 주입한다(기본 `.standard`).
    private let defaults: UserDefaults

    /// APNs 등록에 성공해 서버에 올린 토큰(hex). 이번 세션의 deactivate 대상으로만 쓰는 in-memory 값.
    private var registeredToken: String?

    /// 서버가 이 계정으로 APNs 발송 가능한지의 **영속** 신호(ODO-103).
    /// registeredToken은 in-memory라 콜드 스타트마다 nil로 리셋되지만, 서버의 push_tokens.is_active는 영속이다.
    /// 그 간극이 콜드 스타트 직후 중복 발송의 원인이었다. 이 플래그로 로컬/서버 전환을 판단한다.
    /// 등록 성공 시 true, 로그아웃/세션 만료 시 false. 기기 단위지만 로그인마다 재확립된다.
    static let deliveryArmedKey = "ChewChewIOS.MealPush.serverDeliveryArmed.v1"
    private var serverDeliveryArmed: Bool {
        get { defaults.bool(forKey: Self.deliveryArmedKey) }
        set { defaults.set(newValue, forKey: Self.deliveryArmedKey) }
    }

    init(
        remoteStore: RemoteStore,
        isLoggedIn: @escaping @Sendable () -> Bool = { TokenManager.isLoggedIn },
        onAuthExpired: @escaping @Sendable () -> Void = {},
        defaults: UserDefaults = .standard
    ) {
        self.remoteStore = remoteStore
        self.isLoggedIn = isLoggedIn
        self.onAuthExpired = onAuthExpired
        self.defaults = defaults
    }

    /// init 시점엔 AppState가 self를 캡처할 수 없어, 만료 핸들러는 생성 직후 별도로 연결한다.
    func setAuthExpiredHandler(_ handler: @escaping @Sendable () -> Void) {
        onAuthExpired = handler
    }

    /// 끼니 설정 변경 시(설정 화면) 호출 — 사용자가 정한 값을 서버에 올리고 전달 경로를 정합한다.
    /// 사용자 입력이 정본이므로 로컬→서버 방향으로 PUT한다. 반환값으로 저장 성패를 알려, 설정 화면이
    /// 실패 시 같은 실패 다이얼로그를 띄우고 변경을 되돌릴 수 있게 한다(무성유실 방지, ODO-103).
    @discardableResult
    func apply(_ settings: MealReminderSettings) async -> MealSettingsSaveOutcome {
        guard isLoggedIn() else {
            MealNotificationService.cancelMealReminders()   // 로그아웃: 알림 없음(로그인 게이트)
            return .skipped
        }
        // 끼니 설정은 계정 데이터 — JWT(Authorization)만으로 인증·기록되므로 알림 권한·APNs 토큰과 무관하게
        // 먼저 PUT한다(권한 가드보다 앞에 둬야 저장 실패를 권한과 독립적으로 보고할 수 있다).
        do {
            try await remoteStore.upsertMealNotifications(settings, timeZone: TimeZone.current.identifier)
        } catch RemoteStoreError.authExpired {
            onAuthExpired()   // 세션 만료 → AppState가 로그인 게이트로 복귀시킨다
            return .sessionExpired
        } catch {
            // 오프라인/서버 오류 → 저장 실패. 설정 화면이 실패 다이얼로그를 띄우고 변경을 되돌린다.
            let reason = (error as? RemoteStoreError)?.userMessage ?? "잠시 후 다시 시도해 주세요."
            return .saveFailed(reason: reason)
        }
        // 저장 성공 → 전달 경로 정합(알림 권한 필요).
        guard await MealNotificationService.isAuthorized() else {
            await MealNotificationService.reschedule(settings)   // 권한 없음 → reschedule이 제거만
            return .saved
        }
        // 토큰 미등록일 때만 원격 등록을 요청한다(이미 등록됐으면 재요청 안 함). 결과는 didRegister에서.
        if registeredToken == nil {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        await reconcileDelivery(settings)
        return .saved
    }

    /// 앱 시작·로그인 시 호출 — 끼니 설정의 정본인 서버에서 받아 화면·로컬 캐시를 맞추고 전달 경로를 정합한다(ODO-103).
    ///
    /// 서버 미도달(오프라인/다운)이면 끼니 시각을 신뢰할 수 없으므로 로컬을 새로 걸지 않고 종료한다(폴백 정책).
    func syncFromServer() async {
        guard isLoggedIn() else {
            MealNotificationService.cancelMealReminders()
            return
        }
        let settings: MealReminderSettings
        do {
            if let server = try await remoteStore.fetchMealNotifications() {
                server.save(to: defaults)                          // 서버값으로 로컬 캐시 갱신
                settings = server
            } else {
                MealReminderSettings.default.save(to: defaults)    // 서버 미설정(404) → 이전 계정 값 잔류 방지
                settings = .default
            }
        } catch RemoteStoreError.authExpired {
            onAuthExpired()
            return
        } catch {
            // 서버 미도달 — 끼니 시각 미확보. 로컬 폴백을 새로 걸지 않고 종료한다(서버가 살아 있으면 알아서 발송).
            return
        }
        guard await MealNotificationService.isAuthorized() else {
            await MealNotificationService.reschedule(settings)     // 권한 없음 → 제거만
            return
        }
        if registeredToken == nil {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        await reconcileDelivery(settings)
    }

    /// AppDelegate didRegisterForRemoteNotificationsWithDeviceToken에서 호출.
    func didRegister(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard isLoggedIn() else {
            registeredToken = nil
            return
        }
        do {
            try await remoteStore.registerPushToken(hex, environment: Self.apnsEnvironment)
        } catch RemoteStoreError.authExpired {
            registeredToken = nil
            onAuthExpired()
            return
        } catch {
            // 백엔드 등록 실패 — 토큰 미보유. armed는 바꾸지 않는다(이전 세션에 등록된 서버 토큰이 아직
            // 살아 있을 수 있으므로). reconcile이 armed 기준으로 로컬 보조 여부를 정한다.
            registeredToken = nil
            await reconcileDelivery(MealReminderSettings.load(from: defaults))
            return
        }
        // 등록 성공 → 서버가 이 계정으로 APNs 발송 가능. 끼니 설정 동기화는 syncFromServer/apply가 담당하므로
        // 여기서 로컬 설정을 서버로 올리지 않는다(계정별 설정을 등록 시점에 덮어쓰던 버그 제거, ODO-103).
        registeredToken = hex
        serverDeliveryArmed = true
        await reconcileDelivery(MealReminderSettings.load(from: defaults))
    }

    /// AppDelegate didFailToRegisterForRemoteNotificationsWithError에서 호출.
    /// OS 단계 APNs 등록 실패 — 토큰을 못 받음. armed는 바꾸지 않고(이전 서버 토큰이 살아 있을 수 있음)
    /// reconcile이 armed 기준으로 로컬 보조 여부를 정한다.
    func didFailToRegister() async {
        registeredToken = nil
        await reconcileDelivery(MealReminderSettings.load(from: defaults))
    }

    /// 로그아웃 시 서버 토큰 해제 + 로컬 정리 + 서버 발송 신호 해제.
    func handleLogout() async {
        if let token = registeredToken {
            try? await remoteStore.deactivatePushToken(token)
        }
        registeredToken = nil
        serverDeliveryArmed = false
        MealNotificationService.cancelMealReminders()
    }

    /// 세션 만료(authExpired) 등으로 in-memory 등록 토큰과 영속 발송 신호를 비운다.
    /// 서버 DELETE는 401이라 의미 없어 생략. 다음 로그인 시 재등록으로 armed가 다시 선다.
    func clearRegistration() {
        registeredToken = nil
        serverDeliveryArmed = false
    }

    /// 로컬/서버 발송을 serverDeliveryArmed 기준으로 일치시키는 단일 진입점.
    /// 서버 발송 가능(armed) → 로컬 OFF, 불가 → 로컬 ON. reschedule await 동안 armed가 서면 재확인해 취소.
    /// 이 메서드는 끼니 시각을 아는 맥락에서만 호출된다(서버 미도달 시 syncFromServer가 진입 전에 종료).
    private func reconcileDelivery(_ settings: MealReminderSettings) async {
        if serverDeliveryArmed {
            MealNotificationService.cancelMealReminders()   // 서버가 발송
        } else {
            await MealNotificationService.reschedule(settings)   // 로컬 보조
            if serverDeliveryArmed {
                MealNotificationService.cancelMealReminders()   // await 중 서버 전환됨 → 방금 잡은 로컬 취소
            }
        }
    }

    /// 빌드 구성에 따른 APNs 환경(디버그=sandbox, 릴리스=production).
    private static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

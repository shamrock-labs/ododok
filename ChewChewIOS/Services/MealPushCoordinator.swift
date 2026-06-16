import Foundation
import UIKit

/// 식사 알림을 "서버 단독 + 오프라인 보조" 정책으로 조율한다(ODO-56).
///
/// 서버 수신 가능 = 로그인 AND 알림 권한 AND APNs 토큰 서버 등록 성공.
///  - 가능: 서버에 슬롯 설정을 올리고 로컬 예약은 취소(서버가 APNs로 발송).
///  - 불가(미로그인·권한 없음·토큰 미등록·동기화 실패): 기존 로컬 알림으로 운영(REQ-13 경로).
///
/// 동시성: actor로 registeredToken 접근을 직렬화한다. 로컬/서버 발송 전환은 항상 `reconcileDelivery`
/// 한 곳에서만 하고, 기준은 `registeredToken`(서버가 실제로 보낼 수 있나) 단일 신호다. apply()와
/// didRegister()가 await 중 끼어들어도 reconcile이 reschedule 직후 토큰을 재확인해 "서버 전환됐는데
/// 로컬을 다시 켜는" 중복을 닫는다. UIApplication 호출만 메인으로 hop한다.
actor MealPushCoordinator {

    private let remoteStore: RemoteStore
    /// 로그인 여부 제공자. 기본은 TokenManager.isLoggedIn(Keychain) — 테스트에서 주입해 결정적으로 만든다.
    private let isLoggedIn: @Sendable () -> Bool
    /// APNs 등록에 성공해 서버에 올린 토큰(hex). nil이면 서버 수신 불가로 본다.
    private var registeredToken: String?

    init(remoteStore: RemoteStore, isLoggedIn: @escaping @Sendable () -> Bool = { TokenManager.isLoggedIn }) {
        self.remoteStore = remoteStore
        self.isLoggedIn = isLoggedIn
    }

    /// 앱 활성/설정 변경 시 현재 설정을 정책에 맞게 적용한다.
    func apply(_ settings: MealReminderSettings) async {
        guard isLoggedIn() else {
            MealNotificationService.cancelMealReminders()   // 로그아웃: 알림 없음(로그인 게이트)
            return
        }
        guard await MealNotificationService.isAuthorized() else {
            await MealNotificationService.reschedule(settings)   // 권한 없음 → reschedule이 제거만
            return
        }
        // 끼니 설정은 계정 데이터 — JWT(Authorization)만으로 인증·기록되므로 APNs 토큰과 무관하게 항상 PUT.
        // 단, 세션 만료(authExpired)면 로컬도 잡지 않고 종료한다(만료된 세션에 알림을 새로 깔지 않음).
        do {
            try await remoteStore.upsertMealNotifications(settings, timeZone: TimeZone.current.identifier)
        } catch RemoteStoreError.authExpired {
            return
        } catch {
            // 오프라인 / 서버 미배포(404) 등 → reconcile에서 로컬 보조
        }
        // 토큰 미등록일 때만 원격 등록을 요청한다(이미 등록됐으면 재요청 안 함). 결과는 didRegister에서.
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
        // 1) 토큰 등록. 실패하면 로컬로.
        do {
            try await remoteStore.registerPushToken(hex, environment: Self.apnsEnvironment)
        } catch RemoteStoreError.authExpired {
            registeredToken = nil
            return
        } catch {
            registeredToken = nil
            await reconcileDelivery(.load())
            return
        }
        // 2) 설정 동기화. 토큰은 등록됐지만 여기서 실패하면 "서버 토큰 활성 + 로컬 ON"의 중복 발송을 막기 위해
        //    토큰을 best-effort 해제하고 로컬로 내려간다(서버가 stale/빈 설정으로 잘못 보내지 않게).
        do {
            try await remoteStore.upsertMealNotifications(.load(), timeZone: TimeZone.current.identifier)
        } catch RemoteStoreError.authExpired {
            registeredToken = nil
            try? await remoteStore.deactivatePushToken(hex)
            return
        } catch {
            registeredToken = nil
            try? await remoteStore.deactivatePushToken(hex)
            await reconcileDelivery(.load())
            return
        }
        // 둘 다 성공 → 서버 발송 가능. reconcile이 로컬 예약을 취소한다.
        registeredToken = hex
        await reconcileDelivery(.load())
    }

    /// AppDelegate didFailToRegisterForRemoteNotificationsWithError에서 호출.
    func didFailToRegister() async {
        registeredToken = nil
        await reconcileDelivery(.load())
    }

    /// 로그아웃 시 서버 토큰 해제 + 로컬 정리.
    func handleLogout() async {
        if let token = registeredToken {
            try? await remoteStore.deactivatePushToken(token)
        }
        registeredToken = nil
        MealNotificationService.cancelMealReminders()
    }

    /// 세션 만료(authExpired) 등으로 in-memory 등록 토큰만 비운다. 서버 DELETE는 401이라 의미 없어 생략.
    func clearRegistration() {
        registeredToken = nil
    }

    /// 로컬/서버 발송을 registeredToken 기준으로 일치시키는 단일 진입점.
    /// 서버 가능(토큰 있음) → 로컬 OFF, 불가 → 로컬 ON. reschedule await 동안 토큰이 붙었으면 재확인해 취소.
    private func reconcileDelivery(_ settings: MealReminderSettings) async {
        if registeredToken != nil {
            MealNotificationService.cancelMealReminders()   // 서버가 발송
        } else {
            await MealNotificationService.reschedule(settings)   // 로컬 보조
            if registeredToken != nil {
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

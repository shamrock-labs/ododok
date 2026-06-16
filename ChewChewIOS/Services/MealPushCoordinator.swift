import Foundation
import UIKit

/// 식사 알림을 "서버 단독 + 오프라인 보조" 정책으로 조율한다(ODO-56).
///
/// 서버 수신 가능 = 로그인 AND 알림 권한 AND APNs 토큰 서버 등록 성공.
///  - 가능: 서버에 슬롯 설정을 올리고 로컬 예약은 취소한다(서버가 APNs로 발송).
///  - 불가(미로그인·권한 없음·토큰 미등록·동기화 실패): 기존 로컬 알림으로 운영한다(REQ-13 경로).
///
/// 같은 끼니에 서버·로컬이 동시에 뜨지 않도록 둘은 상호배타로 둔다. APNs 토큰 수신은 비동기라,
/// 첫 진입에는 로컬로 덮어두고 토큰이 등록되면 서버로 전환(로컬 취소)한다.
/// actor로 둬 registeredToken 접근을 직렬화하고, UIApplication 호출만 메인으로 hop한다.
actor MealPushCoordinator {

    private let remoteStore: RemoteStore
    /// APNs 등록에 성공해 서버에 올린 토큰(hex). nil이면 서버 수신 불가로 본다.
    private var registeredToken: String?

    init(remoteStore: RemoteStore) {
        self.remoteStore = remoteStore
    }

    /// 앱 활성/설정 변경 시 현재 설정을 정책에 맞게 적용한다.
    func apply(_ settings: MealReminderSettings) async {
        guard TokenManager.isLoggedIn else {
            MealNotificationService.cancelMealReminders()   // 로그아웃: 알림 없음(로그인 게이트)
            return
        }
        guard await MealNotificationService.isAuthorized() else {
            await MealNotificationService.reschedule(settings)   // 권한 없음 → reschedule이 제거만
            return
        }
        // 로그인 + 권한 → 토큰 미등록이면 원격 등록 요청(결과는 didRegister 콜백에서).
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }

        if registeredToken != nil {
            do {
                try await remoteStore.upsertMealNotifications(settings, timeZone: TimeZone.current.identifier)
                MealNotificationService.cancelMealReminders()   // 서버가 발송 → 로컬 취소
                return
            } catch {
                // 동기화 실패(오프라인 등) → 아래 로컬 보조로 폴백
            }
        }
        await MealNotificationService.reschedule(settings)   // 토큰 미등록 or 동기화 실패 → 로컬
    }

    /// AppDelegate didRegisterForRemoteNotificationsWithDeviceToken에서 호출.
    func didRegister(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard TokenManager.isLoggedIn else {
            registeredToken = nil
            return
        }
        do {
            try await remoteStore.registerPushToken(hex, environment: Self.apnsEnvironment)
            registeredToken = hex
            // 등록 성공 → 서버로 전환: 저장된 설정을 올리고 로컬 예약 취소.
            try await remoteStore.upsertMealNotifications(.load(), timeZone: TimeZone.current.identifier)
            MealNotificationService.cancelMealReminders()
        } catch {
            registeredToken = nil   // 등록·동기화 실패 → 로컬 유지
            await MealNotificationService.reschedule(.load())
        }
    }

    /// AppDelegate didFailToRegisterForRemoteNotificationsWithError에서 호출.
    func didFailToRegister() async {
        registeredToken = nil
        await MealNotificationService.reschedule(.load())
    }

    /// 로그아웃 시 서버 토큰 해제 + 로컬 정리.
    func handleLogout() async {
        if let token = registeredToken {
            try? await remoteStore.deactivatePushToken(token)
        }
        registeredToken = nil
        MealNotificationService.cancelMealReminders()
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

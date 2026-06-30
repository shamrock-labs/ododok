import Foundation
import Sentry

/// Sentry 크래시·에러 모니터링 부트스트랩.
///
/// DSN은 `Secrets.xcconfig` → Info.plist(`SentryDSN`) 경유로 주입한다(Kakao 키와 같은 패턴).
/// xcconfig가 `//`를 주석으로 처리해 URL scheme이 잘리므로, Secrets에는 `https://`를 뺀
/// 본문만 저장하고 여기서 다시 붙인다.
///
/// 초기화는 `ChewChewIOSApp.init()` 맨 앞에서 1회 호출한다(이후 의존성 초기화 실패까지 포착).
enum SentryService {
    private static let smokeTestArgument = "-sentrySmokeTest"

    /// Sentry SDK를 시작한다. DSN 미설정·테스트 런에서는 조용히 건너뛴다(no-op).
    static func start() {
        // 테스트(유닛/UI) 런에서는 외부 전송·노이즈를 막기 위해 초기화하지 않는다.
        // makeDependencies()의 underTest 판정과 동일한 신호를 쓴다.
        let pi = ProcessInfo.processInfo
        let wantsSmokeTest = pi.arguments.contains(smokeTestArgument)
        let underTest = pi.environment["XCTestConfigurationFilePath"] != nil
            || pi.arguments.contains("-useNoopRemote")
        guard !underTest || wantsSmokeTest else { return }

        // DSN 본문(scheme 제외). placeholder(REPLACE)·빈값·미확장 `$(SENTRY_DSN)` 리터럴(키 미설정 시)이면
        // Sentry 비활성 — 로컬/기여자/CI 빌드 보호. garbage 값으로 SDK가 켜지는 오설정을 막는다.
        guard let body = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              !body.isEmpty, !body.contains("REPLACE"), !body.contains("$(") else { return }
        let dsn = "https://" + body

        SentrySDK.start { options in
            options.dsn = dsn

            options.environment = AppEnvironment.current

            // 릴리스 식별 — 이슈를 버전별로 묶고 regression을 추적한다. 형식: ododok@<버전>+<빌드>.
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                options.releaseName = "ododok@\(version)+\(build)"
            }

            // 성능 트레이싱 — 초기엔 보수적으로 20%만 샘플링(쿼터·노이즈 관리). 운영 보며 조정.
            options.tracesSampleRate = 0.2

            // PII(이메일·IP 등) 자동 수집 비활성 — 헬스 앱 프라이버시 보수적 기본값.
            options.sendDefaultPii = false
        }

        if wantsSmokeTest {
            captureSmokeTest()
        }
    }

    /// Sentry 유저 컨텍스트 설정. 비-PII 익명 식별자(DeviceIdentity)만 넣는다.
    /// 크래시·에러를 유저 단위로 묶어 "몇 명에게 영향" 같은 집계를 가능하게 한다.
    /// SDK 미시작(테스트·DSN 미설정) 시 SentrySDK가 안전하게 no-op 처리한다.
    /// 호출부(AppState)가 벤더 SDK에 직접 의존하지 않도록 이 헬퍼로 감싼다.
    static func setUser(id: String?) {
        if let id {
            SentrySDK.setUser(User(userId: id))
        } else {
            SentrySDK.setUser(nil) // 로그아웃·리셋 시 컨텍스트 해제
        }
    }

    private static func captureSmokeTest() {
        let environment = AppEnvironment.current
        let eventId = SentrySDK.capture(message: "Sentry smoke test (\(environment))") { scope in
            scope.setEnvironment(environment)
            scope.setFingerprint(["sentry-smoke-test", environment])
            scope.setTag(value: environment, key: "app_environment")
            scope.setTag(value: "true", key: "smoke_test")
        }
        print("Sentry smoke test sent: environment=\(environment), eventId=\(eventId)")
        SentrySDK.flush(timeout: 5)
    }
}

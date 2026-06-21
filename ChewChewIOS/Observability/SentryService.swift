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
    /// Sentry SDK를 시작한다. DSN 미설정·테스트 런에서는 조용히 건너뛴다(no-op).
    static func start() {
        // 테스트(유닛/UI) 런에서는 외부 전송·노이즈를 막기 위해 초기화하지 않는다.
        // makeDependencies()의 underTest 판정과 동일한 신호를 쓴다.
        let pi = ProcessInfo.processInfo
        let underTest = pi.environment["XCTestConfigurationFilePath"] != nil
            || pi.arguments.contains("-useNoopRemote")
        guard !underTest else { return }

        // DSN 본문(scheme 제외). placeholder(REPLACE)거나 비면 Sentry 비활성 — 로컬/기여자 빌드 보호.
        guard let body = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              !body.isEmpty, !body.contains("REPLACE") else { return }
        let dsn = "https://" + body

        SentrySDK.start { options in
            options.dsn = dsn

            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif

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
    }
}

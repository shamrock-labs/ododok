#if DEBUG
import Foundation

/// Sentry 크래시 수집 파이프라인 검증용 의도적 크래시 트리거.
///
/// **DEBUG 전용** — 파일 전체가 `#if DEBUG`로 격리돼 Release 바이너리엔 컴파일되지 않는다.
/// launch argument `-crashTest <type>`로만 발동하며, 인자가 없으면 아무 일도 하지 않는다(운영 무영향).
///
/// 크래시 유형별로 Sentry의 수집 경로가 다르다:
/// - `fatalError`/`forceUnwrap`/`outOfBounds`: Swift runtime trap → 시그널 핸들러
/// - `nsException`: ObjC uncaught exception → NSException 핸들러(위와 다른 경로)
///
/// 사용: `xcrun simctl launch booted <bundle-id> -crashTest fatalError`
/// Sentry는 크래시 순간이 아니라 **다음 실행 때** 디스크에 저장된 리포트를 전송한다.
enum CrashTester {
    enum Kind: String, CaseIterable {
        case fatalError
        case forceUnwrap
        case outOfBounds
        case nsException
    }

    /// launch argument에 `-crashTest <type>`이 있으면 해당 크래시를 즉시 발생시킨다.
    /// SentryService.start() 직후 호출해 crash handler가 설치된 뒤 크래시하도록 한다.
    static func crashIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-crashTest"), idx + 1 < args.count,
              let kind = Kind(rawValue: args[idx + 1]) else { return }
        crash(kind)
    }

    private static func crash(_ kind: Kind) {
        switch kind {
        case .fatalError:
            fatalError("Sentry crash test: fatalError")
        case .forceUnwrap:
            let value: String? = nil
            print("force-unwrapping nil: \(value!)") // Swift trap: unexpectedly found nil
        case .outOfBounds:
            let arr: [Int] = []
            print("index out of bounds: \(arr[5])") // Swift trap: index out of range
        case .nsException:
            // ObjC uncaught exception 경로 — Swift trap과 다른 핸들러로 잡힌다.
            let empty = NSArray()
            print("NSArray out of bounds: \(empty.object(at: 5))")
        }
    }
}
#endif

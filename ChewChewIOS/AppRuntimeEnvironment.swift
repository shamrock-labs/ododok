import Foundation

/// 앱 런타임 환경명.
///
/// Sentry environment와 Analytics 공통 속성이 같은 값을 쓰도록 한 곳에서만 정의한다.
enum AppRuntimeEnvironment {
    #if DEBUG
    static let name = "dev"
    #else
    static let name = "prod"
    #endif
}

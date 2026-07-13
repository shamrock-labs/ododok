import Foundation

/// 앱 런타임 환경명.
///
/// Sentry environment와 Analytics 공통 속성이 같은 값을 쓰도록 한 곳에서만 정의한다.
enum AppRuntimeEnvironment {
    static let name: String = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AppRuntimeEnvironment") as? String
        guard let value = resolve(raw) else {
            preconditionFailure("AppRuntimeEnvironment가 비었거나 미치환 — Project.swift의 APP_RUNTIME_ENVIRONMENT 확인")
        }
        return value
    }()

    static func resolve(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == "dev" || value == "prod" else { return nil }
        return value
    }
}

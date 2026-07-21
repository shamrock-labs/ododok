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

/// 분석에서 Debug·TestFlight·App Store 트래픽을 분리하는 배포 채널.
/// 백엔드 환경(dev/prod)과 직교한다. TestFlight는 prod 백엔드와 Dev 분석 프로젝트를 사용한다.
enum AppBuildChannel {
    static let name: String = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AppBuildChannel") as? String
        guard let value = resolve(raw) else {
            preconditionFailure("AppBuildChannel이 비었거나 미치환 — Project.swift의 APP_BUILD_CHANNEL 확인")
        }
        return value
    }()

    static func resolve(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == "debug" || value == "testflight" || value == "app_store" else { return nil }
        return value
    }
}

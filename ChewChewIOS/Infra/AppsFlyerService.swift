import AppsFlyerLib
import Foundation
import UIKit

/// AppsFlyer를 시작할 때 필요한 런타임 설정이다.
/// 키가 없거나 플레이스홀더인 빌드는 SDK를 시작하지 않아 CI·테스트 실행이 운영 유입 지표에 섞이지 않게 한다.
struct AppsFlyerConfiguration: Equatable {
    let devKey: String
    let appleAppID: String

    static func resolve(
        infoDictionary: [String: Any],
        isRunningTests: Bool
    ) -> AppsFlyerConfiguration? {
        guard !isRunningTests,
              let devKey = usableValue(infoDictionary["AppsFlyerDevKey"]),
              let appleAppID = usableValue(infoDictionary["AppsFlyerAppleAppID"]),
              appleAppID.allSatisfy(\.isNumber)
        else {
            return nil
        }
        return AppsFlyerConfiguration(devKey: devKey, appleAppID: appleAppID)
    }

    private static func usableValue(_ raw: Any?) -> String? {
        guard let raw = raw as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("REPLACE"),
              !value.contains("$(")
        else {
            return nil
        }
        return value
    }
}

/// OneLink의 `deep_link_value`를 앱이 지원하는 내부 목적지로 제한한다.
/// 마케팅 링크의 임의 문자열을 라우터에 직접 넘기지 않고, 명시적으로 허용한 화면만 열도록 경계를 둔다.
enum AppsFlyerDeepLinkDestination: Equatable {
    case home
    case start

    static func resolve(_ value: String?) -> AppsFlyerDeepLinkDestination? {
        switch value?.lowercased() {
        case "home": .home
        case "start": .start
        default: nil
        }
    }
}

/// AppsFlyer SDK 생명주기와 UDL 콜백을 앱 라우팅 목적지로 변환한다.
/// `AppState`를 직접 변경하지 않고 목적지만 반환해 외부 acquisition SDK와 제품 상태를 분리한다.
final class AppsFlyerService: NSObject, AppsFlyerDeepLinkDelegate {
    private var onDeepLink: ((AppsFlyerDeepLinkDestination) -> Void)?

    func start(
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        onDeepLink: @escaping (AppsFlyerDeepLinkDestination) -> Void
    ) {
        let processInfo = ProcessInfo.processInfo
        // XCTest와 Noop 원격 실행은 실제 사용자가 아니므로 SDK를 시작하지 않는다.
        // 자동화 Launch가 AppsFlyer의 설치·재방문 세션 지표에 섞이는 것을 막는 환경 경계다.
        let isRunningTests = processInfo.environment["XCTestConfigurationFilePath"] != nil
            || processInfo.arguments.contains("-useNoopRemote")
        guard let configuration = AppsFlyerConfiguration.resolve(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            isRunningTests: isRunningTests
        ) else {
            return
        }

        self.onDeepLink = onDeepLink

        let appsFlyer = AppsFlyerLib.shared()
        #if DEBUG
        appsFlyer.isDebug = true
        #endif
        appsFlyer.initialize(
            devKey: configuration.devKey,
            appId: configuration.appleAppID
        )
        appsFlyer.deepLinkDelegate = self
        appsFlyer.handleLaunchOptions(launchOptions)
        // SDK가 초기화 준비를 마친 뒤 start를 호출해 최초 Launch와 이후 Session을 전송한다.
        // 앱 시작 흐름에서 한 번 실행되어야 앞서 기록된 OneLink 클릭과 최초 실행을 매칭할 수 있다.
        appsFlyer.registerSessionReadyListener {
            AppsFlyerLib.shared().start()
        }
    }

    func handleOpenURL(
        _ url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any]
    ) {
        AppsFlyerLib.shared().handleOpen(url, options: options)
    }

    func continueUserActivity(_ userActivity: NSUserActivity) -> Bool {
        AppsFlyerLib.shared().continue(
            userActivity,
            restorationHandler: nil
        )
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard result.status == .found,
              let destination = AppsFlyerDeepLinkDestination.resolve(
                  result.deepLink?.deeplinkValue
              )
        else {
            return
        }
        onDeepLink?(destination)
    }
}

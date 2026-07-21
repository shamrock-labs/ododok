import AppsFlyerLib
import Foundation
import UIKit

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

final class AppsFlyerService: NSObject, AppsFlyerDeepLinkDelegate {
    private var onDeepLink: ((AppsFlyerDeepLinkDestination) -> Void)?

    func start(
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        onDeepLink: @escaping (AppsFlyerDeepLinkDestination) -> Void
    ) {
        let processInfo = ProcessInfo.processInfo
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

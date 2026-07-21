import Foundation
import ProjectDescription

let organizationName = "Shamrock"
let developmentTeam = "26SRR6SP9B"
let deploymentTarget = "17.0"
let versionConfig: Path = "Config/Version.xcconfig"
let secretsConfig: Path = "Config/Secrets.xcconfig"

let appBundleId = "$(ODODOK_BUNDLE_PREFIX).ododok"
let widgetsBundleId = "$(ODODOK_BUNDLE_PREFIX).ododok.OdodokWidgets"
let notificationContentBundleId = "$(ODODOK_BUNDLE_PREFIX).ododok.OdodokNotificationContent"

let googleServiceInfoPlistPath = "ChewChewIOS/GoogleService-Info.plist"
var appResources: [ResourceFileElement] = [
    "ChewChewIOS/Resources/**",
    "ChewChewIOS/PrivacyInfo.xcprivacy",
]
if FileManager.default.fileExists(atPath: googleServiceInfoPlistPath) {
    appResources.append(.glob(pattern: .relativeToRoot(googleServiceInfoPlistPath)))
}

let appInfoPlist: [String: Plist.Value] = [
    // 버전/빌드번호를 빌드 설정(MARKETING_VERSION/CURRENT_PROJECT_VERSION)과 연결한다.
    // 연결하지 않으면 Tuist 기본값(1.0/1)이 하드코딩돼 CI의 빌드번호 주입이 무시된다.
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "CFBundleDisplayName": "Ododok",
    "InsForgeAPIKey": "$(INSFORGE_API_KEY)",
    "SentryDSN": "$(SENTRY_DSN)",
    "AmplitudeAPIKey": "$(AMPLITUDE_API_KEY)",
    "AmplitudeInstanceName": "$(AMPLITUDE_INSTANCE_NAME)",
    "AppBuildChannel": "$(APP_BUILD_CHANNEL)",
    "AppsFlyerDevKey": "$(APPSFLYER_DEV_KEY)",
    "AppsFlyerAppleAppID": "$(APPSFLYER_APP_ID)",
    "BackendBaseURL": "$(BACKEND_BASE_URL)",
    "AppRuntimeEnvironment": "$(APP_RUNTIME_ENVIRONMENT)",
    "KakaoInviteMobileWebURL": "$(KAKAO_INVITE_MOBILE_WEB_URL)",
    // HTTPS/Firebase/Apple 기본 보안 외 자체 비면제 암호화를 사용하지 않는다.
    // 이 값이 없으면 App Store Connect가 빌드마다 수출 규정 확인을 요구할 수 있다.
    "ITSAppUsesNonExemptEncryption": false,
    "NSMotionUsageDescription": "식사 중 AirPods 움직임을 분석해 저작 리듬을 시각화합니다.",
    "UIBackgroundModes": [
        "audio",
    ],
    "UIAppFonts": [
        "Pretendard-Regular.otf",
        "Pretendard-Medium.otf",
        "Pretendard-SemiBold.otf",
        "Pretendard-Bold.otf",
        "Pretendard-Black.otf",
    ],
    "GIDClientID": "$(GOOGLE_CLIENT_ID)",
    "KakaoNativeAppKey": "$(KAKAO_NATIVE_APP_KEY)",
    "LSApplicationQueriesSchemes": [
        "kakaokompassauth",
        "kakaotalk",
        "kakaolink",
    ],
    "CFBundleURLTypes": [
        [
            "CFBundleURLSchemes": [
                "chewchew",
            ],
        ],
        [
            "CFBundleURLSchemes": [
                "$(GOOGLE_REVERSED_CLIENT_ID)",
            ],
        ],
        [
            "CFBundleURLSchemes": [
                "kakao$(KAKAO_NATIVE_APP_KEY)",
            ],
        ],
    ],
    "UILaunchScreen": [:],
    "UISupportedInterfaceOrientations": [
        "UIInterfaceOrientationPortrait",
    ],
    "UIStatusBarStyle": "UIStatusBarStyleDefault",
    "NSSupportsLiveActivities": true,
]

let widgetsInfoPlist: [String: Plist.Value] = [
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "CFBundleDisplayName": "오도독",
    "ITSAppUsesNonExemptEncryption": false,
    "NSExtension": [
        "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
    ],
]

let notificationContentInfoPlist: [String: Plist.Value] = [
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "CFBundleDisplayName": "오도독",
    "ITSAppUsesNonExemptEncryption": false,
    "NSExtension": [
        "NSExtensionPointIdentifier": "com.apple.usernotifications.content-extension",
        "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).NotificationViewController",
        "NSExtensionAttributes": [
            "UNNotificationExtensionCategory": [
                "MEAL_REMINDER",
                "MEAL_INTERRUPTION",
            ],
            "UNNotificationExtensionDefaultContentHidden": true,
            "UNNotificationExtensionInitialContentSizeRatio": 0.56,
        ],
    ],
]

func signingSettings(
    profileSpecifier: String,
    codeSignIdentity: String = "iPhone Developer"
) -> SettingsDictionary {
    [
        "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY[sdk=iphoneos*]": .string(codeSignIdentity),
        "DEVELOPMENT_TEAM": "",
        "DEVELOPMENT_TEAM[sdk=iphoneos*]": .string(developmentTeam),
        "PROVISIONING_PROFILE_SPECIFIER": "",
        "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": .string(profileSpecifier),
    ]
}

func targetSettings(
    base: SettingsDictionary = [:],
    debug: SettingsDictionary = [:],
    testFlight: SettingsDictionary = [:],
    release: SettingsDictionary = [:]
) -> Settings {
    .settings(
        base: base,
        configurations: [
            .debug(
                name: "Debug",
                settings: debug,
                xcconfig: secretsConfig
            ),
            .release(
                name: "TestFlight",
                settings: testFlight,
                xcconfig: secretsConfig
            ),
            .release(
                name: "Release",
                settings: release,
                xcconfig: secretsConfig
            ),
        ],
        defaultSettings: .recommended
    )
}

let sentryDSYMUploadScript = """
case "${CONFIGURATION}" in Release|TestFlight) ;; *) echo "dSYM upload: skip (not distribution)"; exit 0;; esac
# token, org, project가 모두 채워졌고 placeholder가 아닐 때만 업로드한다.
for v in "${SENTRY_AUTH_TOKEN}" "${SENTRY_ORG}" "${SENTRY_PROJECT}"; do
  case "$v" in ""|*REPLACE*) echo "dSYM upload: skip (Sentry token/org/project 미설정)"; exit 0;; esac
done
if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "warning: sentry-cli 미설치 - dSYM 업로드 생략. 설치: brew install getsentry/tools/sentry-cli"; exit 0
fi
sentry-cli debug-files upload \\
  --auth-token "${SENTRY_AUTH_TOKEN}" \\
  --org "${SENTRY_ORG}" \\
  --project "${SENTRY_PROJECT}" \\
  "${DWARF_DSYM_FOLDER_PATH}"
"""

let project = Project(
    name: "ChewChewIOS",
    organizationName: organizationName,
    packages: [
        .remote(url: "https://github.com/google/GoogleSignIn-iOS", requirement: .upToNextMajor(from: "7.1.0")),
        .remote(url: "https://github.com/kakao/kakao-ios-sdk", requirement: .upToNextMajor(from: "2.0.0")),
        .remote(url: "https://github.com/getsentry/sentry-cocoa", requirement: .upToNextMajor(from: "8.0.0")),
        .remote(url: "https://github.com/amplitude/Amplitude-Swift", requirement: .upToNextMajor(from: "1.0.0")),
        .remote(url: "https://github.com/firebase/firebase-ios-sdk", requirement: .upToNextMajor(from: "12.0.0")),
        .remote(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework-Static", requirement: .upToNextMajor(from: "7.0.0")),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.9",
            "DEVELOPMENT_TEAM": .string(developmentTeam),
        ],
        configurations: [
            .debug(name: "Debug", xcconfig: versionConfig),
            .release(name: "TestFlight", xcconfig: versionConfig),
            .release(name: "Release", xcconfig: versionConfig),
        ],
        defaultSettings: .recommended
    ),
    targets: [
        .target(
            name: "ChewChewIOS",
            destinations: .iOS,
            product: .app,
            bundleId: appBundleId,
            deploymentTargets: .iOS(deploymentTarget),
            infoPlist: .extendingDefault(with: appInfoPlist),
            sources: [
                "ChewChewIOS/**/*.swift",
            ],
            resources: .resources(appResources),
            entitlements: "ChewChewIOS/ChewChewIOS.entitlements",
            scripts: [
                .post(
                    script: sentryDSYMUploadScript,
                    name: "Upload dSYMs to Sentry",
                    basedOnDependencyAnalysis: false
                ),
            ],
            dependencies: [
                .target(name: "OdodokWidgets"),
                .target(name: "OdodokNotificationContent"),
                .package(product: "GoogleSignIn"),
                .package(product: "KakaoSDKCommon"),
                .package(product: "KakaoSDKAuth"),
                .package(product: "KakaoSDKUser"),
                .package(product: "KakaoSDKShare"),
                .package(product: "KakaoSDKTemplate"),
                .package(product: "Sentry"),
                .package(product: "AmplitudeSwift"),
                .package(product: "FirebaseAnalytics"),
                .package(product: "AppsFlyerLib-Static"),
            ],
            settings: targetSettings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": .string(appBundleId),
                    "TARGETED_DEVICE_FAMILY": "1",
                    "ENABLE_PREVIEWS": "YES",
                    "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)",
                        "@executable_path/Frameworks",
                    ],
                ].merging(signingSettings(profileSpecifier: "match Development com.shamrock.ododok")) { _, new in new },
                debug: [
                    "APS_ENVIRONMENT": "development",
                    "BACKEND_BASE_URL": "https://api.dev.ododok.cloud",
                    "APP_RUNTIME_ENVIRONMENT": "dev",
                    "APP_BUILD_CHANNEL": "debug",
                    "AMPLITUDE_API_KEY": "$(AMPLITUDE_DEV_API_KEY)",
                    "AMPLITUDE_INSTANCE_NAME": "ododok-amplitude-dev-us-v1",
                ],
                testFlight: [
                    "APS_ENVIRONMENT": "production",
                    "BACKEND_BASE_URL": "https://api.ododok.cloud",
                    "APP_RUNTIME_ENVIRONMENT": "prod",
                    "APP_BUILD_CHANNEL": "testflight",
                    "AMPLITUDE_API_KEY": "$(AMPLITUDE_DEV_API_KEY)",
                    "AMPLITUDE_INSTANCE_NAME": "ododok-amplitude-dev-us-v1",
                ].merging(signingSettings(
                    profileSpecifier: "match AppStore com.shamrock.ododok",
                    codeSignIdentity: "iPhone Distribution"
                )) { _, new in new },
                release: [
                    "APS_ENVIRONMENT": "production",
                    "BACKEND_BASE_URL": "https://api.ododok.cloud",
                    "APP_RUNTIME_ENVIRONMENT": "prod",
                    "APP_BUILD_CHANNEL": "app_store",
                    "AMPLITUDE_API_KEY": "$(AMPLITUDE_PROD_API_KEY)",
                    "AMPLITUDE_INSTANCE_NAME": "ododok-amplitude-prod-us-v1",
                ].merging(signingSettings(
                    profileSpecifier: "match AppStore com.shamrock.ododok",
                    codeSignIdentity: "iPhone Distribution"
                )) { _, new in new }
            )
        ),
        .target(
            name: "OdodokWidgets",
            destinations: .iOS,
            product: .appExtension,
            bundleId: widgetsBundleId,
            deploymentTargets: .iOS(deploymentTarget),
            infoPlist: .extendingDefault(with: widgetsInfoPlist),
            sources: [
                "OdodokWidgets/**/*.swift",
                "ChewChewIOS/Models/MealActivityAttributes.swift",
            ],
            resources: [
                "OdodokWidgets/Assets.xcassets",
            ],
            settings: targetSettings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": .string(widgetsBundleId),
                    "TARGETED_DEVICE_FAMILY": "1",
                    "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)",
                        "@executable_path/Frameworks",
                        "@executable_path/../../Frameworks",
                    ],
                ].merging(signingSettings(profileSpecifier: "match Development com.shamrock.ododok.OdodokWidgets")) { _, new in new },
                testFlight: signingSettings(
                    profileSpecifier: "match AppStore com.shamrock.ododok.OdodokWidgets",
                    codeSignIdentity: "iPhone Distribution"
                ),
                release: signingSettings(
                    profileSpecifier: "match AppStore com.shamrock.ododok.OdodokWidgets",
                    codeSignIdentity: "iPhone Distribution"
                )
            )
        ),
        .target(
            name: "OdodokNotificationContent",
            destinations: .iOS,
            product: .appExtension,
            bundleId: notificationContentBundleId,
            deploymentTargets: .iOS(deploymentTarget),
            infoPlist: .extendingDefault(with: notificationContentInfoPlist),
            sources: [
                "OdodokNotificationContent/**/*.swift",
            ],
            resources: [
                "OdodokWidgets/Assets.xcassets",
            ],
            settings: targetSettings(
                base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": .string(notificationContentBundleId),
                    "TARGETED_DEVICE_FAMILY": "1",
                    "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
                    "APPLICATION_EXTENSION_API_ONLY": "YES",
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)",
                        "@executable_path/Frameworks",
                        "@executable_path/../../Frameworks",
                    ],
                ].merging(signingSettings(profileSpecifier: "match Development com.shamrock.ododok.OdodokNotificationContent")) { _, new in new },
                testFlight: signingSettings(
                    profileSpecifier: "match AppStore com.shamrock.ododok.OdodokNotificationContent",
                    codeSignIdentity: "iPhone Distribution"
                ),
                release: signingSettings(
                    profileSpecifier: "match AppStore com.shamrock.ododok.OdodokNotificationContent",
                    codeSignIdentity: "iPhone Distribution"
                )
            )
        ),
        .target(
            name: "ChewChewIOSTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.shamrock.ChewChewIOSTests",
            deploymentTargets: .iOS(deploymentTarget),
            infoPlist: .default,
            sources: [
                "ChewChewIOSTests/**/*.swift",
            ],
            dependencies: [
                .target(name: "ChewChewIOS"),
            ],
            settings: .settings(
                base: [
                    // 테스트 번들은 시뮬레이터에서만 돌리므로 서명하지 않는다. 실기기 앱 서명(수동/match)과
                    // 얽혀 "requires a development team or provisioning profile" 에러가 뜨는 걸 막는다.
                    "CODE_SIGNING_ALLOWED": "NO",
                    "BUNDLE_LOADER": "$(TEST_HOST)",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/ChewChewIOS.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ChewChewIOS",
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
                    "TARGETED_DEVICE_FAMILY": "1",
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)",
                        "@executable_path/Frameworks",
                        "@loader_path/Frameworks",
                    ],
                ],
                defaultSettings: .recommended
            )
        ),
        .target(
            name: "ChewChewIOSUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "com.shamrock.ChewChewIOSUITests",
            deploymentTargets: .iOS(deploymentTarget),
            infoPlist: .default,
            sources: [
                "ChewChewIOSUITests/**/*.swift",
            ],
            dependencies: [
                .target(name: "ChewChewIOS"),
            ],
            settings: .settings(
                base: [
                    // UI 테스트도 시뮬레이터 전용 — 서명 끔(위 유닛 테스트와 동일 이유).
                    "CODE_SIGNING_ALLOWED": "NO",
                    "TEST_TARGET_NAME": "ChewChewIOS",
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "IPHONEOS_DEPLOYMENT_TARGET": .string(deploymentTarget),
                    "TARGETED_DEVICE_FAMILY": "1",
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)",
                        "@executable_path/Frameworks",
                        "@loader_path/Frameworks",
                    ],
                ],
                defaultSettings: .recommended
            )
        ),
    ],
    schemes: [
        // 앱 전용 스킴 — 실기기 Run/빌드가 테스트 번들 서명을 요구하지 않도록 testAction을 분리했다.
        // 실기기에서 앱만 서명해 돌릴 때 com.shamrock.ChewChewIOSTests/UITests 프로비저닝 요구가 안 뜬다.
        // 유닛/UI 테스트는 아래 "ChewChewIOSTests" 스킴(시뮬레이터)으로 돌린다.
        .scheme(
            name: "ChewChewIOS",
            shared: true,
            buildAction: .buildAction(targets: ["ChewChewIOS"]),
            runAction: .runAction(configuration: "Debug"),
            archiveAction: .archiveAction(configuration: "Release"),
            profileAction: .profileAction(configuration: "Release"),
            analyzeAction: .analyzeAction(configuration: "Debug")
        ),
        .scheme(
            name: "ChewChewIOSTestFlight",
            shared: true,
            buildAction: .buildAction(targets: ["ChewChewIOS"]),
            archiveAction: .archiveAction(configuration: "TestFlight"),
            profileAction: .profileAction(configuration: "TestFlight")
        ),
        // PR CI는 빠른 유닛 테스트만 실행한다. 테스트 타깃이 앱을 의존하므로 앱과 확장도 함께 빌드된다.
        .scheme(
            name: "ChewChewIOSUnitTests",
            shared: true,
            buildAction: .buildAction(targets: ["ChewChewIOSTests"]),
            testAction: .targets(
                ["ChewChewIOSTests"],
                configuration: "Debug"
            )
        ),
        // 테스트 전용 스킴. 앱 스킴에서 떼어내 실기기 서명과 얽히지 않게 한다(시뮬레이터에서 실행).
        .scheme(
            name: "ChewChewIOSTests",
            shared: true,
            buildAction: .buildAction(targets: ["ChewChewIOSTests", "ChewChewIOSUITests"]),
            testAction: .targets(
                [
                    "ChewChewIOSTests",
                    "ChewChewIOSUITests",
                ],
                configuration: "Debug"
            )
        ),
    ]
)

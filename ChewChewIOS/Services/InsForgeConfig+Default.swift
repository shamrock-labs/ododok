import Foundation

extension InsForgeConfig {
    /// 1차 PR — InsForge가 발급한 익명 API 키(anon key)는 RLS로 권한이 통제된다는
    /// 가정 하에 클라이언트에 박는 게 InsForge의 표준 패턴.
    /// TODO: 후속 PR에서 xcconfig 파일을 .gitignore에 두는 방식으로 분리.
    static let `default` = InsForgeConfig(
        baseURL: URL(string: "https://5jr82e8a.us-east.insforge.app")!,
        apiKey: "<REDACTED-MOVED-TO-XCCONFIG>"
    )
}

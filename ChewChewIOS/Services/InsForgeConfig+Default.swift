import Foundation

extension InsForgeConfig {
    /// 익명 API 키는 `Config/Secrets.xcconfig` → `INSFORGE_API_KEY` → Info.plist의
    /// `InsForgeAPIKey`로 흘러들어온다. 키 자체는 .gitignore에 들어가 커밋되지 않음.
    /// `Secrets.xcconfig`이 없으면 빌드 시 빈 문자열이 들어가 어설션이 터진다.
    ///
    /// 베이스 URL은 InsForge 프로젝트 도메인이라 노출돼도 무해 — 코드에 박는다.
    static let `default` = InsForgeConfig(
        baseURL: URL(string: "https://5jr82e8a.us-east.insforge.app")!,
        apiKey: loadAPIKey()
    )

    private static func loadAPIKey() -> String {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "InsForgeAPIKey") as? String,
            !key.isEmpty,
            !key.contains("REPLACE_WITH_YOUR")
        else {
            assertionFailure("InsForgeAPIKey가 비어있거나 placeholder임 — Config/Secrets.xcconfig 셋업 확인")
            return ""
        }
        return key
    }
}

import Foundation

extension SpringConfig {
    /// 백엔드 base URL은 빌드 설정 `BACKEND_BASE_URL`(→ Info.plist `BackendBaseURL`)에서 읽는다.
    /// Swift에 URL을 하드코딩하지 않고 빌드설정(환경)으로 주입한다. 현재 staging 단일.
    /// 레거시 InsForge는 `-useInsForge` 오버라이드로만 사용.
    static let current: SpringConfig = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
              !raw.isEmpty, !raw.contains("$("),
              let url = URL(string: raw) else {
            preconditionFailure("BackendBaseURL이 비었거나 미치환 — project.yml의 BACKEND_BASE_URL 확인")
        }
        return SpringConfig(baseURL: url)
    }()
}

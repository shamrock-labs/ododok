import Foundation

extension SpringConfig {
    /// staging (성호 Mac mini, Tailscale 내부 IP). HTTP라 project.yml의 ATS 예외와 함께 동작한다.
    /// ODO-54부터 기본 백엔드로 주입된다. 레거시 InsForge는 `-useInsForge` 오버라이드로만 사용.
    static let stagingDefault = SpringConfig(
        baseURL: URL(string: "http://100.99.252.124:8080")!
    )
}

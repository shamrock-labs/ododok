import Foundation

extension SpringConfig {
    /// staging (성호 Mac mini, Tailscale 내부 IP). HTTP라 project.yml의 ATS 예외와 함께 동작한다.
    /// `-useSpringBackend` launch argument일 때만 주입된다(기본 백엔드는 InsForge 유지).
    static let stagingDefault = SpringConfig(
        baseURL: URL(string: "http://100.99.252.124:8080")!
    )
}

import Foundation

enum AppEnvironment {
    #if DEBUG
    static let current = "dev"
    #else
    static let current = "prod"
    #endif
}

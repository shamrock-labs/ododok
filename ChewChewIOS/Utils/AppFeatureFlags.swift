import Foundation

enum AppFeatureFlags {
    #if DEBUG
    static let showsCalibrationDiagnostics = true
    #else
    static let showsCalibrationDiagnostics = false
    #endif
}

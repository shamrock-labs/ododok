import Foundation

enum CalibrationArtifactKind: String, Codable, CaseIterable {
    case measurementRaw = "MEASUREMENT_RAW"
    case validationRaw = "VALIDATION_RAW"
    case events = "EVENTS"
    case summary = "SUMMARY"

    var filename: String {
        switch self {
        case .measurementRaw: "measurement-raw.csv"
        case .validationRaw: "validation-raw.csv"
        case .events: "events.csv"
        case .summary: "summary.json"
        }
    }
}

struct CalibrationArtifactUpload {
    let kind: CalibrationArtifactKind
    let data: Data
}

struct CalibrationArtifactBundle {
    let calibrationId: UUID
    let artifacts: [CalibrationArtifactUpload]
}

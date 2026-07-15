import Foundation

struct MeasurementCalibrationCapture {
    let startedAt: Date
    let endedAt: Date
    let samples: [HeadphoneMotionSample]

    var csvData: Data {
        var csv = IMURow.csvHeader
        let firstTimestamp = samples.first?.timestamp ?? 0
        for sample in samples {
            let row = IMURow(
                tMach: sample.timestamp,
                tRelSec: sample.timestamp - firstTimestamp,
                attitudeRoll: sample.attitudeRoll,
                attitudePitch: sample.attitudePitch,
                attitudeYaw: sample.attitudeYaw,
                rotationX: sample.rotationX,
                rotationY: sample.rotationY,
                rotationZ: sample.rotationZ,
                gravityX: sample.gravityX,
                gravityY: sample.gravityY,
                gravityZ: sample.gravityZ,
                userAccelX: sample.userAccelX,
                userAccelY: sample.userAccelY,
                userAccelZ: sample.userAccelZ,
                magneticFieldX: sample.magneticFieldX,
                magneticFieldY: sample.magneticFieldY,
                magneticFieldZ: sample.magneticFieldZ,
                sensorLocation: sample.sensorLocation
            )
            csv += "\n\(row.csvLine())"
        }
        return Data("\(csv)\n".utf8)
    }
}

enum MeasurementCalibrationOutcome: String, Encodable {
    case passed
    case passedAfterAdjustment
    case insufficientCalibration
    case insufficientSeparation
    case validationOutOfRange
}

enum MeasurementCalibrationArtifactFactory {
    struct Input {
        let calibrationId: UUID
        let measurementCapture: MeasurementCalibrationCapture?
        let validationCapture: MeasurementCalibrationCapture?
        let calibrationEvents: [ChewDetectionEvent]
        let adjustmentRun: MeasurementAdjustmentRun
        let threshold: Double?
        let gateThresholds: ChewingGateThresholds?
        let naturalChewInterval: TimeInterval?
        let representativeAmplitudes: [Double]
        let guidedExpectedCount: Int
        let outcome: MeasurementCalibrationOutcome
    }

    static func makeBundle(input: Input) -> CalibrationArtifactBundle {
        let summary = Summary(
            calibrationId: input.calibrationId,
            createdAt: Date(),
            outcome: input.outcome,
            minPeakAmplitude: input.threshold,
            gateThresholds: input.gateThresholds,
            initialValidationGateThresholds: input.adjustmentRun.initialThresholds,
            adjustedValidationGateThresholds: input.adjustmentRun.adjustedThresholds,
            naturalChewInterval: input.naturalChewInterval,
            representativeAmplitudes: input.representativeAmplitudes,
            validationDetectedCount: input.adjustmentRun.finalCount,
            validationDetectedCountBeforeAdjustment: input.adjustmentRun.initialCount,
            validationDetectedCountAfterAdjustment: input.adjustmentRun.adjustedCount,
            validationAdjustmentApplied: input.adjustmentRun.adjustmentApplied,
            validationAdjustmentStrategy: input.adjustmentRun.adjustmentStrategy,
            validationReplayCount: input.adjustmentRun.replayCount,
            guidedExpectedCount: input.guidedExpectedCount,
            measurementSampleCount: input.measurementCapture?.samples.count ?? 0,
            validationSampleCount: input.validationCapture?.samples.count ?? 0,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            modelVersion: ChewDetectionEngine.modelVersion
        )

        return CalibrationArtifactBundle(
            calibrationId: input.calibrationId,
            artifacts: [
                .init(kind: .measurementRaw, data: input.measurementCapture?.csvData ?? emptyRawCSV),
                .init(kind: .validationRaw, data: input.validationCapture?.csvData ?? emptyRawCSV),
                .init(kind: .events, data: eventsCSV(
                    calibrationEvents: input.calibrationEvents,
                    validationEvents: input.adjustmentRun.initialEvents,
                    adjustedValidationEvents: input.adjustmentRun.adjustedEvents
                )),
                .init(kind: .summary, data: encode(summary)),
            ]
        )
    }

    private struct Summary: Encodable {
        let calibrationId: UUID
        let createdAt: Date
        let outcome: MeasurementCalibrationOutcome
        let minPeakAmplitude: Double?
        let gateThresholds: ChewingGateThresholds?
        let initialValidationGateThresholds: ChewingGateThresholds?
        let adjustedValidationGateThresholds: ChewingGateThresholds?
        let naturalChewInterval: TimeInterval?
        let representativeAmplitudes: [Double]
        let validationDetectedCount: Int
        let validationDetectedCountBeforeAdjustment: Int
        let validationDetectedCountAfterAdjustment: Int?
        let validationAdjustmentApplied: Bool
        let validationAdjustmentStrategy: GateAdjustmentResult.Strategy?
        let validationReplayCount: Int
        let guidedExpectedCount: Int
        let measurementSampleCount: Int
        let validationSampleCount: Int
        let appVersion: String?
        let modelVersion: String
    }

    private static let emptyRawCSV = Data("\(IMURow.csvHeader)\n".utf8)

    private static func eventsCSV(
        calibrationEvents: [ChewDetectionEvent],
        validationEvents: [ChewDetectionEvent],
        adjustedValidationEvents: [ChewDetectionEvent]
    ) -> Data {
        var csv = "phase,event_index,timestamp,amplitude"
        for (index, event) in calibrationEvents.enumerated() {
            csv += line(phase: "measurement", index: index, event: event)
        }
        for (index, event) in validationEvents.enumerated() {
            csv += line(phase: "validation_initial", index: index, event: event)
        }
        for (index, event) in adjustedValidationEvents.enumerated() {
            csv += line(phase: "validation_adjusted", index: index, event: event)
        }
        return Data("\(csv)\n".utf8)
    }

    private static func line(phase: String, index: Int, event: ChewDetectionEvent) -> String {
        String(format: "\n%@,%d,%.6f,%.6f", phase, index + 1, event.timestamp, event.amplitude)
    }

    private static func encode(_ summary: Summary) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(summary)) ?? Data("{}".utf8)
    }
}

enum MeasurementCalibrationArtifactExporter {
    static func export(
        _ bundle: CalibrationArtifactBundle,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) -> [URL] {
        let root = rootDirectory ?? fileManager.temporaryDirectory
        let directory = root.appendingPathComponent(
            "ododok-calibration-\(bundle.calibrationId.uuidString.lowercased())",
            isDirectory: true
        )

        do {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return try bundle.artifacts.map { artifact in
                let url = directory.appendingPathComponent(artifact.kind.filename)
                try artifact.data.write(to: url, options: .atomic)
                return url
            }
        } catch {
            return []
        }
    }
}

@MainActor
protocol MeasurementCalibrationArtifactUploading: AnyObject {
    func enqueue(_ bundle: CalibrationArtifactBundle) async
    func retryPending() async
}

@MainActor
final class CalibrationArtifactUploadQueue: MeasurementCalibrationArtifactUploading {
    private let remoteStore: any RemoteStore
    private let fileManager: FileManager
    private let rootDirectory: URL

    init(
        remoteStore: any RemoteStore,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.remoteStore = remoteStore
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("CalibrationUploads", isDirectory: true)
    }

    func enqueue(_ bundle: CalibrationArtifactBundle) async {
        do {
            try persist(bundle)
            try await remoteStore.uploadCalibrationArtifacts(bundle)
            try remove(calibrationId: bundle.calibrationId)
        } catch {
            // 업로드 실패가 사용자의 측정 완료를 막지 않는다. 다음 진입 때 retryPending이 재시도한다.
        }
    }

    func retryPending() async {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for directory in directories {
            guard let calibrationId = UUID(uuidString: directory.lastPathComponent),
                  let bundle = load(calibrationId: calibrationId) else { continue }
            do {
                try await remoteStore.uploadCalibrationArtifacts(bundle)
                try remove(calibrationId: calibrationId)
            } catch {
                continue
            }
        }
    }

    private func persist(_ bundle: CalibrationArtifactBundle) throws {
        let directory = directory(for: bundle.calibrationId)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for artifact in bundle.artifacts {
            try artifact.data.write(
                to: directory.appendingPathComponent(artifact.kind.filename),
                options: .atomic
            )
        }
    }

    private func load(calibrationId: UUID) -> CalibrationArtifactBundle? {
        let directory = directory(for: calibrationId)
        let artifacts = CalibrationArtifactKind.allCases.compactMap { kind -> CalibrationArtifactUpload? in
            let url = directory.appendingPathComponent(kind.filename)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return CalibrationArtifactUpload(kind: kind, data: data)
        }
        guard artifacts.count == CalibrationArtifactKind.allCases.count else { return nil }
        return CalibrationArtifactBundle(calibrationId: calibrationId, artifacts: artifacts)
    }

    private func remove(calibrationId: UUID) throws {
        try fileManager.removeItem(at: directory(for: calibrationId))
    }

    private func directory(for calibrationId: UUID) -> URL {
        rootDirectory.appendingPathComponent(calibrationId.uuidString.lowercased(), isDirectory: true)
    }

}

@MainActor
final class NoopCalibrationArtifactUploader: MeasurementCalibrationArtifactUploading {
    func enqueue(_ bundle: CalibrationArtifactBundle) async {}
    func retryPending() async {}
}

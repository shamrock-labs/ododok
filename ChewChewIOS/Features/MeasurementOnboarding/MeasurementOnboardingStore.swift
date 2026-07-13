import Foundation
import Observation

@MainActor
@Observable
final class MeasurementOnboardingStore {
    enum Stage: String, CaseIterable {
        case intro
        case connection
        case rest
        case chew
        case ready
        case signalIssue

        var progressIndex: Int {
            switch self {
            case .intro, .connection: 0
            case .rest: 1
            case .chew: 2
            case .ready: 3
            case .signalIssue: 2
            }
        }
    }

    struct Timing {
        let tickCount: Int
        let tickInterval: Duration

        static let live = Timing(tickCount: 100, tickInterval: .milliseconds(100))
    }

    private(set) var stage: Stage
    private(set) var progress = 0.0
    private(set) var isMeasuring = false
    private(set) var measurementCompleted = false
    private(set) var isAirPodsConnected: Bool

    private let timing: Timing
    private var measurementTask: Task<Void, Never>?

    init(
        stage: Stage = .intro,
        isAirPodsConnected: Bool = false,
        timing: Timing = .live
    ) {
        self.stage = stage
        self.isAirPodsConnected = isAirPodsConnected
        self.timing = timing

        if stage == .ready {
            progress = 1
            measurementCompleted = true
        }
    }

    var remainingSeconds: Int {
        max(0, Int(ceil((1 - progress) * 10)))
    }

    func setAirPodsConnected(_ connected: Bool) {
        isAirPodsConnected = connected
    }

    func moveForward() {
        guard !isMeasuring else { return }

        switch stage {
        case .intro:
            setStage(.connection)
        case .connection where isAirPodsConnected:
            setStage(.rest)
        case .rest where measurementCompleted:
            setStage(.chew)
        case .chew where measurementCompleted:
            setStage(.ready)
        case .signalIssue:
            setStage(.chew)
        default:
            break
        }
    }

    func startMeasurement() {
        guard stage == .rest || stage == .chew, !isMeasuring else { return }

        measurementTask?.cancel()
        progress = 0
        measurementCompleted = false
        isMeasuring = true

        measurementTask = Task { [weak self] in
            guard let self else { return }

            for tick in 1...timing.tickCount {
                do {
                    try await Task.sleep(for: timing.tickInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                progress = Double(tick) / Double(timing.tickCount)
            }

            isMeasuring = false
            measurementCompleted = true
        }
    }

    func showSignalIssue() {
        measurementTask?.cancel()
        isMeasuring = false
        measurementCompleted = false
        setStage(.signalIssue)
    }

    func retryChewMeasurement() {
        setStage(.chew)
        startMeasurement()
    }

    func cancelMeasurement() {
        measurementTask?.cancel()
        isMeasuring = false
    }

    private func setStage(_ newStage: Stage) {
        measurementTask?.cancel()
        stage = newStage
        progress = newStage == .ready ? 1 : 0
        measurementCompleted = newStage == .ready
        isMeasuring = false
    }
}

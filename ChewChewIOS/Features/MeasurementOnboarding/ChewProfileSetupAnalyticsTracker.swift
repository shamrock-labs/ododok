import Foundation

final class ChewProfileSetupAnalyticsTracker {
    private let source: ChewProfileSetupSource
    private let analytics: AnalyticsService
    private let now: () -> Date

    private var startedAt: Date?
    private var stageStartedAt: Date?
    private var retryCount = 0
    private var finished = false
    private var lastActiveStage: MeasurementOnboardingStage = .intro

    init(
        source: ChewProfileSetupSource,
        analytics: AnalyticsService,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.analytics = analytics
        self.now = now
    }

    func start() {
        guard startedAt == nil else { return }
        let timestamp = now()
        startedAt = timestamp
        stageStartedAt = timestamp
        analytics.track(.chewProfileSetupStarted(source: source))
    }

    func transition(
        from oldStage: MeasurementOnboardingStage,
        to newStage: MeasurementOnboardingStage,
        issue: MeasurementOnboardingIssue?
    ) {
        guard !finished else { return }

        if oldStage == .signalIssue, newStage != .signalIssue {
            retryCount += 1
        }

        if newStage == .signalIssue, let issue {
            let failedStage = oldStage == .signalIssue ? lastActiveStage : oldStage
            analytics.track(.chewProfileSetupFailed(
                source: source,
                step: Self.analyticsStep(for: failedStage),
                reason: Self.analyticsReason(for: issue),
                retryCount: retryCount
            ))
        } else if let completedStep = Self.completedStep(from: oldStage, to: newStage) {
            analytics.track(.chewProfileSetupStepCompleted(
                source: source,
                step: completedStep,
                durationSec: elapsed(since: stageStartedAt)
            ))
        }

        if newStage != .signalIssue {
            lastActiveStage = newStage
        }
        stageStartedAt = now()
    }

    func complete() {
        guard !finished else { return }
        finished = true
        analytics.track(.chewProfileSetupCompleted(
            source: source,
            durationSec: elapsed(since: startedAt),
            retryCount: retryCount
        ))
    }

    func failSave() {
        guard !finished else { return }
        analytics.track(.chewProfileSetupFailed(
            source: source,
            step: .ready,
            reason: .profileSaveFailed,
            retryCount: retryCount
        ))
    }

    func dismiss(at stage: MeasurementOnboardingStage) {
        guard !finished else { return }
        finished = true
        let activeStage = stage == .signalIssue ? lastActiveStage : stage
        analytics.track(.chewProfileSetupDismissed(
            source: source,
            step: Self.analyticsStep(for: activeStage)
        ))
    }

    private func elapsed(since start: Date?) -> Int {
        guard let start else { return 0 }
        return max(0, Int(now().timeIntervalSince(start).rounded(.down)))
    }

    private static func completedStep(
        from oldStage: MeasurementOnboardingStage,
        to newStage: MeasurementOnboardingStage
    ) -> ChewProfileSetupStep? {
        switch (oldStage, newStage) {
        case (.connection, .baseline): .connection
        case (.baseline, .calibration): .restingSignal
        case (.calibration, .adjustment): .chewingSignal
        case (.adjustment, .ready): .verification
        default: nil
        }
    }

    private static func analyticsStep(for stage: MeasurementOnboardingStage) -> ChewProfileSetupStep {
        switch stage {
        case .intro: .intro
        case .connection: .connection
        case .baseline: .restingSignal
        case .calibration: .chewingSignal
        case .adjustment: .verification
        case .ready: .ready
        case .signalIssue: .intro
        }
    }

    private static func analyticsReason(
        for issue: MeasurementOnboardingIssue
    ) -> ChewProfileSetupFailureReason {
        switch issue {
        case .motionUnavailable: .motionUnavailable
        case .insufficientCalibration: .insufficientChewingSignal
        case .insufficientSeparation: .insufficientSignalSeparation
        case .adjustmentNeeded: .verificationOutOfRange
        case .sensor: .sensorError
        }
    }
}

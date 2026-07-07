import Foundation

struct MealSessionMeasurementContext: Equatable {
    let startedAt: Date
}

struct MealSessionPauseContext: Equatable {
    let startedAt: Date
    let pausedAt: Date
    let reason: MealSessionPauseReason
}

enum MealSessionPauseReason: Equatable {
    case call
}

struct MealSessionAnalysisContext: Equatable {
    let startedAt: Date
    let endedAt: Date
}

enum MealSessionPhase: Equatable {
    case idle
    case measuring(MealSessionMeasurementContext)
    case paused(MealSessionPauseContext)
    case confirmingShortStop(MealSessionMeasurementContext)
    case analyzing(MealSessionAnalysisContext)

    var isEating: Bool {
        switch self {
        case .measuring, .paused, .confirmingShortStop:
            true
        case .idle, .analyzing:
            false
        }
    }

    var startedAt: Date? {
        switch self {
        case .idle:
            nil
        case let .measuring(context):
            context.startedAt
        case let .paused(context):
            context.startedAt
        case let .confirmingShortStop(context):
            context.startedAt
        case let .analyzing(context):
            context.startedAt
        }
    }

    var isConfirmingShortStop: Bool {
        if case .confirmingShortStop = self { return true }
        return false
    }
}

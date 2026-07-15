import CoreMotion
import Foundation

protocol MealMotionServicing: AnyObject {
    var liveMotionUnavailableSource: IMUWaveformSource? { get }
    var isDeviceMotionAvailable: Bool { get }
    var authorizationStatus: CMAuthorizationStatus { get }

    func start(
        onSample: @escaping (HeadphoneMotionSample) -> Void,
        onError: @escaping (String) -> Void
    )
    func stop()
}

protocol MealAudioFeedbackServicing: AnyObject {
    var volume: Float { get set }

    func start()
    func stop()
    func playTone(for pace: ChewPaceSample)
}

protocol MealCallInterruptionMonitoring: AnyObject {
    var onCallStarted: (() -> Void)? { get set }
    var onCallEnded: (() -> Void)? { get set }

    func start()
    func stop()
}

protocol MealActivityControlling: AnyObject {
    func start(startedAt: Date)
    func setPaused(_ paused: Bool, callActive: Bool) async
    func end() async
}

extension MealActivityControlling {
    func setPaused(_ paused: Bool) async {
        await setPaused(paused, callActive: false)
    }
}

protocol MealInterruptionNotificationScheduling {
    func requestAuthorizationIfNeeded() async -> Bool
    func scheduleInterruptionPrompt() async
    func cancelInterruptionPrompt()
}

struct MealSessionRuntimeServices {
    let makeMotionService: () -> any MealMotionServicing
    let makeAudioFeedbackService: () -> any MealAudioFeedbackServicing
    let makeCallInterruptionMonitor: () -> any MealCallInterruptionMonitoring
    let makeActivityController: () -> any MealActivityControlling
    let makeAirPodsConnectionMonitor: () -> any AirPodsConnectionMonitoring
    let makeStartCountdownController: () -> StartCountdownController
    let notificationScheduler: any MealInterruptionNotificationScheduling
    let now: () -> Date

    static let live = MealSessionRuntimeServices(
        makeMotionService: { HeadphoneMotionService() },
        makeAudioFeedbackService: { BackgroundAudioKeepAlive() },
        makeCallInterruptionMonitor: { CallInterruptionMonitor() },
        makeActivityController: { MealActivityController() },
        makeAirPodsConnectionMonitor: { AirPodsConnectionMonitor() },
        makeStartCountdownController: { StartCountdownController() },
        notificationScheduler: LiveInterruptionNotifier(),
        now: Date.init
    )
}

extension HeadphoneMotionService: MealMotionServicing {
    var liveMotionUnavailableSource: IMUWaveformSource? {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        return nil
        #endif
    }
}

extension BackgroundAudioKeepAlive: MealAudioFeedbackServicing {}

extension CallInterruptionMonitor: MealCallInterruptionMonitoring {}

extension MealActivityController: MealActivityControlling {}

private struct LiveInterruptionNotifier: MealInterruptionNotificationScheduling {
    func requestAuthorizationIfNeeded() async -> Bool {
        await MealNotificationService.requestAuthorizationIfNeeded()
    }

    func scheduleInterruptionPrompt() async {
        await MealNotificationService.scheduleInterruptionPrompt()
    }

    func cancelInterruptionPrompt() {
        MealNotificationService.cancelInterruptionPrompt()
    }
}

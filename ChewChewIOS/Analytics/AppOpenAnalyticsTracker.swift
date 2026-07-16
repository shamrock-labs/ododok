import Foundation

enum AppLifecyclePhase {
    case active
    case inactive
    case background
}

struct AppOpenAnalyticsTracker {
    private var trackedColdStart = false
    private var enteredBackground = false

    mutating func transition(to phase: AppLifecyclePhase) -> AppOpenLaunchType? {
        switch phase {
        case .active:
            if !trackedColdStart {
                trackedColdStart = true
                enteredBackground = false
                return .coldStart
            }
            guard enteredBackground else { return nil }
            enteredBackground = false
            return .foreground
        case .background:
            enteredBackground = trackedColdStart
            return nil
        case .inactive:
            return nil
        }
    }

    mutating func event(
        for phase: AppLifecyclePhase,
        isLoggedIn: Bool,
        onboardingCompleted: Bool,
        chewProfileConfigured: Bool
    ) -> AnalyticsEvent? {
        guard let launchType = transition(to: phase) else { return nil }
        return .appOpened(
            launchType: launchType,
            authenticationState: isLoggedIn ? .loggedIn : .loggedOut,
            onboardingCompleted: onboardingCompleted,
            chewProfileConfigured: chewProfileConfigured
        )
    }
}

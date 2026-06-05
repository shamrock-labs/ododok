import Foundation
#if os(iOS) && !targetEnvironment(simulator)
import CallKit
#endif

/// 식사 세션 동안 전화 통화 시작을 관찰한다.
/// 오디오 인터럽트는 전화와 재난문자(시스템 경보)를 구분하지 못하므로, CallKit으로 활성 통화 유무를
/// 확인해 "이 인터럽트가 전화 때문인가"를 판별하는 용도다. `CXCallObserver`는 관찰 전용이라
/// 별도 엔타이틀먼트나 권한이 필요 없다.
///
/// 시뮬레이터엔 실제 통화가 없어 전체 노옵 — `onCallStarted`가 호출되지 않는다.
final class CallInterruptionMonitor: NSObject {

    /// 활성 통화가 새로 감지될 때 호출. `setDelegate` 큐(`.main`)에서 불린다.
    var onCallStarted: (() -> Void)?

    #if os(iOS) && !targetEnvironment(simulator)
    private let observer = CXCallObserver()
    private var hasActiveCall = false

    func start() {
        observer.setDelegate(self, queue: .main)
    }

    func stop() {
        observer.setDelegate(nil, queue: nil)
        hasActiveCall = false
    }
    #else
    func start() {}
    func stop() {}
    #endif
}

#if os(iOS) && !targetEnvironment(simulator)
extension CallInterruptionMonitor: CXCallObserverDelegate {
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        // 수신 벨이 울리는 시점부터 통화 종료 전까지를 "활성"으로 본다.
        let active = callObserver.calls.contains { !$0.hasEnded }
        let wasActive = hasActiveCall
        hasActiveCall = active
        if active && !wasActive {
            onCallStarted?()
        }
    }
}
#endif

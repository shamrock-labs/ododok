import Foundation

/// AirPods 자동 시작 전 3-2-1 카운트다운 타이머를 소유한다.
final class StartCountdownController {
    var onValueChange: ((Int?) -> Void)?

    private var timer: Timer?
    private(set) var value: Int?

    var isRunning: Bool {
        value != nil
    }

    static func nextCountdownValue(from value: Int) -> Int? {
        value > 1 ? value - 1 : nil
    }

    func begin(onFinished: @escaping () -> Void) {
        guard value == nil else { return }
        setValue(3)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let current = self.value else { return }
                let next = Self.nextCountdownValue(from: current)
                self.setValue(next)
                if next == nil {
                    self.cancel()
                    onFinished()
                }
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        setValue(nil)
    }

    private func setValue(_ value: Int?) {
        self.value = value
        onValueChange?(value)
    }

    deinit {
        timer?.invalidate()
    }
}

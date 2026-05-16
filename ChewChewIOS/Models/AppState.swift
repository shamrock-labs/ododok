import Foundation
import Observation

/// 앱의 글로벌 상태 + 식사 세션 관리.
///
/// 현재 chew 신호는 `startEating()` 호출 시 가짜 Timer가 0.85초마다 `chew()`를
/// 흉내냄. 추후 AirPods Pro 2의 `CMHeadphoneMotionManager`를 붙이게 되면
/// `startFakeChewLoop()` 대신 실제 IMU 신호 → chew 추정 알고리즘으로 갈아끼우면 됨.
@Observable
final class AppState {
    // MARK: - Persisted-ish state (현재는 인메모리)

    var chewCount: Int = 247
    var streak: Int = 7
    var points: Int = 1240
    var animKey: Int = 0
    var weeklyScores: [Int] = [72, 85, 68, 78, 82, 88, 41]
    var owned: Set<String> = ["hat-beanie", "gls-round"]
    var equipped: Equipped = .init(hat: "hat-beanie", glasses: nil, acc: nil)

    struct Equipped {
        var hat: String?
        var glasses: String?
        var acc: String?
    }

    // MARK: - Eating session

    /// 현재 식사 중인지 여부. 홈의 "식사 시작/종료" 버튼이 토글, 트래킹 탭이 관찰.
    var isEating: Bool = false

    /// 식사 시작 시각. 통계/지속시간 표시 등에 사용.
    @ObservationIgnored private(set) var eatingStartedAt: Date?

    /// 최근 60초 안의 chew 타임스탬프 (분당 저작 횟수 계산용).
    @ObservationIgnored private var chewTimestamps: [Date] = []

    /// 분당 저작 횟수. chew() 호출 시 갱신.
    var chewRatePerMinute: Int = 0

    @ObservationIgnored private var fakeChewTimer: Timer?
    @ObservationIgnored private var goalAlreadyHit = false

    // MARK: - Eating actions

    func startEating() {
        guard !isEating else { return }
        isEating = true
        eatingStartedAt = Date()
        startFakeChewLoop()
    }

    func stopEating() {
        guard isEating else { return }
        isEating = false
        eatingStartedAt = nil
        stopFakeChewLoop()
        chewTimestamps.removeAll()
        chewRatePerMinute = 0
    }

    func toggleEating() {
        isEating ? stopEating() : startEating()
    }

    // MARK: - Chew (한 입 = 한 번의 저작 신호)

    /// 한 번의 chew 이벤트. 추후 실제 IMU 감지기가 호출할 진입점.
    func chew() {
        chewCount += 1
        points += 1
        animKey &+= 1

        let now = Date()
        chewTimestamps = chewTimestamps.filter { now.timeIntervalSince($0) < 60 }
        chewTimestamps.append(now)
        chewRatePerMinute = chewTimestamps.count

        if chewCount >= Constants.dailyGoal && !goalAlreadyHit {
            goalAlreadyHit = true
            points += 200
        }
    }

    // MARK: - Reset

    func reset() {
        stopEating()
        chewCount = 247
        streak = 7
        points = 1240
        animKey = 0
        weeklyScores = [72, 85, 68, 78, 82, 88, 41]
        owned = ["hat-beanie", "gls-round"]
        equipped = .init(hat: "hat-beanie", glasses: nil, acc: nil)
        goalAlreadyHit = false
    }

    // MARK: - Shop

    @discardableResult
    func buy(_ item: ShopItem) -> Bool {
        guard points >= item.price else { return false }
        points -= item.price
        owned.insert(item.id)
        return true
    }

    @discardableResult
    func toggleEquip(_ item: ShopItem) -> Bool {
        let current = equippedID(for: item.type)
        let willEquip = current != item.id
        switch item.type {
        case .hat:     equipped.hat     = willEquip ? item.id : nil
        case .glasses: equipped.glasses = willEquip ? item.id : nil
        case .acc:     equipped.acc     = willEquip ? item.id : nil
        }
        return willEquip
    }

    func equippedID(for type: ShopItem.Kind) -> String? {
        switch type {
        case .hat:     equipped.hat
        case .glasses: equipped.glasses
        case .acc:     equipped.acc
        }
    }

    @discardableResult
    func consume(_ pack: AcornPack) -> Bool {
        guard points >= pack.price else { return false }
        points -= pack.price
        return true
    }

    // MARK: - Derived

    var status: MoodStatus { MoodStatus.from(count: chewCount) }

    var progress: Double {
        min(1.0, max(0.0, Double(chewCount) / Double(Constants.dailyGoal)))
    }

    // MARK: - Fake chew loop (백엔드 IMU 붙으면 이 함수만 교체)

    private func startFakeChewLoop() {
        stopFakeChewLoop()
        fakeChewTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: true) { [weak self] _ in
            self?.chew()
        }
    }

    private func stopFakeChewLoop() {
        fakeChewTimer?.invalidate()
        fakeChewTimer = nil
    }
}

import Foundation

/// PRD #8 도토리 리워드 정책. 적립 로직은 모두 이 ledger를 통과해야 idempotency와
/// 일일 상한이 보장된다.
///
/// 정책:
///   - **일일 출석 보너스 +2🌰**: foreground 진입 시 1회. `claimDailyAttendance` 호출.
///   - **세션 종료 적립 = `estimatedTotalChews × 0.05`**: `accrue(forSession:chewCount:)`
///     호출. 분석 5필드 nil인 세션은 0.
///   - **일일 상한 500🌰**: 같은 날 누적 적립이 500을 넘으면 이후 호출은 0 반환.
///   - **`idempotencyKey` 중복 방지**: 같은 key(예: 같은 sessionId)는 한 번만 적립.
///
/// 저장은 `UserDefaults`로 단순화 (앱 재시작 후에도 유지). 다른 디바이스 sync는
/// 익명 device id 정책상 보장 안 함. 서버 ledger 테이블로 옮기는 건 별도 PR.
@MainActor
enum RewardLedger {
    static let dailyAttendanceBonus: Int = 2
    static let chewMultiplier: Double = 0.05
    static let dailyCapacity: Int = 500

    private static let processedKeysKey = "ChewChewIOS.RewardLedger.processedKeys"
    private static let dailyAccrualKey = "ChewChewIOS.RewardLedger.dailyAccrual"

    /// foreground 진입 시 호출. 같은 날엔 처음 한 번만 적립.
    /// 반환값은 실제로 적립된 도토리 수(0이면 이미 받았거나 상한 도달).
    @discardableResult
    static func claimDailyAttendance(now: Date = .now) -> Int {
        let day = isoDay(now)
        return accrue(key: "attendance:\(day)", amount: dailyAttendanceBonus, day: day)
    }

    /// 식사 세션 종료 + INSERT 성공 시 호출. 같은 sessionId는 한 번만.
    /// `chewCount`가 nil이거나 0이면 0 반환.
    @discardableResult
    static func accrue(forSession sessionId: UUID, chewCount: Int?, now: Date = .now) -> Int {
        guard let chewCount, chewCount > 0 else { return 0 }
        let amount = max(1, Int((Double(chewCount) * chewMultiplier).rounded()))
        return accrue(key: "session:\(sessionId.uuidString.lowercased())", amount: amount, day: isoDay(now))
    }

    /// 테스트/리셋용 — `AppState.reset()` 또는 `clearPersistedSnapshot()`에서 호출 가능.
    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: processedKeysKey)
        UserDefaults.standard.removeObject(forKey: dailyAccrualKey)
    }

    // MARK: - Internals

    private static func accrue(key: String, amount: Int, day: String) -> Int {
        var processed = processedKeys
        if processed.contains(key) { return 0 }

        var daily = dailyAccrual
        let alreadyToday = daily[day] ?? 0
        let remaining = max(0, dailyCapacity - alreadyToday)
        let granted = min(amount, remaining)

        // 상한 도달이라도 key는 처리됨으로 마크 — 같은 key로 반복 호출되어도 매번
        // 재시도하지 않도록.
        processed.insert(key)
        processedKeys = processed

        if granted > 0 {
            daily[day] = alreadyToday + granted
            dailyAccrual = daily
        }
        return granted
    }

    private static var processedKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: processedKeysKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: processedKeysKey) }
    }

    private static var dailyAccrual: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: dailyAccrualKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: dailyAccrualKey) }
    }

    /// 로컬 시간대 기준 `yyyy-MM-dd` — 자정 기준 일 구분.
    private static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

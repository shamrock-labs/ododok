import Foundation

protocol HomeRepository {
    func fetchHome() async throws -> HomeStateDTO
    func earnAttendance(now: Date) async throws -> AttendanceResultDTO
    func fetchRewardHistory() async throws -> [RewardHistoryDTO]
}

enum AttendanceKey {
    /// 앱-열기 출석 멱등키 — REQ-08 형식(`app-open-<deviceId>-<yyyyMMdd Asia/Seoul>`).
    /// iOS가 트리거 시점에 키를 만들고, 서버가 이 키로 일 1회 적립을 판정한다.
    /// 서버(AttendanceService)가 같은 포맷으로 키를 유도하므로, 포맷 변경 시 양쪽을 함께 고쳐야
    /// 같은 날 두 키가 갈라져 이중 적립되는 일을 막는다.
    static func make(deviceId: String, now: Date = Date()) -> String {
        "app-open-\(deviceId)-\(formatter.string(from: now))"
    }

    /// DateFormatter의 포맷팅은 iOS 7+에서 thread-safe지만, 현재 호출 경로는 모두 MainActor다.
    /// 비-메인 호출자를 추가한다면 그 점을 인지하고 쓸 것.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

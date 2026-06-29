import Foundation

/// ko_KR `DateFormatter`를 포맷 문자열별로 캐싱한다.
/// 뷰 body·computed property에서 호출당 `DateFormatter()`를 새로 만들던 비용(스크롤 시
/// 셀마다 반복 할당)을 없앤다. 전부 메인 스레드(SwiftUI)에서 호출되고, 캐시 dict만 락으로 보호한다.
enum KoDate {
    private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    /// `date`를 ko_KR + `format`으로 문자열화. 포맷터는 재사용된다.
    /// `DateFormatter.string(from:)`은 스레드 불안전이라 캐시 조회·포매팅을 모두 락 안에서
    /// 수행한다(전제를 호출자에 의존하지 않고 코드로 못박음). 호출은 거의 메인 스레드라 경합 미미.
    static func string(_ date: Date, _ format: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = cache[format] {
            formatter = cached
        } else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ko_KR")
            f.dateFormat = format
            cache[format] = f
            formatter = f
        }
        return formatter.string(from: date)
    }

    /// 사용자에게 보여줄 시각 — 12시간제 + 오전/오후(영점 패딩). 서버에서 받은 시간을 화면에
    /// 표시할 땐 항상 이 함수를 쓴다(표기 일관성의 단일 소스). 예: 17:28 → "오후 05:28".
    static func clockTime(_ date: Date) -> String {
        string(date, "a hh:mm")
    }

    /// 날짜 + 시각 한 줄. 예: "6월 28일 일요일 · 오후 05:28". 시각부는 `clockTime`을 재사용.
    static func dateWithClock(_ date: Date, dateFormat: String = "M월 d일 EEEE") -> String {
        "\(string(date, dateFormat)) · \(clockTime(date))"
    }
}

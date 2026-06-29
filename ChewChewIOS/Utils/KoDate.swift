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
}

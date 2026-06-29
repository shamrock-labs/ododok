import Foundation

/// ko_KR `DateFormatter`를 포맷 문자열별로 캐싱한다.
/// 뷰 body·computed property에서 호출당 `DateFormatter()`를 새로 만들던 비용(스크롤 시
/// 셀마다 반복 할당)을 없앤다. 전부 메인 스레드(SwiftUI)에서 호출되고, 캐시 dict만 락으로 보호한다.
enum KoDate {
    private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    static func formatter(_ format: String) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[format] { return cached }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        cache[format] = f
        return f
    }

    /// `date`를 ko_KR + `format`으로 문자열화. 포맷터는 재사용된다.
    static func string(_ date: Date, _ format: String) -> String {
        formatter(format).string(from: date)
    }
}

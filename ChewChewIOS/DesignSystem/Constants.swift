import Foundation

enum Constants {
    static let dailyGoal: Int = 600
    static let pointsPerChew: Double = 0.15
}

extension Int {
    /// 한국어 천 단위 구분자가 들어간 문자열. e.g. 1240 → "1,240"
    var koLocale: String {
        Self.koFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    private static let koFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()
}

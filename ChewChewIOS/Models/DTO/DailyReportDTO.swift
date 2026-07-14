import Foundation

/// `GET /v1/me/reports/daily` 응답. 집계값과 끼니 수는 서버 저장 리포트가 정본이다.
struct DailyReportDTO: Codable, Equatable {
    var date: String
    var timezone: String
    var mealCount: Int
    var totalEatingSeconds: Double
    var totalChews: Int
    var avgChewRatePerMin: Double?
    var avgChewingFraction: Double?
    var avgTotalScore: Double?
    var meals: [DailyReportMealDTO]
    var vsYesterday: DailyReportYesterdayDTO?
}

struct DailyReportYesterdayDTO: Codable, Equatable {
    var mealCountDelta: Int?
    var avgChewRatePerMinDelta: Double?
    var totalEatingSecondsDelta: Double?
}

struct DailyReportMealDTO: Codable, Equatable {
    var sessionId: UUID
    var slot: String
    var startedAt: Date
    var endedAt: Date
    var durationSec: Double
    var totalChews: Int?
    var chewRatePerMin: Double?
    var chewingFraction: Double?
    var paceBadge: String?
    var mealReport: MealReportDTO

    /// 단건 상세 화면은 세션 DTO를 입력으로 받으므로, daily 응답의 저장 리포트만으로
    /// 읽기 전용 세션을 구성한다. raw 분석값을 점수·표시에 다시 사용하지 않는다.
    var session: ChewingSessionDTO {
        ChewingSessionDTO(
            id: sessionId,
            deviceId: "",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSec: durationSec,
            sensorLocation: "server-report",
            sampleCount: 0,
            sampleRateHz: 0,
            storagePath: nil,
            appVersion: nil,
            chewingSeconds: nil,
            restSeconds: nil,
            chewingFraction: nil,
            estimatedTotalChews: nil,
            modelVersion: mealReport.analysisModelVersion,
            mealReport: mealReport
        )
    }
}

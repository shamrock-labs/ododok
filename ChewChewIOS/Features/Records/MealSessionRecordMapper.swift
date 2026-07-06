import Foundation

enum MealSessionRecordMapper {
    static func map(_ dto: ChewingSessionDTO) -> MealSessionRecord? {
        guard let reportCard = ReportCardModel.from(dto) else { return nil }
        return MealSessionRecord(
            id: dto.id,
            startedAt: dto.startedAt,
            durationSec: dto.durationSec,
            reportCard: reportCard
        )
    }

    static func isReportable(_ dto: ChewingSessionDTO) -> Bool {
        guard dto.durationSec >= 60 else { return false }
        return SessionScore.compute(dto) != nil
    }
}

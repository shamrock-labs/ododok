import Foundation

/// 한 끼 식사 동안 받은 AirPods IMU 샘플을 메모리에 누적해 두었다가 식사 종료 시
/// gzip CSV로 봉인하는 단순 버퍼.
///
/// 메모리 부담: 50Hz × 6채널 × 8byte ≈ 분당 18KB(double 기준). 한 끼 30분이라도
/// 4MB 정도라 디스크 dump 없이 안전. raw IMU는 DB row로 풀지 않고 봉인된 CSV를
/// Storage에 그대로 올린다(설계 문서 §2).
final class IMUSessionRecorder {
    let sessionId: UUID
    let startedAt: Date

    private(set) var rows: [IMURow] = []
    private(set) var sensorLocation: String = "default"

    init(sessionId: UUID = UUID(), startedAt: Date = Date()) {
        self.sessionId = sessionId
        self.startedAt = startedAt
    }

    func append(_ row: IMURow) {
        rows.append(row)
    }

    /// 한 세션에 두 가지 위치(left/right)가 섞일 일은 거의 없지만 안전하게 마지막 값으로 덮어씀.
    func updateSensorLocation(_ location: String) {
        sensorLocation = location
    }

    /// 봉인 — CSV 직렬화 후 gzip 압축. 호출 후 인스턴스는 폐기 대상.
    /// 압축 실패는 Storage 경로 컨벤션(`.csv.gz`)이 깨지는 일이므로 throws로 전파한다.
    func finalize(endedAt: Date) throws -> Output {
        var csv = IMURow.csvHeader
        csv.reserveCapacity(rows.count * 80 + IMURow.csvHeader.count + 16)
        for row in rows {
            csv.append("\n")
            csv.append(row.csvLine())
        }
        csv.append("\n")

        let csvData = Data(csv.utf8)
        guard let payload = GZip.compress(csvData) else {
            throw FinalizeError.compressionFailed
        }

        return Output(
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSec: endedAt.timeIntervalSince(startedAt),
            sampleCount: rows.count,
            sensorLocation: sensorLocation,
            gzippedCSV: payload
        )
    }

    struct Output {
        let sessionId: UUID
        let startedAt: Date
        let endedAt: Date
        let durationSec: Double
        let sampleCount: Int
        let sensorLocation: String
        let gzippedCSV: Data
    }

    enum FinalizeError: Error {
        case compressionFailed
    }
}

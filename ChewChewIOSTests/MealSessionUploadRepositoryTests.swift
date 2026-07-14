import XCTest
@testable import ChewChewIOS

final class MealSessionUploadRepositoryTests: XCTestCase {
    func testUploadReturnsDecodedServerSessionWhenBothReportsAreEqual() async throws {
        let sessionId = UUID()
        let report = makeReport(status: .generated, sessionId: sessionId)
        let response = try makeNetworkResponse(
            sessionId: sessionId,
            topLevelReport: report,
            embeddedReport: report
        )
        let remoteStore = MealSessionRepositoryRemoteStore(response: response)
        let repository = RemoteStoreMealSessionUploadRepository(
            remoteStore: remoteStore,
            deviceIdProvider: { "test-device" }
        )

        let upload = try await repository.uploadSession(
            output: makeOutput(sessionId: sessionId),
            stats: nil,
            appVersion: "test-version"
        )

        XCTAssertEqual(upload.session, response.chewingSession)
        XCTAssertEqual(upload.result.mealReport, report)
        XCTAssertEqual(upload.result.chewingSession.mealReport, report)
    }

    func testUploadRejectsTopLevelOnlyReport() async throws {
        let sessionId = UUID()
        let report = makeReport(status: .generated, sessionId: sessionId)
        let response = try makeNetworkResponse(
            sessionId: sessionId,
            topLevelReport: report,
            embeddedReport: nil
        )

        await assertMalformed(response)
    }

    func testUploadRejectsEmbeddedOnlyReport() async throws {
        let sessionId = UUID()
        let report = makeReport(status: .generated, sessionId: sessionId)
        let response = try makeNetworkResponse(
            sessionId: sessionId,
            topLevelReport: nil,
            embeddedReport: report
        )

        await assertMalformed(response)
    }

    func testUploadRejectsBothReportsMissing() async throws {
        let response = try makeNetworkResponse(
            sessionId: UUID(),
            topLevelReport: nil,
            embeddedReport: nil
        )

        await assertMalformed(response)
    }

    func testUploadRejectsContradictoryReports() async throws {
        let sessionId = UUID()
        let response = try makeNetworkResponse(
            sessionId: sessionId,
            topLevelReport: makeReport(status: .generated, sessionId: sessionId),
            embeddedReport: makeReport(
                status: .unreportable,
                sessionId: sessionId,
                reason: .analysisMissing
            )
        )

        await assertMalformed(response)
    }

    private func assertMalformed(
        _ response: CreateSessionResultDTO,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let repository = RemoteStoreMealSessionUploadRepository(
            remoteStore: MealSessionRepositoryRemoteStore(response: response),
            deviceIdProvider: { "test-device" }
        )

        do {
            _ = try await repository.uploadSession(
                output: makeOutput(sessionId: response.chewingSession.id),
                stats: nil,
                appVersion: nil
            )
            XCTFail("Expected malformed meal-report response", file: file, line: line)
        } catch RemoteStoreError.malformed(let message) {
            XCTAssertTrue(message.contains("mealReport"), file: file, line: line)
        } catch {
            XCTFail("Expected malformed, got \(error)", file: file, line: line)
        }
    }

    private func makeNetworkResponse(
        sessionId: UUID,
        topLevelReport: MealReportDTO?,
        embeddedReport: MealReportDTO?
    ) throws -> CreateSessionResultDTO {
        let placeholder = makeReport(status: .generated, sessionId: sessionId)
        let valid = CreateSessionResultDTO(
            chewingSession: makeSession(id: sessionId, mealReport: placeholder),
            mealReport: placeholder,
            chewingSessionAccepted: true,
            rewardEligible: true,
            ineligibleReason: nil,
            reward: SessionRewardDTO(grantedPoints: 3, capped: false, idempotentReplay: false),
            streak: SessionStreakDTO(current: 1, event: "FIRST_DAY", freezeInventory: 0),
            today: SessionTodayDTO(completed: true),
            userStats: .empty(deviceId: "test-device")
        )
        let encoder = JSONEncoder()
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(valid)) as? [String: Any]
        )

        if let topLevelReport {
            json["mealReport"] = try reportJSONObject(topLevelReport, encoder: encoder)
        } else {
            json.removeValue(forKey: "mealReport")
        }

        var sessionJSON = try XCTUnwrap(json["chewingSession"] as? [String: Any])
        if let embeddedReport {
            sessionJSON["mealReport"] = try reportJSONObject(embeddedReport, encoder: encoder)
        } else {
            sessionJSON.removeValue(forKey: "mealReport")
        }
        json["chewingSession"] = sessionJSON

        return try JSONDecoder().decode(
            CreateSessionResultDTO.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
    }

    private func reportJSONObject(
        _ report: MealReportDTO,
        encoder: JSONEncoder
    ) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(report)) as? [String: Any]
        )
    }

    private func makeReport(
        status: MealReportStatusDTO,
        sessionId: UUID,
        reason: MealReportReasonDTO? = nil
    ) -> MealReportDTO {
        MealReportDTO(status: status, reason: reason, sessionId: sessionId)
    }

    private func makeSession(id: UUID, mealReport: MealReportDTO?) -> ChewingSessionDTO {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        return ChewingSessionDTO(
            id: id,
            deviceId: "test-device",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(180),
            durationSec: 180,
            sensorLocation: "headphone_left",
            sampleCount: 9_000,
            sampleRateHz: 50,
            storagePath: "imu/\(id).csv",
            appVersion: "test-version",
            chewingSeconds: 90,
            restSeconds: 90,
            chewingFraction: 0.5,
            estimatedTotalChews: 180,
            modelVersion: "test-model",
            mealReport: mealReport
        )
    }

    private func makeOutput(sessionId: UUID) -> IMUSessionRecorder.Output {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        return IMUSessionRecorder.Output(
            sessionId: sessionId,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(180),
            durationSec: 180,
            sampleCount: 9_000,
            sensorLocation: "headphone_left",
            csvData: Data("csv".utf8),
            interruptionGaps: []
        )
    }
}

private final class MealSessionRepositoryRemoteStore: RemoteStore {
    let response: CreateSessionResultDTO

    init(response: CreateSessionResultDTO) {
        self.response = response
    }

    func upsertProfile(_ profile: ProfileDTO) async throws {}
    func fetchProfile() async throws -> ProfileDTO? { nil }
    func fetchUserStats() async throws -> UserStatsDTO? { nil }
    func deleteUserData() async throws {}
    func createChewingSession(_ session: ChewingSessionDTO) async throws -> CreateSessionResultDTO { response }
    func fetchHome(deviceId: String) async throws -> HomeStateDTO { .empty(deviceId: deviceId) }
    func earnAttendance(deviceId: String, idempotencyKey: String) async throws -> AttendanceResultDTO {
        AttendanceResultDTO(
            grantedPoints: 0,
            capped: false,
            idempotentReplay: false,
            userStats: .empty(deviceId: deviceId)
        )
    }
    func fetchChewingSessions(
        deviceId: String,
        since: Date,
        until: Date?
    ) async throws -> [ChewingSessionDTO] { [] }
    func deleteChewingSession(id: UUID, deviceId: String) async throws {}
    func deleteAllChewingSessions(deviceId: String) async throws {}
    func uploadIMUCSV(sessionId: UUID, deviceId: String, csvData: Data) async throws -> String {
        "imu/\(sessionId).csv"
    }
}

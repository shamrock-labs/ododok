import XCTest
@testable import ChewChewIOS

final class MealReportDTOTests: XCTestCase {
    private let sessionId = UUID(uuidString: "7ad46ae5-3521-45b5-950f-97d433081737")!

    func testGeneratedReportDecodesExactServerSnapshotIncludingExplicitNullRate() throws {
        let report = try JSONDecoder().decode(MealReportDTO.self, from: Data(generatedReportJSON.utf8))

        XCTAssertEqual(report.status, .generated)
        XCTAssertNil(report.reason)
        XCTAssertEqual(report.sessionId, sessionId)
        XCTAssertEqual(report.scorePolicyVersion, "legacy-ios-v1")
        XCTAssertEqual(report.analysisModelVersion, "dsp-chewcounter-1")
        XCTAssertEqual(report.totalScore, 71)
        XCTAssertEqual(report.axisScores?.chewingRate, 0)
        XCTAssertEqual(report.axisScores?.chewingTimeRatio, 100)
        XCTAssertEqual(report.axisScores?.totalChewCount, 100)
        XCTAssertEqual(report.axisScores?.mealDuration, 85)
        XCTAssertNil(report.metrics?.chewingRatePerMin)
        XCTAssertEqual(report.metrics?.legacyMealRatePerMin ?? 0, 43.57583230579531, accuracy: 0.000_001)
        XCTAssertEqual(report.metrics?.chewingTimeRatio, 0.97)
        XCTAssertEqual(report.metrics?.totalChewCount, 589)
        XCTAssertEqual(report.metrics?.mealDurationSec, 811)
        XCTAssertEqual(report.grade, .soso)
        XCTAssertEqual(report.recommendedBaseline?.chewingRatePerMin.target, 28)
        XCTAssertEqual(report.recommendedBaseline?.chewingTimeRatio, 0.6)
        XCTAssertEqual(report.recommendedBaseline?.totalChewCount, 300)
        XCTAssertEqual(report.recommendedBaseline?.mealDurationSec, 720)
    }

    func testAllUnreportableReasonsDecodeFromServerTags() throws {
        let cases: [(String, MealReportReasonDTO)] = [
            ("SESSION_TOO_SHORT", .sessionTooShort),
            ("ANALYSIS_MISSING", .analysisMissing),
            ("INVALID_ANALYSIS_INPUT", .invalidAnalysisInput),
        ]

        for (rawReason, expectedReason) in cases {
            let json = #"{"status":"UNREPORTABLE","reason":"\#(rawReason)"}"#
            let report = try JSONDecoder().decode(MealReportDTO.self, from: Data(json.utf8))

            XCTAssertEqual(report.status, .unreportable)
            XCTAssertEqual(report.reason, expectedReason)
            XCTAssertNil(report.totalScore)
        }
    }

    func testSessionResponseDecodesEmbeddedMealReport() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(ChewingSessionDTO.self, from: Data(sessionJSON.utf8))

        XCTAssertEqual(session.mealReport?.status, .generated)
        XCTAssertEqual(session.mealReport?.totalScore, 71)
        XCTAssertNil(session.mealReport?.metrics?.chewingRatePerMin)
    }

    func testSessionUploadEncodingOmitsServerOwnedMealReport() throws {
        let report = try JSONDecoder().decode(MealReportDTO.self, from: Data(generatedReportJSON.utf8))
        let session = ChewingSessionDTO(
            id: sessionId,
            deviceId: "ios-device",
            startedAt: Date(timeIntervalSince1970: 1_752_220_800),
            endedAt: Date(timeIntervalSince1970: 1_752_221_611),
            durationSec: 811,
            sensorLocation: "headphoneLeft",
            sampleCount: 40_550,
            sampleRateHz: 50,
            storagePath: nil,
            appVersion: "1.0.0",
            chewingSeconds: 787,
            restSeconds: 24,
            chewingFraction: 0.97,
            estimatedTotalChews: 589,
            modelVersion: "dsp-chewcounter-1",
            chewingTimeline: "1110",
            mealReport: report
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any]
        )
        XCTAssertNil(object["mealReport"])
    }

    func testCreateResultCarriesTopLevelAndEmbeddedMealReport() throws {
        let report = try JSONDecoder().decode(MealReportDTO.self, from: Data(generatedReportJSON.utf8))
        let session = ChewingSessionDTO(
            id: sessionId,
            deviceId: "ios-device",
            startedAt: .distantPast,
            endedAt: .distantFuture,
            durationSec: 811,
            sensorLocation: "headphoneLeft",
            sampleCount: 40_550,
            sampleRateHz: 50,
            storagePath: nil,
            appVersion: nil,
            chewingSeconds: 787,
            restSeconds: 24,
            chewingFraction: 0.97,
            estimatedTotalChews: 589,
            modelVersion: "dsp-chewcounter-1",
            mealReport: report
        )
        let result = CreateSessionResultDTO(
            chewingSession: session,
            mealReport: report,
            chewingSessionAccepted: true,
            rewardEligible: true,
            ineligibleReason: nil,
            reward: SessionRewardDTO(grantedPoints: 10, capped: false, idempotentReplay: false),
            streak: SessionStreakDTO(current: 1, event: "FIRST_DAY", freezeInventory: 0),
            today: SessionTodayDTO(completed: true),
            userStats: .empty(deviceId: "ios-device")
        )

        XCTAssertEqual(result.mealReport, report)
        XCTAssertEqual(result.chewingSession.mealReport, report)
    }

    private var generatedReportJSON: String {
        """
        {
          "status": "GENERATED",
          "sessionId": "\(sessionId.uuidString)",
          "scorePolicyVersion": "legacy-ios-v1",
          "analysisModelVersion": "dsp-chewcounter-1",
          "totalScore": 71,
          "axisScores": {
            "chewingRate": 0,
            "chewingTimeRatio": 100,
            "totalChewCount": 100,
            "mealDuration": 85
          },
          "metrics": {
            "chewingRatePerMin": null,
            "legacyMealRatePerMin": 43.57583230579531,
            "chewingTimeRatio": 0.97,
            "totalChewCount": 589,
            "mealDurationSec": 811.0
          },
          "grade": "soso",
          "recommendedBaseline": {
            "chewingRatePerMin": {"target": 28.0},
            "chewingTimeRatio": 0.6,
            "totalChewCount": 300,
            "mealDurationSec": 720.0
          }
        }
        """
    }

    private var sessionJSON: String {
        """
        {
          "id": "\(sessionId.uuidString)",
          "deviceId": "ios-device",
          "startedAt": "2025-07-11T08:00:00Z",
          "endedAt": "2025-07-11T08:13:31Z",
          "durationSec": 811.0,
          "sensorLocation": "headphoneLeft",
          "sampleCount": 40550,
          "sampleRateHz": 50,
          "chewingSeconds": 787.0,
          "restSeconds": 24.0,
          "chewingFraction": 0.97,
          "estimatedTotalChews": 589,
          "modelVersion": "dsp-chewcounter-1",
          "mealReport": \(generatedReportJSON)
        }
        """
    }
}

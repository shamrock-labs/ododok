import XCTest
@testable import ChewChewIOS

final class SpringRemoteStoreDailyReportTests: XCTestCase {
    override func tearDown() {
        DailyReportMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchDailyReportUsesDateQueryAndDecodesStoredReports() async throws {
        let sessionId = UUID()
        DailyReportMockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/me/reports/daily")
            XCTAssertEqual(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "date" })?.value,
                "2026-07-15"
            )
            let body = """
            {
              "code": 0,
              "message": "ok",
              "result": {
                "date": "2026-07-15",
                "timezone": "Asia/Seoul",
                "mealCount": 1,
                "totalEatingSeconds": 811.0,
                "totalChews": 589,
                "avgChewRatePerMin": 43.58,
                "avgChewingFraction": 0.97,
                "avgTotalScore": 71.0,
                "meals": [{
                  "sessionId": "\(sessionId.uuidString)",
                  "slot": "LUNCH",
                  "startedAt": "2026-07-15T03:00:00Z",
                  "endedAt": "2026-07-15T03:13:31Z",
                  "durationSec": 811.0,
                  "totalChews": 589,
                  "chewRatePerMin": 43.58,
                  "chewingFraction": 0.97,
                  "paceBadge": "RECOMMENDED",
                  "mealReport": {
                    "status": "GENERATED",
                    "sessionId": "\(sessionId.uuidString)",
                    "scorePolicyVersion": "legacy-ios-v1",
                    "analysisModelVersion": "server",
                    "totalScore": 71,
                    "axisScores": {"chewingRate": 0, "chewingTimeRatio": 100, "totalChewCount": 100, "mealDuration": 85},
                    "metrics": {"legacyMealRatePerMin": 43.58, "chewingTimeRatio": 0.97, "totalChewCount": 589, "mealDurationSec": 811.0},
                    "grade": "soso",
                    "recommendedBaseline": {
                      "chewingRatePerMin": {"target": 28},
                      "chewingTimeRatio": 0.5,
                      "totalChewCount": 200,
                      "mealDurationSec": 720
                    }
                  }
                }],
                "vsYesterday": null
              }
            }
            """
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DailyReportMockURLProtocol.self]
        let store = SpringRemoteStore(
            config: SpringConfig(baseURL: URL(string: "https://example.test")!),
            session: URLSession(configuration: configuration)
        )

        let report = try await store.fetchDailyReport(date: "2026-07-15")

        XCTAssertEqual(report.mealCount, 1)
        XCTAssertEqual(report.avgTotalScore, 71)
        XCTAssertEqual(report.meals.first?.mealReport.sessionId, sessionId)
    }

    func testFetchDailyReportRejectsResponseForDifferentRequestedDate() async throws {
        stubDailyReport(result: emptyReportJSON(date: "2026-07-14"))
        let store = makeStore()

        do {
            _ = try await store.fetchDailyReport(date: "2026-07-15")
            XCTFail("Expected malformed daily report")
        } catch RemoteStoreError.malformed(let message) {
            XCTAssertTrue(message.contains("date"))
        }
    }

    func testFetchDailyReportRejectsInconsistentAggregateMealCount() async throws {
        stubDailyReport(result: emptyReportJSON(date: "2026-07-15", mealCount: 1))
        let store = makeStore()

        do {
            _ = try await store.fetchDailyReport(date: "2026-07-15")
            XCTFail("Expected malformed daily report")
        } catch RemoteStoreError.malformed(let message) {
            XCTAssertTrue(message.contains("aggregate"))
        }
    }

    func testFetchDailyReportRejectsInvalidEmptyDayAggregates() async throws {
        stubDailyReport(result: emptyReportJSON(
            date: "2026-07-15",
            totalEatingSeconds: -1,
            totalChews: -1,
            avgTotalScore: 101
        ))
        let store = makeStore()

        do {
            _ = try await store.fetchDailyReport(date: "2026-07-15")
            XCTFail("Expected malformed daily report")
        } catch RemoteStoreError.malformed(let message) {
            XCTAssertTrue(message.contains("aggregate"))
        }
    }

    func testIOSCIExecutesUnitTests() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/ios-ci.yml"))

        XCTAssertTrue(workflow.contains("-scheme ChewChewIOSTests"))
        XCTAssertTrue(workflow.contains("-only-testing:ChewChewIOSTests"))
        XCTAssertTrue(workflow.contains(" test"))
        XCTAssertTrue(workflow.contains("platform=iOS Simulator,name=iPhone"))
    }

    private func makeStore() -> SpringRemoteStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DailyReportMockURLProtocol.self]
        return SpringRemoteStore(
            config: SpringConfig(baseURL: URL(string: "https://example.test")!),
            session: URLSession(configuration: configuration)
        )
    }

    private func stubDailyReport(result: String) {
        DailyReportMockURLProtocol.handler = { request in
            let body = """
            {"code":0,"message":"ok","result":\(result)}
            """
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
    }

    private func emptyReportJSON(
        date: String,
        mealCount: Int = 0,
        totalEatingSeconds: Double = 0,
        totalChews: Int = 0,
        avgTotalScore: Double? = nil
    ) -> String {
        let score = avgTotalScore.map { String($0) } ?? "null"
        return """
        {
          "date":"\(date)",
          "timezone":"Asia/Seoul",
          "mealCount":\(mealCount),
          "totalEatingSeconds":\(totalEatingSeconds),
          "totalChews":\(totalChews),
          "avgChewRatePerMin":null,
          "avgChewingFraction":null,
          "avgTotalScore":\(score),
          "meals":[],
          "vsYesterday":null
        }
        """
    }
}

private final class DailyReportMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

import XCTest
@testable import ChewChewIOS

// Attendance recovery request coverage intentionally shares the existing remote-store fixture.
// swiftlint:disable:next type_body_length
final class SpringRemoteStoreAttendanceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        TokenManager.clear()
        super.tearDown()
    }

    func testAttendanceStatusDTO_decodesRecoveryStatusAndMissedDates() throws {
        let dto = try JSONDecoder().decode(
            AttendanceStatusDTO.self,
            from: Data(
                #"""
                {
                  "asOf": "2026-07-16",
                  "status": "RECOVERY_AVAILABLE",
                  "missedDates": ["2026-07-14", "2026-07-15"],
                  "requiredFreezes": 2,
                  "freezeInventory": 2
                }
                """#.utf8
            )
        )

        XCTAssertEqual(dto.status, .recoveryAvailable)
        XCTAssertEqual(dto.missedDates, ["2026-07-14", "2026-07-15"])
        XCTAssertEqual(dto.requiredFreezes, 2)
    }

    func testFetchAttendanceStatus_sendsExpectedRequestAndDecodesResult() async throws {
        let store = makeStore()
        var capturedRequest: URLRequest?

        MockURLProtocol.handler = { request in
            capturedRequest = request
            return (
                try Self.response(
                    for: request,
                    statusCode: 200,
                    headerFields: ["Content-Type": "application/json"]
                ),
                Data(
                    #"""
                    {
                      "code": 1000,
                      "message": "요청에 성공하였습니다.",
                      "result": {
                        "asOf": "2026-07-16",
                        "status": "RECOVERY_AVAILABLE",
                        "missedDates": ["2026-07-14", "2026-07-15"],
                        "requiredFreezes": 2,
                        "freezeInventory": 2
                      }
                    }
                    """#.utf8
                )
            )
        }

        let result = try await store.fetchAttendanceStatus()

        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "http://localhost:8080/v1/me/attendance/status")
        XCTAssertEqual(result.status, .recoveryAvailable)
        XCTAssertEqual(result.requiredFreezes, 2)
    }

    func testEarnAttendance_sendsExpectedRequestAndDecodesResult() async throws {
        let store = makeStore()
        var capturedRequest: URLRequest?

        MockURLProtocol.handler = { request in
            capturedRequest = request
            let body = try Self.bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/me/attendance")
            // `/v1/me/*`는 JWT(user_id)로만 스코프 — device 헤더는 더 이상 보내지 않는다.
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Device-Id"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(json?["idempotencyKey"] as? String, "app-open-device-1-20260612")
            XCTAssertEqual(json?["freezeDecision"] as? String, "USE")
            XCTAssertEqual(json?["expectedMissedDays"] as? Int, 2)

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Self.successBody
            )
        }

        let result = try await store.earnAttendance(
            deviceId: "device-1",
            idempotencyKey: "app-open-device-1-20260612",
            decision: .use,
            expectedMissedDays: 2
        )

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "http://localhost:8080/v1/me/attendance")
        XCTAssertEqual(result.grantedPoints, 10)
        XCTAssertFalse(result.capped)
        XCTAssertFalse(result.idempotentReplay)
        XCTAssertEqual(result.userStats.deviceId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(result.userStats.userId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(result.userStats.points, 10)
        XCTAssertEqual(result.streak.current, 8)
        XCTAssertEqual(result.streak.freezeConsumed, 1)
        XCTAssertEqual(result.streak.freezeGranted, 1)
    }

    func testEarnAttendance_skipOmitsExpectedMissedDays() async throws {
        let store = makeStore()

        MockURLProtocol.handler = { request in
            let body = try Self.bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

            XCTAssertEqual(json?["freezeDecision"] as? String, "SKIP")
            XCTAssertNil(json?["expectedMissedDays"])

            return (
                try Self.response(
                    for: request,
                    statusCode: 200,
                    headerFields: ["Content-Type": "application/json"]
                ),
                Self.successBody
            )
        }

        _ = try await store.earnAttendance(
            deviceId: "device-1",
            idempotencyKey: "app-open-device-1-20260612",
            decision: .skip,
            expectedMissedDays: 2
        )
    }

    func testEarnAttendance_useWithoutExpectedMissedDaysFailsBeforeSendingRequest() async {
        let store = makeStore()
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            return (
                try Self.response(for: request, statusCode: 200),
                Self.successBody
            )
        }

        do {
            _ = try await store.earnAttendance(
                deviceId: "device-1",
                idempotencyKey: "app-open-device-1-20260612",
                decision: .use,
                expectedMissedDays: nil
            )
            XCTFail("Expected invalid attendance request")
        } catch {
            XCTAssertEqual(requestCount, 0)
        }
    }

    func testFetchStreakDetail_sendsExpectedRequestAndDecodesDays() async throws {
        let store = makeStore()
        var capturedRequest: URLRequest?
        MockURLProtocol.handler = { request in
            capturedRequest = request
            return (
                try Self.response(
                    for: request,
                    statusCode: 200,
                    headerFields: ["Content-Type": "application/json"]
                ),
                Data(
                    """
                    {
                      "code": 1000,
                      "message": "요청에 성공하였습니다.",
                      "result": {
                        "asOf": "2026-07-15",
                        "current": 8,
                        "longest": 18,
                        "startedOn": "2026-07-08",
                        "freezeInventory": 1,
                        "days": [
                          {"date": "2026-07-14", "state": "ATTENDED"},
                          {"date": "2026-07-15", "state": "FROZEN"}
                        ]
                      }
                    }
                    """.utf8
                )
            )
        }

        let result = try await store.fetchStreakDetail()

        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "http://localhost:8080/v1/me/streak")
        XCTAssertEqual(result.asOf, "2026-07-15")
        XCTAssertEqual(result.current, 8)
        XCTAssertEqual(result.days.map(\.state), [.attended, .frozen])
    }

    func testEarnAttendance_decodesStaleRecoveryErrorCode() async throws {
        let store = makeStore()
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!,
                Data(#"{"code":4014,"message":"출석 복구 상태가 변경되었습니다."}"#.utf8)
            )
        }

        do {
            _ = try await store.earnAttendance(deviceId: " ", idempotencyKey: "key")
            XCTFail("Expected RemoteStoreError.server")
        } catch let error as RemoteStoreError {
            guard case .server(let status, let code, let message) = error else {
                return XCTFail("Expected server error, got \(error)")
            }
            XCTAssertEqual(status, 409)
            XCTAssertEqual(code, 4014)
            XCTAssertEqual(message, "출석 복구 상태가 변경되었습니다.")
        }
    }

    func testEarnAttendanceThrowsAuthExpiredWhenRefreshFails() async throws {
        let tokenStore = InMemoryAuthTokenStore(
            accessToken: "expired-access",
            refreshToken: "expired-refresh"
        )
        let store = makeStore(tokenStore: tokenStore)

        MockURLProtocol.handler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data(#"{"code":5000,"message":"인증이 필요합니다."}"#.utf8)
            )
        }

        do {
            _ = try await store.earnAttendance(deviceId: "device-1", idempotencyKey: "key")
            XCTFail("Expected RemoteStoreError.authExpired")
        } catch let error as RemoteStoreError {
            guard case .authExpired = error else {
                return XCTFail("Expected authExpired, got \(error)")
            }
        }

        XCTAssertNil(tokenStore.accessToken)
        XCTAssertNil(tokenStore.refreshToken)
    }

    /// refresh는 성공했지만 재발급 후 재시도한 요청이 다시 401이면, 최종 401을 authExpired로
    /// 승격해 만료 세션 처리 경로(AppState.expireSession)로 이어지게 한다.
    func testEarnAttendance_throwsAuthExpired_whenRetriedRequestStill401AfterRefresh() async throws {
        let tokenStore = InMemoryAuthTokenStore(
            accessToken: "stale-access",
            refreshToken: "valid-refresh"
        )
        let store = makeStore(tokenStore: tokenStore)

        var refreshCount = 0
        var attendanceCount = 0
        MockURLProtocol.handler = { request in
            if request.url?.path == "/auth/refresh" {
                refreshCount += 1
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Self.refreshSuccessBody
                )
            }
            attendanceCount += 1
            return (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data(#"{"code":5000,"message":"인증이 필요합니다."}"#.utf8)
            )
        }

        do {
            _ = try await store.earnAttendance(deviceId: "device-1", idempotencyKey: "key")
            XCTFail("Expected RemoteStoreError.authExpired")
        } catch let error as RemoteStoreError {
            guard case .authExpired = error else {
                return XCTFail("Expected authExpired, got \(error)")
            }
        }

        // refresh 1회 + attendance 2회(최초 + 재시도)만 발생 — 무한 재시도 없음.
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(attendanceCount, 2)
        // refresh 성공으로 새 토큰이 저장됐음 — 재발급 경로를 실제로 탔다는 증거.
        XCTAssertEqual(tokenStore.accessToken, "new-access")
    }

    func testDeleteUserData_usesRefreshSnapshotWithoutRestoringKeychainWhenAccessExpired() async throws {
        let store = makeStore()
        TokenManager.clear()

        var paths: [String] = []
        var deleteAuthorizations: [String?] = []
        MockURLProtocol.handler = { request in
            paths.append(request.url?.path ?? "")
            if request.url?.path == "/auth/refresh" {
                let body = try Self.bodyData(from: request)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
                XCTAssertEqual(json?["refreshToken"], "refresh-snapshot")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Self.refreshSuccessBody
                )
            }

            deleteAuthorizations.append(request.value(forHTTPHeaderField: "Authorization"))
            if deleteAuthorizations.count == 1 {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"code":5000,"message":"인증이 필요합니다."}"#.utf8)
                )
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"code":1000,"message":"요청에 성공하였습니다."}"#.utf8)
            )
        }

        try await store.deleteUserData(accessToken: "expired-access", refreshToken: "refresh-snapshot")

        XCTAssertEqual(paths, ["/v1/me", "/auth/refresh", "/v1/me"])
        XCTAssertEqual(deleteAuthorizations, ["Bearer expired-access", "Bearer new-access"])
        XCTAssertNil(TokenManager.accessToken)
        XCTAssertNil(TokenManager.refreshToken)
    }

    func testFetchRewardHistory_sendsExpectedRequestAndDecodesResult() async throws {
        let store = makeStore()
        var capturedRequest: URLRequest?

        MockURLProtocol.handler = { request in
            capturedRequest = request
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(
                    """
                    {
                      "code": 1000,
                      "message": "요청에 성공하였습니다.",
                      "result": [
                        {
                          "id": "11111111-1111-1111-1111-111111111111",
                          "eventType": "SESSION",
                          "eventDay": "2026-07-03",
                          "grantedPoints": 24,
                          "capped": false,
                          "sessionId": "22222222-2222-2222-2222-222222222222"
                        },
                        {
                          "id": "33333333-3333-3333-3333-333333333333",
                          "eventType": "ATTENDANCE",
                          "eventDay": "2026-07-01",
                          "grantedPoints": 10,
                          "capped": false,
                          "sessionId": null
                        }
                      ]
                    }
                    """.utf8
                )
            )
        }

        let result = try await store.fetchRewardHistory()

        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "http://localhost:8080/v1/me/rewards")
        XCTAssertEqual(result.map(\.eventType), [.session, .attendance])
        XCTAssertEqual(result.map(\.grantedPoints), [24, 10])
        XCTAssertEqual(result.first?.eventDay, "2026-07-03")
        XCTAssertEqual(result.first?.sessionId?.uuidString.lowercased(), "22222222-2222-2222-2222-222222222222")
        XCTAssertNil(result.last?.sessionId)
    }

    private func makeStore(
        tokenStore: any AuthTokenStorage = KeychainAuthTokenStorage()
    ) -> SpringRemoteStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return SpringRemoteStore(
            config: SpringConfig(baseURL: URL(string: "http://localhost:8080")!),
            session: URLSession(configuration: config),
            tokenStore: tokenStore
        )
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        if let stream = request.httpBodyStream {
            return try readBody(stream)
        }
        throw URLError(.cannotDecodeContentData)
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int,
        headerFields: [String: String]? = nil
    ) throws -> HTTPURLResponse {
        let url = try XCTUnwrap(request.url)
        return try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headerFields
            )
        )
    }

    private static func readBody(_ stream: InputStream) throws -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private static let successBody = Data(
        """
        {
          "code": 1000,
          "message": "요청에 성공하였습니다.",
          "result": {
            "grantedPoints": 10,
            "capped": false,
            "idempotentReplay": false,
            "streak": {
              "current": 8,
              "longest": 18,
              "startedOn": "2026-07-08",
              "event": "MILESTONE",
              "freezeInventory": 1,
              "freezeConsumed": 1,
              "freezeGranted": 1
            },
            "userStats": {
              "userId": "11111111-1111-1111-1111-111111111111",
              "displayName": null,
              "points": 10,
              "streak": 0,
              "freezeInventory": 0,
              "todayRealChewCount": 0,
              "dailyGoal": 400,
              "todayProgress": 0.0,
              "todayCompleted": false
            }
          }
        }
        """.utf8
    )

    private static let refreshSuccessBody = Data(
        """
        {
          "code": 1000,
          "message": "요청에 성공하였습니다.",
          "result": {
            "accessToken": "new-access",
            "refreshToken": "new-refresh",
            "expiresIn": 3600,
            "user": {
              "id": "11111111-1111-1111-1111-111111111111",
              "displayName": null,
              "onboardingCompleted": false
            }
          }
        }
        """.utf8
    )
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}

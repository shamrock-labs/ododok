import XCTest
@testable import ChewChewIOS

final class SpringRemoteStoreAttendanceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        TokenManager.clear()
        super.tearDown()
    }

    func testEarnAttendance_sendsExpectedRequestAndDecodesResult() async throws {
        let store = makeStore()
        var capturedRequest: URLRequest?

        MockURLProtocol.handler = { request in
            capturedRequest = request
            let body = try Self.bodyData(from: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: String]

            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/me/attendance")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-Id"), "device-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(json?["idempotencyKey"], "app-open-device-1-20260612")

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
            idempotencyKey: "app-open-device-1-20260612"
        )

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "http://localhost:8080/v1/me/attendance")
        XCTAssertEqual(result.grantedPoints, 10)
        XCTAssertFalse(result.capped)
        XCTAssertFalse(result.idempotentReplay)
        XCTAssertEqual(result.userStats.deviceId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(result.userStats.userId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(result.userStats.points, 10)
    }

    func testEarnAttendance_decodesServerErrorEnvelope() async throws {
        let store = makeStore()
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                Data(#"{"code":4004,"message":"유효하지 않은 디바이스 식별자입니다."}"#.utf8)
            )
        }

        do {
            _ = try await store.earnAttendance(deviceId: " ", idempotencyKey: "key")
            XCTFail("Expected RemoteStoreError.server")
        } catch let error as RemoteStoreError {
            guard case .server(let status, let code, let message) = error else {
                return XCTFail("Expected server error, got \(error)")
            }
            XCTAssertEqual(status, 400)
            XCTAssertEqual(code, 4004)
            XCTAssertEqual(message, "유효하지 않은 디바이스 식별자입니다.")
        }
    }

    func testEarnAttendanceThrowsAuthExpiredWhenRefreshFails() async throws {
        TokenManager.save(access: "expired-access", refresh: "expired-refresh")
        let store = makeStore()

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

        XCTAssertNil(TokenManager.accessToken)
        XCTAssertNil(TokenManager.refreshToken)
    }

    private func makeStore() -> SpringRemoteStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return SpringRemoteStore(
            config: SpringConfig(baseURL: URL(string: "http://localhost:8080")!),
            session: URLSession(configuration: config)
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

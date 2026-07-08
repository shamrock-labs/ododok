import XCTest
@testable import ChewChewIOS

final class SpringAuthClientMeTests: XCTestCase {
    override func tearDown() {
        SpringAuthClientMeMockURLProtocol.handler = nil
        TokenManager.clear()
        super.tearDown()
    }

    func testMe_decodesAlertVolumeFromAuthMe() async throws {
        TokenManager.save(access: "access-token", refresh: "refresh-token")
        let client = makeClient()
        var capturedRequest: URLRequest?

        SpringAuthClientMeMockURLProtocol.handler = { request in
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
                      "result": {
                        "id": "11111111-1111-1111-1111-111111111111",
                        "displayName": "보형",
                        "onboardingCompleted": true,
                        "alertVolume": 0.35
                      }
                    }
                    """.utf8
                )
            )
        }

        let result = try await client.me()

        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.url?.path, "/auth/me")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(result.userId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(result.displayName, "보형")
        XCTAssertTrue(result.onboardingCompleted)
        let alertVolume = try XCTUnwrap(result.alertVolume)
        XCTAssertEqual(alertVolume, 0.35, accuracy: 0.0001)
    }

    func testMe_allowsMissingAlertVolumeForBackwardCompatibility() async throws {
        let client = makeClient()

        SpringAuthClientMeMockURLProtocol.handler = { request in
            (
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
                      "result": {
                        "id": "11111111-1111-1111-1111-111111111111",
                        "displayName": null,
                        "onboardingCompleted": false
                      }
                    }
                    """.utf8
                )
            )
        }

        let result = try await client.me()

        XCTAssertEqual(result.userId, "11111111-1111-1111-1111-111111111111")
        XCTAssertNil(result.displayName)
        XCTAssertFalse(result.onboardingCompleted)
        XCTAssertNil(result.alertVolume)
    }

    private func makeClient() -> SpringAuthClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpringAuthClientMeMockURLProtocol.self]
        return SpringAuthClient(
            config: SpringConfig(baseURL: URL(string: "https://api.dev.ododok.cloud")!),
            session: URLSession(configuration: config)
        )
    }
}

private final class SpringAuthClientMeMockURLProtocol: URLProtocol {
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

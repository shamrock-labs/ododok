import XCTest
@testable import ChewChewIOS

final class SpringRemoteStoreChewProfileTests: XCTestCase {
    override func tearDown() {
        SpringChewProfileURLProtocol.handler = nil
        super.tearDown()
    }

    func testCurrentProfileRequestEncodesModelVersionAndDecodesAbsentResult() async throws {
        let store = makeStore()
        SpringChewProfileURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/me/chew-detection-profiles/current")
            XCTAssertEqual(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "modelVersion" })?.value,
                "dsp-chewcounter-3"
            )
            return Self.response(request, body: #"{"code":1000,"message":"ok"}"#)
        }

        let profile = try await store.fetchCurrentChewDetectionProfile(modelVersion: "dsp-chewcounter-3")

        XCTAssertNil(profile)
    }

    func testCreateProfileSendsIdempotencyKeyAndFullDSPSettings() async throws {
        let store = makeStore()
        let settings = PersonalizedChewDetectionSettings(
            minPeakAmplitude: 0.008,
            calibrationPeakCount: 12,
            validationDetectedCount: 8,
            calibratedAt: Date(timeIntervalSince1970: 1_000),
            naturalChewInterval: 0.7,
            calibrationAmplitudes: [0.007, 0.008],
            gateThresholds: .standard
        )
        let requestDTO = ChewDetectionProfileRequestDTO(
            settings: settings,
            modelVersion: "dsp-chewcounter-3",
            source: "PERSONALIZATION"
        )
        SpringChewProfileURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/me/chew-detection-profiles")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "save-attempt-1")
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["modelVersion"] as? String, "dsp-chewcounter-3")
            XCTAssertEqual(json["minPeakAmplitude"] as? Double, 0.008)
            XCTAssertEqual(json["source"] as? String, "PERSONALIZATION")
            let gate = try XCTUnwrap(json["gateThresholds"] as? [String: Any])
            XCTAssertEqual(gate["requiresOpenActivityGate"] as? Bool, true)
            return Self.response(request, body: Self.profileEnvelope)
        }

        let profile = try await store.createChewDetectionProfile(requestDTO, idempotencyKey: "save-attempt-1")

        XCTAssertEqual(profile.id.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(profile.revision, 2)
        XCTAssertEqual(profile.configuration.minPeakAmplitude, 0.008)
    }

    func testResetUsesCurrentEndpointWithoutSendingAProfileBody() async throws {
        let store = makeStore()
        SpringChewProfileURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v1/me/chew-detection-profiles/current")
            XCTAssertNil(request.httpBody)
            return Self.response(request, body: #"{"code":1000,"message":"ok"}"#)
        }

        try await store.resetCurrentChewDetectionProfile(modelVersion: "dsp-chewcounter-3")
    }

    private func makeStore() -> SpringRemoteStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpringChewProfileURLProtocol.self]
        return SpringRemoteStore(
            config: SpringConfig(baseURL: URL(string: "http://localhost:8080")!),
            session: URLSession(configuration: configuration)
        )
    }

    private static func response(_ request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw URLError(.cannotDecodeContentData) }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static let profileEnvelope = """
        {
          "code": 1000,
          "message": "ok",
          "result": {
            "id": "11111111-1111-1111-1111-111111111111",
            "modelVersion": "dsp-chewcounter-3",
            "revision": 2,
            "minPeakAmplitude": 0.008,
            "calibrationPeakCount": 12,
            "validationDetectedCount": 8,
            "calibratedAt": "1970-01-01T00:16:40.000Z",
            "naturalChewInterval": 0.7,
            "calibrationAmplitudes": [0.007, 0.008],
            "gateThresholds": {
              "minimumRotationYStd": 0.03,
              "minimumRotationYDominance": 0.15,
              "minimumRotationYJitterBandDominance": 0.15,
              "requiresOpenActivityGate": true
            },
            "source": "PERSONALIZATION",
            "createdAt": "1970-01-01T00:16:41.000Z"
          }
        }
        """
}

private final class SpringChewProfileURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

    override func stopLoading() {}
}

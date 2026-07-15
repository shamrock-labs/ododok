import XCTest
@testable import ChewChewIOS

final class SpringCalibrationUploadTests: XCTestCase {
    override func tearDown() {
        CalibrationUploadURLProtocol.handler = nil
        super.tearDown()
    }

    func testUploadsArtifactBodiesDirectlyToPresignedURLs() async throws {
        let calibrationId = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let artifacts = CalibrationArtifactKind.allCases.map { kind in
            CalibrationArtifactUpload(kind: kind, data: Data("body-\(kind.rawValue)".utf8))
        }
        var planRequestCount = 0
        var uploadedKinds: [CalibrationArtifactKind] = []

        CalibrationUploadURLProtocol.handler = { request in
            guard request.url?.host == "uploads.example.com" else {
                planRequestCount += 1
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(
                    request.url?.path,
                    "/v1/me/calibrations/\(calibrationId.uuidString.lowercased())/upload-plan"
                )
                return try Self.response(
                    for: request,
                    status: 200,
                    body: Self.planBody(calibrationId: calibrationId)
                )
            }

            XCTAssertEqual(request.httpMethod, "PUT")
            let rawKind = request.url?.lastPathComponent.replacingOccurrences(of: ".bin", with: "") ?? ""
            let kind = try XCTUnwrap(CalibrationArtifactKind(rawValue: rawKind))
            uploadedKinds.append(kind)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), Self.contentType(for: kind))
            XCTAssertEqual(try Self.bodyData(from: request), Data("body-\(kind.rawValue)".utf8))
            return try Self.response(for: request, status: 200, body: Data())
        }

        try await makeStore().uploadCalibrationArtifacts(.init(
            calibrationId: calibrationId,
            artifacts: artifacts
        ))

        XCTAssertEqual(planRequestCount, 1)
        XCTAssertEqual(uploadedKinds, CalibrationArtifactKind.allCases)
    }

    private func makeStore() throws -> SpringRemoteStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CalibrationUploadURLProtocol.self]
        let baseURL = try XCTUnwrap(URL(string: "https://api.example.com"))
        return SpringRemoteStore(
            config: SpringConfig(baseURL: baseURL),
            session: URLSession(configuration: configuration)
        )
    }

    private static func planBody(calibrationId: UUID) throws -> Data {
        let uploads = CalibrationArtifactKind.allCases.map { kind in
            [
                "type": kind.rawValue,
                "key": "calibrations/user/\(calibrationId)/\(kind.rawValue).bin",
                "uploadUrl": "https://uploads.example.com/\(kind.rawValue).bin",
                "headers": ["content-type": contentType(for: kind)],
            ] as [String: Any]
        }
        let result: [String: Any] = [
            "calibrationId": calibrationId.uuidString.lowercased(),
            "expiresAt": "2026-07-14T09:00:00Z",
            "uploads": uploads,
        ]
        return try JSONSerialization.data(withJSONObject: [
            "code": 1000,
            "message": "success",
            "result": result,
        ])
    }

    private static func contentType(for kind: CalibrationArtifactKind) -> String {
        kind == .summary ? "application/json" : "text/csv"
    }

    private static func response(
        for request: URLRequest,
        status: Int,
        body: Data
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        ))
        return (response, body)
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private class CalibrationUploadURLProtocol: URLProtocol {
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

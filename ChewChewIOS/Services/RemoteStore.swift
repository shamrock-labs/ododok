import Foundation

/// 원격 영속화 추상화. AppState는 이 프로토콜에만 의존해서, 시뮬레이터/유닛테스트에서
/// `NoopRemoteStore`로 갈아끼울 수 있다.
protocol RemoteStore {
    func upsertProgress(_ snapshot: ProgressDTO) async throws
    func fetchProgress(deviceId: String) async throws -> ProgressDTO?
    func deleteProgress(deviceId: String) async throws
    func insertSession(_ session: ChewingSessionDTO) async throws
    func uploadIMUCSV(sessionId: UUID, deviceId: String, gzippedData: Data) async throws -> String
}

struct NoopRemoteStore: RemoteStore {
    func upsertProgress(_ snapshot: ProgressDTO) async throws {}
    func fetchProgress(deviceId: String) async throws -> ProgressDTO? { nil }
    func deleteProgress(deviceId: String) async throws {}
    func insertSession(_ session: ChewingSessionDTO) async throws {}
    func uploadIMUCSV(sessionId: UUID, deviceId: String, gzippedData: Data) async throws -> String { "" }
}

struct InsForgeConfig {
    let baseURL: URL
    let apiKey: String
}

enum RemoteStoreError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case invalidUploadResponse

    var description: String {
        switch self {
        case .http(let s, let b): return "RemoteStoreError.http(\(s)): \(b)"
        case .invalidUploadResponse: return "RemoteStoreError.invalidUploadResponse"
        }
    }
}

/// InsForge REST 백엔드 구현. PostgREST 스타일 DB + 3단계 Storage 업로드(strategy → upload → confirm).
final class InsForgeRemoteStore: RemoteStore {
    private let config: InsForgeConfig
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(config: InsForgeConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(Self.isoFormatter.string(from: date))
        }
        self.encoder = enc

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = Self.isoFormatter.date(from: s) { return d }
            if let d = Self.isoFormatterNoFractional.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "invalid ISO8601: \(s)")
        }
        self.decoder = dec
    }

    // MARK: - user_progress

    func upsertProgress(_ snapshot: ProgressDTO) async throws {
        var req = try jsonRequest(method: "POST", path: "/api/database/records/user_progress")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try encoder.encode([snapshot])
        _ = try await sendExpectingSuccess(req)
    }

    func fetchProgress(deviceId: String) async throws -> ProgressDTO? {
        let escaped = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "GET",
            path: "/api/database/records/user_progress?device_id=eq.\(escaped)&limit=1"
        )
        let data = try await sendExpectingSuccess(req)
        let rows = try decoder.decode([ProgressDTO].self, from: data)
        return rows.first
    }

    func deleteProgress(deviceId: String) async throws {
        let escaped = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        let req = try jsonRequest(
            method: "DELETE",
            path: "/api/database/records/user_progress?device_id=eq.\(escaped)"
        )
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - chewing_session

    func insertSession(_ session: ChewingSessionDTO) async throws {
        var req = try jsonRequest(method: "POST", path: "/api/database/records/chewing_session")
        req.httpBody = try encoder.encode([session])
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - imu-sessions storage (3-step)

    func uploadIMUCSV(sessionId: UUID, deviceId: String, gzippedData: Data) async throws -> String {
        let filename = "\(deviceId)/\(sessionId.uuidString).csv.gz"
        let strategy = try await fetchUploadStrategy(
            bucket: "imu-sessions",
            filename: filename,
            contentType: "application/gzip",
            size: gzippedData.count
        )
        try await performUpload(strategy: strategy, data: gzippedData)
        if strategy.confirmRequired {
            try await confirmUpload(strategy: strategy, size: gzippedData.count)
        }
        return strategy.key
    }

    private struct UploadStrategy: Decodable {
        let method: String           // "direct" (local) | "presigned" (S3)
        let uploadUrl: String
        let key: String
        let fields: [String: String]?
        let confirmRequired: Bool
        let confirmUrl: String?
    }

    private func fetchUploadStrategy(
        bucket: String, filename: String, contentType: String, size: Int
    ) async throws -> UploadStrategy {
        var req = try jsonRequest(
            method: "POST",
            path: "/api/storage/buckets/\(bucket)/upload-strategy"
        )
        let body: [String: Any] = [
            "filename": filename,
            "contentType": contentType,
            "size": size
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await sendExpectingSuccess(req)
        return try JSONDecoder().decode(UploadStrategy.self, from: data)
    }

    private func performUpload(strategy: UploadStrategy, data: Data) async throws {
        let boundary = "ChewChew-\(UUID().uuidString)"
        let isPresigned = strategy.method == "presigned"

        let endpoint: URL
        if isPresigned {
            guard let u = URL(string: strategy.uploadUrl) else {
                throw RemoteStoreError.invalidUploadResponse
            }
            endpoint = u
        } else {
            endpoint = resolveURL(strategy.uploadUrl)
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = isPresigned ? "POST" : "PUT"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !isPresigned {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = Self.makeMultipartBody(
            boundary: boundary,
            fields: isPresigned ? (strategy.fields ?? [:]) : [:],
            fileFieldName: "file",
            filename: strategy.key,
            fileContentType: "application/gzip",
            fileData: data
        )
        _ = try await sendExpectingSuccess(req)
    }

    private func confirmUpload(strategy: UploadStrategy, size: Int) async throws {
        guard let confirmPath = strategy.confirmUrl else { return }
        var req = try jsonRequest(method: "POST", path: confirmPath, allowAbsolute: true)
        let body: [String: Any] = ["size": size, "contentType": "application/gzip"]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await sendExpectingSuccess(req)
    }

    // MARK: - Helpers

    private func jsonRequest(method: String, path: String, allowAbsolute: Bool = false) throws -> URLRequest {
        let url = allowAbsolute && path.hasPrefix("http") ? URL(string: path)! : resolveURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func resolveURL(_ pathOrAbsolute: String) -> URL {
        if let u = URL(string: pathOrAbsolute), u.scheme != nil {
            return u
        }
        var base = config.baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + pathOrAbsolute)!
    }

    private func sendExpectingSuccess(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteStoreError.http(status: -1, body: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RemoteStoreError.http(status: http.statusCode, body: body)
        }
        return data
    }

    private static func makeMultipartBody(
        boundary: String,
        fields: [String: String],
        fileFieldName: String,
        filename: String,
        fileContentType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        for (key, value) in fields {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\(crlf)\(crlf)".utf8))
            body.append(Data("\(value)\(crlf)".utf8))
        }

        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\(crlf)".utf8))
        body.append(Data("Content-Type: \(fileContentType)\(crlf)\(crlf)".utf8))
        body.append(fileData)
        body.append(Data("\(crlf)--\(boundary)--\(crlf)".utf8))
        return body
    }

    // MARK: - Date formatters
    //
    // Postgres `timestamptz`는 보통 millisecond까지 들어있는 ISO8601로 직렬화된다.
    // 송신은 fractional 포함, 수신은 둘 다 시도.

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

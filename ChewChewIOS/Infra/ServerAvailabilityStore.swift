import Foundation
import Observation

protocol ServerHealthChecking: Sendable {
    func isAvailable() async -> Bool
}

struct HTTPServerHealthChecker: ServerHealthChecking {
    private let healthURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.healthURL = baseURL.appending(path: "health")
        self.session = session
    }

    func isAvailable() async -> Bool {
        var request = URLRequest(url: healthURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

@Observable
@MainActor
final class ServerAvailabilityStore {
    enum Status: Equatable {
        case checking
        case preparing
        case available
    }

    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let requiresMonitoring: Bool
    private let checker: any ServerHealthChecking
    private let retryInterval: Duration
    private let sleep: Sleep
    private var checkGeneration = 0

    private(set) var status: Status

    init(
        environment: String,
        checker: any ServerHealthChecking,
        retryInterval: Duration = .seconds(10),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.requiresMonitoring = environment == "dev"
        self.checker = checker
        self.retryInterval = retryInterval
        self.sleep = sleep
        self.status = environment == "dev" ? .checking : .available
    }

    func monitor() async {
        guard requiresMonitoring else {
            status = .available
            return
        }

        while !Task.isCancelled && status != .available {
            if await checkOnce() { return }
            do {
                try await sleep(retryInterval)
            } catch {
                return
            }
        }
    }

    func retryNow() async {
        guard requiresMonitoring else { return }
        status = .checking
        _ = await checkOnce()
    }

    private func checkOnce() async -> Bool {
        checkGeneration &+= 1
        let generation = checkGeneration
        let isAvailable = await checker.isAvailable()
        guard generation == checkGeneration else {
            return status == .available
        }
        status = isAvailable ? .available : .preparing
        return isAvailable
    }
}

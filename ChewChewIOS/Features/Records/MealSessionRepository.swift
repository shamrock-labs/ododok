import Foundation

protocol MealSessionRepository {
    func fetchSessions(since: Date, until: Date?) async throws -> [MealSessionRecord]
    func deleteSession(id: UUID) async throws
    func deleteAllSessions() async throws
}

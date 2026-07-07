import Foundation

protocol HomeRepository {
    func fetchHome() async throws -> HomeStateDTO
}

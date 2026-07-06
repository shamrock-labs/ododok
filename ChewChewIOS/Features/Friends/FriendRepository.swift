import Foundation

protocol FriendRepository {
    func fetchInviteCode() async throws -> FriendInviteCodeDTO
    func fetchRanking() async throws -> [FriendRankingDTO]
    func acceptInvite(code: String) async throws -> FriendAcceptResultDTO
}

import Foundation

struct FriendInviteCodeDTO: Codable, Equatable {
    var code: String
    /// 공유용 딥링크(chewchew://invite?code=...). 구버전 서버 호환 위해 옵셔널.
    var deepLink: String?
}

struct FriendAcceptResultDTO: Codable, Equatable {
    var accepted: Bool
    var bonusGranted: Bool
}

struct FriendRankingDTO: Codable, Equatable, Identifiable {
    var userId: UUID
    var name: String?
    var points: Int
    var me: Bool

    var id: UUID { userId }
}

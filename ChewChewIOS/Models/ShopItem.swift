import Foundation

struct ShopItem: Identifiable, Hashable {
    enum Kind: String, Hashable { case hat, glasses, acc }
    enum Rarity: String, Hashable { case common, rare }

    let id: String
    let name: String
    let type: Kind
    let emoji: String
    let price: Int
    let rarity: Rarity

    static let all: [ShopItem] = [
        .init(id: "hat-beanie",  name: "겨울 비니",     type: .hat,     emoji: "🧢", price: 120, rarity: .common),
        .init(id: "hat-crown",   name: "도토리 왕관",   type: .hat,     emoji: "👑", price: 850, rarity: .rare),
        .init(id: "hat-cap",     name: "데님 모자",     type: .hat,     emoji: "🎩", price: 280, rarity: .common),
        .init(id: "gls-round",   name: "동그라미 안경", type: .glasses, emoji: "👓", price: 200, rarity: .common),
        .init(id: "gls-sun",     name: "여름 선글라스", type: .glasses, emoji: "🕶️", price: 450, rarity: .rare),
        .init(id: "acc-scarf",   name: "체크 머플러",   type: .acc,     emoji: "🧣", price: 320, rarity: .common),
        .init(id: "acc-bow",     name: "리본 타이",     type: .acc,     emoji: "🎀", price: 380, rarity: .rare),
        .init(id: "acc-flower",  name: "꽃 한 송이",    type: .acc,     emoji: "🌸", price: 160, rarity: .common),
    ]

    static func by(id: String?) -> ShopItem? {
        guard let id else { return nil }
        return all.first(where: { $0.id == id })
    }
}

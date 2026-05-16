import Foundation
import Observation

@Observable
final class AppState {
    var chewCount: Int = 247
    var streak: Int = 7
    var points: Int = 1240
    var animKey: Int = 0
    var weeklyScores: [Int] = [72, 85, 68, 78, 82, 88, 41]
    var owned: Set<String> = ["hat-beanie", "gls-round"]
    var equipped: Equipped = .init(hat: "hat-beanie", glasses: nil, acc: nil)

    struct Equipped {
        var hat: String?
        var glasses: String?
        var acc: String?
    }

    private var goalAlreadyHit = false

    func chew() {
        chewCount += 1
        points += 1
        animKey &+= 1
        if chewCount >= Constants.dailyGoal && !goalAlreadyHit {
            goalAlreadyHit = true
            points += 200
        }
    }

    func reset() {
        chewCount = 247
        streak = 7
        points = 1240
        animKey = 0
        weeklyScores = [72, 85, 68, 78, 82, 88, 41]
        owned = ["hat-beanie", "gls-round"]
        equipped = .init(hat: "hat-beanie", glasses: nil, acc: nil)
        goalAlreadyHit = false
    }

    @discardableResult
    func buy(_ item: ShopItem) -> Bool {
        guard points >= item.price else { return false }
        points -= item.price
        owned.insert(item.id)
        return true
    }

    @discardableResult
    func toggleEquip(_ item: ShopItem) -> Bool {
        let current = equippedID(for: item.type)
        let willEquip = current != item.id
        switch item.type {
        case .hat:     equipped.hat     = willEquip ? item.id : nil
        case .glasses: equipped.glasses = willEquip ? item.id : nil
        case .acc:     equipped.acc     = willEquip ? item.id : nil
        }
        return willEquip
    }

    func equippedID(for type: ShopItem.Kind) -> String? {
        switch type {
        case .hat:     equipped.hat
        case .glasses: equipped.glasses
        case .acc:     equipped.acc
        }
    }

    @discardableResult
    func consume(_ pack: AcornPack) -> Bool {
        guard points >= pack.price else { return false }
        points -= pack.price
        return true
    }

    var status: MoodStatus { MoodStatus.from(count: chewCount) }

    var progress: Double {
        min(1.0, max(0.0, Double(chewCount) / Double(Constants.dailyGoal)))
    }
}

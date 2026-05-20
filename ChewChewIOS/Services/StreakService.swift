import Foundation

/// PRD #11 streak 측정 서비스. AppState의 `streak`(count) + `freezeInventory` +
/// `lastSuccessDate`를 일관 mutate. 호출 시점은 두 곳:
///   - 세션 종료 INSERT 성공 후 (`performSessionUpload`)
///   - foreground 진입 (`sceneDidChange(toForeground: true)`) — 자동 방어 trigger
///
/// 정책:
///   - 일 단위 (로컬 자정 기준 `Calendar.dateComponents([.day], ...)`).
///   - 마일스톤 7/30/100일 도달 시 프리즈 +1 적립, 인벤토리 상한 3개.
///   - 2일 공백 + 프리즈 보유 시 자동 소진해서 streak 유지.
///   - 2일 공백 + 프리즈 0 시 카운트 1로 리셋.
///   - 같은 날 두 번째 호출은 변화 없음.
///   - foreground 진입에서만 자동 방어 — 사용자가 식사 안 해도 그 자리에서 정리.
enum StreakService {
    static let maxFreezeInventory = 3
    static let milestones: Set<Int> = [7, 30, 100]
    static let milestoneFreezeReward = 1

    enum Event: Equatable {
        case incremented(newCount: Int)
        case milestone(count: Int, freezeGain: Int)
        case savedByFreeze(remainingFreeze: Int)
        case reset
    }

    /// 세션 종료 또는 메인 진입 시 호출. 카운트 / 프리즈 인벤토리 / lastSuccessDate를
    /// mutate하고 발생한 이벤트 목록을 반환. 호출자는 events 중 가장 임팩트 큰 것을
    /// UI 알림으로 띄운다.
    @MainActor
    @discardableResult
    static func evaluate(_ state: AppState, now: Date = .now) -> [Event] {
        let cal = Calendar(identifier: .gregorian)
        var events: [Event] = []

        guard let last = state.lastSuccessDate else {
            // 첫 성공 — 카운트 1
            state.streak = 1
            state.lastSuccessDate = now
            events.append(.incremented(newCount: 1))
            return events
        }

        let lastDay = cal.startOfDay(for: last)
        let nowDay = cal.startOfDay(for: now)
        let gapDays = cal.dateComponents([.day], from: lastDay, to: nowDay).day ?? 0

        if gapDays <= 0 {
            return events
        }
        if gapDays == 1 {
            state.streak += 1
            state.lastSuccessDate = now
            events.append(.incremented(newCount: state.streak))
            appendMilestoneIfNeeded(state: state, events: &events)
            return events
        }
        // gapDays >= 2
        if state.freezeInventory > 0 {
            state.freezeInventory -= 1
            state.streak += 1
            state.lastSuccessDate = now
            events.append(.savedByFreeze(remainingFreeze: state.freezeInventory))
            events.append(.incremented(newCount: state.streak))
            appendMilestoneIfNeeded(state: state, events: &events)
            return events
        }
        // 프리즈 0 → 끊김 리셋
        state.streak = 1
        state.lastSuccessDate = now
        events.append(.reset)
        return events
    }

    @MainActor
    private static func appendMilestoneIfNeeded(state: AppState, events: inout [Event]) {
        guard milestones.contains(state.streak) else { return }
        let room = max(0, maxFreezeInventory - state.freezeInventory)
        let gain = min(milestoneFreezeReward, room)
        guard gain > 0 else { return }
        state.freezeInventory += gain
        events.append(.milestone(count: state.streak, freezeGain: gain))
    }

    /// foreground 진입 시 자동 방어 전용 평가.
    /// - lastSuccessDate nil이면 변화 없음 (첫 사용자는 세션 종료에서만 시작).
    /// - gapDays <= 1이면 변화 없음 (당일/연속 진입).
    /// - gapDays >= 2 + freezeInventory > 0: 프리즈 1개 소진, lastSuccessDate를 어제로 되돌려
    ///   다음 세션 종료에서 정상 +1이 가능하도록. streak count는 변경 안 함.
    /// - gapDays >= 2 + freezeInventory == 0: lastSuccessDate를 nil로 set해 다음 세션 종료에서
    ///   "첫 성공" path(streak=1)를 타도록. count는 이 시점에 건드리지 않음.
    @MainActor
    @discardableResult
    static func evaluateForegroundDefense(_ state: AppState, now: Date = .now) -> [Event] {
        let cal = Calendar(identifier: .gregorian)
        var events: [Event] = []

        guard let last = state.lastSuccessDate else {
            return events
        }

        let lastDay = cal.startOfDay(for: last)
        let nowDay = cal.startOfDay(for: now)
        let gapDays = cal.dateComponents([.day], from: lastDay, to: nowDay).day ?? 0

        guard gapDays >= 2 else {
            return events
        }

        if state.freezeInventory > 0 {
            state.freezeInventory -= 1
            // streak count는 유지, lastSuccessDate를 어제로 되돌려 다음 세션 종료 시 gapDays=1 path 타도록
            let yesterday = cal.date(byAdding: .day, value: -1, to: nowDay)!
            state.lastSuccessDate = yesterday
            events.append(.savedByFreeze(remainingFreeze: state.freezeInventory))
        } else {
            // 프리즈 없음 — lastSuccessDate nil로 set해 다음 세션 종료에서 첫 성공(streak=1) path 타도록
            state.lastSuccessDate = nil
            events.append(.reset)
        }

        return events
    }

    /// 이벤트 목록에서 dialog로 띄울 가장 임팩트 큰 단일 RewardGrant를 골라낸다.
    /// 우선순위: milestone > savedByFreeze > reset > incremented(알림 안 함, nil).
    /// 동일 evaluate 호출에서 incremented + milestone이 같이 발생하면 milestone만 표시.
    static func noticeGrant(from events: [Event]) -> RewardGrant? {
        for event in events {
            switch event {
            case .milestone(let count, let freezeGain):
                return RewardGrant(amount: freezeGain, kind: .streakMilestone(streakCount: count))
            default: continue
            }
        }
        for event in events {
            switch event {
            case .savedByFreeze(let remainingFreeze):
                return RewardGrant(amount: remainingFreeze, kind: .streakSaved)
            default: continue
            }
        }
        for event in events {
            if case .reset = event {
                return RewardGrant(amount: 0, kind: .streakReset)
            }
        }
        return nil
    }
}

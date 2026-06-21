import SwiftUI

/// 서버가 도토리·스트릭을 적립할 때 사용자에게 표시되는 시각적 보상. PRD #8의
/// "토스트 + 다람이 happy"의 in-app 구현. 시스템 alert 대신 커스텀 다이얼로그 +
/// 다람이 happy 이미지 + 적립 도토리 수 + 짧은 카피. 자동 2.5초 dismiss, 탭으로도
/// dismiss.
struct RewardDialogView: View {
    let grant: RewardGrant
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(grant.kind.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)

            Text(grant.kind.title)
                .font(.appFont(.heavy, size: 18))
                .foregroundStyle(Color.ink800)

            if grant.kind.isAcorn {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("+\(grant.amount)")
                        .font(.appFont(.heavy, size: 36))
                        .foregroundStyle(Color.acorn700)
                        .monospacedDigit()
                    Text("🌰")
                        .font(.appFont(.regular, size: 28))
                }
            } else if grant.kind.isFreezeGain {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("+\(grant.amount)")
                        .font(.appFont(.heavy, size: 36))
                        .foregroundStyle(Color.sage600)
                        .monospacedDigit()
                    Text("🛡️")
                        .font(.appFont(.regular, size: 28))
                }
            }

            Text(grant.kind.subtitle)
                .font(.appFont(.semibold, size: 14))
                .foregroundStyle(Color.ink600)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 22)
        .frame(maxWidth: 320)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28))
        .neuoShadow(.md)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            onDismiss()
        }
    }
}

/// AppState가 publish하는 적립/알림 trigger. `ContentView` overlay가 이 값을 관찰해서
/// 다이얼로그를 띄운다. dismiss 시 nil로 비움. 도토리 적립(`attendance`/`sessionComplete`)과
/// PRD #11 streak 이벤트(`streakMilestone`/`streakSaved`/`streakReset`)를 한 type으로
/// 묶어 ContentView overlay 코드를 단순화.
struct RewardGrant: Equatable {
    /// 표시할 숫자(도토리 또는 프리즈 잔여). kind에 따라 의미가 다름. 0이면 숫자 표시 안 함.
    let amount: Int
    let kind: Kind

    enum Kind: Equatable {
        case attendance                          // 도토리 출석 보너스 +n
        case sessionComplete                     // 도토리 세션 종료 적립 +n
        case streakMilestone(streakCount: Int)   // 7/30/100일 도달, 프리즈 +n(amount)
        case streakSaved                         // 프리즈 1 자동 소진, amount=잔여
        case streakReset                         // 끊김 리셋
        case streakFirstDay                      // 첫 성공(스트릭 1일째) 토스트

        /// 분석 이벤트용 안정적 식별자(ODO-79). 표시 문구(title)와 독립 — 문구가 바뀌어도 값은 유지된다.
        var analyticsType: String {
            switch self {
            case .attendance:      "attendance"
            case .sessionComplete: "session_complete"
            case .streakMilestone: "streak_milestone"
            case .streakSaved:     "streak_saved"
            case .streakReset:     "streak_reset"
            case .streakFirstDay:  "streak_first_day"
            }
        }

        var title: String {
            switch self {
            case .attendance:      "출석 보상"
            case .sessionComplete: "식사 완료"
            case .streakMilestone(let count): "🔥 \(count)일 연속"
            case .streakSaved:     "🛡️ 프리즈로 스트릭 유지"
            case .streakReset:     "스트릭이 끊겼어요"
            case .streakFirstDay:  "🔥 1일째"
            }
        }

        var subtitle: String {
            switch self {
            case .attendance:      "오늘도 와줘서 고마워요"
            case .sessionComplete: "꼭꼭 잘 씹었어요"
            case .streakMilestone: "프리즈를 받았어요"
            case .streakSaved:     "프리즈 1개로 스트릭을 지켰어요"
            case .streakReset:     "다시 시작해 볼까요?"
            case .streakFirstDay:  "스트릭을 시작했어요"
            }
        }

        /// 도토리 적립 케이스 — RewardDialogView가 "+n🌰" 표시
        var isAcorn: Bool {
            switch self {
            case .attendance, .sessionComplete: true
            default: false
            }
        }

        /// 프리즈 적립 케이스 — "+n🛡️" 표시
        var isFreezeGain: Bool {
            if case .streakMilestone = self { return true }
            return false
        }

        /// 보상 종류별 다람이 일러스트. 매핑이 없으면 기본 happy.
        var imageName: String {
            switch self {
            case .attendance:      "DaramHeart"
            case .sessionComplete: "DaramDotori"
            case .streakReset:     "DaramSad"
            case .streakMilestone, .streakSaved, .streakFirstDay: Mood.happy.imageName
            }
        }
    }
}

#Preview("Attendance") {
    ZStack {
        Color.black.opacity(0.25).ignoresSafeArea()
        RewardDialogView(
            grant: RewardGrant(amount: 2, kind: .attendance),
            onDismiss: {}
        )
    }
}

#Preview("Session") {
    ZStack {
        Color.black.opacity(0.25).ignoresSafeArea()
        RewardDialogView(
            grant: RewardGrant(amount: 15, kind: .sessionComplete),
            onDismiss: {}
        )
    }
}

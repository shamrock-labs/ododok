import SwiftUI

/// 서버가 도토리·스트릭을 적립할 때 사용자에게 표시되는 시각적 보상. PRD #8의
/// "토스트 + 다람이 happy"의 in-app 구현. 시스템 alert 대신 커스텀 다이얼로그 +
/// 다람이 happy 이미지 + 적립 도토리 수 + 짧은 카피. 자동 2.5초 dismiss, 탭으로도
/// dismiss.
struct RewardDialogView: View {
    let grant: RewardGrant
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.cell) {
            Image(grant.kind.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.image, height: Metrics.image)
                .scaleEffect(AppArtwork.daramContentScale)

            Text(grant.title)
                .font(.appFont(.heavyHeadlineLarge))
                .foregroundStyle(Color.textDefault)
                .multilineTextAlignment(.center)

            if grant.kind.isAcorn {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.one) {
                    Text("+\(grant.amount)")
                        .font(.appFont(.rewardNumber))
                        .foregroundStyle(Color.rewardAcorn)
                        .monospacedDigit()
                    OpenIconView(icon: .acorn, color: .rewardAcorn, lineWidth: 2.2)
                        .frame(width: Metrics.icon, height: Metrics.icon)
                }
            } else if let amountText = grant.amountText {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.one) {
                    Text(amountText)
                        .font(.appFont(.rewardNumber))
                        .foregroundStyle(Color.freezeForeground)
                        .monospacedDigit()
                    Text("🛡️")
                        .font(.appFont(.regularEmojiMedium))
                }
            }

            Text(grant.detailText)
                .font(.appFont(.semiboldLabel))
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if let inventoryText = grant.inventoryText {
                Text(inventoryText)
                    .font(.appFont(.semiboldCaption))
                    .foregroundStyle(Color.freezeForeground)
                    .padding(.horizontal, AppSpacing.two)
                    .padding(.vertical, AppSpacing.one)
                    .background(Color.freezeSurface, in: Capsule())
            }
        }
        .padding(.vertical, AppSpacing.dialogContentV)
        .padding(.horizontal, AppSpacing.dialogContentH)
        .frame(maxWidth: AppSize.dialogMaxWidth)
        .background(Color.bgPopover, in: RoundedRectangle(cornerRadius: AppRadius.page))
        .appElevation(.floating)
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
/// 출석 streak 이벤트(프리즈 지급/사용/초기화)를 한 type으로
/// 묶어 ContentView overlay 코드를 단순화.
struct RewardGrant: Equatable {
    /// 분석에 사용할 보상 수량. 화면의 정확한 사용·지급 수량은 `kind`의 연관값을 표시한다.
    let amount: Int
    let kind: Kind

    var title: String {
        switch kind {
        case .streakFreezeGranted(let streakCount, _, _):
            "\(streakCount)일 연속 접속!"
        case .streakFreezeUsed:
            "스트릭을 지켰어요"
        default:
            kind.title
        }
    }

    var amountText: String? {
        switch kind {
        case .streakFreezeGranted(_, let granted, _):
            "+\(granted)"
        case .streakFreezeUsed(let consumed, _):
            "-\(consumed)"
        case .streakFreezeUsedAndGranted:
            nil
        case .streakMilestone:
            "+\(amount)"
        default:
            nil
        }
    }

    var detailText: String {
        switch kind {
        case .streakFreezeUsed(let consumed, _):
            "\(consumed)일을 쉬어 프리즈 \(consumed)개를 사용했어요"
        default:
            kind.subtitle
        }
    }

    var inventoryText: String? {
        let inventory: Int? = switch kind {
        case .streakFreezeGranted(_, _, let inventory): inventory
        case .streakFreezeUsed(_, let inventory): inventory
        case .streakFreezeUsedAndGranted(_, _, let inventory, _): inventory
        default: nil
        }
        return inventory.map { "현재 프리즈 \($0)개" }
    }

    enum Kind: Equatable {
        case attendance                          // 도토리 출석 보너스 +n
        case sessionComplete                     // 도토리 세션 종료 적립 +n
        case streakMilestone(streakCount: Int)   // 7/30/100일 도달, 프리즈 +n(amount)
        case streakSaved                         // 프리즈 사용 결과, amount=잔여
        case streakReset                         // 끊김 리셋
        case streakFirstDay                      // 첫 성공(스트릭 1일째) 토스트
        case streakFreezeGranted(streakCount: Int, granted: Int, inventory: Int)
        case streakFreezeUsed(consumed: Int, inventory: Int)
        case streakFreezeUsedAndGranted(consumed: Int, granted: Int, inventory: Int, streakCount: Int)

        /// 분석 이벤트용 안정적 식별자(ODO-79). 표시 문구(title)와 독립 — 문구가 바뀌어도 값은 유지된다.
        var analyticsType: String {
            switch self {
            case .attendance:      "attendance"
            case .sessionComplete: "session_complete"
            case .streakMilestone: "streak_milestone"
            case .streakSaved:     "streak_saved"
            case .streakReset:     "streak_reset"
            case .streakFirstDay:  "streak_first_day"
            case .streakFreezeGranted: "streak_freeze_granted"
            case .streakFreezeUsed: "streak_freeze_used"
            case .streakFreezeUsedAndGranted: "streak_freeze_used_and_granted"
            }
        }

        var title: String {
            switch self {
            case .attendance:      "출석 보상"
            case .sessionComplete: "식사 완료"
            case .streakMilestone(let count): "\(count)일 연속"
            case .streakSaved:     "🛡️ 프리즈로 스트릭 유지"
            case .streakReset:     "스트릭이 끊겼어요"
            case .streakFirstDay:  "1일째"
            case .streakFreezeGranted(let count, _, _): "\(count)일 연속 접속!"
            case .streakFreezeUsed: "스트릭을 지켰어요"
            case .streakFreezeUsedAndGranted: "스트릭을 지키고 보상도 받았어요"
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
            case .streakFreezeGranted: "프리즈를 받았어요"
            case .streakFreezeUsed(let consumed, _): "프리즈 \(consumed)개로 스트릭을 지켰어요"
            case .streakFreezeUsedAndGranted(let consumed, let granted, _, _):
                "\(consumed)개 사용 · \(granted)개 획득"
            }
        }

        /// 도토리 적립 케이스 — RewardDialogView가 "+n🌰" 표시
        var isAcorn: Bool {
            switch self {
            case .attendance, .sessionComplete: true
            default: false
            }
        }

        /// 보상 종류별 다람이 일러스트. 매핑이 없으면 기본 happy.
        var imageName: String {
            "RealDaram"
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

private enum Metrics {
    static let image: CGFloat = 110
    static let icon = AppSize.controlMedium
}

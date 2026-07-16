import SwiftUI

struct FreezeRecoveryPresentation: Equatable {
    let title: String
    let message: String
    let supportingText: String?
    let primaryTitle: String
    let secondaryTitle: String?
    let quantityText: String
    let missedDateTexts: [String]

    static func make(status: AttendanceStatusDTO) -> Self {
        let missedDateTexts = status.missedDates.map(Self.koreanDateText)
        let missedDatesText = missedDateTexts.joined(separator: " · ")
        let quantityText = "필요 \(status.requiredFreezes)개 · 보유 \(status.freezeInventory)개"

        switch status.status {
        case .recoveryAvailable:
            return Self(
                title: "스트릭을 이어갈까요?",
                message: "놓친 날짜\n\(missedDatesText)\n\n\(quantityText)",
                supportingText: "사용하지 않으면 오늘부터 새 스트릭이 시작돼요",
                primaryTitle: "프리즈 \(status.requiredFreezes)개 사용하기",
                secondaryTitle: "사용하지 않기",
                quantityText: quantityText,
                missedDateTexts: missedDateTexts
            )
        case .insufficient:
            return Self(
                title: "스트릭이 새로 시작돼요",
                message: "놓친 날짜\n\(missedDatesText)\n\n\(quantityText)",
                supportingText: "프리즈는 부분 사용하지 않아요",
                primaryTitle: "확인",
                secondaryTitle: nil,
                quantityText: quantityText,
                missedDateTexts: missedDateTexts
            )
        case .notNeeded:
            return Self(
                title: "출석을 확인했어요",
                message: quantityText,
                supportingText: nil,
                primaryTitle: "확인",
                secondaryTitle: nil,
                quantityText: quantityText,
                missedDateTexts: missedDateTexts
            )
        }
    }

    private static func koreanDateText(_ dateText: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "Asia/Seoul")
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: dateText) else { return dateText }

        let formatter = DateFormatter()
        formatter.calendar = parser.calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = parser.timeZone
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }
}

/// 앱을 연 직후 출석 복구 결정을 받는 blocking overlay.
/// backdrop과 닫기 컨트롤은 의도적으로 제공하지 않고 명시적 결정만 store로 전달한다.
struct FreezeRecoveryDialog: View {
    let status: AttendanceStatusDTO
    let onUse: () -> Void
    let onSkip: () -> Void
    let onConfirmInsufficient: () -> Void

    private var presentation: FreezeRecoveryPresentation {
        .make(status: status)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.bgOverlayScrim
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                AppDialog(
                    title: presentation.title,
                    message: presentation.message,
                    supportingText: presentation.supportingText,
                    primary: .init(presentation.primaryTitle) {
                        if status.status == .recoveryAvailable {
                            onUse()
                        } else {
                            onConfirmInsufficient()
                        }
                    },
                    secondary: presentation.secondaryTitle.map { title in
                        .init(title, role: .cancel, perform: onSkip)
                    },
                    onDismiss: {},
                    contentMaxHeight: max(
                        AppSize.dialogActionHeight,
                        proxy.size.height - AppSize.dialogActionHeight - (AppSpacing.six * 2)
                    ),
                    contentScrollAccessibilityIdentifier: "FreezeRecoveryContentScroll"
                )
                .padding(.horizontal, AppSpacing.overlayH)
                .padding(.vertical, AppSpacing.six)
                .accessibilityAddTraits(.isModal)
            }
        }
    }
}

#Preview("Recovery available") {
    FreezeRecoveryDialog(
        status: AttendanceStatusDTO(
            asOf: "2026-07-16",
            status: .recoveryAvailable,
            missedDates: ["2026-07-14", "2026-07-15"],
            requiredFreezes: 2,
            freezeInventory: 2
        ),
        onUse: {},
        onSkip: {},
        onConfirmInsufficient: {}
    )
}

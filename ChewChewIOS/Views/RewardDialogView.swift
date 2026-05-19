import SwiftUI

/// `RewardLedger`가 도토리를 적립할 때 사용자에게 표시되는 시각적 보상. PRD #8의
/// "토스트 + 다람이 happy"의 in-app 구현. 시스템 alert 대신 커스텀 다이얼로그 +
/// 다람이 happy 이미지 + 적립 도토리 수 + 짧은 카피. 자동 2.5초 dismiss, 탭으로도
/// dismiss.
struct RewardDialogView: View {
    let grant: RewardGrant
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(Mood.happy.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)

            Text(grant.kind.title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.ink800)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("+\(grant.amount)")
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(Color.acorn700)
                    .monospacedDigit()
                Text("🌰")
                    .font(.system(size: 28))
            }

            Text(grant.kind.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.ink600)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 32)
        .frame(maxWidth: 280)
        .background(
            LinearGradient(
                colors: [Color.acorn50, .cream, Color.sage50],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .neuoShadow(.md)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            onDismiss()
        }
    }
}

/// AppState가 publish하는 적립 trigger. `ContentView` overlay가 이 값을 관찰해서
/// 다이얼로그를 띄운다. dismiss 시 nil로 비움.
struct RewardGrant: Equatable {
    let amount: Int
    let kind: Kind

    enum Kind: Equatable {
        case attendance
        case sessionComplete

        var title: String {
            switch self {
            case .attendance:      "출석 보상!"
            case .sessionComplete: "식사 완료!"
            }
        }

        var subtitle: String {
            switch self {
            case .attendance:      "오늘도 와줘서 고마워요"
            case .sessionComplete: "꼭꼭 잘 씹었어요"
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

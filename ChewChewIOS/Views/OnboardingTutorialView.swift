import SwiftUI

/// 이름 입력 다음 단계 — 앱 사용법을 가로 스와이프 카드로 안내한다.
/// 디자인 레퍼런스: chewing-imu-collector의 RecordingGuideView.
/// 마지막 카드의 "시작하기" 또는 우상단 "건너뛰기"에서 `onFinish`를 호출해 온보딩을 끝낸다.
struct OnboardingTutorialView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let steps = OnboardingStep.all
    private var isLastPage: Bool { page == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            skipBar

            TabView(selection: $page) {
                ForEach(steps) { step in
                    cardView(step)
                        .padding(.horizontal, 28)
                        .tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageIndicator
                .padding(.top, 4)

            primaryButton
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.appBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    // MARK: 건너뛰기 바

    private var skipBar: some View {
        HStack {
            Spacer()
            Button(action: onFinish) {
                Text("건너뛰기")
                    .font(.appFont(.semibold, size: 14))
                    .foregroundStyle(Color.ink400)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .accessibilityIdentifier("OnboardingSkip")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: 카드

    private func cardView(_ step: OnboardingStep) -> some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(step.accent.opacity(0.18))
                    .frame(width: 96, height: 96)
                Image(systemName: step.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(step.accent)
            }

            Text(step.title)
                .font(.appFont(.heavy, size: 21))
                .foregroundStyle(Color.ink800)
                .multilineTextAlignment(.center)

            Text(step.message)
                .font(.appFont(.regular, size: 14))
                .foregroundStyle(Color.ink600)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 26))
        .neuoShadow(.md)
    }

    // MARK: 페이지 인디케이터

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<steps.count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.acorn600 : Color.acorn200)
                    .frame(width: i == page ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: page)
            }
        }
    }

    // MARK: 다음 / 시작하기

    private var primaryButton: some View {
        Button {
            if isLastPage {
                onFinish()
            } else {
                withAnimation { page += 1 }
            }
        } label: {
            Text(isLastPage ? "시작하기" : "다음")
                .font(.appFont(.heavy, size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [Color.acorn400, Color.acorn600],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .softShadow(.pill)
        .accessibilityIdentifier(isLastPage ? "OnboardingStart" : "OnboardingNext")
    }
}

#Preview {
    OnboardingTutorialView(onFinish: {})
}

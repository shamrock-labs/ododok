import SwiftUI

/// 이름 입력 다음 단계 — 앱 사용법을 가로 스와이프 카드로 안내한다.
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
        .background(Color.cream.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

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

    private func cardView(_ step: OnboardingStep) -> some View {
        VStack(spacing: 22) {
            visual(step)
                .frame(height: 180)

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
    }

    @ViewBuilder
    private func visual(_ step: OnboardingStep) -> some View {
        if let asset = step.asset {
            Image(asset)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: step.icon)
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Color.acorn600)
        }
    }

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
                .background(Color.acorn600, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(isLastPage ? "OnboardingStart" : "OnboardingNext")
    }
}

#Preview {
    OnboardingTutorialView(onFinish: {})
}

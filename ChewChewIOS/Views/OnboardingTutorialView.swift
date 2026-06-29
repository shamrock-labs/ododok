import SwiftUI

/// 이름 입력 다음 단계 — 앱 사용법을 가로 스와이프 카드로 안내한다.
/// 각 카드의 비주얼은 정적 일러스트 대신 실제 앱 컴포넌트(측정 파형·씹는 다람이 등)를
/// 그대로 애니메이션으로 미리보여 "실제 기능 화면"처럼 느끼게 한다.
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
        .background(Color.pageBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private var skipBar: some View {
        HStack {
            Spacer()
            Button(action: onFinish) {
                Text("건너뛰기")
                    .font(.appFont(.semibold, size: 14))
                    .foregroundStyle(Color.textTertiary)
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
                .frame(height: 188)

            Text(step.title)
                .font(.appFont(.heavy, size: 21))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            Text(step.message)
                .font(.appFont(.regular, size: 16))
                .foregroundStyle(Color.ink600)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }

    /// 단계별 실제 기능 미리보기. id로 라우팅한다(0=에어팟, 1=측정, 2=씹기, 3=출석).
    @ViewBuilder
    private func visual(_ step: OnboardingStep) -> some View {
        switch step.id {
        case 0: AirPodsConnectDemo()
        case 1: MeasureDemo()
        case 2: ChewDemo()
        default: StreakDemo(isActive: page == step.id)
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

// MARK: - 단계별 미리보기 (실제 컴포넌트 재사용)

/// 0 · 에어팟 연결 — 실제 AirPods 글리프(SF Symbol) 위로 연결 신호 펄스가 퍼진다.
private struct AirPodsConnectDemo: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.acorn400.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                    .scaleEffect(animate ? 1.9 : 0.72)
                    .opacity(animate ? 0 : 0.55)
                    .animation(
                        .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.72),
                        value: animate
                    )
            }

            Circle()
                .fill(Color.acorn50)
                .frame(width: 116, height: 116)

            Image(systemName: "airpodspro")
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(Color.acorn600)
        }
        .onAppear { animate = true }
    }
}

/// 1 · 측정 — 실제 측정 화면의 라이브 파형 카드를 그대로 미리보기. 흐르는 IMU 파형 + 타이머 + "측정 중".
private struct MeasureDemo: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    PulsingDot()
                    Text("측정 중")
                        .font(.appFont(.bold, size: 12))
                        .foregroundStyle(Color.acorn700)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.acorn50, in: Capsule())

                Spacer()

                Text("00:42")
                    .font(.appFont(.bold, size: 14))
                    .foregroundStyle(Color.ink600)
            }

            WaveformDemo()
                .frame(height: 72)
        }
        .padding(14)
        .frame(width: 252)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .neuoShadow(.sm)
    }
}

/// 측정 카드 안에서 끊임없이 흐르는 IMU 파형. 시간으로 진폭 포락선을 굴려 라이브처럼 움직인다.
private struct WaveformDemo: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.09)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let samples: [Double] = (0..<54).map { i in
                let x = Double(i)
                let envelope = 0.4 + 0.42 * (0.5 + 0.5 * sin(x * 0.16 - t * 1.4))
                let burst = 0.5 + 0.5 * sin(x * 0.5 - t * 4.0)
                return max(0.08, envelope * burst)
            }
            IMUWaveformView(samples: samples, isLive: true)
        }
    }
}

/// "측정 중" 칩의 깜빡이는 점.
private struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Color.acorn500)
            .frame(width: 7, height: 7)
            .opacity(on ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// 2 · 씹기 — 홈 화면처럼 흰 카드로 감싼 다람이 + 오늘 씹기 진행 바.
/// 측정 카드(파형·타이머)와 같은 "흰 카드" 결이되, 내용은 마스코트+진행도라 겹치지 않게 구분.
private struct ChewDemo: View {
    @State private var chew = false

    var body: some View {
        VStack(spacing: 10) {
            Image("DaramEating")
                .resizable()
                .scaledToFit()
                .frame(height: 96)
                .scaleEffect(chew ? 1.02 : 0.99)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: chew)
                .onAppear { chew = true }

            VStack(spacing: 6) {
                HStack {
                    Text("오늘 씹기")
                        .font(.appFont(.semibold, size: 12))
                        .foregroundStyle(Color.ink600)
                    Spacer()
                    Text("312 / 400")
                        .font(.appFont(.bold, size: 12))
                        .foregroundStyle(Color.acorn700)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ink100)
                        Capsule().fill(Color.acorn500).frame(width: geo.size.width * 0.78)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .frame(width: 252)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .neuoShadow(.sm)
    }
}

/// 3 · 출석 — 마지막 페이지로 스와이프해 도달한 순간(startDate)부터 한 주 스트립이 빈 상태에서
/// 채워지고, 가득 차면 리셋해 반복한다. 전역 시계가 아니라 도달 시점 기준이라 페이지에 들어올
/// 때마다 처음부터 시작한다(TabView가 페이지를 살려둬 onAppear만으론 부족 → isActive로 제어).
private struct StreakDemo: View {
    let isActive: Bool
    private let days = ["월", "화", "수", "목", "금", "토", "일"]

    @State private var startDate: Date?

    var body: some View {
        Group {
            if let startDate {
                TimelineView(.periodic(from: startDate, by: 0.4)) { timeline in
                    // 11틱(약 4.4초) 주기: 0=리셋, 1~7=하나씩 채움, 8~10=가득 찬 채 멈춤 → 반복.
                    let tick = Int(timeline.date.timeIntervalSince(startDate) / 0.4) % 11
                    strip(filled: max(0, min(tick, 7)))
                }
            } else {
                strip(filled: 0)
            }
        }
        .onChange(of: isActive) { _, active in
            startDate = active ? Date() : nil
        }
        .onAppear {
            if isActive { startDate = Date() }
        }
    }

    private func strip(filled: Int) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.acorn500)
                Text("7일째")
                    .font(.appFont(.heavy, size: 20))
                    .foregroundStyle(Color.acorn700)
            }

            HStack(spacing: 9) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(i < filled ? Color.acorn600 : Color.acorn200)
                                .frame(width: 28, height: 28)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(i < filled ? 1 : 0)
                        }
                        Text(days[i])
                            .font(.appFont(.medium, size: 10))
                            .foregroundStyle(Color.ink400)
                    }
                }
            }
            .animation(.spring(response: 0.3), value: filled)
        }
    }
}

#Preview {
    OnboardingTutorialView(onFinish: {})
}

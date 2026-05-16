import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            topBar
            statRow
            squirrelCard
                .frame(maxHeight: .infinity)
            mealToggleButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ink400)
                Text("안녕, 성호님")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
            HStack(spacing: 10) {
                circleButton("bell.fill")
                circleButton("gearshape.fill")
            }
        }
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "오늘 · M월 d일"
        return f.string(from: Date())
    }

    private func circleButton(_ symbol: String) -> some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.ink600)
                .frame(width: 46, height: 46)
                .background(Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .neuoShadow(.sm)
    }

    // MARK: Streak + Points

    private var statRow: some View {
        HStack(spacing: 14) {
            statCard(
                label: "연속 출석",
                value: "\(state.streak)일째 🔥",
                iconBG: Color.blush100
            ) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.blush500)
                    .font(.system(size: 26))
            }

            statCard(
                label: "보유 도토리",
                value: state.points.koLocale,
                iconBG: Color.butter100
            ) {
                Text("🌰").font(.system(size: 26))
            }
        }
    }

    private func statCard<I: View>(
        label: String,
        value: String,
        iconBG: Color,
        @ViewBuilder icon: () -> I
    ) -> some View {
        HStack(spacing: 10) {
            iconBG
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay { icon() }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink400)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    // MARK: Squirrel card + IMU waveform

    private var squirrelCard: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            SquirrelView(
                mood: state.isEating ? state.status.mood : .happy,
                hat: nil,
                glasses: nil,
                acc: nil,
                animKey: state.animKey,
                isEating: state.isEating
            )
            .scaleEffect(1.5)
            .frame(height: 246)

            VStack(spacing: 2) {
                Text(state.status.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.ink800)
                Text(state.status.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink400)
            }

            imuWaveformCard
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 390)
        .background(
            LinearGradient(
                colors: [.white, .cream, Color.acorn50],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
        .neuoShadow(.md)
    }

    private var imuWaveformCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("IMU 파형")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.ink800)
                    Text(state.imuWaveformStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(state.isIMUWaveformLive ? Color.sage600 : Color.ink400)
                }

                Spacer()

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(state.isIMUWaveformLive ? Color.sage600 : Color.ink400)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
            }

            IMUWaveformView(samples: state.imuWaveformSamples, isLive: state.isIMUWaveformLive)
                .frame(height: 44)
        }
        .padding(12)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Meal toggle button

    private var mealToggleButton: some View {
        Button {
            state.toggleEating()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: state.isEating ? "stop.fill" : "fork.knife")
                    .font(.system(size: 22, weight: .bold))
                Text(state.isEating ? "식사 종료" : "식사 시작")
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    colors: state.isEating
                        ? [Color.blush400, Color.blush500]
                        : [Color.acorn400, Color.acorn600],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .softShadow(.pill)
        .animation(.easeInOut(duration: 0.22), value: state.isEating)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

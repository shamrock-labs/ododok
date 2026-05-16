import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 20) {
            topBar
            statRow
            squirrelCard
            chewButton
            achievementsRow
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(todayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink400)
                Text("안녕, 성호님")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
            HStack(spacing: 8) {
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.ink600)
                .frame(width: 40, height: 40)
                .background(Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .neuoShadow(.sm)
    }

    // MARK: Streak + Points

    private var statRow: some View {
        HStack(spacing: 12) {
            statCard(
                label: "연속 출석",
                value: "\(state.streak)일째 🔥",
                iconBG: Color.blush100
            ) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.blush500)
                    .font(.system(size: 22))
            }

            statCard(
                label: "보유 도토리",
                value: state.points.koLocale,
                iconBG: Color.butter100
            ) {
                Text("🌰").font(.system(size: 22))
            }
        }
    }

    private func statCard<I: View>(
        label: String,
        value: String,
        iconBG: Color,
        @ViewBuilder icon: () -> I
    ) -> some View {
        HStack(spacing: 12) {
            iconBG
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay { icon() }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.ink400)
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.ink800)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    // MARK: Squirrel card + progress

    private var squirrelCard: some View {
        VStack(spacing: 14) {
            SquirrelView(
                mood: state.status.mood,
                hat: ShopItem.by(id: state.equipped.hat),
                glasses: ShopItem.by(id: state.equipped.glasses),
                acc: ShopItem.by(id: state.equipped.acc),
                animKey: state.animKey
            )

            VStack(spacing: 2) {
                Text(state.status.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.ink800)
                Text(state.status.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink400)
            }

            progressBar
                .padding(.top, 4)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [.white, .cream, Color.acorn50],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .neuoShadow(.md)
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("오늘의 저작 목표")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink600)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(state.chewCount.koLocale)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ink800)
                    Text("/ \(Constants.dailyGoal.koLocale)회")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.ink400)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.acorn50)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.butter400, Color.acorn300, Color.sage400],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * state.progress)
                        .animation(.easeOut(duration: 0.5), value: state.progress)
                }
            }
            .frame(height: 12)
        }
    }

    // MARK: Big chew button

    private var chewButton: some View {
        Button {
            state.chew()
        } label: {
            HStack(spacing: 8) {
                Text("🐿️").font(.system(size: 20))
                Text("한입 씹기 (+\(Int(Constants.pointsPerChew * 5)) 도토리)")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.acorn400, Color.acorn600],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .softShadow(.pill)
    }

    // MARK: Achievements

    private var achievementsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 업적")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.ink600)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    achievement("🏆", "7일 연속")
                    achievement("⏱️", "천천히 씹기")
                    achievement("🌰", "1000 도토리")
                    achievement("💪", "주간 챌린저")
                }
            }
        }
    }

    private func achievement(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text(icon).font(.system(size: 28))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.ink600)
        }
        .frame(width: 80, height: 96)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

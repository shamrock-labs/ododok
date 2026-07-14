import SwiftUI

struct SquirrelView: View {
    let mood: Mood
    let hat: ShopItem?
    let glasses: ShopItem?
    let acc: ShopItem?
    let animKey: Int
    let isEating: Bool
    /// 야간 시간대(22:00~06:00)이면 잠자는 다람이로 교체.
    var isNight: Bool = false

    @State private var bounce = false
    @State private var eatingMotion = false
    @State private var blinkFrame: BlinkFrame = .open

    private var currentImageName: String {
        // 식사 중에는 깜빡임 루프의 직전 프레임이 남아 있더라도 항상 원본 눈 상태를 쓴다.
        isEating ? "RealDaram" : blinkFrame.imageName
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.illustrationHalo.opacity(0.4))
                .frame(width: Metrics.halo, height: Metrics.halo)
                .scaleEffect(bounce ? 1.6 : (isEating && eatingMotion ? 1.05 : 0.95))
                .opacity(bounce ? 0 : 0.6)
                .animation(.easeOut(duration: AppMotion.durationPulse), value: bounce)
                .animation(.easeInOut(duration: AppMotion.durationChew).repeatForever(autoreverses: true), value: eatingMotion)

            Image(currentImageName)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.image, height: Metrics.image)
                .scaleEffect(AppArtwork.daramContentScale * (bounce ? 1.08 : 1.0))
                .rotationEffect(.degrees(
                    bounce ? -2
                        : (isEating && eatingMotion ? 2.5 : 0)
                ))
                .offset(y: isEating && eatingMotion ? -4 : 0)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
                .animation(.spring(response: AppMotion.springSquirrelResponse, dampingFraction: AppMotion.springSquirrelDamping), value: bounce)
                .animation(.easeInOut(duration: AppMotion.durationChew).repeatForever(autoreverses: true), value: eatingMotion)

            if let hat {
                Text(hat.emoji)
                    .font(.appFont(.regularEmojiLarge))
                    .offset(y: -52)
            }
            if let glasses {
                Text(glasses.emoji)
                    .font(.appFont(.regularTitle))
                    .offset(y: -2)
            }
            if let acc {
                Text(acc.emoji)
                    .font(.appFont(.regularHeadline))
                    .offset(x: 40, y: 36)
            }

            if mood == .sleepy {
                Text("💤")
                    .font(.appFont(.regularHeadline))
                    .offset(x: 48, y: -50)
            }

            if mood == .champ {
                ForEach(0..<3, id: \.self) { i in
                    let xs: [CGFloat] = [-48, -34, 48]
                    let ys: [CGFloat] = [-48, 48, -34]
                    Image(systemName: "sparkles")
                        .font(.appFont(.regularHeadline))
                        .foregroundStyle(Color.illustrationSparkle)
                        .offset(x: xs[i], y: ys[i])
                }
            }
        }
        .frame(height: Metrics.halo)
        .onAppear {
            eatingMotion = isEating
        }
        .onChange(of: isEating) { _, isOn in
            eatingMotion = isOn
        }
        .onChange(of: animKey) { _, _ in
            bounce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + AppMotion.springSquirrelResponse) {
                bounce = false
            }
        }
        .task(id: isEating) {
            await runBlinkLoop()
        }
    }

    /// 평상시에는 정지해 있다가 매 5초마다 0.5초 간격으로 한 번 눈을 깜빡인다.
    private func runBlinkLoop() async {
        blinkFrame = .open
        guard !isEating else { return }

        do {
            try await Task.sleep(for: .seconds(Metrics.blinkInterval))

            while !Task.isCancelled {
                blinkFrame = .halfClosed
                try await Task.sleep(for: .seconds(Metrics.blinkFrameDuration))
                blinkFrame = .closed
                try await Task.sleep(for: .seconds(Metrics.blinkFrameDuration))
                blinkFrame = .halfClosed
                try await Task.sleep(for: .seconds(Metrics.blinkFrameDuration))
                blinkFrame = .open

                try await Task.sleep(for: .seconds(Metrics.blinkRestDuration))
            }
        } catch {
            blinkFrame = .open
        }
    }
}

private enum BlinkFrame {
    case open
    case halfClosed
    case closed

    var imageName: String {
        switch self {
        case .open: "RealDaram"
        case .halfClosed: "DaramHalfClosed"
        case .closed: "DaramClosed"
        }
    }
}

private enum Metrics {
    static let halo = AppSize.visualXLarge
    static let image: CGFloat = 115
    static let blinkInterval: TimeInterval = 5
    static let blinkFrameDuration: TimeInterval = 0.5
    static let blinkRestDuration = blinkInterval - blinkFrameDuration * 3
}

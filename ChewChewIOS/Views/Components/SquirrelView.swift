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
    /// 식사 중이 아닐 때 다람쥐가 살짝 좌우로 흔들리는 idle 모션.
    @State private var idleSway = false

    private var currentImageName: String {
        if isEating { return "DaramEating" }
        if isNight  { return "DaramSleeping" }
        return mood.imageName
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.illustrationHalo.opacity(0.4))
                .frame(width: AppSize.squirrelHalo, height: AppSize.squirrelHalo)
                .scaleEffect(bounce ? 1.6 : (isEating && eatingMotion ? 1.05 : 0.95))
                .opacity(bounce ? 0 : 0.6)
                .animation(.easeOut(duration: AppMotion.durationPulse), value: bounce)
                .animation(.easeInOut(duration: AppMotion.durationChew).repeatForever(autoreverses: true), value: eatingMotion)

            Image(currentImageName)
                .resizable()
                .scaledToFit()
                .frame(width: AppSize.squirrelImage, height: AppSize.squirrelImage)
                .scaleEffect(bounce ? 1.08 : 1.0)
                .rotationEffect(.degrees(
                    bounce ? -2
                        : (isEating && eatingMotion ? 2.5
                           : (idleSway ? 0.6 : -0.6))
                ))
                .offset(y: isEating && eatingMotion ? -4 : (idleSway ? -1.2 : 1.2))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
                .animation(.spring(response: AppMotion.springSquirrelResponse, dampingFraction: AppMotion.springSquirrelDamping), value: bounce)
                .animation(.easeInOut(duration: AppMotion.durationChew).repeatForever(autoreverses: true), value: eatingMotion)
                .animation(.easeInOut(duration: AppMotion.durationWave).repeatForever(autoreverses: true), value: idleSway)

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
        .frame(height: AppSize.squirrelHalo)
        .onAppear {
            eatingMotion = isEating
            // 첫 프레임 직후 토글 → 미세 sway가 자연스럽게 시작
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                idleSway = true
            }
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
    }
}

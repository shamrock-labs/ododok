import SwiftUI

struct SquirrelView: View {
    let mood: Mood
    let hat: ShopItem?
    let glasses: ShopItem?
    let acc: ShopItem?
    let animKey: Int
    let isEating: Bool

    @State private var bounce = false
    @State private var eatingMotion = false
    /// 식사 중이 아닐 때 다람쥐가 살짝 좌우로 흔들리는 idle 모션.
    @State private var idleSway = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.butter200.opacity(0.4))
                .frame(width: 140, height: 140)
                .scaleEffect(bounce ? 1.6 : (isEating && eatingMotion ? 1.05 : 0.95))
                .opacity(bounce ? 0 : 0.6)
                .animation(.easeOut(duration: 1.2), value: bounce)
                .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: eatingMotion)

            Image(mood.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 115, height: 115)
                .scaleEffect(bounce ? 1.08 : 1.0)
                .rotationEffect(.degrees(
                    bounce ? -2
                        : (isEating && eatingMotion ? 2.5
                           : (idleSway ? 0.6 : -0.6))
                ))
                .offset(y: isEating && eatingMotion ? -4 : (idleSway ? -1.2 : 1.2))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
                .animation(.spring(response: 0.42, dampingFraction: 0.55), value: bounce)
                .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: eatingMotion)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: idleSway)

            if let hat {
                Text(hat.emoji)
                    .font(.system(size: 30))
                    .offset(y: -52)
            }
            if let glasses {
                Text(glasses.emoji)
                    .font(.system(size: 20))
                    .offset(y: -2)
            }
            if let acc {
                Text(acc.emoji)
                    .font(.system(size: 18))
                    .offset(x: 40, y: 36)
            }

            if mood == .sleepy {
                Text("💤")
                    .font(.system(size: 18))
                    .offset(x: 48, y: -50)
            }

            if mood == .champ {
                ForEach(0..<3, id: \.self) { i in
                    let xs: [CGFloat] = [-48, -34, 48]
                    let ys: [CGFloat] = [-48, 48, -34]
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.butter500)
                        .offset(x: xs[i], y: ys[i])
                }
            }
        }
        .frame(height: 140)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                bounce = false
            }
        }
    }
}

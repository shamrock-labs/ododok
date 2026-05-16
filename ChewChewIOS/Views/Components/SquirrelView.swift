import SwiftUI

struct SquirrelView: View {
    let mood: Mood
    let hat: ShopItem?
    let glasses: ShopItem?
    let acc: ShopItem?
    let animKey: Int

    @State private var bounce = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.butter200.opacity(0.4))
                .frame(width: 140, height: 140)
                .scaleEffect(bounce ? 1.6 : 0.95)
                .opacity(bounce ? 0 : 0.6)
                .animation(.easeOut(duration: 1.2), value: bounce)

            Image(mood.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 115, height: 115)
                .scaleEffect(bounce ? 1.08 : 1.0)
                .rotationEffect(.degrees(bounce ? -2 : 0))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
                .animation(.spring(response: 0.42, dampingFraction: 0.55), value: bounce)

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
        .onChange(of: animKey) { _, _ in
            bounce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                bounce = false
            }
        }
    }
}

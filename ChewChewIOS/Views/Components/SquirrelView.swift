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
                .frame(width: 220, height: 220)
                .scaleEffect(bounce ? 1.6 : 0.95)
                .opacity(bounce ? 0 : 0.6)
                .animation(.easeOut(duration: 1.2), value: bounce)

            Image(mood.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .scaleEffect(bounce ? 1.08 : 1.0)
                .rotationEffect(.degrees(bounce ? -2 : 0))
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 8)
                .animation(.spring(response: 0.42, dampingFraction: 0.55), value: bounce)

            if let hat {
                Text(hat.emoji)
                    .font(.system(size: 44))
                    .offset(y: -82)
            }
            if let glasses {
                Text(glasses.emoji)
                    .font(.system(size: 28))
                    .offset(y: -6)
            }
            if let acc {
                Text(acc.emoji)
                    .font(.system(size: 24))
                    .offset(x: 60, y: 60)
            }

            if mood == .sleepy {
                Text("💤")
                    .font(.system(size: 24))
                    .offset(x: 70, y: -78)
            }

            if mood == .champ {
                ForEach(0..<3, id: \.self) { i in
                    let xs: [CGFloat] = [-70, -50, 70]
                    let ys: [CGFloat] = [-70, 70, -50]
                    Image(systemName: "sparkles")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.butter500)
                        .offset(x: xs[i], y: ys[i])
                }
            }
        }
        .frame(height: 220)
        .onChange(of: animKey) { _, _ in
            bounce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                bounce = false
            }
        }
    }
}

import SwiftUI

struct ShopView: View {
    var body: some View {
        VStack(spacing: 18) {
            header
            Spacer(minLength: 24)
            comingSoonCard
            Spacer(minLength: 24)
            roadmapCard
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MVP 이후")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ink400)
                Text("상점")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
        }
    }

    // MARK: Coming soon

    private var comingSoonCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.butter200.opacity(0.45))
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 108, height: 108)
                    .neuoShadow(.sm)
                Text("상점은\n준비 중")
                    .font(.system(size: 20, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.acorn700)
            }

            VStack(spacing: 6) {
                Text("상점은 MVP 이후 추가 예정입니다")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(Color.ink800)
                    .multilineTextAlignment(.center)
                Text("현재 버전에서는 저작 트래킹과 목표 달성 경험에 집중합니다.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ink600)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
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

    private var roadmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.butter600)
                    .frame(width: 38, height: 38)
                    .background(Color.butter100, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("다음 단계")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ink800)
                    Text("꾸미기, 리워드, 도토리 사용 기능")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ink400)
                }

                Spacer(minLength: 0)
            }

            Text("상점 기능은 트래킹 MVP가 안정화된 뒤 별도 버전에서 열릴 예정이에요.")
                .font(.system(size: 12))
                .foregroundStyle(Color.ink600)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }
}

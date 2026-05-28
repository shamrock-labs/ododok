import SwiftUI

struct FriendsView: View {
    @State private var inviteToastVisible = false

    var body: some View {
        VStack(spacing: 18) {
            header
            inviteCard
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if inviteToastVisible {
                Text("친구 초대 기능은 MVP 이후 연결됩니다")
                    .font(.appFont(.bold, size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.ink800, in: RoundedRectangle(cornerRadius: 16))
                    .softShadow(.lg)
                    .padding(.bottom, 110)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("함께 씹기")
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
                Text("친구")
                    .font(.appFont(.bold, size: 24))
                    .foregroundStyle(Color.ink800)
            }
            Spacer()
        }
    }

    // MARK: Invite

    private var inviteCard: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 6)

            Image("DaramHi")
                .resizable()
                .scaledToFit()
                .frame(height: 150)

            VStack(spacing: 6) {
                Text("친구들과 식사 현황을 나눠요")
                    .font(.appFont(.heavy, size: 21))
                    .foregroundStyle(Color.ink800)
                    .multilineTextAlignment(.center)
                Text("함께 목표를 채우고, 아직 시작하지 않은 친구를 초대할 수 있어요.")
                    .font(.appFont(.medium, size: 13))
                    .foregroundStyle(Color.ink600)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                showInviteToast()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                        .font(.appFont(.bold, size: 15))
                    Text("친구 초대하기")
                        .font(.appFont(.bold, size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.sage600, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(PressableButtonStyle())
            .softShadow(.pill)

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 360)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28))
        .neuoShadow(.md)
    }

    private func showInviteToast() {
        withAnimation { inviteToastVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { inviteToastVisible = false }
        }
    }
}

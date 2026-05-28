import SwiftUI

struct FriendsView: View {
    @State private var inviteToastVisible = false

    private let friends: [FriendStatus] = [
        .init(name: "민지", status: "식사 중", detail: "18회/분", color: .sage500, icon: "fork.knife"),
        .init(name: "준호", status: "목표 근접", detail: "522/600회", color: .butter600, icon: "target"),
        .init(name: "서연", status: "오늘 완료", detail: "640회", color: .acorn600, icon: "checkmark")
    ]

    var body: some View {
        VStack(spacing: 18) {
            header
            inviteCard
                .frame(maxHeight: .infinity)
            friendList
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

            ZStack {
                Circle()
                    .fill(Color.sage100.opacity(0.8))
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 108, height: 108)
                    .neuoShadow(.sm)
                Image(systemName: "person.2.fill")
                    .font(.appFont(.bold, size: 42))
                    .foregroundStyle(Color.sage600)
            }

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
                .background(
                    LinearGradient(
                        colors: [Color.sage400, Color.sage600],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16)
                )
            }
            .buttonStyle(PressableButtonStyle())
            .softShadow(.pill)

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 360)
        .background(
            LinearGradient(
                colors: [.white, .cream, Color.sage50],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .neuoShadow(.md)
    }

    // MARK: Friend list

    private var friendList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("친구 현황")
                .font(.appFont(.bold, size: 13))
                .foregroundStyle(Color.ink800)

            ForEach(friends) { friend in
                friendRow(friend)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .neuoShadow(.sm)
    }

    private func friendRow(_ friend: FriendStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: friend.icon)
                .font(.appFont(.bold, size: 14))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(friend.color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name)
                    .font(.appFont(.bold, size: 13))
                    .foregroundStyle(Color.ink800)
                Text(friend.status)
                    .font(.appFont(.medium, size: 11))
                    .foregroundStyle(Color.ink400)
            }

            Spacer(minLength: 0)

            Text(friend.detail)
                .font(.appFont(.bold, size: 12))
                .foregroundStyle(friend.color)
        }
    }

    private func showInviteToast() {
        withAnimation { inviteToastVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { inviteToastVisible = false }
        }
    }
}

private struct FriendStatus: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let detail: String
    let color: Color
    let icon: String
}
